import Foundation
import SwiftUI

// MARK: - Color

/// A plain sRGB colour that is cheap to copy, compare, interpolate and encode.
nonisolated struct RGB: Codable, Hashable, Sendable {
	var r: Float
	var g: Float
	var b: Float

	init(_ r: Float, _ g: Float, _ b: Float) {
		self.r = r
		self.g = g
		self.b = b
	}

	init(hex: UInt32) {
		self.init(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
	}

	static let black = RGB(0, 0, 0)
	static let white = RGB(1, 1, 1)

	var simd: SIMD3<Float> { SIMD3(r, g, b) }

	var color: Color { Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b)) }

	func clamped() -> RGB {
		func c(_ v: Float) -> Float { v.isFinite ? min(max(v, 0), 1) : 0.5 }
		return RGB(c(r), c(g), c(b))
	}

	func mixed(_ other: RGB, _ t: Float) -> RGB {
		RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
	}
}

#if os(iOS)
	extension RGB {
		init(_ color: Color) {
			let resolved = color.resolve(in: EnvironmentValues())
			self.init(resolved.red, resolved.green, resolved.blue)
			self = clamped()
		}
	}
#endif

// MARK: - Enumerations

nonisolated enum DitherPattern: Int, Codable, CaseIterable, Identifiable, Sendable {
	case bayer8, bayer4, bayer2, halftone, lines, crosshatch, noise, none
	var id: Int { rawValue }
	var title: String {
		switch self {
			case .bayer8: "Bayer 8×8"
			case .bayer4: "Bayer 4×4"
			case .bayer2: "Bayer 2×2"
			case .halftone: "Halftone"
			case .lines: "Lines"
			case .crosshatch: "Crosshatch"
			case .noise: "Noise"
			case .none: "None"
		}
	}
}

nonisolated enum BackgroundStyle: String, Codable, CaseIterable, Identifiable, Sendable {
	case custom, black, white, dim
	var id: String { rawValue }
	var title: String {
		switch self {
			case .custom: "Custom"
			case .black: "Black"
			case .white: "White"
			case .dim: "Dimmed Wave"
		}
	}
}

nonisolated enum ColorPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
	case squares, background
	var id: String { rawValue }
	var title: String { self == .squares ? "Squares" : "Background" }
}

nonisolated enum SquareStyle: String, Codable, CaseIterable, Identifiable, Sendable {
	case white, black
	var id: String { rawValue }
	var title: String { self == .white ? "White" : "Black" }
}

nonisolated enum FrameRate: Int, CaseIterable, Identifiable, Sendable {
	case low = 7, medium = 12, high = 25
	var id: Int { rawValue }
	var title: String {
		switch self {
			case .low: "Low"
			case .medium: "Medium"
			case .high: "High"
		}
	}

	static func nearest(_ fps: Int) -> FrameRate {
		allCases.min { abs($0.rawValue - fps) < abs($1.rawValue - fps) } ?? .medium
	}
}

// MARK: - Dither settings

