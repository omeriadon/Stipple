import SwiftUI

struct ClockSettingsView: View {
	@State private var store = ConfigStore.shared

	var body: some View {
		@Bindable var store = store
		let c = $store.config.clock
		let s = store.config.clock

		Form {
			Section {
				Toggle("Show Clock", isOn: c.enabled.animation(.smooth))
			} footer: {
				Text("Off by default, so the watch shows only the dither.")
			}

			if s.enabled {
				Section {
					Picker("Effect", selection: c.effect) {
						ForEach(ClockEffect.allCases) { Text($0.title).tag($0) }
					}
					.pickerStyle(.segmented)
					Picker("Layout", selection: c.layout) {
						ForEach(ClockLayout.allCases) { Text($0.title).tag($0) }
					}
					if s.effect != .glass {
						Picker("Font", selection: c.fontDesign) {
							ForEach(ClockFontDesign.allCases) { Text($0.title).tag($0) }
						}
					}
					Picker(s.effect == .glass ? "Thickness" : "Weight", selection: c.weight) {
						ForEach(ClockWeight.allCases) { Text($0.title).tag($0) }
					}
					ValueSlider(title: "Size", value: c.size, range: 0.15 ... 0.7, format: { "\(Int(($0 * 100).rounded()))%" })
				} header: {
					Text("Style")
				} footer: {
					Text(effectFooter(s.effect))
				}

				Section {
					ColorPicker(s.effect == .overlay ? "Color" : "Date Color", selection: c.color.color, supportsOpacity: false)
					Toggle("Shadow", isOn: c.shadow)
				} header: {
					Text("Color")
				}

				Section {
					Toggle("24-Hour Time", isOn: c.use24Hour)
					Toggle("Seconds", isOn: c.showSeconds)
					Toggle("Date", isOn: c.showDate)
				} header: {
					Text("Format")
				} footer: {
					Text("Always On only updates once a minute, so the seconds fade out until you raise your wrist.")
				}
			}
		}
		.contentMargins(.top, 16, for: .scrollContent)
		.animation(.default, value: s.effect)
	}

	private func effectFooter(_ effect: ClockEffect) -> String {
		switch effect {
			case .overlay: "Solid text over the dither."
			case .window: "The dither shows only through the time, brightened so it stays readable. The date is plain text."
			case .glass: "The time is drawn in Liquid Glass digits over the dither. The date is plain text."
		}
	}
}
