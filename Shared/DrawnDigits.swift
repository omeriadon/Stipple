import SwiftUI

/// A row of digits Stipple draws itself, filled with the foreground style.
struct DrawnRow: View {
	let text: String
	/// Height of the digits.
	let height: CGFloat
	let font: ClockFontDesign
	let weight: ClockWeight

	var body: some View {
		HStack(spacing: height * DrawnGlyphShape.spacing(font)) {
			ForEach(Array(text.enumerated()), id: \.offset) { _, character in
				let glyph = Glyph(character)
				DrawnGlyphShape(font: font, glyph: glyph, weight: weight)
					.frame(width: height * DrawnGlyphShape.widthRatio(font, glyph), height: height)
			}
		}
	}
}

/// Stretches its content horizontally for real (layout included), so condensed and expanded look identical on the
/// watch and the phone, whatever the system font supports.
struct StretchedWidth<Content: View>: View {
	let factor: CGFloat
	@ViewBuilder let content: Content

	var body: some View {
		if factor == 1 {
			content
		} else {
			StretchLayout(factor: factor) { content.scaleEffect(x: factor, y: 1) }
		}
	}
}

private struct StretchLayout: Layout {
	let factor: CGFloat

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
		guard let child = subviews.first else { return .zero }
		let size = child.sizeThatFits(.unspecified)
		return CGSize(width: size.width * factor, height: size.height)
	}

	func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
		subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
	}
}

