import SwiftUI

/// The whole watch face: the dither field, plus the optional clock.
/// Shared so the phone's live preview is the exact same view the watch shows.
struct StippleScreen: View {
	let config: StippleConfig
	/// Radius of the display's rounded corners, so cells can stay clear of them.
	var screenCornerRadius: CGFloat = 0
	/// The phone preview ignores Always On.
	var followsAlwaysOn = true

	/// Owned here, not by the surface, so switching clock effects re-wraps the surface without resetting the field.
	@State private var engine = DitherEngine()
	@Environment(\.isLuminanceReduced) private var luminanceReduced

	private var dimmed: Bool { followsAlwaysOn && luminanceReduced }
	/// The Window effect only shows the field through the digits, so it is brightened to stay readable.
	private var gain: Float { config.clock.enabled && config.clock.effect == .window ? 1.3 : 1 }

	var body: some View {
		let dither = config.dither.bounded()
		let clock = config.clock
		GeometryReader { proxy in
			let surface = DitherSurface(
				engine: engine,
				settings: dither,
				screenCornerRadius: screenCornerRadius,
				followsAlwaysOn: followsAlwaysOn,
				// In Window mode the field *is* the time, and the clock never dims.
				dimsInAlwaysOn: !(clock.enabled && clock.effect == .window)
			)
			let face = { (parts: ClockFace.Parts) in
				ClockFace(settings: clock, screen: proxy.size, dimmed: dimmed, parts: parts)
					.allowsHitTesting(false)
			}
			ZStack {
				Color.black
				if clock.enabled {
					switch clock.effect {
						case .overlay, .glass:
							surface
							face(.all)
						case .window:
							// Only the time is a window; the date stays ordinary text on top.
							surface.mask { face(.time) }
							face(.extras)
					}
				} else {
					surface
				}
			}
			// A GeometryReader pins its child top-leading. Without a fixed frame, a clock wider than the screen would
			// grow this stack and push everything off to the right.
			.frame(width: proxy.size.width, height: proxy.size.height)
		}
		.ignoresSafeArea()
		.onChange(of: gain, initial: true) { _, value in engine.gain = value }
	}
}

// MARK: - Dither surface

struct DitherSurface: View {
	let engine: DitherEngine
	let settings: DitherSettings
	var screenCornerRadius: CGFloat = 0
	var followsAlwaysOn = true
	var dimsInAlwaysOn = true

	@State private var viewport: CGSize = .zero
	@GestureState private var isTouching = false
	@Environment(\.displayScale) private var displayScale
	@Environment(\.isLuminanceReduced) private var luminanceReduced
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.scenePhase) private var scenePhase

	private var awake: Bool { !(followsAlwaysOn && luminanceReduced) }

	var body: some View {
		DitherBitmap(engine: engine)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			.clipped()
			.blur(radius: CGFloat(settings.blur) / displayScale, opaque: true)
			.contentShape(Rectangle())
			.gesture(touchGesture, isEnabled: settings.touchEnabled)
			.onGeometryChange(for: CGSize.self, of: \.size) { size in
				viewport = size
				engine.setViewport(size, scale: displayScale, cornerRadius: screenCornerRadius)
			}
			.onChange(of: displayScale) { _, scale in
				engine.setViewport(viewport, scale: scale, cornerRadius: screenCornerRadius)
			}
			.onChange(of: screenCornerRadius) { _, radius in
				engine.setViewport(viewport, scale: displayScale, cornerRadius: radius)
			}
			// Gesture state resets on cancellation too (edge swipes, wrist drops), so a touch can never stick.
			.onChange(of: isTouching) { _, touching in
				if !touching { engine.setTouch(nil) }
			}
			// Always On: the field coasts to a stop (in the engine) while the surface drops to its dim level. This is
			// deliberately not animated: Always On redraws about once a second, so a fade is sampled coarsely and can sit
			// at an in-between brightness for seconds before landing.
			.opacity(awake || !dimsInAlwaysOn ? 1 : Double(settings.alwaysOnBrightness))
			.transaction(value: awake) { $0.animation = nil }
			.onChange(of: settings, initial: true) { _, value in engine.setSettings(value) }
			.onChange(of: awake, initial: true) { _, value in engine.isAwake = value }
			.onChange(of: reduceMotion, initial: true) { _, value in engine.reduceMotion = value }
			// Only a real background stops rendering outright. Always On reports `.inactive`, and the frozen frame must stay.
			.onChange(of: scenePhase, initial: true) { _, phase in engine.sceneActive = phase != .background }
			.onAppear { engine.surfaceAppeared() }
			.onDisappear { engine.surfaceDisappeared() }
			.accessibilityHidden(true)
	}

	private var touchGesture: some Gesture {
		DragGesture(minimumDistance: 0, coordinateSpace: .local)
			.updating($isTouching) { _, touching, _ in touching = true }
			.onChanged { engine.setTouch($0.location) }
	}
}

