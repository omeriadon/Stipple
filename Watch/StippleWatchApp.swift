import SwiftUI

@main
struct StippleWatchApp: App {
	var body: some Scene {
		WindowGroup {
			WatchRoot()
		}
	}
}

/// No chrome, no settings: just the field, edge to edge. Everything is configured from the phone.
struct WatchRoot: View {
	@State private var store = ConfigStore.shared

	var body: some View {
		GeometryReader { proxy in
			StippleScreen(
				config: store.config,
				// watchOS has no API for the display's corner radius; this tracks the rounded-rectangle displays closely.
				screenCornerRadius: min(proxy.size.width, proxy.size.height) * 0.22
			)
		}
		.ignoresSafeArea()
		.persistentSystemOverlays(.hidden)
		.hidingStatusBarInDevelopment()
	}
}

private extension View {
	/// Private SwiftUI API that hides the watchOS time in the corner. It is not App Store safe, so it only exists in
	/// Debug builds; Release builds (archives, TestFlight, the App Store) leave the system time showing.
	@ViewBuilder
	func hidingStatusBarInDevelopment() -> some View {
		#if DEBUG
		self._statusBarHidden(true)
		#else
		self
		#endif
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
