import SwiftUI

/// A titled slider with its value shown on the right.
struct ValueSlider: View {
	let title: String
	@Binding var value: Float
	let range: ClosedRange<Float>
	var step: Float? = nil
	var format: (Float) -> String = { String(format: "%.2f", $0) }

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			LabeledContent(title) {
				Text(format(value))
					.monospacedDigit()
					.contentTransition(.numericText(value: Double(value)))
			}
			if let step {
				Slider(value: $value, in: range, step: step)
			} else {
				Slider(value: $value, in: range)
			}
		}
		.sensoryFeedback(.selection, trigger: step == nil ? 0 : value)
	}
}

extension Binding where Value == RGB {
	var color: Binding<Color> {
		Binding<Color>(get: { wrappedValue.color }, set: { wrappedValue = RGB($0) })
	}
}

// MARK: - Watch previews

/// A 46 mm watch screen, in points.
enum WatchGeometry {
	static let size = CGSize(width: 208, height: 248)
	static let corner: CGFloat = 46
}

/// Live, watch-shaped preview using the exact view the watch renders. It is laid out at a 46 mm watch's real point
/// size and pixel density (208 × 248 pt at 2×), so cell counts and sizes match the wrist, then scaled down to fit.
struct WatchPreview: View {
	let config: StippleConfig
	var width: CGFloat = 140

	var body: some View {
		let factor = width / WatchGeometry.size.width
		StippleScreen(config: config, screenCornerRadius: WatchGeometry.corner, followsAlwaysOn: false)
			.environment(\.displayScale, 2)
			.frame(width: WatchGeometry.size.width, height: WatchGeometry.size.height)
			.clipShape(RoundedRectangle(cornerRadius: WatchGeometry.corner, style: .continuous))
			.scaleEffect(factor)
			.frame(width: width, height: WatchGeometry.size.height * factor)
			.watchBezel(corner: WatchGeometry.corner * factor, padding: 5)
			.accessibilityLabel("Watch preview")
	}
}

/// A miniature watch for the preset grid. It renders the whole 46 mm screen at 1×, then shrinks it so each rendered
/// pixel lands on exactly one phone pixel: crisp, no moiré, and a quarter of the full preview's work.
struct MiniWatch: View {
	let settings: DitherSettings
	var selected = false
	@Environment(\.displayScale) private var phoneScale

	var body: some View {
		let factor = 1 / max(phoneScale, 1)
		var config = StippleConfig()
		var dither = settings
		dither.touchEnabled = false
		// Tiles are rebuilt as they scroll back in; replaying the intro each time would flash them black.
		dither.intro = false
		// Rendered at 1× rather than the watch's 2×, and blur is measured in pixels.
		dither.blur /= 2
		config.dither = dither
		return StippleScreen(config: config, screenCornerRadius: WatchGeometry.corner, followsAlwaysOn: false)
			.environment(\.displayScale, 1)
			.frame(width: WatchGeometry.size.width, height: WatchGeometry.size.height)
			.clipShape(RoundedRectangle(cornerRadius: WatchGeometry.corner, style: .continuous))
			.scaleEffect(factor)
			.frame(width: WatchGeometry.size.width * factor, height: WatchGeometry.size.height * factor)
			.allowsHitTesting(false)
			.watchBezel(corner: WatchGeometry.corner * factor, padding: 3, selected: selected)
	}
}

private extension View {
	func watchBezel(corner: CGFloat, padding: CGFloat, selected: Bool = false) -> some View {
		let shape = RoundedRectangle(cornerRadius: corner + padding, style: .continuous)
		return self
			.padding(padding)
			.background(.black, in: shape)
			.overlay {
				shape.strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.18)), lineWidth: selected ? 2 : 1)
			}
			.shadow(color: .black.opacity(0.25), radius: 10, y: 5)
	}
}

// MARK: - Shared header

/// The one live preview, pinned above both tabs, with a button to save the current look as a preset.
struct PreviewHeader: View {
	/// Preview (140 pt wide, plus its bezel) and vertical padding. The tab lists start below this.
	static let height: CGFloat = 197

	@State private var store = ConfigStore.shared
	@State private var presets = PresetStore.shared
	@State private var naming = false
	@State private var name = ""
	@State private var saved = 0