/// One digit or colon in a drawn face. How heavy it is follows the clock's weight setting.
nonisolated struct DrawnGlyphShape: Shape {
	let font: ClockFontDesign
	let glyph: Glyph
	let weight: ClockWeight

	/// 0 (thin) ... 1 (black).
	private var heaviness: CGFloat { CGFloat(ClockWeight.allCases.firstIndex(of: weight) ?? 0) / 7 }
	private static let italicLean: CGFloat = 0.18

	static func widthRatio(_ font: ClockFontDesign, _ glyph: Glyph) -> CGFloat {
		switch font {
			case .pixel, .dots: glyph == .colon ? 1.0 / 7 : 5.0 / 7
			case .chunky: glyph == .colon ? 1.0 / 5 : 3.0 / 5
			case .segment: glyph == .colon ? 0.16 : 0.56
			case .italic: (glyph == .colon ? 0.2 : 0.58) + italicLean
			default: glyph == .colon ? 0.2 : 0.58
		}
	}

	/// Gap between glyphs, as a fraction of the height.
	static func spacing(_ font: ClockFontDesign) -> CGFloat {
		switch font {
			case .pixel, .dots: 1.0 / 7
			case .chunky: 1.0 / 5
			case .segment: 0.12
			default: 0.08
		}
	}

	func path(in rect: CGRect) -> Path {
		switch font {
			case .pixel: return matrixPath(in: rect, round: false, gap: 0.3)
			case .chunky: return matrixPath(in: rect, round: false, gap: 0.2)
			case .dots: return matrixPath(in: rect, round: true, gap: 0)
			case .segment: return segmentPath(in: rect)
			case .italic:
				// Lean the monoline digits: shear about the baseline inside a narrower box, so they still fit the rect.
				let inner = CGRect(x: rect.minX, y: rect.minY, width: rect.width - rect.height * Self.italicLean, height: rect.height)
				let line = GlyphShape(glyph: glyph, stroke: rect.height * weight.glyphStroke).path(in: inner)
				return line.applying(CGAffineTransform(a: 1, b: 0, c: -Self.italicLean, d: 1, tx: Self.italicLean * rect.maxY, ty: 0))
			case .outline:
				// Hollow digits: just the edge of a monoline digit.
				let solid = GlyphShape(glyph: glyph, stroke: rect.height * (weight.glyphStroke + 0.05)).path(in: rect)
				return solid.strokedPath(StrokeStyle(lineWidth: max(1, rect.height * (0.02 + 0.02 * heaviness)), lineJoin: .round))
			default: return GlyphShape(glyph: glyph, stroke: rect.height * weight.glyphStroke).path(in: rect)
		}
	}

	// MARK: Dot matrix (pixel, chunky, dots)

	private static let bitmaps5x7: [[String]] = [
		["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
		["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
		["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
		["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
		["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
		["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
		["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
		["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
		["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
		["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	]

	private static let bitmaps3x5: [[String]] = [
		["111", "101", "101", "101", "111"],
		["010", "110", "010", "010", "111"],
		["111", "001", "111", "100", "111"],
		["111", "001", "111", "001", "111"],
		["101", "101", "111", "001", "001"],
		["111", "100", "111", "001", "111"],
		["111", "100", "111", "101", "111"],
		["111", "001", "001", "010", "010"],
		["111", "101", "111", "101", "111"],
		["111", "101", "111", "001", "111"],
	]

	private func matrixPath(in rect: CGRect, round: Bool, gap: CGFloat) -> Path {
		let chunky = font == .chunky
		let rows: [String]
		if case let .digit(value) = glyph {
			rows = chunky ? Self.bitmaps3x5[value] : Self.bitmaps5x7[value]
		} else {
			rows = chunky ? ["0", "1", "0", "1", "0"] : ["0", "0", "1", "0", "0", "1", "0"]
		}
		let cell = rect.height / CGFloat(rows.count)
		var path = Path()
		for (y, row) in rows.enumerated() {
			for (x, bit) in row.enumerated() where bit == "1" {
				let box = CGRect(x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cell, width: cell, height: cell)
				if round {
					// Dots swell with the weight.
					path.addEllipse(in: box.insetBy(dx: cell * (0.3 - 0.26 * heaviness) , dy: cell * (0.3 - 0.26 * heaviness)))
				} else {
					let inset = cell * gap * (1 - 0.87 * heaviness) / 2
					path.addRoundedRect(in: box.insetBy(dx: inset, dy: inset), cornerSize: CGSize(width: cell * 0.14, height: cell * 0.14))
				}
			}
		}
		return path
	}

	// MARK: 7-segment

	/// Segments a (top), b (upper right), c (lower right), d (bottom), e (lower left), f (upper left), g (middle).
	private static let segments: [String] = ["abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"]

	private func segmentPath(in rect: CGRect) -> Path {
		let t = rect.height * (0.075 + 0.1 * heaviness)
		var path = Path()
		if glyph == .colon {
			let r = t * 0.62
			for y in [0.32, 0.72] {
				path.addRoundedRect(
					in: CGRect(x: rect.midX - r, y: rect.minY + rect.height * y - r, width: r * 2, height: r * 2),
					cornerSize: CGSize(width: r * 0.4, height: r * 0.4)
				)
			}
			return path
		}
		guard case let .digit(value) = glyph, rect.width > t * 2.4, rect.height > t * 3.4 else { return path }

		let left = rect.minX + t / 2, right = rect.maxX - t / 2
		let top = rect.minY + t / 2, middle = rect.midY, bottom = rect.maxY - t / 2
		let tip = t * 0.65
		func horizontal(_ y: CGFloat) {
			path.addPath(Self.bar(from: CGPoint(x: left + tip, y: y), to: CGPoint(x: right - tip, y: y), thickness: t))
		}
		func vertical(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) {
			path.addPath(Self.bar(from: CGPoint(x: x, y: y0 + tip), to: CGPoint(x: x, y: y1 - tip), thickness: t))
		}
		let on = Set(Self.segments[value])
		if on.contains("a") { horizontal(top) }
		if on.contains("g") { horizontal(middle) }
		if on.contains("d") { horizontal(bottom) }
		if on.contains("f") { vertical(left, top, middle) }
		if on.contains("b") { vertical(right, top, middle) }
		if on.contains("e") { vertical(left, middle, bottom) }
		if on.contains("c") { vertical(right, middle, bottom) }
		return path
	}

	/// A segment: a bar with pointed ends, running between two points on a horizontal or vertical line.
	private static func bar(from a: CGPoint, to b: CGPoint, thickness t: CGFloat) -> Path {
		var path = Path()
		let h = t / 2
		if a.y == b.y {
			path.move(to: CGPoint(x: a.x - h, y: a.y))
			path.addLine(to: CGPoint(x: a.x, y: a.y - h))
			path.addLine(to: CGPoint(x: b.x, y: b.y - h))
			path.addLine(to: CGPoint(x: b.x + h, y: b.y))
			path.addLine(to: CGPoint(x: b.x, y: b.y + h))
			path.addLine(to: CGPoint(x: a.x, y: a.y + h))
		} else {
			path.move(to: CGPoint(x: a.x, y: a.y - h))
			path.addLine(to: CGPoint(x: a.x + h, y: a.y))
			path.addLine(to: CGPoint(x: b.x + h, y: b.y))
			path.addLine(to: CGPoint(x: b.x, y: b.y + h))
			path.addLine(to: CGPoint(x: b.x - h, y: b.y))
			path.addLine(to: CGPoint(x: a.x - h, y: a.y))
		}
		path.closeSubpath()
		return path
	}
}
