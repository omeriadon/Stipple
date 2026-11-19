import SwiftUI

struct ClockSettingsView: View {
	@State private var store = ConfigStore.shared

	var body: some View {
		// The shared preview header sits above everything, so there is no navigation bar; the font list has its own
		// back row.
		NavigationStack {
			form
				.toolbar(.hidden, for: .navigationBar)
		}
	}

	private var form: some View {
		@Bindable var store = store
		let c = $store.config.clock
		let s = store.config.clock

		return Form {
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
					DockPicker(dock: c.dock)
					Picker("Layout", selection: c.layout) {
						ForEach(ClockLayout.allCases) { Text($0.title).tag($0) }
					}
					if s.effect != .glass {
						NavigationLink {
							FontListView()
						} label: {
							LabeledContent("Font", value: s.fontDesign.title)
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

/// Every font, each drawn in itself. Choosing one updates the watch and the preview above, and stays on this list.
private struct FontListView: View {
	@State private var store = ConfigStore.shared
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		let clock = store.config.clock
		Form {
			Section {
				Button("Clock", systemImage: "chevron.backward") { dismiss() }
			}
			Section {
				ForEach(ClockFontDesign.allCases) { font in
					Button {
						store.config.clock.fontDesign = font
					} label: {
						HStack {
							Text(font.title)
								.foregroundStyle(.primary)
							Spacer()
							FontSample(font: font, weight: clock.weight)
								.foregroundStyle(font == clock.fontDesign ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
							Image(systemName: "checkmark")
								.foregroundStyle(.tint)
								.opacity(font == clock.fontDesign ? 1 : 0)
						}
					}
				}
			} header: {
				Text("Font")
			} footer: {
				Text("Every font follows the weight you pick. Drawn fonts (pixel, dot matrix, 7-segment, monoline and so on) are made by Stipple.")
			}
		}
		.sensoryFeedback(.selection, trigger: clock.fontDesign)
		.contentMargins(.top, 16, for: .scrollContent)
		.toolbar(.hidden, for: .navigationBar)
	}
}

private struct FontSample: View {
	let font: ClockFontDesign
	let weight: ClockWeight

	var body: some View {
		Group {
			if font.isDrawn {
				DrawnRow(text: "10:28", height: 20, font: font, weight: weight)
			} else {
				StretchedWidth(factor: font.stretch) {
					Text("10:28")
						.font(.system(size: 26, weight: weight.weight, design: font.design))
						.monospacedDigit()
				}
			}
		}
		.frame(height: 28)
	}
}