/// The only view that reads `engine.image`, so each frame re-evaluates one `Image` and nothing else.
private struct DitherBitmap: View {
	let engine: DitherEngine

	var body: some View {
		let layout = engine.layout
		if let image = engine.image {
			Image(decorative: image, scale: 1)
				.resizable()
				.interpolation(.none)
				.antialiased(false)
				.frame(width: layout.gridSize.width, height: layout.gridSize.height)
				.offset(layout.gridOffset)
		} else {
			Color.clear
		}
	}
}

// MARK: - Clock

/// The clock, docked to one of nine regions of the screen. Spacers with a minimum length of 0 push it toward its dock
/// and no further, so it only ever moves in from the edges. It is never scaled: if it is bigger than the screen it
/// overflows evenly. Text is always fully opaque.
struct ClockFace: View {
	enum Parts { case all, time, extras }

	let settings: ClockSettings
	/// The full size of the screen the clock is docked within.
	let screen: CGSize
	let dimmed: Bool
	var parts: Parts = .all

	private var showsTime: Bool { parts != .extras }
	private var showsExtras: Bool { parts != .time }
	/// Inside a mask (Window), the time is pure shape: no shadow, no glass.
	private var isMask: Bool { parts == .time }
	private var size: CGFloat { screen.height * CGFloat(settings.size) }
	private var dock: ClockDock { settings.dock }

	private var stackAlignment: HorizontalAlignment {
		switch dock.column {
			case 0: .leading
			case 2: .trailing
			default: .center
		}
	}

	var body: some View {
		// Anchored to the start of the minute so ticks land exactly on the boundary. Always On updates once a minute.
		TimelineView(.periodic(from: Self.minuteStart, by: settings.showSeconds && !dimmed ? 1 : 60)) { context in
			docked(content(for: context.date))
		}
		.animation(.smooth(duration: 0.6), value: dimmed)
	}

	/// Spacers fill every side except the docked ones, so the block sits against its dock (inset from the edge) and
	/// can never be pushed past it.
	private func docked(_ block: some View) -> some View {
		let inset = screen.width * 0.09
		return VStack(spacing: 0) {
			if dock.row != 0 { Spacer(minLength: 0) }
			HStack(spacing: 0) {
				if dock.column != 0 { Spacer(minLength: 0) }
				block.fixedSize()
				if dock.column != 2 { Spacer(minLength: 0) }
			}
			if dock.row != 2 { Spacer(minLength: 0) }
		}
		.padding(.top, dock.row == 0 ? inset : 0)
		.padding(.bottom, dock.row == 2 ? inset : 0)
		.padding(.leading, dock.column == 0 ? inset : 0)
		.padding(.trailing, dock.column == 2 ? inset : 0)
		.frame(width: screen.width, height: screen.height)
	}

	@ViewBuilder
	private func content(for date: Date) -> some View {
		VStack(alignment: stackAlignment, spacing: size * 0.08) {
			time(for: date)
				.opacity(showsTime ? 1 : 0)
			if settings.showDate {
				Text(date, format: .dateTime.weekday(.abbreviated).day())
					.font(.system(size: max(12, size * 0.28), weight: .semibold, design: settings.fontDesign.design))
					.textCase(.uppercase)
					.foregroundStyle(settings.color.color)
					.modifier(ClockShadow(enabled: settings.shadow, size: size))
					.opacity(showsExtras ? 1 : 0)
			}
		}
		.lineLimit(1)
		.animation(.snappy, value: date)
	}

	// MARK: Time

	private var hourFormat: String {
		switch (settings.use24Hour, settings.layout) {
			case (true, _): "HH"
			case (false, .inline): "h"
			case (false, .stacked): "hh"
		}
	}

	/// In Always On the seconds blur and fade out (they keep their space, so nothing shifts) and return on wake.
	private func seconds(_ date: Date) -> String { Self.string(date, "ss") }

	@ViewBuilder
	private func time(for date: Date) -> some View {
		let hours = Self.string(date, hourFormat), minutes = Self.string(date, "mm")
		if settings.fontDesign.isDrawn, settings.effect != .glass || isMask {
			drawnTime(hours: hours, minutes: minutes, date: date)
				.foregroundStyle(settings.color.color)
				.modifier(ClockShadow(enabled: settings.shadow && !isMask && settings.effect == .overlay, size: size))
		} else if settings.effect == .glass, !isMask {
			glassTime(hours: hours, minutes: minutes, date: date)
				.modifier(ClockShadow(enabled: settings.shadow, size: size))
		} else {
			StretchedWidth(factor: settings.fontDesign.stretch) {
				textTime(hours: hours, minutes: minutes, date: date)
			}
			.foregroundStyle(settings.color.color)
			.modifier(ClockShadow(enabled: settings.shadow && !isMask && settings.effect == .overlay, size: size))
		}
	}

