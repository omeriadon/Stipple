import Foundation
import Observation

struct Preset: Identifiable, Codable, Equatable {
	var id: String
	var name: String
	var settings: DitherSettings
	var isCustom = false

	init(id: String? = nil, name: String, settings: DitherSettings, isCustom: Bool = false) {
		self.id = id ?? name
		self.name = name
		self.settings = settings.bounded()
		self.isCustom = isCustom
	}

	private static func make(_ name: String, _ configure: (inout DitherSettings) -> Void) -> Preset {
		var s = DitherSettings()
		configure(&s)
		return Preset(name: name, settings: s)
	}

	static let builtIn: [Preset] = [
		Preset(name: "Aurora", settings: DitherSettings()),
		make("Ember") { s in
			// Ergo's detail-view preset.
			s.waveSpeed = 0.02
			s.colorLevels = 10
			s.gap = 0.2
			s.cornerRadius = 0.2
			s.cellSize = 3
			s.waveColor = .black
			s.backgroundColor = .black
			s.palette = [RGB(hex: 0x7A5230), RGB(hex: 0xC9A07A)]
		},
		make("Phosphor") { s in
			s.waveColor = RGB(hex: 0x39FF6A)
			s.backgroundStyle = .black
			s.backgroundColor = .black
			s.palette = []
			s.pattern = .lines
			s.colorLevels = 3
			s.cellSize = 2
			s.waveSpeed = 0.04
			s.waveDirection = 180
		},
		make("Tide") { s in
			s.palette = [RGB(hex: 0x0B3D91), RGB(hex: 0x1E88E5), RGB(hex: 0x4DD0E1), RGB(hex: 0xE0F7FA)]
			s.backgroundColor = RGB(hex: 0x020814)
			s.pattern = .halftone
			s.cellSize = 3
			s.waveDirection = 90
			s.scale = 1.4
		},
		make("Bloom") { s in
			s.palette = [RGB(hex: 0xFF5F6D), RGB(hex: 0xFFC371), RGB(hex: 0xC471F5)]
			s.colorField = true
			s.backgroundColor = RGB(hex: 0x12030A)
			s.cellSize = 4
			s.cornerRadius = 0.5
			s.joinAdjacentSquares = true
			s.colorLevels = 3
		},
		make("Mono") { s in
			s.waveColor = .white
			s.backgroundStyle = .black
			s.backgroundColor = .black
			s.palette = []
			s.pattern = .bayer4
			s.colorLevels = 2
			s.cellSize = 1.5
			s.waveSpeed = 0.03
		},
		make("Paper") { s in
			s.waveColor = RGB(hex: 0xF2EDE3)
			s.colorPlacement = .background
			s.squareStyle = .black
			s.palette = []
			s.pattern = .crosshatch
			s.cellSize = 2
			s.contrast = 1.3
		},
		make("Sunset") { s in
			s.palette = [RGB(hex: 0x2B1055), RGB(hex: 0xD53369), RGB(hex: 0xFF8C42), RGB(hex: 0xFFD166)]
			s.backgroundColor = RGB(hex: 0x10031C)
			s.waveDirection = 0
			s.scale = 0.8
			s.colorLevels = 5
			s.waveSpeed = 0.03
		},
		make("Haze") { s in
			s.palette = [RGB(hex: 0x5B5FEF), RGB(hex: 0xA77BFF), RGB(hex: 0xFF9EC7)]
			s.colorField = true
			s.backgroundColor = RGB(hex: 0x0A0820)
			s.blur = 6
			s.cellSize = 3
			s.pattern = .bayer4
			s.waveSpeed = 0.025
		},
		make("Glacier") { s in
			s.waveColor = RGB(hex: 0xBFEFFF)
			s.palette = []
			s.backgroundStyle = .dim
			s.pattern = .bayer2
			s.cellSize = 3
			s.gap = 0.15
			s.waveSpeed = 0.015
			s.waveDirection = 270
			s.contrast = 1.2
		},
		make("Lava") { s in
			s.palette = [RGB(hex: 0x3A0000), RGB(hex: 0xB31312), RGB(hex: 0xFF6A00), RGB(hex: 0xFFE259)]
			s.backgroundStyle = .black
			s.cellSize = 5
			s.cornerRadius = 0.5
			s.joinAdjacentSquares = true
			s.waveAmplitude = 0.6
			s.waveSpeed = 0.035
			s.colorLevels = 6
		},
		make("Neon") { s in
			s.palette = [RGB(hex: 0x00F5FF), RGB(hex: 0xFF00E5)]
			s.colorField = true
			s.backgroundStyle = .black
			s.pattern = .lines
			s.cellSize = 2
			s.contrast = 1.6
			s.waveSpeed = 0.06
			s.waveDirection = 45
		},
		make("Sakura") { s in
			s.palette = [RGB(hex: 0xFFD6E0), RGB(hex: 0xFF8FAB), RGB(hex: 0xFB6F92)]
			s.backgroundColor = RGB(hex: 0x1C0A12)
			s.pattern = .halftone
			s.cellSize = 4
			s.gap = 0.1
			s.cornerRadius = 0.5
			s.waveSpeed = 0.02
			s.waveDirection = 225
		},
		make("Moss") { s in
			s.palette = [RGB(hex: 0x1B4332), RGB(hex: 0x40916C), RGB(hex: 0x95D5B2)]
			s.backgroundColor = RGB(hex: 0x050F0A)
			s.pattern = .noise
			s.cellSize = 2.5
			s.scale = 1.8
			s.waveSpeed = 0.02
		},
		make("Midnight") { s in
			s.waveColor = RGB(hex: 0x3D5AFE)
			s.palette = []
			s.backgroundStyle = .black
			s.brightness = -0.2
			s.contrast = 1.4
			s.cellSize = 2
			s.waveSpeed = 0.012
		},
		make("Sepia") { s in
			s.waveColor = RGB(hex: 0x704214)
			s.colorPlacement = .background
			s.squareStyle = .white
			s.palette = []
			s.pattern = .bayer8
			s.cellSize = 2
			s.colorLevels = 3
			s.waveSpeed = 0.02
		},
		make("Candy") { s in
			s.palette = [RGB(hex: 0xFFADAD), RGB(hex: 0xFDFFB6), RGB(hex: 0xCAFFBF), RGB(hex: 0x9BF6FF), RGB(hex: 0xBDB2FF)]
			s.colorField = true
			s.backgroundColor = RGB(hex: 0x15101F)
			s.cellSize = 6
			s.cornerRadius = 0.5
			s.gap = 0.12
			s.colorLevels = 3
			s.waveSpeed = 0.03
		},
		make("Static") { s in
			s.waveColor = .white
			s.palette = []
			s.backgroundStyle = .black
			s.pattern = .noise
			s.cellSize = 1.5
			s.waveFrequency = 8
			s.scale = 3
			s.waveSpeed = 0.066
		},
	]
}

/// The user's own presets. They are made and saved on the phone, which hands a copy to the watch so the Digital Crown
/// can step through them too.
@MainActor
@Observable
final class PresetStore {
	static let shared = PresetStore()
	private static let key = "stipple.customPresets"

	private(set) var custom: [Preset] {
		didSet {
			if let data = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(data, forKey: Self.key) }
				#if os(iOS)
					ConfigStore.shared.presetsChanged()
				#endif
		}
	}

	var all: [Preset] { custom + Preset.builtIn }

	private init() {
		let data = UserDefaults.standard.data(forKey: Self.key)
		custom = data.flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? []
	}

	/// The watch takes the phone's list as it is.
	func replaceCustom(with presets: [Preset]) {
		guard presets != custom else { return }
		custom = presets
	}

	var suggestedName: String { "My Preset \(custom.count + 1)" }

	func add(name: String, settings: DitherSettings) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		custom.insert(Preset(id: UUID().uuidString, name: trimmed.isEmpty ? suggestedName : trimmed,
		                     settings: settings, isCustom: true), at: 0)
	}

	func delete(_ preset: Preset) {
		custom.removeAll { $0.id == preset.id }
	}
}
