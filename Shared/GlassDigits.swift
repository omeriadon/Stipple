import SwiftUI

/// A row of hand-drawn digit shapes, each rendered as its own piece of Liquid Glass.
/// Must sit inside a `GlassEffectContainer` so neighbouring glyphs render (and morph) together.
struct GlyphRow: View {
	let text: String
	let height: CGFloat
	let stroke: CGFloat

	var body: some View {
		HStack(spacing: height * 0.08) {
			// Identity includes the character, so a changed digit is a new piece of glass: the old one dissolves and the
			// new one materialises in its place, while unchanged digits stay put.
			ForEach(Array(text.enumerated()), id: \.offset) { offset, character in
				let glyph = Glyph(character)
				Color.clear
					.frame(width: height * glyph.widthRatio, height: height)
					// Clear glass vanishes into a busy field, so it is frosted toward white to read as solid digits.
					.glassEffect(.regular.tint(.white.opacity(0.5)), in: GlyphShape(glyph: glyph, stroke: stroke))
					.glassEffectTransition(.materialize)
					.id("\(offset)\(character)")
			}
		}
	}
}

/// The characters the clock needs: 0–9 and a colon.
nonisolated enum Glyph: Equatable, Sendable {
	case digit(Int)
	case colon

	init(_ character: Character) {
		if let value = character.wholeNumberValue, (0 ... 9).contains(value) {
			self = .digit(value)
		} else {
			self = .colon
		}
	}

	var widthRatio: CGFloat { self == .colon ? 0.2 : 0.58 }
}

/// A geometric, monoline digit: a centre-line path in a unit box, stroked with round caps and joins into a filled
/// outline. Coordinates run 0...1 on both axes (y down) and are stretched to the glyph's box before stroking, so the
/// stroke width stays even.
nonisolated struct GlyphShape: Shape {
	let glyph: Glyph
	let stroke: CGFloat

	func path(in rect: CGRect) -> Path {
		// The 4 has a closed triangle that heavy strokes would fill in, so it is drawn slightly lighter.
		let stroke = glyph == .digit(4) ? stroke * 0.82 : stroke
		let inset = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
		guard inset.width > 0, inset.height > 0 else { return Path() }

		if glyph == .colon {
			let r = stroke * 0.62
			var dots = Path()
			for y in [0.32, 0.72] {
				let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * y)
				dots.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
			}
			return dots
		}

		let transform = CGAffineTransform(translationX: inset.minX, y: inset.minY)
			.scaledBy(x: inset.width, y: inset.height)
		let line = centerLine.applying(transform)
		return line.strokedPath(StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
	}

	private var centerLine: Path {
		var p = Path()
		func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
		guard case let .digit(value) = glyph else { return p }
		switch value {
			case 0:
				p.addRoundedRect(in: CGRect(x: 0, y: 0, width: 1, height: 1), cornerSize: CGSize(width: 0.5, height: 0.32))
			case 1:
				p.move(to: pt(0.12, 0.22))
				p.addLine(to: pt(0.62, 0))
				p.addLine(to: pt(0.62, 1))
			case 2:
				p.move(to: pt(0.02, 0.24))
				p.addCurve(to: pt(0.5, 0), control1: pt(0.04, 0.08), control2: pt(0.25, 0))
				p.addCurve(to: pt(0.98, 0.27), control1: pt(0.78, 0), control2: pt(0.98, 0.12))
				p.addCurve(to: pt(0.72, 0.6), control1: pt(0.98, 0.42), control2: pt(0.86, 0.5))
				p.addLine(to: pt(0, 1))
				p.addLine(to: pt(1, 1))
			case 3:
				p.move(to: pt(0.02, 0.18))
				p.addCurve(to: pt(0.5, 0), control1: pt(0.1, 0.05), control2: pt(0.3, 0))
				p.addCurve(to: pt(0.95, 0.25), control1: pt(0.76, 0), control2: pt(0.95, 0.1))
				p.addCurve(to: pt(0.42, 0.48), control1: pt(0.95, 0.4), control2: pt(0.7, 0.48))
				p.addCurve(to: pt(1, 0.73), control1: pt(0.78, 0.48), control2: pt(1, 0.58))
				p.addCurve(to: pt(0.5, 1), control1: pt(1, 0.9), control2: pt(0.78, 1))
				p.addCurve(to: pt(0, 0.82), control1: pt(0.25, 1), control2: pt(0.06, 0.94))
			case 4:
				// A closed triangle (the counter) with the stem running through it. Tall and wide so the hole survives
				// the stroke.
				p.move(to: pt(0.78, 1))
				p.addLine(to: pt(0.78, 0))
				p.addLine(to: pt(0, 0.8))
				p.addLine(to: pt(1, 0.8))
			case 5:
				p.move(to: pt(0.94, 0))
				p.addLine(to: pt(0.12, 0))
				p.addLine(to: pt(0.04, 0.46))
				p.addCurve(to: pt(0.5, 0.37), control1: pt(0.18, 0.4), control2: pt(0.32, 0.37))
				p.addCurve(to: pt(1, 0.68), control1: pt(0.8, 0.37), control2: pt(1, 0.5))
				p.addCurve(to: pt(0.5, 1), control1: pt(1, 0.88), control2: pt(0.8, 1))
				p.addCurve(to: pt(0, 0.84), control1: pt(0.25, 1), control2: pt(0.06, 0.95))
			case 6:
				p.move(to: pt(0.82, 0))
				p.addCurve(to: pt(0.01, 0.66), control1: pt(0.36, 0.06), control2: pt(0.01, 0.38))
				p.addEllipse(in: CGRect(x: 0, y: 0.36, width: 1, height: 0.64))
			case 7:
				p.move(to: pt(0, 0))
				p.addLine(to: pt(1, 0))
				p.addLine(to: pt(0.34, 1))
			case 8:
				p.addEllipse(in: CGRect(x: 0.08, y: 0, width: 0.84, height: 0.46))
				p.addEllipse(in: CGRect(x: 0, y: 0.45, width: 1, height: 0.55))
			default: // 9
				p.move(to: pt(0.18, 1))
				p.addCurve(to: pt(0.99, 0.34), control1: pt(0.64, 0.94), control2: pt(0.99, 0.62))
				p.addEllipse(in: CGRect(x: 0, y: 0, width: 1, height: 0.64))
		}
		return p
	}
}
