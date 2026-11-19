import SwiftUI
import UIKit

@main
struct StippleApp: App {
	var body: some Scene {
		WindowGroup {
			RootView()
		}
	}
}

/// Whether the setup guide sheet is showing. Shared so the UIKit tab bar and the SwiftUI lists can both open it.
@MainActor
@Observable
final class SetupPresenter {
	static let shared = SetupPresenter()
	var isPresented = false
}

/// One shared live preview pinned at the top, over a UIKit tab bar whose third, separated tab opens the setup sheet
/// instead of switching tabs.
struct RootView: View {
	@AppStorage("hasSeenSetup") private var hasSeenSetup = false
	@State private var setup = SetupPresenter.shared

	var body: some View {
		@Bindable var setup = setup
		MainTabs()
			.ignoresSafeArea()
			.overlay(alignment: .top) { PreviewHeader() }
			.sheet(isPresented: $setup.isPresented, onDismiss: { hasSeenSetup = true }) {
				SetupGuideView()
			}
			.task {
				if !hasSeenSetup { setup.isPresented = true }
			}
	}
}

private struct MainTabs: UIViewControllerRepresentable {
	func makeUIViewController(context: Context) -> UITabBarController {
		let controller = IconTabBarController()
		let dither = Self.host(DitherSettingsView())
		let clock = Self.host(ClockSettingsView())
		// Shown as the tab bar's prominent tab. Tapping it opens the setup sheet; it is never actually selected.
		let setup = Self.makeSetupTab()
		controller.tabs = [
			UITab(title: "", image: UIImage(systemName: "circle.grid.3x3.fill"), identifier: "dither") { _ in dither },
			UITab(title: "", image: UIImage(systemName: "clock"), identifier: "clock") { _ in clock },
			setup,
		]
		if #available(iOS 27.0, *) {
			controller.prominentTabIdentifier = Self.setupID
		}
		controller.delegate = context.coordinator
		return controller
	}

	static let setupID = "setup"

	/// iOS 27 can make any tab prominent. On iOS 26 only the search tab gets that treatment, so it stands in there.
	private static func makeSetupTab() -> UITab {
		let image = UIImage(systemName: "applewatch")
		if #available(iOS 27.0, *) {
			return UITab(title: "", image: image, identifier: setupID) { _ in UIViewController() }
		}
		let tab = UISearchTab { _ in UIViewController() }
		tab.title = ""
		tab.image = image
		return tab
	}

	/// Icons only. The titles are empty, so VoiceOver gets its names here instead.
	final class IconTabBarController: UITabBarController {
		private static let names = ["Dither", "Clock", "Setup"]

		override func viewDidLayoutSubviews() {
			super.viewDidLayoutSubviews()
			for (item, name) in zip(tabBar.items ?? [], Self.names) { item.accessibilityLabel = name }
		}
	}

	func updateUIViewController(_: UITabBarController, context _: Context) {}

	func makeCoordinator() -> Coordinator { Coordinator() }

	/// Each list's safe area starts below the shared preview header.
	private static func host(_ view: some View) -> UIViewController {
		let host = UIHostingController(rootView: view)
		host.additionalSafeAreaInsets.top = PreviewHeader.height
		return host
	}

	final class Coordinator: NSObject, UITabBarControllerDelegate {
		func tabBarController(_: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
			guard tab.identifier == MainTabs.setupID || tab is UISearchTab else { return true }
			SetupPresenter.shared.isPresented = true
			return false
		}
	}
}

#Preview {
	RootView()
}