	private var font: Font { .system(size: size, weight: settings.weight.weight, design: settings.fontDesign.design) }

	@ViewBuilder
	private func textTime(hours: String, minutes: String, date: Date) -> some View {
		Group {
			switch settings.layout {
				case .inline:
					HStack(spacing: 0) {
						Text(hours + ":" + minutes)
						if settings.showSeconds {
							Text(":")
							secondsText(date)
						}
					}
				case .stacked:
					VStack(alignment: stackAlignment, spacing: -size * 0.14) {
						Text(hours)
						Text(minutes)
						if settings.showSeconds { secondsText(date) }
					}
			}
		}
		.font(font)
		.monospacedDigit()
		.contentTransition(.numericText())
	}

	private func secondsText(_ date: Date) -> some View {
		Text(seconds(date))
			.contentTransition(.numericText())
			.blur(radius: dimmed ? size * 0.09 : 0)
			.opacity(dimmed ? 0 : 1)
	}

	/// Pixel, 7-segment and monoline digits: shapes, so they work as a Window mask too.
	@ViewBuilder
	private func drawnTime(hours: String, minutes: String, date: Date) -> some View {
		let height = size * 0.78
		let row = { (text: String) in DrawnRow(text: text, height: height, font: settings.fontDesign, weight: settings.weight) }
		let seconds = row(seconds(date))
			.blur(radius: dimmed ? size * 0.09 : 0)
			.opacity(dimmed ? 0 : 1)
		switch settings.layout {
			case .inline:
				HStack(spacing: height * 0.14) {
					row(hours + ":" + minutes)
					if settings.showSeconds {
						row(":")
						seconds
					}
				}
			case .stacked:
				VStack(alignment: stackAlignment, spacing: height * 0.16) {
					row(hours)
					row(minutes)
					if settings.showSeconds { seconds }
				}
		}
	}

	@ViewBuilder
	private func glassTime(hours: String, minutes: String, date: Date) -> some View {
		let stroke = size * settings.weight.glyphStroke
		GlassEffectContainer(spacing: size * 0.04) {
			switch settings.layout {
				case .inline:
					HStack(spacing: size * 0.08) {
						GlyphRow(text: hours + ":" + minutes, height: size, stroke: stroke)
						if settings.showSeconds {
							GlyphRow(text: ":", height: size, stroke: stroke)
							glassSeconds(date, stroke: stroke)
						}
					}
				case .stacked:
					VStack(alignment: stackAlignment, spacing: size * 0.1) {
						GlyphRow(text: hours, height: size, stroke: stroke)
						GlyphRow(text: minutes, height: size, stroke: stroke)
						if settings.showSeconds { glassSeconds(date, stroke: stroke) }
					}
			}
		}
	}

	private func glassSeconds(_ date: Date, stroke: CGFloat) -> some View {
		GlyphRow(text: seconds(date), height: size, stroke: stroke)
			.blur(radius: dimmed ? size * 0.09 : 0)
			.opacity(dimmed ? 0 : 1)
	}

	// MARK: Formatting

	private static var minuteStart: Date {
		Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
	}

	private static var formatters: [String: DateFormatter] = [:]

	static func string(_ date: Date, _ format: String) -> String {
		if let formatter = formatters[format] { return formatter.string(from: date) }
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = format
		formatters[format] = formatter
		return formatter.string(from: date)
	}
}

/// A strong, two-layer shadow so light text reads over bright dither.
private struct ClockShadow: ViewModifier {
	let enabled: Bool
	let size: CGFloat

	func body(content: Content) -> some View {
		content
			.shadow(color: .black.opacity(enabled ? 0.9 : 0), radius: max(1, size * 0.03))
			.shadow(color: .black.opacity(enabled ? 0.75 : 0), radius: size * 0.12)
	}
}

nonisolated extension ClockWeight {
	/// Stroke width of the glass digits, as a fraction of their height.
	var glyphStroke: CGFloat {
		switch self {
			case .thin: 0.07
			case .light: 0.09
			case .regular: 0.11
			case .medium: 0.13
			case .semibold: 0.15
			case .bold: 0.17
			case .heavy: 0.19
			case .black: 0.22
		}
	}
}
