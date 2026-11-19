import SwiftUI
import WidgetKit

/// The app icon's Bayer-dithered orb, redrawn as vector cells with real transparency so it works on every face:
/// full colour where the face allows it, and as levels of the face's tint where it doesn't. The orb stretches to fill
/// the shape it is given.
struct StippleMark: View {
	enum Outline { case circle, roundedRectangle }

	/// Cells across; rows follow from the aspect ratio so cells stay square.
	let columns: Int
	let shape: Outline

	@Environment(\.widgetRenderingMode) private var renderingMode

	private static let palette: [Color] = [
		Color(.sRGB, red: 0.55, green: 0.18, blue: 1),
		Color(.sRGB, red: 1, green: 0.2, blue: 0.55),
		Color(.sRGB, red: 1, green: 0.72, blue: 0.18),
		Color(.sRGB, red: 0.12, green: 0.85, blue: 1),
	]
	private static let background = Color(.sRGB, red: 0.02, green: 0.01, blue: 0.08)

	var body: some View {
		GeometryReader { proxy in
			let size = proxy.size
			let cell = size.width / CGFloat(columns)
			let rows = max(1, Int((size.height / cell).rounded()))
			let paths = Self.levelPaths(columns: columns, rows: rows, size: size)
			ZStack {
				if renderingMode == .fullColor {
					outline.fill(Self.background)
				} else {
					AccessoryWidgetBackground().clipShape(outline)
				}
				ForEach(paths.indices, id: \.self) { level in
					if renderingMode == .fullColor {
						paths[level].fill(Self.palette[level])
					} else {
						// Tinted and vibrant faces only read alpha, so brightness becomes opacity.
						paths[level].fill(.white.opacity(0.4 + 0.2 * Double(level))).widgetAccentable()
					}
				}
			}
			.clipShape(outline)
		}
	}

	private var outline: AnyShape {
		switch shape {
			case .circle: AnyShape(Circle())
			case .roundedRectangle: AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
		}
	}

	private static let bayer: [Double] = [0, 48, 12, 60, 3, 51, 15, 63, 32, 16, 44, 28, 35, 19, 47, 31,
	                                      8, 56, 4, 52, 11, 59, 7, 55, 40, 24, 36, 20, 43, 27, 39, 23,
	                                      2, 50, 14, 62, 1, 49, 13, 61, 34, 18, 46, 30, 33, 17, 45, 29,
	                                      10, 58, 6, 54, 9, 57, 5, 53, 42, 26, 38, 22, 41, 25, 37, 21].map { $0 / 64 }

	/// Same maths as `Tools/MakeIcon.swift`: an orb lit from the upper left, with a soft wave through it, dithered
	/// into four colour levels (level 0 is an empty cell). One path per level.
	private static func levelPaths(columns: Int, rows: Int, size: CGSize) -> [Path] {
		var paths = Array(repeating: Path(), count: palette.count)
		let cellWidth = size.width / CGFloat(columns), cellHeight = size.height / CGFloat(rows)
		let levels = 5.0
		for row in 0 ..< rows {
			for column in 0 ..< columns {
				// Normalised so the orb stretches to the outline (a circle in a circle, an ellipse in a rectangle).
				let x = (Double(column) + 0.5) / Double(columns) - 0.5
				let y = (Double(row) + 0.5) / Double(rows) - 0.5
				let distance = (x * x + y * y).squareRoot()
				let light = pow(max(0, 1 - distance / 0.52), 1.1)
				let highlight = max(0, 1 - (((x + 0.12) * (x + 0.12) + (y + 0.12) * (y + 0.12)).squareRoot()) / 0.3)
				let wave = 0.08 * sin((x - y) * 14)
				let value = min(1, max(0, light * 0.8 + highlight * 0.35 + wave * light))
				let threshold = bayer[(row % 8) * 8 + column % 8] - 0.25
				let index = Int(((value + threshold / (levels - 1)) * (levels - 1)).rounded(.down))
				guard index >= 1 else { continue }
				let rect = CGRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight)
					.insetBy(dx: cellWidth * 0.09, dy: cellHeight * 0.09)
				paths[min(index - 1, palette.count - 1)]
					.addRoundedRect(in: rect, cornerSize: CGSize(width: cellWidth * 0.24, height: cellHeight * 0.24))
			}
		}
		return paths
	}
}
