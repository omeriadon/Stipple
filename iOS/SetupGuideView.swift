import SwiftUI

/// Walks through the two watch settings that make Stipple behave like a watch face.
struct SetupGuideView: View {
	@Environment(\.dismiss) private var dismiss
	@State private var store = ConfigStore.shared

	var body: some View {
		NavigationStack {
			List {
				Section {
					VStack(spacing: 14) {
						WatchPreview(config: store.config)
						Text("Make Stipple your watch face")
							.font(.title2.bold())
							.multilineTextAlignment(.center)
						Text("watchOS doesn't allow custom watch faces, but two settings let Stipple stay on your wrist like one.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
					.listRowBackground(Color.clear)
				}

				Section {
					Step(number: 1, symbol: "arrow.down.app", title: "Install on your watch",
					     detail: "In the Watch app on iPhone, go to My Watch, then Available Apps, and install Stipple.",
					     done: store.isWatchAppInstalled)
					Step(number: 2, symbol: "sun.max", title: "Turn on Always On",
					     detail: "On your watch, go to Settings → Display & Brightness → Always On and switch it on.")
					Step(number: 3, symbol: "eye", title: "Let Stipple show in Always On",
					     detail: "On that same screen, tap Show Apps and make sure Stipple is on, so it dims instead of hiding.")
					Step(number: 4, symbol: "clock.arrow.circlepath", title: "Set Return to Clock to one hour",
					     detail: "Go to Settings → General → Return to Clock. Either choose After 1 hour for every app, or scroll down, tap Stipple, choose Custom, then After 1 hour.")
					Step(number: 5, symbol: "applewatch", title: "Open Stipple",
					     detail: "Lower your wrist and the field slows to a stop and dims. Raise it and it starts moving again.")
					Step(number: 6, symbol: "watchface.applewatch.case", title: "Add the complication (optional)",
					     detail: "Touch and hold your watch face, tap Edit, swipe to Complications, and choose Stipple. Tap it any time to jump back in, for example after watchOS returns to the clock.")
				} footer: {
					Text("You can also change Return to Clock on your iPhone, in the Watch app under My Watch → General. watchOS goes back to the clock after an hour without use; open Stipple again whenever that happens.")
				}
			}
			.navigationTitle("Watch Setup")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
	}
}

private struct Step: View {
	let number: Int
	let symbol: String
	let title: String
	let detail: String
	var done = false

	var body: some View {
		HStack(alignment: .top, spacing: 14) {
			Image(systemName: done ? "checkmark.circle.fill" : symbol)
				.font(.title3)
				.foregroundStyle(done ? .green : .accentColor)
				.symbolRenderingMode(.hierarchical)
				.contentTransition(.symbolEffect(.replace))
				.frame(width: 30)
			VStack(alignment: .leading, spacing: 4) {
				Text("\(number). \(title)").font(.headline)
				Text(detail).font(.subheadline).foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 4)
	}
}
