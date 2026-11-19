import SwiftUI

struct DitherSettingsView: View {
	@State private var store = ConfigStore.shared
	@State private var confirmingReset = false

	var body: some View {
		@Bindable var store = store
		let d = $store.config.dither
		let s = store.config.dither

		Form {
			if !store.isWatchAppInstalled {
				Section {
					Button {
						SetupPresenter.shared.isPresented = true
					} label: {
						Label("Set up Stipple on your Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
					}
				}
			}

			PresetSection(current: s.bounded()) { preset in
				var look = preset.settings
				look.crownSwitchesPresets = store.config.dither.crownSwitchesPresets
				withAnimation(.smooth) { store.config.dither = look }
			}

			Section("Wave") {
				ValueSlider(title: "Speed", value: d.waveSpeed, range: 0 ... DitherSettings.maxWaveSpeed,
				            format: { String(format: "%.3f", $0) })
				DirectionDial(degrees: d.waveDirection)
				ValueSlider(title: "Frequency", value: d.waveFrequency, range: 0.5 ... 8)
				ValueSlider(title: "Amplitude", value: d.waveAmplitude, range: 0 ... 1)
				ValueSlider(title: "Scale", value: d.scale, range: 0.2 ... 4)
				ValueSlider(title: "Contrast", value: d.contrast, range: 0.2 ... 3)
				ValueSlider(title: "Brightness", value: d.brightness, range: -0.6 ... 0.6)
			}

			Section {
				LabeledContent("Frame Rate") {
					Picker("Frame Rate", selection: Binding(
						get: { s.frameRate },
						set: { store.config.dither.framesPerSecond = $0.rawValue }
					)) {
						ForEach(FrameRate.allCases) { Text($0.title).tag($0) }
					}
					.pickerStyle(.segmented)
					.labelsHidden()
					.frame(maxWidth: 210)
				}
				Toggle("Intro Reveal", isOn: d.intro)
				Toggle("Replay Intro on Wrist Raise", isOn: d.replayIntroOnWake)
					.disabled(!s.intro)
				Toggle("Digital Crown Switches Presets", isOn: d.crownSwitchesPresets)
			} header: {
				Text("Motion")
			} footer: {
				Text("When you lower your wrist, the field coasts to a stop and then stops rendering entirely. Higher frame rates look smoother but use more battery.")
			}

			Section {
				ValueSlider(title: "Cell Size", value: d.cellSize, range: 1.5 ... 12, step: 0.5,
				            format: { "\(Int(($0 * 2).rounded())) px" })
				Picker("Pattern", selection: d.pattern) {
					ForEach(DitherPattern.allCases) { Text($0.title).tag($0) }
				}
				ValueSlider(title: "Strength", value: d.ditherStrength, range: 0 ... 1)
				ValueSlider(title: "Color Levels", value: d.colorLevels, range: 2 ... 16, step: 1, format: { "\(Int($0))" })
				ValueSlider(title: "Gap", value: d.gap, range: 0 ... 0.45)
				ValueSlider(title: "Corner Radius", value: d.cornerRadius, range: 0 ... 0.5)
				Toggle("Join Adjacent Squares", isOn: d.joinAdjacentSquares)
					.disabled(s.gap > 0 || s.cornerRadius == 0)
			} header: {
				Text("Cells")
			} footer: {
				Text("Sizes are in Apple Watch pixels. Bigger cells render faster. Gap and corner radius draw each cell's shape, which costs a little more.")
			}

			Section("Color") {
				ColorPicker("Wave", selection: d.waveColor.color, supportsOpacity: false)
				Picker("Background", selection: d.backgroundStyle) {
					ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
				}
				if s.backgroundStyle == .custom {
					ColorPicker("Background Color", selection: d.backgroundColor.color, supportsOpacity: false)
				}
				Picker("Color Goes On", selection: d.colorPlacement) {
					ForEach(ColorPlacement.allCases) { Text($0.title).tag($0) }
				}
				if s.colorPlacement == .background {
					Picker("Squares", selection: d.squareStyle) {
						ForEach(SquareStyle.allCases) { Text($0.title).tag($0) }
					}
				}
			}

			PaletteSection(palette: d.palette, colorField: d.colorField)

			Section {
				ValueSlider(title: "Blur", value: d.blur, range: 0 ... 10, step: 0.5, format: { String(format: "%.1f px", $0) })
				// Blurred, the field is never clipped to the corners; the user's choice comes back when blur returns to 0.
				Toggle("Keep Cells Inside Screen Corners", isOn: Binding(
					get: { s.clipsToScreenCorners },
					set: { store.config.dither.avoidScreenCorners = $0 }
				))
				.disabled(s.blur > 0)
				ValueSlider(title: "Always On Brightness", value: d.alwaysOnBrightness, range: 0.1 ... 1,
				            format: { "\(Int(($0 * 100).rounded()))%" })
			} header: {
				Text("Composition")
			} footer: {
				if s.blur > 0 {
					Text("Cells can't be kept inside the screen corners while the field is blurred.")
				}
			}

			Section {
				Toggle("Touch Ripples", isOn: d.touchEnabled)
				if s.touchEnabled {
					ValueSlider(title: "Radius", value: d.touchRadius, range: 0.05 ... 2)
					ValueSlider(title: "Strength", value: d.touchStrength, range: -2 ... 2)
					ValueSlider(title: "Follow Response", value: d.touchResponse, range: 0.05 ... 1, format: { String(format: "%.2f s", $0) })
					ValueSlider(title: "Trail Length", value: d.touchTrail, range: 0 ... 2, format: { String(format: "%.2f s", $0) })
					ValueSlider(title: "Fade Out", value: d.touchFade, range: 0.1 ... 3, format: { String(format: "%.2f s", $0) })
					ValueSlider(title: "Swirl", value: d.touchWarp, range: 0 ... 1)
				}
			} header: {
				Text("Touch")
			} footer: {
				Text("Drag a finger across the watch to push the field around. Try it in the preview above.")
			}

			Section {
				Button("Reset Dither Settings", role: .destructive) { confirmingReset = true }
			}
		}
		.contentMargins(.top, 16, for: .scrollContent)
		.confirmationDialog("Reset all dither settings?", isPresented: $confirmingReset, titleVisibility: .visible) {
			Button("Reset", role: .destructive) {
				withAnimation(.smooth) { store.config.dither = DitherSettings() }
			}
		}
		.animation(.default, value: s.touchEnabled)
		.animation(.default, value: s.backgroundStyle)
		.animation(.default, value: s.colorPlacement)
		.animation(.default, value: s.blur > 0)
	}
}

/// Two rows of live miniature watches, each playing its preset, scrolling sideways edge to edge through the row.
private struct PresetSection: View {
	let current: DitherSettings
	let apply: (Preset) -> Void
	@State private var presets = PresetStore.shared
	@State private var tapped = 0
	@Environment(\.displayScale) private var displayScale

