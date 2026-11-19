// Generates Stipple's app icon: a Bayer-dithered glowing orb in rounded cells.
// Usage: swiftc -O Tools/MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon <output.png>...
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let grid = 24
let cell = CGFloat(size) / CGFloat(grid)
let bayer: [Double] = [0, 48, 12, 60, 3, 51, 15, 63, 32, 16, 44, 28, 35, 19, 47, 31,
                       8, 56, 4, 52, 11, 59, 7, 55, 40, 24, 36, 20, 43, 27, 39, 23,
                       2, 50, 14, 62, 1, 49, 13, 61, 34, 18, 46, 30, 33, 17, 45, 29,
                       10, 58, 6, 54, 9, 57, 5, 53, 42, 26, 38, 22, 41, 25, 37, 21].map { $0 / 64 }
typealias RGB = (Double, Double, Double)
let background: RGB = (0.02, 0.01, 0.08)
let palette: [RGB] = [(0.55, 0.18, 1), (1, 0.2, 0.55), (1, 0.72, 0.18), (0.12, 0.85, 1)]

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(colorSpace: space, components: [background.0, background.1, background.2, 1])!)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Level 0 is an empty cell, so the orb's edge dithers away into the background.
let levels = 5.0
for row in 0 ..< grid {
	for column in 0 ..< grid {
		// An orb lit from the upper left, with a soft wave through it.
		let x = (Double(column) + 0.5) / Double(grid) - 0.5
		let y = (Double(row) + 0.5) / Double(grid) - 0.5
		let distance = (x * x + y * y).squareRoot()
		let light = pow(max(0, 1 - distance / 0.46), 1.1)
		let highlight = max(0, 1 - (((x + 0.12) * (x + 0.12) + (y + 0.12) * (y + 0.12)).squareRoot()) / 0.3)
		let wave = 0.08 * sin((x - y) * 14)
		let value = min(1, max(0, light * 0.8 + highlight * 0.35 + wave * light))
		let threshold = bayer[(row % 8) * 8 + column % 8] - 0.25
		let level = (value + threshold / (levels - 1)) * (levels - 1)
		let index = Int(level.rounded(.down))
		guard index >= 1 else { continue }
		let color = palette[min(index - 1, palette.count - 1)]
		ctx.setFillColor(CGColor(colorSpace: space, components: [color.0, color.1, color.2, 1])!)
		// CoreGraphics' origin is bottom-left; flip rows so "upper left" reads correctly.
		let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(grid - 1 - row) * cell, width: cell, height: cell)
			.insetBy(dx: cell * 0.09, dy: cell * 0.09)
		ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cell * 0.24, cornerHeight: cell * 0.24, transform: nil))
		ctx.fillPath()
	}
}

let image = ctx.makeImage()!
for path in CommandLine.arguments.dropFirst() where path.hasSuffix(".png") {
	let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
	CGImageDestinationAddImage(destination, image, nil)
	CGImageDestinationFinalize(destination)
	print("wrote", path)
}
