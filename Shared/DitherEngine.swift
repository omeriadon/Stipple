import CoreGraphics
import Foundation
import Observation
import simd

/// Owns the render loop. The loop only runs while something is actually changing (the wave is moving, the intro is
/// revealing, a setting is gliding, or a finger is down) and stops completely once the field has coasted to rest,
/// so a lowered wrist costs nothing after the slow-down finishes.
@MainActor
@Observable
final class DitherEngine {
	/// The latest frame. Read only by `DitherBitmap`, so a new frame invalidates just that one view.
	private(set) var image: CGImage?
	private(set) var layout = Layout()

	struct Layout: Equatable {
		var columns = 0
		var rows = 0
		var cellPixels = 3
		var scale: CGFloat = 2
		/// Grid size in points. Slightly larger than the viewport so cells always reach the edges.
		var gridSize: CGSize = .zero
		/// Whole-pixel offset of the grid inside the viewport, in points, so every cell stays pixel aligned.
		var gridOffset: CGSize = .zero
		var originPixels: SIMD2<Float> = .zero
		var viewportPixels: SIMD2<Float> = .zero
		var cornerRadiusPixels: Float = 0
	}

	@ObservationIgnored private var target = DitherSettings()
	@ObservationIgnored private var current = DitherSettings()
	@ObservationIgnored private var hasSettings = false
	@ObservationIgnored private var offset: SIMD2<Float> = .zero
	@ObservationIgnored private var reveal: Float = 1
	/// Linear 0...1 progress of the speed ramp; the actual speed is a smoothstep of it, so it eases both ways.
	@ObservationIgnored private var ramp: Float = 1
	private static let touchFramesPerSecond = 50
	@ObservationIgnored private var touch = DitherTouch()
	@ObservationIgnored private var touchLocation: SIMD2<Float>?
	@ObservationIgnored private var loop: Task<Void, Never>?
	@ObservationIgnored private var needsFrame = true
	@ObservationIgnored private let worker = RenderWorker()

	/// Brightness multiplier for the rendered field (1 = as designed).
	@ObservationIgnored var gain: Float = 1 { didSet { if gain != oldValue { needsFrame = true; wake() } } }
	@ObservationIgnored var isAwake = true { didSet { if isAwake != oldValue { awakeChanged() } } }
	@ObservationIgnored var reduceMotion = false { didSet { if reduceMotion != oldValue { wake() } } }
	/// False only when the app is truly backgrounded.
	@ObservationIgnored var sceneActive = true { didSet { if sceneActive != oldValue { updateVisibility() } } }
	@ObservationIgnored private var surfaces = 0
	@ObservationIgnored private var isVisible = false
	@ObservationIgnored private var loopID = 0

	func surfaceAppeared() {
		surfaces += 1
		updateVisibility()
	}

	/// Deferred a tick, so a surface being re-wrapped (clock effect changes) appears before the old one leaves.
	func surfaceDisappeared() {
		surfaces = max(0, surfaces - 1)
		Task { @MainActor [weak self] in self?.updateVisibility() }
	}

	private func updateVisibility() {
		let visible = sceneActive && surfaces > 0
		guard visible != isVisible else { return }
		isVisible = visible
		visibilityChanged()
	}

	init() {}

	// MARK: Inputs

	func setSettings(_ settings: DitherSettings) {
		let bounded = settings.bounded()
		guard bounded != target || !hasSettings else { return }
		let first = !hasSettings
		hasSettings = true
		let geometryChanged = bounded.cellSize != target.cellSize
		target = bounded
		if first {
			current = bounded
			reveal = bounded.intro ? 0 : 1
			ramp = 1
		} else {
			// Discrete values snap now; continuous ones glide over the next few frames.
			current = current.interpolated(to: bounded, 0)
			if !bounded.intro { reveal = 1 }
		}
		if geometryChanged || first { recomputeLayout() }
		needsFrame = true
		wake()
	}

	@ObservationIgnored private var viewport: CGSize = .zero
	@ObservationIgnored private var cornerRadius: CGFloat = 0

	func setViewport(_ size: CGSize, scale: CGFloat, cornerRadius: CGFloat) {
		guard size != viewport || scale != layout.scale || cornerRadius != self.cornerRadius else { return }
		viewport = size
		layout.scale = scale
		self.cornerRadius = cornerRadius
		recomputeLayout()
		needsFrame = true
		wake()
	}

	/// `point` is in the surface's local coordinates, in points. `nil` lifts the finger.
	func setTouch(_ point: CGPoint?) {
		touchLocation = point.map {
			SIMD2(Float($0.x * layout.scale), Float($0.y * layout.scale)) + layout.originPixels
		}
		wake()
	}

