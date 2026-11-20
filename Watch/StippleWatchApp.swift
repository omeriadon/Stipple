import SwiftUI

@main
struct StippleWatchApp: App {
	var body: some Scene {
		WindowGroup {
			WatchRoot()
		}
	}
}

/// No chrome, no settings: just the field, edge to edge. Everything is configured from the phone, and the Digital
/// Crown scrubs through the presets: the look blends toward the next preset as you turn, and the change is sent to the
/// phone once it lands.
struct WatchRoot: View {
	@State private var store = ConfigStore.shared
	@State private var crown = 0.0
	/// Signed progress toward the neighbouring preset (positive is the next one): -1 ... 1.
	@State private var progress = 0.0
	@State private var settleTask: Task<Void, Never>?

	/// Crown travel for one whole preset.
	private static let crownSpanPerPreset = 5.0
	/// One haptic tick per detent: five per preset.
	private static let crownDetent = 1.0
	private static let crownRange = 50.0

	/// The preset the crown would blend toward in this direction.
	private func neighbour(_ step: Int) -> Preset? {
		let presets = PresetStore.shared.all
		guard !presets.isEmpty else { return nil }
		let current = store.config.dither.bounded()
		let index = presets.firstIndex { $0.settings.matches(current) } ?? (step > 0 ? -1 : presets.count)
		return presets[(index + step + presets.count) % presets.count]
	}

	/// What's on screen: the saved look, or the blend while the crown is mid-way between two presets.
	private var shown: StippleConfig {
		var config = store.config
		guard progress != 0, config.dither.crownSwitchesPresets, let target = neighbour(progress > 0 ? 1 : -1) else { return config }
		config.dither = config.dither.blended(to: target.settings, Float(abs(progress)))
		return config
	}

	var body: some View {
		GeometryReader { proxy in
			StippleScreen(
				config: shown,
				// watchOS has no API for the display's corner radius; this tracks the rounded-rectangle displays closely.
				screenCornerRadius: min(proxy.size.width, proxy.size.height) * 0.22
			)
		}
		.ignoresSafeArea()
		.persistentSystemOverlays(.hidden)
		.hidingStatusBarInDevelopment()
		.focusable()
		// The crown's own detent ticks are the haptics: light, and in step with the turn.
		// A small, wrapping range: the crown builds a table of detents for its range, so a huge one exhausts the watch's memory.
		.digitalCrownRotation($crown, from: 0, through: Self.crownRange, by: Self.crownDetent, sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: true)
		.onChange(of: crown) { old, new in
			// The value wraps around the range, so a jump across the seam is really a small step.
			var delta = new - old
			if delta > Self.crownRange / 2 { delta -= Self.crownRange }
			if delta < -Self.crownRange / 2 { delta += Self.crownRange }
			crownMoved(by: delta)
		}
	}

	private func crownMoved(by delta: Double) {
		guard store.config.dither.crownSwitchesPresets else { return }
		settleTask?.cancel()
		progress += delta / Self.crownSpanPerPreset
		// Past a whole preset: it lands, and the rest of the turn heads for the one after.
		while abs(progress) >= 1 {
			let step = progress > 0 ? 1 : -1
			land(step)
			progress -= Double(step)
		}
		// Let go part-way and it finishes the nearer preset by itself.
		settleTask = Task { await settle() }
	}

	/// Makes the neighbouring preset the real, saved look (and so sends it to the phone).
	private func land(_ step: Int) {
		guard let next = neighbour(step) else { return }
		var look = next.settings
		look.crownSwitchesPresets = store.config.dither.crownSwitchesPresets
		store.config.dither = look
	}

	private func settle() async {
		try? await Task.sleep(for: .milliseconds(220))
		guard !Task.isCancelled, progress != 0 else { return }
		let start = progress
		let goal = abs(start) >= 0.5 ? (start > 0 ? 1.0 : -1.0) : 0.0
		let steps = 8
		for i in 1 ... steps {
			try? await Task.sleep(for: .milliseconds(18))
			guard !Task.isCancelled else { return }
			let t = Double(i) / Double(steps)
			progress = start + (goal - start) * (t * t * (3 - 2 * t))
		}
		if goal != 0 { land(goal > 0 ? 1 : -1) }
		progress = 0
	}
}

private extension View {
	@ViewBuilder
	func hidingStatusBarInDevelopment() -> some View {
//		#if DEBUG
		self._statusBarHidden(true)
//		#else
//		self
//		#endif
	}
}

#Preview("Stipple") {
	WatchRoot()
}

#Preview("Clock, cut out") {
	var config = StippleConfig()
	config.clock.enabled = true
	config.clock.effect = .glass
	config.clock.weight = .black
	config.clock.showDate = true
	return GeometryReader { proxy in
		StippleScreen(config: config, screenCornerRadius: proxy.size.width * 0.22)
	}
	.ignoresSafeArea()
}