/// Every adjustable property of the dither field. Mirrors Ergo's `DitherConfiguration`,
/// minus the Metal-only knobs, plus the watch-specific ones.
nonisolated struct DitherSettings: Codable, Equatable, Sendable {
	// Wave
	var waveSpeed: Float = 0.05
	var waveDirection: Float = 135
	var waveFrequency: Float = 3
	var waveAmplitude: Float = 0.3
	var scale: Float = 1
	var contrast: Float = 1
	var brightness: Float = 0

	// Motion
	var framesPerSecond = FrameRate.medium.rawValue
	var intro = true
	var replayIntroOnWake = false
	/// Turning the Digital Crown on the watch steps through the presets.
	var crownSwitchesPresets = true

	// Cells
	/// Cell edge in points. The watch never draws a cell smaller than 3×3 physical pixels.
	var cellSize: Float = 2.5
	var colorLevels: Float = 4
	var pattern: DitherPattern = .bayer8
	var ditherStrength: Float = 1
	var gap: Float = 0
	var cornerRadius: Float = 0
	var joinAdjacentSquares = false

	// Colour
	var waveColor = RGB(0.12, 0.85, 1)
	var backgroundColor = RGB(0.02, 0.01, 0.08)
	var backgroundStyle: BackgroundStyle = .custom
	var colorPlacement: ColorPlacement = .squares
	var squareStyle: SquareStyle = .white
	var palette: [RGB] = [RGB(0.12, 0.85, 1), RGB(0.55, 0.18, 1), RGB(1, 0.2, 0.55), RGB(1, 0.72, 0.18)]
	/// Blends the palette spatially across the screen instead of by brightness (Ergo's theme colours).
	var colorField = false

	// Composition
	/// Blur in physical pixels, 0...10.
	var blur: Float = 0
	/// The user's choice; only honoured while blur is zero (see `clipsToScreenCorners`).
	var avoidScreenCorners = true
	var alwaysOnBrightness: Float = 0.6

	// Touch
	var touchEnabled = false
	var touchRadius: Float = 0.5
	var touchStrength: Float = 1
	var touchResponse: Float = 0.28
	var touchTrail: Float = 0.7
	var touchFade: Float = 0.8
	var touchWarp: Float = 0.15

	static let maxPaletteCount = 8
	static let minimumCellPixels = 3
	static let maxWaveSpeed: Float = 0.066
	/// How long the field takes to coast to a stop when the wrist goes down.
	static let wristDownSlowdown: Float = 1.2

	var frameRate: FrameRate { FrameRate.nearest(framesPerSecond) }
	/// A blurred field has soft edges anyway, so cells are never kept clear of the screen corners then.
	var clipsToScreenCorners: Bool { avoidScreenCorners && blur == 0 }

	init() {}

	init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		let d = DitherSettings()
		waveSpeed = c.value(.waveSpeed, d.waveSpeed)
		waveDirection = c.value(.waveDirection, d.waveDirection)
		waveFrequency = c.value(.waveFrequency, d.waveFrequency)
		waveAmplitude = c.value(.waveAmplitude, d.waveAmplitude)
		scale = c.value(.scale, d.scale)
		contrast = c.value(.contrast, d.contrast)
		brightness = c.value(.brightness, d.brightness)
		framesPerSecond = c.value(.framesPerSecond, d.framesPerSecond)
		intro = c.value(.intro, d.intro)
		replayIntroOnWake = c.value(.replayIntroOnWake, d.replayIntroOnWake)
		crownSwitchesPresets = c.value(.crownSwitchesPresets, d.crownSwitchesPresets)
		cellSize = c.value(.cellSize, d.cellSize)
		colorLevels = c.value(.colorLevels, d.colorLevels)
		pattern = c.value(.pattern, d.pattern)
		ditherStrength = c.value(.ditherStrength, d.ditherStrength)
		gap = c.value(.gap, d.gap)
		cornerRadius = c.value(.cornerRadius, d.cornerRadius)
		joinAdjacentSquares = c.value(.joinAdjacentSquares, d.joinAdjacentSquares)
		waveColor = c.value(.waveColor, d.waveColor)
		backgroundColor = c.value(.backgroundColor, d.backgroundColor)
		backgroundStyle = c.value(.backgroundStyle, d.backgroundStyle)
		colorPlacement = c.value(.colorPlacement, d.colorPlacement)
		squareStyle = c.value(.squareStyle, d.squareStyle)
		palette = c.value(.palette, d.palette)
		colorField = c.value(.colorField, d.colorField)
		blur = c.value(.blur, d.blur)
		avoidScreenCorners = c.value(.avoidScreenCorners, d.avoidScreenCorners)
		alwaysOnBrightness = c.value(.alwaysOnBrightness, d.alwaysOnBrightness)
		touchEnabled = c.value(.touchEnabled, d.touchEnabled)
		touchRadius = c.value(.touchRadius, d.touchRadius)
		touchStrength = c.value(.touchStrength, d.touchStrength)
		touchResponse = c.value(.touchResponse, d.touchResponse)
		touchTrail = c.value(.touchTrail, d.touchTrail)
		touchFade = c.value(.touchFade, d.touchFade)
		touchWarp = c.value(.touchWarp, d.touchWarp)
	}

	/// Clamps every value into the range the renderer supports.
	func bounded() -> DitherSettings {
		var v = self
		func f(_ x: Float, _ fallback: Float, _ r: ClosedRange<Float>) -> Float {
			min(max(x.isFinite ? x : fallback, r.lowerBound), r.upperBound)
		}
		v.waveSpeed = f(waveSpeed, 0.05, 0 ... Self.maxWaveSpeed)
		v.waveDirection = Self.snappedDirection(waveDirection)
		v.waveFrequency = f(waveFrequency, 3, 0.01 ... 12)
		v.waveAmplitude = f(waveAmplitude, 0.3, 0 ... 1)
		v.scale = f(scale, 1, 0.05 ... 32)
		v.contrast = f(contrast, 1, 0.01 ... 8)
		v.brightness = f(brightness, 0, -1 ... 1)
		v.framesPerSecond = FrameRate.nearest(framesPerSecond).rawValue
		v.cellSize = f(cellSize, 2.5, 1.5 ... 16)
		v.colorLevels = f(colorLevels, 4, 2 ... 16)
		v.ditherStrength = f(ditherStrength, 1, 0 ... 1)
		v.gap = f(gap, 0, 0 ... 0.45)
		v.cornerRadius = f(cornerRadius, 0, 0 ... 0.5)
		v.waveColor = waveColor.clamped()
		v.backgroundColor = backgroundColor.clamped()
		v.palette = palette.prefix(Self.maxPaletteCount).map { $0.clamped() }
		v.blur = f(blur, 0, 0 ... 10)
		v.alwaysOnBrightness = f(alwaysOnBrightness, 0.6, 0.1 ... 1)
		v.touchRadius = f(touchRadius, 0.5, 0.05 ... 2)
		v.touchStrength = f(touchStrength, 1, -2 ... 2)
		v.touchResponse = f(touchResponse, 0.28, 0.05 ... 1)
		v.touchTrail = f(touchTrail, 0.7, 0 ... 2)
		v.touchFade = f(touchFade, 0.8, 0.1 ... 3)
		v.touchWarp = f(touchWarp, 0.15, 0 ... 1)
		return v
	}

	/// True when the two have the same look, ignoring the crown switch (a preset doesn't carry the user's choice).
	func matches(_ other: DitherSettings) -> Bool {
		var copy = self
		copy.crownSwitchesPresets = other.crownSwitchesPresets
		return copy == other
	}

	/// A mix of this look and `target` (`fraction` 0 ... 1) for scrubbing between presets: everything that can vary
	/// smoothly does; the rest (pattern, cell size, direction, styles) flips at the halfway point.
	func blended(to target: DitherSettings, _ fraction: Float) -> DitherSettings {
		var v = fraction < 0.5 ? self : target
		v.crownSwitchesPresets = crownSwitchesPresets
		func l(_ a: Float, _ b: Float) -> Float { a + (b - a) * fraction }
		v.waveSpeed = l(waveSpeed, target.waveSpeed)
		v.waveFrequency = l(waveFrequency, target.waveFrequency)
		v.waveAmplitude = l(waveAmplitude, target.waveAmplitude)
		v.scale = l(scale, target.scale)
		v.contrast = l(contrast, target.contrast)
		v.brightness = l(brightness, target.brightness)
		v.colorLevels = l(colorLevels, target.colorLevels)
		v.ditherStrength = l(ditherStrength, target.ditherStrength)
		v.gap = l(gap, target.gap)
		v.cornerRadius = l(cornerRadius, target.cornerRadius)
		v.blur = l(blur, target.blur)
		v.waveColor = waveColor.mixed(target.waveColor, fraction)
		v.backgroundColor = backgroundColor.mixed(target.backgroundColor, fraction)
		if palette.count == target.palette.count {
			v.palette = zip(palette, target.palette).map { $0.mixed($1, fraction) }
		}
		return v
	}

	static func snappedDirection(_ degrees: Float) -> Float {
		guard degrees.isFinite else { return 135 }
		let n = degrees.truncatingRemainder(dividingBy: 360)
		let snapped = ((n >= 0 ? n : n + 360) / 45).rounded() * 45
		return snapped >= 360 ? 0 : snapped
	}

	var directionVector: SIMD2<Float> {
		let radians = Self.snappedDirection(waveDirection) * .pi / 180
		return SIMD2(sin(radians), -cos(radians)) * Float(2).squareRoot()
	}

	/// Moves colours and a few soft values towards `target` by `t`, and snaps everything else.
	/// The wave's shape (speed, frequency, scale…) always snaps: gliding those sweeps the whole field for a second or
	/// two, which feels laggy while dragging a slider.
	func interpolated(to target: DitherSettings, _ t: Float) -> DitherSettings {
		var v = target
		func l(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
		v.ditherStrength = l(ditherStrength, target.ditherStrength)
		v.colorLevels = l(colorLevels, target.colorLevels)
		v.blur = l(blur, target.blur)
		v.waveColor = waveColor.mixed(target.waveColor, t)
		v.backgroundColor = backgroundColor.mixed(target.backgroundColor, t)
		if palette.count == target.palette.count {
			v.palette = zip(palette, target.palette).map { $0.mixed($1, t) }
		}
		return v
	}

	/// Largest distance between the continuous values of two settings, to know when a glide has settled.
	func distance(to o: DitherSettings) -> Float {
		var d: Float = 0
		for pair in [(ditherStrength, o.ditherStrength), (colorLevels / 16, o.colorLevels / 16), (blur / 10, o.blur / 10)]
		{
			d = max(d, abs(pair.0 - pair.1))
		}
		let colors = [(waveColor, o.waveColor), (backgroundColor, o.backgroundColor)] + (palette.count == o.palette.count ? Array(zip(palette, o.palette)) : [])
		for (a, b) in colors {
			d = max(d, abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
		}
		return d
	}
}

// MARK: - Clock settings

nonisolated enum ClockFontDesign: String, Codable, CaseIterable, Identifiable, Sendable {
	// System faces.
	case rounded, standard, serif, monospaced, condensed, expanded
	// Digits drawn by Stipple itself.
	case pixel, chunky, dots, segment, line, italic, outline

	var id: String { rawValue }
	var title: String {
		switch self {
			case .standard: "Standard"
			case .segment: "7-Segment"
			case .line: "Monoline"
			case .dots: "Dot Matrix"
			default: rawValue.capitalized
		}
	}

	/// Digits Stipple draws as shapes, rather than text in a system font.
	var isDrawn: Bool { ![.rounded, .standard, .serif, .monospaced, .condensed, .expanded].contains(self) }

	/// The system design used for text (the date, and the time for system faces). Drawn faces pair with the date
	/// style closest to them.
	var design: Font.Design {
		switch self {
			case .rounded, .line, .dots, .chunky: .rounded
			case .standard, .condensed, .expanded, .italic, .outline: .default
			case .monospaced, .pixel, .segment: .monospaced
			case .serif: .serif
		}
	}

	/// Horizontal stretch for the system faces. `Font.Width` has no effect on watchOS's SF Compact (and little on
	/// phone previews), so widths are applied as a real stretch that looks the same on both.
	var stretch: CGFloat {
		switch self {
			case .condensed: 0.8
			case .expanded: 1.25
			default: 1
		}
	}
}

nonisolated enum ClockWeight: String, Codable, CaseIterable, Identifiable, Sendable {
	case thin, light, regular, medium, semibold, bold, heavy, black
	var id: String { rawValue }
	var title: String { rawValue.capitalized }
	var weight: Font.Weight {
		switch self {
			case .thin: .thin
			case .light: .light
			case .regular: .regular
			case .medium: .medium
			case .semibold: .semibold
			case .bold: .bold
			case .heavy: .heavy
			case .black: .black
		}
	}
}

nonisolated enum ClockEffect: String, Codable, CaseIterable, Identifiable, Sendable {
	/// Solid text over the dither.
	case overlay
	/// The dither only shows through the time.
	case window
	/// The time is drawn as Liquid Glass digits over the dither.
	case glass
	var id: String { rawValue }
	var title: String {
		switch self {
			case .overlay: "Overlay"
			case .window: "Window"
			case .glass: "Glass"
		}
	}
}

nonisolated enum ClockLayout: String, Codable, CaseIterable, Identifiable, Sendable {
	case inline, stacked
	var id: String { rawValue }
	var title: String { self == .inline ? "Inline" : "Stacked" }
}

/// Which of the screen's nine regions the clock is docked to.
nonisolated enum ClockDock: String, Codable, CaseIterable, Identifiable, Sendable {
	case topLeading, top, topTrailing
	case leading, center, trailing
	case bottomLeading, bottom, bottomTrailing

	var id: String { rawValue }
	/// 0 = top, 1 = middle, 2 = bottom.
	var row: Int { Self.allCases.firstIndex(of: self)! / 3 }
	/// 0 = leading, 1 = middle, 2 = trailing.
	var column: Int { Self.allCases.firstIndex(of: self)! % 3 }

	init(row: Int, column: Int) {
		self = Self.allCases[min(2, max(0, row)) * 3 + min(2, max(0, column))]
	}

	var title: String {
		switch self {
			case .topLeading: "Top Left"
			case .top: "Top"
			case .topTrailing: "Top Right"
			case .leading: "Left"
			case .center: "Center"
			case .trailing: "Right"
			case .bottomLeading: "Bottom Left"
			case .bottom: "Bottom"
			case .bottomTrailing: "Bottom Right"
		}
	}
}

nonisolated struct ClockSettings: Codable, Equatable, Sendable {
	var enabled = false
	var dock: ClockDock = .center
	var layout: ClockLayout = .inline
	var effect: ClockEffect = .overlay
	var fontDesign: ClockFontDesign = .rounded
	var weight: ClockWeight = .semibold
	var size: Float = 0.42
	var color = RGB.white
	var showSeconds = false
	var use24Hour = false
	var showDate = false
	var shadow = true

	init() {}

	init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		let d = ClockSettings()
		enabled = c.value(.enabled, d.enabled)
		dock = c.value(.dock, d.dock)
		layout = c.value(.layout, d.layout)
		effect = c.value(.effect, d.effect)
		fontDesign = c.value(.fontDesign, d.fontDesign)
		weight = c.value(.weight, d.weight)
		size = c.value(.size, d.size)
		color = c.value(.color, d.color)
		showSeconds = c.value(.showSeconds, d.showSeconds)
		use24Hour = c.value(.use24Hour, d.use24Hour)
		showDate = c.value(.showDate, d.showDate)
		shadow = c.value(.shadow, d.shadow)
	}
}

// MARK: - Whole configuration

nonisolated struct StippleConfig: Codable, Equatable, Sendable {
	var dither = DitherSettings()
	var clock = ClockSettings()

	init() {}

	init(from decoder: any Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		dither = c.value(.dither, DitherSettings())
		clock = c.value(.clock, ClockSettings())
	}

	static let defaultsKey = "stipple.config"

	func encoded() -> Data? { try? JSONEncoder().encode(self) }

	static func decode(_ data: Data?) -> StippleConfig? {
		guard let data else { return nil }
		return try? JSONDecoder().decode(StippleConfig.self, from: data)
	}

	static func loadSaved() -> StippleConfig {
		decode(UserDefaults.standard.data(forKey: defaultsKey)) ?? StippleConfig()
	}

	func save() {
		UserDefaults.standard.set(encoded(), forKey: Self.defaultsKey)
	}
}

private extension KeyedDecodingContainer {
	/// Decodes a key, falling back to `fallback` when it is missing or malformed, so older payloads keep working.
	nonisolated func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
		((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
	}
}