	// MARK: Layout

	private func recomputeLayout() {
		let scale = max(layout.scale, 1)
		let widthPixels = viewport.width * scale, heightPixels = viewport.height * scale
		guard widthPixels >= 1, heightPixels >= 1 else { return }
		let cellPixels = max(DitherSettings.minimumCellPixels, Int((CGFloat(target.cellSize) * scale).rounded()))
		let columns = Int((widthPixels / CGFloat(cellPixels)).rounded(.up))
		let rows = Int((heightPixels / CGFloat(cellPixels)).rounded(.up))
		let gridWidth = CGFloat(columns * cellPixels), gridHeight = CGFloat(rows * cellPixels)
		let overflowX = ((gridWidth - widthPixels) / 2).rounded(.down)
		let overflowY = ((gridHeight - heightPixels) / 2).rounded(.down)
		layout = Layout(
			columns: columns,
			rows: rows,
			cellPixels: cellPixels,
			scale: scale,
			gridSize: CGSize(width: gridWidth / scale, height: gridHeight / scale),
			gridOffset: CGSize(width: -overflowX / scale, height: -overflowY / scale),
			originPixels: SIMD2(Float(overflowX), Float(overflowY)),
			viewportPixels: SIMD2(Float(widthPixels), Float(heightPixels)),
			cornerRadiusPixels: Float(cornerRadius * scale)
		)
	}

	// MARK: Loop

	private var wantsMotion: Bool {
		isAwake && isVisible && !reduceMotion
	}

	private func awakeChanged() {
		if !isAwake {
			touchLocation = nil
		}
		if isAwake, target.replayIntroOnWake, target.intro {
			reveal = 0
		}
		wake()
	}

	private func visibilityChanged() {
		if !isVisible {
			// Backgrounded: no coast, nobody is looking.
			ramp = 0
			loop?.cancel()
			loop = nil
			touch = DitherTouch()
			touchLocation = nil
		} else {
			needsFrame = true
			wake()
		}
	}

	private func wake() {
		guard isVisible, hasSettings, loop == nil, layout.columns > 0 else { return }
		loopID += 1
		let id = loopID
		loop = Task { [weak self] in
			await self?.run(id: id)
		}
	}

	private func run(id: Int) async {
		let clock = ContinuousClock()
		var last = clock.now
		while !Task.isCancelled {
			let start = clock.now
			// Clamped so a throttled or suspended process never jumps the field on resume.
			let dt = Float(min(max((start - last) / .seconds(1), 0), 0.1))
			last = start

			let moving = step(dt: dt, now: CACurrentMediaTimeShim())
			let frame = makeFrame()
			needsFrame = false
			let renderStart = clock.now
			let rendered = await worker.render(frame)
			let renderTime = clock.now - renderStart
			guard !Task.isCancelled else { break }
			// Never swap a good frame for nothing: a blank frame would flash black and fade back in.
			if let rendered { image = rendered }

			if !moving, !needsFrame { break }
			// CPU budget: always rest at least as long as the frame took to render (<= 50% duty cycle), and slow down
			// further when the device is hot. watchOS kills apps that hold the CPU, so a slow frame (an unoptimised
			// build, a huge grid) lowers the frame rate instead of pinning both cores.
			// While a finger is dragging the field, render smoother than the chosen rate. The duty-cycle cap below still
			// bounds the CPU use if frames are slow.
			let fps = touchLocation != nil && target.touchEnabled ? max(target.framesPerSecond, Self.touchFramesPerSecond) : target.framesPerSecond
			var interval = Duration.seconds(1 / Double(fps))
			switch ProcessInfo.processInfo.thermalState {
				case .serious: interval *= 2
				case .critical: interval *= 4
				default: break
			}
			let rest = max(renderTime, Duration.milliseconds(4))
			try? await Task.sleep(until: max(start + interval, clock.now + rest), clock: clock)
		}
		// A cancelled run must not clear (or restart over) a newer loop.
		guard id == loopID else { return }
		loop = nil
		// Something may have changed while the last frame was rendering.
		if needsFrame || wantsMotion && ramp < 1 || touchLocation != nil {
			wake()
		}
	}

