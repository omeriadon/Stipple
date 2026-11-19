import Foundation
import Observation
import SwiftUI
import WatchConnectivity

/// The single source of truth on each device. Either side can change it (the phone's settings, or the watch's Digital
/// Crown switching presets) and pushes it to the other, which applies and persists it.
///
/// Sync uses `updateApplicationContext` as the durable channel (the latest config always arrives, even if the watch
/// app is closed), plus `sendMessage` while the watch app is open and reachable, so sliders feel live on the wrist.
@MainActor
@Observable
final class ConfigStore {
	static let shared = ConfigStore()

	var config: StippleConfig {
		didSet {
			guard config != oldValue else { return }
			config.save()
			// A config that just arrived from the other device isn't echoed back (that would fight a slider drag). The
			// phone still refreshes its outgoing context, so a relaunched watch doesn't start from a stale one.
			if applyingRemote {
				#if os(iOS)
					link.push(config, live: false)
				#endif
				return
			}
			link.push(config)
		}
	}

	private(set) var isWatchAppInstalled = false
	private(set) var isPaired = false

	@ObservationIgnored private let link = WatchLink()
	@ObservationIgnored private var applyingRemote = false

	private init() {
		config = StippleConfig.loadSaved()
		link.onReceive = { [weak self] config, presets in
			guard let self else { return }
			if let presets { PresetStore.shared.replaceCustom(with: presets) }
			if let config, config != self.config {
				self.applyingRemote = true
				withAnimation(.smooth) { self.config = config }
				self.applyingRemote = false
			}
		}
		link.onState = { [weak self] paired, installed in
			self?.isPaired = paired
			self?.isWatchAppInstalled = installed
		}
		link.activate()
	}

	/// The phone's custom presets changed: send the watch the new list (with the current config).
	func presetsChanged() {
		#if os(iOS)
			link.push(config)
		#endif
	}

	func reset() {
		config = StippleConfig()
	}
}

/// Thin WatchConnectivity wrapper. Delegate callbacks arrive off the main actor and hop back.
private final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
	@MainActor var onReceive: ((StippleConfig?, [Preset]?) -> Void)?
	@MainActor var onState: ((Bool, Bool) -> Void)?

	@MainActor private var pending: StippleConfig?
	@MainActor private var contextTask: Task<Void, Never>?
	@MainActor private var lastMessage = Date.distantPast

	@MainActor
	func activate() {
		guard WCSession.isSupported() else { return }
		WCSession.default.delegate = self
		WCSession.default.activate()
	}

	/// Sends live while reachable (throttled to ~12 Hz), and always settles the application context shortly after.
	@MainActor
	private func payload(_ config: StippleConfig) -> [String: Any]? {
		guard let data = config.encoded() else { return nil }
		var payload: [String: Any] = ["config": data]
		#if os(iOS)
			// The phone owns the custom presets.
			if let presets = try? JSONEncoder().encode(PresetStore.shared.custom) { payload["presets"] = presets }
		#endif
		return payload
	}

	@MainActor
	func push(_ config: StippleConfig, live: Bool = true) {
		guard WCSession.isSupported(), let message = payload(config) else { return }
		let session = WCSession.default
		guard session.activationState == .activated else { return }
		pending = config
		if live, session.isReachable, Date().timeIntervalSince(lastMessage) > 0.08 {
			lastMessage = Date()
			session.sendMessage(message, replyHandler: nil, errorHandler: nil)
		}
		contextTask?.cancel()
		contextTask = Task { [weak self] in
			try? await Task.sleep(for: .milliseconds(350))
			guard !Task.isCancelled, let self, let latest = self.pending, let message = self.payload(latest) else { return }
			try? WCSession.default.updateApplicationContext(message)
			// A final live message guarantees the watch lands on the exact end value of a drag.
			if live, WCSession.default.isReachable {
				WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
			}
		}
	}

	nonisolated func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: (any Error)?) {
		let received = session.receivedApplicationContext
		#if os(watchOS)
			let context = (StippleConfig.decode(received["config"] as? Data), Self.decodePresets(received["presets"] as? Data))
		#endif
		#if os(iOS)
			let paired = session.isPaired, installed = session.isWatchAppInstalled
		#else
			let paired = true, installed = true
		#endif
		Task { @MainActor in
			self.onState?(paired, installed)
			#if os(watchOS)
				self.onReceive?(context.0, context.1)
			#else
				// Hand the watch the current config straight away, so a fresh install matches the phone.
				self.push(StippleConfig.loadSaved())
			#endif
		}
	}

	nonisolated func session(_: WCSession, didReceiveApplicationContext context: [String: Any]) {
		receive(context)
	}

	nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
		receive(message)
	}

	nonisolated private static func decodePresets(_ data: Data?) -> [Preset]? {
		data.flatMap { try? JSONDecoder().decode([Preset].self, from: $0) }
	}

	nonisolated private func receive(_ message: [String: Any]) {
		let config = StippleConfig.decode(message["config"] as? Data)
		// Only the phone's presets matter; the watch never sends them.
		#if os(watchOS)
			let presets = Self.decodePresets(message["presets"] as? Data)
		#else
			let presets: [Preset]? = nil
		#endif
		guard config != nil || presets != nil else { return }
		Task { @MainActor in self.onReceive?(config, presets) }
	}

	#if os(iOS)
		nonisolated func sessionDidBecomeInactive(_: WCSession) {}

		nonisolated func sessionDidDeactivate(_ session: WCSession) {
			session.activate()
		}

		nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
			let paired = session.isPaired, installed = session.isWatchAppInstalled
			Task { @MainActor in self.onState?(paired, installed) }
		}

		nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
			// When the watch app opens, hand it the current config straight away.
			guard session.isReachable else { return }
			Task { @MainActor in
				self.push(StippleConfig.loadSaved())
			}
		}
	#endif
}