	/// Mini watch (drawn 1:1 in phone pixels), its bezel, and the name below it.
	private var rowHeight: CGFloat { WatchGeometry.size.height / max(displayScale, 1) + 6 + 22 }

	var body: some View {
		Section {
			ScrollView(.horizontal) {
				LazyHGrid(rows: [GridItem(.fixed(rowHeight), spacing: 14), GridItem(.fixed(rowHeight))], spacing: 14) {
					ForEach(presets.all) { preset in
						PresetTile(preset: preset, selected: preset.settings.matches(current), action: {
							tapped += 1
							apply(preset)
						}, delete: preset.isCustom ? {
							withAnimation(.smooth) { presets.delete(preset) }
						} : nil)
						.transition(.scale.combined(with: .opacity))
						// Shrinks, blurs and fades as tiles scroll off either edge.
						.scrollTransition(axis: .horizontal) { content, phase in
							content
								.scaleEffect(phase.isIdentity ? 1 : 0.78)
								.blur(radius: phase.isIdentity ? 0 : 8)
								.opacity(phase.isIdentity ? 1 : 0.25)
						}
					}
				}
				.scrollTargetLayout()
			}
			.contentMargins(.horizontal, 16, for: .scrollContent)
			.contentMargins(.vertical, 14, for: .scrollContent)
			.scrollIndicators(.hidden)
			.scrollTargetBehavior(.viewAligned)
			.listRowInsets(EdgeInsets())
			.sensoryFeedback(.impact(weight: .light), trigger: tapped)
		} header: {
			Text("Presets")
		} footer: {
			Text("Save your own with the heart button above. Touch and hold one of yours to delete it.")
		}
	}
}

private struct PresetTile: View {
	let preset: Preset
	let selected: Bool
	let action: () -> Void
	/// Only your own presets can be deleted.
	var delete: (() -> Void)?

	var body: some View {
		// A Form row adopts any `contextMenu` inside it as its own (highlighting the whole row and using the first
		// tile's actions). A Menu is a real control, so each tile owns its menu: tap applies, touch and hold deletes.
		if let delete {
			Menu {
				Button("Delete", systemImage: "trash", role: .destructive, action: delete)
			} label: {
				content
			} primaryAction: {
				action()
			}
			.menuStyle(.button)
			.buttonStyle(.plain)
		} else {
			content
				.contentShape(Rectangle())
				.onTapGesture(perform: action)
				.accessibilityAddTraits(.isButton)
		}
	}

	private var content: some View {
		Group {
			VStack(spacing: 6) {
				MiniWatch(settings: preset.settings, selected: selected)
				HStack(spacing: 3) {
					if preset.isCustom {
						Image(systemName: "heart.fill").font(.system(size: 8)).foregroundStyle(.pink)
					}
					Text(preset.name)
						.font(.caption2.weight(selected ? .semibold : .regular))
						.foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
						.lineLimit(1)
				}
				.frame(maxWidth: 80)
			}
		}
	}
}

private struct PaletteSection: View {
	@Binding var palette: [RGB]
	@Binding var colorField: Bool

	/// Bounds-checked, so a picker that outlives its row during a delete never indexes past the end.
	private func color(at index: Int) -> Binding<Color> {
		Binding(
			get: { palette.indices.contains(index) ? palette[index].color : .clear },
			set: { if palette.indices.contains(index) { palette[index] = RGB($0) } }
		)
	}

	var body: some View {
		Section {
			ForEach(palette.indices, id: \.self) { index in
				ColorPicker("Color \(index + 1)", selection: color(at: index), supportsOpacity: false)
			}
			.onDelete { offsets in
				withAnimation { palette.remove(atOffsets: offsets) }
			}
			if palette.count < DitherSettings.maxPaletteCount {
				Button("Add Color", systemImage: "plus.circle.fill") {
					withAnimation { palette.append(palette.last ?? RGB(1, 1, 1)) }
				}
			}
			Toggle("Spread Colors Across Screen", isOn: $colorField)
				.disabled(palette.isEmpty)
		} header: {
			Text("Palette")
		} footer: {
			Text("With two or more colors, brighter parts of the wave use later colors. Spread instead blends the palette across the screen. With one or none, the wave color is used.")
		}
	}
}