	/// Advances time. Returns whether anything is still changing.
	private func step(dt: Float, now: TimeInterval) -> Bool {
		// Speed ramp: coast down when the wrist lowers (or animation is turned off), ease back up when it rises.
		if wantsMotion {
			ramp = min(1, ramp + dt / 0.6)
		} else {
			let duration = DitherSettings.wristDownSlowdown
			ramp = duration > 0 ? max(0, ramp - dt / duration) : 0
		}
		let speed = ramp * ramp * (3 - 2 * ramp)
		if speed > 0 {
			offset += current.directionVector * current.waveSpeed * speed * dt
			// The noise repeats every 289 lattice units at the base octave; wrapping keeps float precision over long sessions.
			if current.waveFrequency.rounded() == current.waveFrequency {
				offset.x = offset.x.truncatingRemainder(dividingBy: 289)
				offset.y = offset.y.truncatingRemainder(dividingBy: 289)
			}
		}

		var revealing = false
		if reveal < 1 {
			reveal = isAwake ? min(1, reveal + dt / 1.8) : 1
			revealing = reveal < 1
		}

		var gliding = false
		if current != target {
			current = current.interpolated(to: target, 1 - exp(-dt / 0.18))
			if current.distance(to: target) < 0.002 { current = target } else { gliding = true }
		}

		let touching = touch.advance(location: touchLocation, now: now, settings: current)

		return speed > 0 || (wantsMotion && ramp < 1) || revealing || gliding || touching
	}

	private func makeFrame() -> DitherFrame {
		let state = touch.state
		return DitherFrame(
			settings: current,
			columns: layout.columns,
			rows: layout.rows,
			cellPixels: layout.cellPixels,
			offset: offset,
			reveal: reveal,
			trail: state.trail,
			touchPresence: state.presence,
			screenOrigin: layout.originPixels,
			screenSize: layout.viewportPixels,
			screenCornerRadius: layout.cornerRadiusPixels,
			gain: gain
		)
	}
}

/// Renders on its own serial GCD queue rather than in an actor: a frame can take a while on a watch, and blocking
/// one of Swift concurrency's few cooperative threads for that long starves the rest of the app.
nonisolated private final class RenderWorker: @unchecked Sendable {
	private let renderer = DitherRenderer()
	private let queue = DispatchQueue(label: "Stipple.render", qos: .userInitiated)

	func render(_ frame: DitherFrame) async -> CGImage? {
		await withCheckedContinuation { continuation in
			queue.async {
				continuation.resume(returning: self.renderer.render(frame))
			}
		}
	}
}

@inline(__always)
private func CACurrentMediaTimeShim() -> TimeInterval {
	ProcessInfo.processInfo.systemUptime
}

// MARK: - Touch

/// Port of Ergo's cursor interaction: a springy follow point plus an eight-sample fading trail.
struct DitherTouch {
	private var position: SIMD2<Float>?
	private var lastTime: TimeInterval?
	private var presence: Float = 0
	private var history: [(time: TimeInterval, position: SIMD2<Float>)] = []
	private(set) var state: (trail: [SIMD3<Float>], presence: Float) = ([], 0)

	/// Returns whether the touch effect is still visible.
	mutating func advance(location: SIMD2<Float>?, now: TimeInterval, settings: DitherSettings) -> Bool {
		guard settings.touchEnabled else {
			if position != nil || presence > 0 { self = DitherTouch() }
			return false
		}
		let delta = Float(max(0, now - (lastTime ?? now)))
		lastTime = now
		if let location {
			if let previous = position {
				position = previous + (location - previous) * (1 - exp(-delta / settings.touchResponse))
			} else {
				position = location
			}
			presence = 1
		} else {
			presence = max(0, presence - delta / settings.touchFade)
		}
		guard let position, presence > 0 else {
			self = DitherTouch()
			return false
		}
		history.append((now, position))
		let cutoff = now - TimeInterval(settings.touchTrail)
		while history.count > 1, history[1].time < cutoff {
			history.removeFirst()
		}
		var trail: [SIMD3<Float>] = []
		trail.reserveCapacity(8)
		for index in 0 ..< 8 {
			let fraction = Float(index) / 7
			let sample = interpolated(at: now - TimeInterval(settings.touchTrail * fraction))
			trail.append(SIMD3(sample.x, sample.y, presence * (1 - fraction * 0.8)))
		}
		state = (trail, presence)
		return true
	}

	private func interpolated(at time: TimeInterval) -> SIMD2<Float> {
		guard var previous = history.first else { return .zero }
		for sample in history.dropFirst() {
			if sample.time >= time {
				let duration = sample.time - previous.time
				let blend = duration > 0 ? Float(min(1, max(0, (time - previous.time) / duration))) : 1
				return previous.position + (sample.position - previous.position) * blend
			}
			previous = sample
		}
		return previous.position
	}
}
