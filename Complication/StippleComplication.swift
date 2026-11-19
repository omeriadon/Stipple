import SwiftUI
import WidgetKit

/// A static complication: Stipple's dithered orb, filling whatever shape the face gives it. Tapping it opens the app.
@main
struct StippleComplication: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "com.adonis.Stipple.mark", provider: MarkProvider()) { _ in
			MarkView()
		}
		.configurationDisplayName("Stipple")
		.description("Opens Stipple.")
		.supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
	}
}

struct MarkEntry: TimelineEntry {
	let date: Date
}

/// Nothing changes over time, so there is one entry and no refreshes.
struct MarkProvider: TimelineProvider {
	func placeholder(in _: Context) -> MarkEntry { MarkEntry(date: .now) }

	func getSnapshot(in _: Context, completion: @escaping (MarkEntry) -> Void) {
		completion(MarkEntry(date: .now))
	}

	func getTimeline(in _: Context, completion: @escaping (Timeline<MarkEntry>) -> Void) {
		completion(Timeline(entries: [MarkEntry(date: .now)], policy: .never))
	}
}

struct MarkView: View {
	@Environment(\.widgetFamily) private var family

	var body: some View {
		Group {
			switch family {
				case .accessoryInline:
					// Inline complications only take text and an SF Symbol.
					Label("Stipple", systemImage: "circle.grid.3x3.fill")
				case .accessoryRectangular:
					StippleMark(columns: 22, shape: .roundedRectangle)
				default:
					StippleMark(columns: 12, shape: .circle)
			}
		}
		.containerBackground(for: .widget) { Color.clear }
	}
}

#Preview(as: .accessoryCircular) {
	StippleComplication()
} timeline: {
	MarkEntry(date: .now)
}

#Preview(as: .accessoryRectangular) {
	StippleComplication()
} timeline: {
	MarkEntry(date: .now)
}
