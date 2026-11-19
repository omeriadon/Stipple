import CoreGraphics
import Dispatch
import Foundation
import simd

/// Everything one frame needs. Positions are in physical pixels, relative to the cell grid's top-left corner.
nonisolated struct DitherFrame: Sendable {
	var settings: DitherSettings
	var columns: Int
	var rows: Int
	var cellPixels: Int
	/// Accumulated wave travel. Integrated by the caller so speed changes and the wrist-down coast never jump.
	var offset: SIMD2<Float>
	/// 0...1 radial reveal for the intro.
	var reveal: Float
	var trail: [SIMD3<Float>]
	var touchPresence: Float
	/// The visible screen rectangle in grid pixel coordinates, for keeping cells out of the rounded corners.
	var screenOrigin: SIMD2<Float>
	var screenSize: SIMD2<Float>
	var screenCornerRadius: Float
	/// Exposure multiplier applied to every output colour (the clock's Window effect brightens the field).
	var gain: Float = 1
}

/// CPU port of Ergo's `OptimizedDither.metal`. One field value is computed per cell (not per pixel), cell-invariant
/// work such as thresholds, corner masks and colour-field tints is cached per layout, and rows are split across cores.
/// The result is a single small bitmap, shown by one SwiftUI `Image` with nearest-neighbour scaling.
nonisolated final class DitherRenderer: @unchecked Sendable {
	private var colors: [UInt32] = []
	private var alphas: [Float] = []
	private var pixels: [UInt32] = []

	private var layoutKey: LayoutKey?
	private var thresholds: [Float] = []
	private var outsideCorners: [Bool] = []
	private var uvs: [SIMD2<Float>] = []
	private var tintKey: TintKey?
	private var tints: [SIMD3<Float>] = []
	private var maskKey: MaskKey?
	private var masks: [[UInt8]] = []

	private let workers = max(1, ProcessInfo.processInfo.activeProcessorCount)

	init() {}

	/// Renders a frame. Returns the image plus its size in physical pixels.
	func render(_ frame: DitherFrame) -> CGImage? {
		let s = frame.settings
		let columns = max(1, frame.columns), rows = max(1, frame.rows), cellPixels = max(1, frame.cellPixels)
		let count = columns * rows
		prepareLayout(frame, columns: columns, rows: rows, cellPixels: cellPixels)
		if colors.count != count {
			colors = .init(repeating: 0, count: count)
			alphas = .init(repeating: 0, count: count)
		}

		let colorPlan = ColorPlan(settings: s, gain: frame.gain)
		if s.colorField, colorPlan.paletteSource.count > 0 {
			prepareTints(columns: columns, rows: rows, palette: colorPlan.paletteSource)
		}

		let field = FieldPlan(frame: frame, columns: columns, rows: rows, cellPixels: cellPixels)
		let usesTint = s.colorField && !colorPlan.paletteSource.isEmpty

		// Field + colour pass, rows split across cores.
		do {
			colors.withUnsafeMutableBufferPointer { colorBuffer in
				alphas.withUnsafeMutableBufferPointer { alphaBuffer in
					thresholds.withUnsafeBufferPointer { thresholdBuffer in
						outsideCorners.withUnsafeBufferPointer { outsideBuffer in
							uvs.withUnsafeBufferPointer { uvBuffer in
								tints.withUnsafeBufferPointer { tintBuffer in
									let shared = Unchecked((colorBuffer, alphaBuffer, thresholdBuffer, outsideBuffer, uvBuffer, tintBuffer))
									let chunks = min(rows, workers * 2)
									DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
										let (c, a, t, o, uv, tint) = shared.value
										let start = rows * chunk / chunks, end = rows * (chunk + 1) / chunks
										for row in start ..< end {
											for column in 0 ..< columns {
												let i = row * columns + column
												let value = field.value(uv: uv[i], column: column, row: row)
												let (color, alpha) = colorPlan.color(
													value: value,
													threshold: t[i],
													outside: o[i],
													tint: usesTint ? tint[i] : nil
												)
												c[i] = color
												a[i] = alpha
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}

		if s.gap > 0 || s.cornerRadius > 0, cellPixels > 1 {
			return rasterShaped(settings: s, plan: colorPlan, columns: columns, rows: rows, cellPixels: cellPixels)
		}
		return makeImage(from: colors, width: columns, height: rows, opaque: true)
	}

	// MARK: Layout caches

	private struct LayoutKey: Equatable {
		var columns: Int, rows: Int, cellPixels: Int, pattern: DitherPattern
		var origin: SIMD2<Float>, size: SIMD2<Float>, radius: Float
	}

	private func prepareLayout(_ frame: DitherFrame, columns: Int, rows: Int, cellPixels: Int) {
		let radius = frame.settings.clipsToScreenCorners ? frame.screenCornerRadius : 0
		let key = LayoutKey(columns: columns, rows: rows, cellPixels: cellPixels, pattern: frame.settings.pattern,
		                    origin: frame.screenOrigin, size: frame.screenSize, radius: radius)
		guard key != layoutKey else { return }
		layoutKey = key
		tintKey = nil
		let count = columns * rows
		thresholds = .init(repeating: 0, count: count)
		outsideCorners = .init(repeating: false, count: count)
		uvs = .init(repeating: .zero, count: count)
		let aspect = Float(columns) / Float(rows)
		let center = frame.screenOrigin + frame.screenSize * 0.5
		let inner = frame.screenSize * 0.5 - radius
		let size = Float(cellPixels)
		for row in 0 ..< rows {
			for column in 0 ..< columns {
				let i = row * columns + column
				thresholds[i] = Self.threshold(column: column, row: row, pattern: frame.settings.pattern)
				uvs[i] = SIMD2((Float(column) / Float(columns) - 0.5) * aspect, Float(row) / Float(rows) - 0.5)
				if radius > 0 {
					let origin = SIMD2(Float(column), Float(row)) * size
					for corner in 0 ..< 4 {
						let point = origin + SIMD2(Float(corner & 1), Float(corner >> 1)) * size
						let q = simd_abs(point - center) - inner
						let distance = simd_length(simd_max(q, .zero)) + min(max(q.x, q.y), 0) - radius
						if distance > 0 {
							outsideCorners[i] = true
							break
						}
					}
				}
			}
		}
	}

	private struct TintKey: Equatable {
		var columns: Int, rows: Int, palette: [SIMD3<Float>]
	}

	/// Ergo's theme-colour field, with the palette standing in for theme colours, placed evenly around the screen.
	private func prepareTints(columns: Int, rows: Int, palette: [SIMD3<Float>]) {
		let key = TintKey(columns: columns, rows: rows, palette: palette)
		guard key != tintKey else { return }
		tintKey = key
		let positions = (0 ..< palette.count).map { index -> SIMD2<Float> in
			guard palette.count > 1 else { return SIMD2(0.5, 0.5) }
			let angle = Float(index) / Float(palette.count) * 2 * .pi - .pi / 2
			return SIMD2(0.5 + cos(angle) * 0.38, 0.5 + sin(angle) * 0.38)
		}
		tints = .init(repeating: .zero, count: columns * rows)
		for row in 0 ..< rows {
			for column in 0 ..< columns {
				let cell = (SIMD2(Float(column), Float(row)) + 0.5) / SIMD2(Float(columns), Float(rows))
				var weighted = SIMD3<Float>.zero, total: Float = 0
				for (index, position) in positions.enumerated() {
					let d = cell - position
					let weight = 1 / (simd_dot(d, d) + 0.015)
					weighted += palette[index] * weight
					total += weight
				}
				var tint = weighted / max(total, 0.0001)
				let peak = max(tint.x, tint.y, tint.z)
				let gain = mix(2.85, 1.2, smoothstep(0.12, 0.85, peak))
				tint = simd_clamp(tint * gain + 0.24, SIMD3(repeating: 0), SIMD3(repeating: 1))
				tints[row * columns + column] = tint
			}
		}
	}

	private static let bayer8: [Float] = [
		0, 48, 12, 60, 3, 51, 15, 63, 32, 16, 44, 28, 35, 19, 47, 31,
		8, 56, 4, 52, 11, 59, 7, 55, 40, 24, 36, 20, 43, 27, 39, 23,
		2, 50, 14, 62, 1, 49, 13, 61, 34, 18, 46, 30, 33, 17, 45, 29,
		10, 58, 6, 54, 9, 57, 5, 53, 42, 26, 38, 22, 41, 25, 37, 21,
	].map { $0 / 64 }
	private static let bayer4: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { $0 / 16 }
	private static let bayer2: [Float] = [0, 2, 3, 1].map { $0 / 4 }

	private static func threshold(column: Int, row: Int, pattern: DitherPattern) -> Float {
		let x = Float(column), y = Float(row)
		func fract(_ v: Float) -> Float { v - v.rounded(.down) }
		switch pattern {
			case .bayer8: return bayer8[(row % 8) * 8 + column % 8]
			case .bayer4: return bayer4[(row % 4) * 4 + column % 4]
			case .bayer2: return bayer2[(row % 2) * 2 + column % 2]
			case .halftone:
				let r = SIMD2(x + y, x - y) * 0.70710678 / 4
				return min(max(simd_length(SIMD2(fract(r.x), fract(r.y)) - 0.5) * 1.41421356, 0), 0.999)
			case .lines: return abs(fract(y / 4) - 0.5) * 2 * 0.999
			case .crosshatch:
				let a = abs(fract((x + y) / 6) - 0.5) * 2, b = abs(fract((x - y) / 6) - 0.5) * 2
				return min(a, b) * 0.999
			case .noise: return fract(52.9829189 * fract(x * 0.06711056 + y * 0.00583715))
			case .none: return 0.25
		}
	}

	// MARK: Shaped cells (gap, corner radius, joined squares)

	private struct MaskKey: Equatable {
		var cellPixels: Int, gap: Float, radius: Float
	}

	/// Coverage masks for one cell: index 16 is the plain shape, 0...15 are the joined variants keyed by neighbour bits
	/// (1 left, 2 right, 4 top, 8 bottom). Computed once per shape, then stamped.
	private func prepareMasks(cellPixels: Int, gap: Float, radius: Float) {
		let key = MaskKey(cellPixels: cellPixels, gap: gap, radius: radius)
		guard key != maskKey else { return }
		maskKey = key
		let size = Float(cellPixels)
		masks = (0 ... 16).map { variant in
			let join = variant < 16
			let hasLeft = join && variant & 1 != 0, hasRight = join && variant & 2 != 0
			let hasTop = join && variant & 4 != 0, hasBottom = join && variant & 8 != 0
			var mask = [UInt8](repeating: 0, count: cellPixels * cellPixels)
			for y in 0 ..< cellPixels {
				for x in 0 ..< cellPixels {
					let point = SIMD2(Float(x) + 0.5, Float(y) + 0.5) - size * 0.5
					let inset = min(gap * size, size * 0.49)
					let half = SIMD2(repeating: max(size * 0.5 - inset, 0.5))
					var r = min(radius * size, min(half.x, half.y))
					if join {
						let leftSide = point.x < 0, topSide = point.y < 0
						if (leftSide && (hasLeft || topSide && hasTop)) || (!leftSide && (hasRight || topSide && hasTop)) ||
							(leftSide && !topSide && (hasLeft || hasBottom)) || (!leftSide && !topSide && (hasRight || hasBottom))
						{
							r = 0
						}
					}
					let q = simd_abs(point) - (half - r)
					let distance = simd_length(simd_max(q, .zero)) + min(max(q.x, q.y), 0) - r
					var shape = 1 - smoothstep(-0.75, 0.75, distance)
					if join, (hasLeft && point.x < -half.x + 1) || (hasRight && point.x > half.x - 1) ||
						(hasTop && point.y < -half.y + 1) || (hasBottom && point.y > half.y - 1)
					{
						shape = 1
					}
					mask[y * cellPixels + x] = UInt8(min(max(shape * 255, 0), 255).rounded())
				}
			}
			return mask
		}
	}

	private func rasterShaped(settings s: DitherSettings, plan: ColorPlan, columns: Int, rows: Int, cellPixels: Int) -> CGImage? {
		prepareMasks(cellPixels: cellPixels, gap: s.gap, radius: s.cornerRadius)
		let width = columns * cellPixels, height = rows * cellPixels
		if pixels.count != width * height { pixels = .init(repeating: 0, count: width * height) }
		let canJoin = s.joinAdjacentSquares && s.gap == 0 && s.cornerRadius > 0
		let background = plan.backgroundPixel
		pixels.withUnsafeMutableBufferPointer { out in
			colors.withUnsafeBufferPointer { colorBuffer in
				alphas.withUnsafeBufferPointer { alphaBuffer in
					let shared = Unchecked((out, colorBuffer, alphaBuffer, masks))
					let chunks = min(rows, workers * 2)
					DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
						let (out, color, alpha, masks) = shared.value
						let start = rows * chunk / chunks, end = rows * (chunk + 1) / chunks
						for row in start ..< end {
							for column in 0 ..< columns {
								let i = row * columns + column
								var variant = 16
								if canJoin, alpha[i] > 0 {
									variant = 0
									if column > 0, alpha[i - 1] > 0 { variant |= 1 }
									if column < columns - 1, alpha[i + 1] > 0 { variant |= 2 }
									if row > 0, alpha[i - columns] > 0 { variant |= 4 }
									if row < rows - 1, alpha[i + columns] > 0 { variant |= 8 }
								}
								let mask = masks[variant]
								let fg = color[i]
								let base = row * cellPixels * width + column * cellPixels
								for y in 0 ..< cellPixels {
									let rowBase = base + y * width
									let maskRow = y * cellPixels
									for x in 0 ..< cellPixels {
										out[rowBase + x] = Self.blend(background, fg, mask[maskRow + x])
									}
								}
							}
						}
					}
				}
			}
		}
		return makeImage(from: pixels, width: width, height: height, opaque: true)
	}

	/// Per-channel `mix(a, b, t / 255)` on packed premultiplied BGRA.
	@inline(__always)
	private static func blend(_ a: UInt32, _ b: UInt32, _ t: UInt8) -> UInt32 {
		if t == 255 { return b }
		if t == 0 { return a }
		let t = UInt32(t), u = 255 - t
		let rb = ((a & 0x00FF_00FF) &* u &+ (b & 0x00FF_00FF) &* t) >> 8 & 0x00FF_00FF
		let ag = ((a >> 8 & 0x00FF_00FF) &* u &+ (b >> 8 & 0x00FF_00FF) &* t) & 0xFF00_FF00
		return rb | ag
	}

	private func makeImage(from buffer: [UInt32], width: Int, height: Int, opaque: Bool) -> CGImage? {
		let data = buffer.withUnsafeBytes { Data($0) } as CFData
		guard let provider = CGDataProvider(data: data) else { return nil }
		let alpha: CGImageAlphaInfo = opaque ? .noneSkipFirst : .premultipliedFirst
		return CGImage(
			width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
			space: Self.colorSpace,
			bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
			provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
		)
	}

	private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
}

// MARK: - Field

/// The per-frame constants of the wave field, and the field function itself.
nonisolated private struct FieldPlan: Sendable {
	let offset: SIMD2<Float>
	let frequency: Float
	let amplitude: Float
	let inverseScale: Float
	let contrast: Float
	let brightness: Float
	let reach: Float
	let cellPixels: Float
	let inverseHeight: Float
	let trail: [SIMD3<Float>]
	let touchActive: Bool
	let touchRadius: Float
	let touchStrength: Float
	let touchWarp: Float
	let noise = Noise.shared

	init(frame: DitherFrame, columns: Int, rows: Int, cellPixels: Int) {
		let s = frame.settings
		offset = frame.offset
		frequency = s.waveFrequency
		amplitude = s.waveAmplitude
		inverseScale = 1 / max(s.scale, 0.05)
		contrast = s.contrast
		brightness = s.brightness
		reach = frame.reveal * 1.5
		self.cellPixels = Float(cellPixels)
		inverseHeight = 1 / Float(rows * cellPixels)
		trail = frame.trail
		touchActive = s.touchEnabled && frame.touchPresence > 0.001 && !frame.trail.isEmpty
		touchRadius = s.touchRadius
		touchStrength = s.touchStrength
		touchWarp = s.touchWarp
	}

	@inline(__always)
	func value(uv: SIMD2<Float>, column: Int, row: Int) -> Float {
		var point = uv
		var touch: Float = 0
		if touchActive {
			let corner = SIMD2(Float(column), Float(row)) * cellPixels
			for (index, sample) in trail.enumerated() where sample.z > 0 {
				let delta = (corner - SIMD2(sample.x, sample.y)) * inverseHeight
				let reach = touchRadius * (0.55 + 0.45 * sample.z)
				let influence = sample.z * (1 - smoothstep(0, reach, simd_length(delta)))
				touch = max(touch, influence)
				if index == 0 {
					point += SIMD2(-delta.y, delta.x) * influence * touchWarp / max(reach, 0.001)
				}
			}
		}
		var value = pattern(point * inverseScale)
		value -= touch * touchStrength * 0.75
		value = (value - 0.5) * contrast + 0.5 + brightness
		let show = min(max((reach - simd_length(uv)) / 0.45, 0), 1)
		return min(max(value, 0), 1) * show * show * (3 - 2 * show)
	}

	@inline(__always)
	private func pattern(_ point: SIMD2<Float>) -> Float {
		let shifted = point - offset
		let warpX = fbm(shifted + SIMD2(17.3, 41.7))
		let warpY = fbm(shifted + SIMD2(73.1, 11.9))
		return fbm(shifted + SIMD2(warpX, warpY) - 0.5)
	}

	@inline(__always)
	private func fbm(_ start: SIMD2<Float>) -> Float {
		var point = start, value: Float = 0, weight: Float = 1
		for _ in 0 ..< 4 {
			value += weight * abs(noise.perlin(point))
			point *= frequency
			weight *= amplitude
			if weight == 0 { break }
		}
		return value
	}
}

/// Classic Perlin noise matching the shader's `cnoise` (mod-289 permutation, Taylor-normalised gradients),
/// with the permutation and gradients folded into lookup tables held by raw pointer so the hot loop does no
/// lazy-initialisation checks, bounds checks or modulo for the second hash.
nonisolated private struct Noise: @unchecked Sendable {
	let permutation: UnsafePointer<Int32>
	let gradients: UnsafePointer<SIMD2<Float>>

	static let shared = Noise()

	private init() {
		// 578 entries so `permutation[permutation[x] + y]` never needs a modulo: the polynomial only depends on v mod 289.
		let perm = UnsafeMutablePointer<Int32>.allocate(capacity: 578)
		for v in 0 ..< 578 {
			perm[v] = Int32((34 * v + 1) * v % 289)
		}
		let grad = UnsafeMutablePointer<SIMD2<Float>>.allocate(capacity: 289)
		for index in 0 ..< 289 {
			var gx = (Float(index) / 41).truncatingRemainder(dividingBy: 1) * 2 - 1
			let gy = abs(gx) - 0.5
			gx -= (gx + 0.5).rounded(.down)
			let g = SIMD2(gx, gy)
			grad[index] = g * (1.79284291400159 - 0.85373472095314 * simd_dot(g, g))
		}
		permutation = UnsafePointer(perm)
		gradients = UnsafePointer(grad)
	}

	@inline(__always)
	func perlin(_ p: SIMD2<Float>) -> Float {
		// Converting a non-finite or enormous float to Int traps; such input can only come from corrupt settings.
		guard abs(p.x) < 1e7, abs(p.y) < 1e7 else { return 0 }
		let floorX = p.x.rounded(.down), floorY = p.y.rounded(.down)
		let fx = p.x - floorX, fy = p.y - floorY
		var ix = Int(floorX) % 289, iy = Int(floorY) % 289
		if ix < 0 { ix += 289 }
		if iy < 0 { iy += 289 }
		let ix1 = ix == 288 ? 0 : ix + 1, iy1 = iy == 288 ? 0 : iy + 1
		let px0 = Int(permutation[ix]), px1 = Int(permutation[ix1])
		let g00 = gradients[Int(permutation[px0 + iy])]
		let g10 = gradients[Int(permutation[px1 + iy])]
		let g01 = gradients[Int(permutation[px0 + iy1])]
		let g11 = gradients[Int(permutation[px1 + iy1])]
		let n00 = g00.x * fx + g00.y * fy
		let n10 = g10.x * (fx - 1) + g10.y * fy
		let n01 = g01.x * fx + g01.y * (fy - 1)
		let n11 = g11.x * (fx - 1) + g11.y * (fy - 1)
		let u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
		let v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
		let nx0 = n00 + (n10 - n00) * u
		let nx1 = n01 + (n11 - n01) * u
		return 2.3 * (nx0 + (nx1 - nx0) * v)
	}
}

// MARK: - Colour

/// Precomputed colours for one frame, and the shader's `quantizedCellColor`.
nonisolated private struct ColorPlan: Sendable {
	let levels: Float
	let strength: Float
	let usesThreshold: Bool
	let gain: Float
	let background: SIMD3<Float>
	let wave: SIMD3<Float>
	let placementBackground: Bool
	let paletteSource: [SIMD3<Float>]
	let palette: [SIMD3<Float>]
	let backgroundPixel: UInt32

	init(settings s: DitherSettings, gain: Float) {
		self.gain = gain
		levels = max(s.colorLevels, 1.01) - 1
		strength = s.ditherStrength
		usesThreshold = s.ditherStrength != 0 && s.pattern != .none
		placementBackground = s.colorPlacement == .background
		let effectiveBackground: SIMD3<Float> = switch s.backgroundStyle {
			case .black: .zero
			case .white: SIMD3(repeating: 1)
			case .dim: s.waveColor.simd * 0.2
			case .custom: s.backgroundColor.simd
		}
		wave = placementBackground ? (s.squareStyle == .black ? .zero : SIMD3(repeating: 1)) : s.waveColor.simd
		background = placementBackground ? s.waveColor.simd : effectiveBackground
		paletteSource = s.palette.map(\.simd)
		palette = placementBackground ? [] : paletteSource
		backgroundPixel = Self.pack(background * gain, alpha: 1)
	}

	@inline(__always)
	func color(value: Float, threshold: Float, outside: Bool, tint: SIMD3<Float>?) -> (UInt32, Float) {
		let t = usesThreshold ? (threshold - 0.25) * strength : 0
		var opacity = value + t / levels
		opacity = min(max(opacity - 0.2 * (1 - smoothstep(0.45, 0.8, opacity)), 0), 1)
		var alpha = (opacity * levels + 0.5).rounded(.down) / levels
		if outside { alpha = 0 }

		let foreground: SIMD3<Float>
		var back = background
		if let tint {
			back = placementBackground ? tint : background
			foreground = placementBackground ? wave : tint
		} else if palette.count > 1 {
			let count = Float(palette.count)
			var pv = value + t / (count - 1)
			pv = min(max(pv - 0.2 * (1 - smoothstep(0.45, 0.8, pv)), 0), 1)
			foreground = palette[min(palette.count - 1, Int((pv * (count - 1) + 0.5).rounded(.down)))]
		} else {
			foreground = wave
		}
		return (Self.pack((back + (foreground - back) * alpha) * gain, alpha: 1), alpha)
	}

	/// Packs into premultiplied BGRA (little-endian ARGB).
	@inline(__always)
	static func pack(_ c: SIMD3<Float>, alpha: Float) -> UInt32 {
		@inline(__always) func byte(_ v: Float) -> UInt32 { UInt32(min(max(v * 255 + 0.5, 0), 255)) }
		return byte(alpha) << 24 | byte(c.x) << 16 | byte(c.y) << 8 | byte(c.z)
	}
}

// MARK: - Helpers

@inline(__always)
nonisolated func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
	let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
	return t * t * (3 - 2 * t)
}

@inline(__always)
nonisolated func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

/// Lets row-disjoint buffer pointers cross into `concurrentPerform`.
nonisolated private struct Unchecked<T>: @unchecked Sendable {
	let value: T
	init(_ value: T) { self.value = value }
}