	var body: some View {
		WatchPreview(config: store.config)
			// Matches the watch, which applies every incoming change inside a `.smooth` animation.
			.animation(.smooth, value: store.config)
			.frame(maxWidth: .infinity)
			.frame(height: Self.height)
			.overlay(alignment: .bottomTrailing) {
				Button {
					name = presets.suggestedName
					naming = true
				} label: {
					HStack(spacing: 1) {
						Image(systemName: "plus").font(.caption.bold())
						Image(systemName: "heart.fill")
					}
					.padding(.vertical, 4)
				}
				.buttonStyle(.glass)
				.accessibilityLabel("Save as Preset")
				.padding(16)
			}
			.background(.bar, ignoresSafeAreaEdges: .top)
			.sensoryFeedback(.success, trigger: saved)
			.alert("Save as Preset", isPresented: $naming) {
				TextField("Name", text: $name)
				Button("Save") {
					withAnimation(.smooth) { presets.add(name: name, settings: store.config.dither) }
					saved += 1
				}
				Button("Cancel", role: .cancel) {}
			} message: {
				Text("Saves the current dither settings. Touch and hold a preset to delete it.")
			}
	}
}

// MARK: - Direction dial

/// Eight-way compass for the wave direction. The ring of cells fades away from the chosen heading like a dither
/// gradient, and a pixel arrow in the middle swings round to point the way the wave travels.
struct DirectionDial: View {
	@Binding var degrees: Float

	private static let longNames = ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"]
	private let diameter: CGFloat = 92

	/// Unwrapped angle, so the arrow always turns the short way (NW → N is +45°, not −315°).
	@State private var rotation: Double = 0

	private var index: Int { Int((DitherSettings.snappedDirection(degrees) / 45).rounded()) % 8 }

	var body: some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				Text("Direction")
				Text(Self.longNames[index])
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.contentTransition(.numericText())
			}
			Spacer()
			dial
		}
		.onAppear { rotation = Double(index * 45) }
		.onChange(of: index) { old, new in
			var delta = Double((new - old) * 45)
			if delta > 180 { delta -= 360 }
			if delta < -180 { delta += 360 }
			withAnimation(.spring(duration: 0.45, bounce: 0.35)) { rotation += delta }
		}
		.sensoryFeedback(.selection, trigger: index)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Direction")
		.accessibilityValue(Self.longNames[index])
		.accessibilityAdjustableAction { direction in
			let step = direction == .increment ? 1 : 7
			degrees = Float((index + step) % 8 * 45)
		}
	}

	private var dial: some View {
		let radius = diameter / 2 - 9
		return ZStack {
			Circle().fill(.quaternary.opacity(0.6))
			ForEach(0 ..< 8, id: \.self) { slot in
				let angle = Double(slot) * .pi / 4
				let distance = min((slot - index + 8) % 8, (index - slot + 8) % 8)
				RoundedRectangle(cornerRadius: 2, style: .continuous)
					.fill(.tint)
					.opacity([1, 0.45, 0.22, 0.12, 0.08][distance])
					.frame(width: distance == 0 ? 11 : 8, height: distance == 0 ? 11 : 8)
					.offset(x: sin(angle) * radius, y: -cos(angle) * radius)
					.animation(.snappy, value: index)
			}
			PixelArrow()
				.fill(.tint)
				.frame(width: 26, height: 26)
				.rotationEffect(.degrees(rotation))
		}
		.frame(width: diameter, height: diameter)
		.contentShape(Circle())
		.gesture(
			DragGesture(minimumDistance: 0)
				.onChanged { value in
					let dx = value.location.x - diameter / 2, dy = value.location.y - diameter / 2
					guard dx * dx + dy * dy > 64 else { return }
					let angle = atan2(dx, -dy) * 180 / .pi
					degrees = DitherSettings.snappedDirection(Float(angle))
				}
		)
	}
}

/// An upward arrow drawn from square cells, on a 5 × 5 grid.
nonisolated private struct PixelArrow: Shape {
	private static let cells: [(Int, Int)] = [(2, 0), (1, 1), (2, 1), (3, 1), (0, 2), (2, 2), (4, 2), (2, 3), (2, 4)]

	func path(in rect: CGRect) -> Path {
		let cell = min(rect.width, rect.height) / 5
		let gap = cell * 0.12
		var path = Path()
		for (x, y) in Self.cells {
			path.addRoundedRect(
				in: CGRect(x: rect.minX + CGFloat(x) * cell + gap / 2, y: rect.minY + CGFloat(y) * cell + gap / 2,
				           width: cell - gap, height: cell - gap),
				cornerSize: CGSize(width: cell * 0.2, height: cell * 0.2)
			)
		}
		return path
	}
}
