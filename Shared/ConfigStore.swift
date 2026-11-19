import Foundation
import Observation
import SwiftUI
import WatchConnectivity

/// The single source of truth on each device. The phone edits it and pushes; the watch receives and persists.
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
			#if os(iOS)
				link.push(config)
			#endif
		}
	}

	private(set) var isWatchAppInstalled = false
	private(set) var isPaired = false

	@ObservationIgnored private let link = WatchLink()

	private init() {
		config = StippleConfig.loadSaved()
		link.onReceive = { [weak self] config in
			guard let self, config != self.config else { return }
			withAnimation(.smooth) { self.config = config }
		}
		link.onState = { [weak self] paired, installed in
			self?.isPaired = paired
			self?.isWatchAppInstalled = installed
		}
		link.activate()
	}

	func reset() {
		config = StippleConfig()
	}
}

/// Thin WatchConnectivity wrapper. Delegate callbacks arrive off the main actor and hop back.
private final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
	@MainActor var onReceive: ((StippleConfig) -> Void)?
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
	func push(_ config: StippleConfig) {
		guard WCSession.isSupported(), let data = config.encoded() else { return }
		let session = WCSession.default
		guard session.activationState == .activated else { return }
		pending = config
		if session.isReachable, Date().timeIntervalSince(lastMessage) > 0.08 {
			lastMessage = Date()
			session.sendMessage(["config": data], replyHandler: nil, errorHandler: nil)
		}
		contextTask?.cancel()
		contextTask = Task { [weak self] in
			try? await Task.sleep(for: .milliseconds(350))
			guard !Task.isCancelled, let self, let latest = self.pending, let data = latest.encoded() else { return }
			try? WCSession.default.updateApplicationContext(["config": data])
			// A final live message guarantees the watch lands on the exact end value of a drag.
			if WCSession.default.isReachable {
				WCSession.default.sendMessage(["config": data], replyHandler: nil, errorHandler: nil)
			}
		}
	}

	nonisolated func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: (any Error)?) {
		let context = StippleConfig.decode(session.receivedApplicationContext["config"] as? Data)
		#if os(iOS)
			let paired = session.isPaired, installed = session.isWatchAppInstalled
		#else
			let paired = true, installed = true
		#endif
		Task { @MainActor in
			self.onState?(paired, installed)
			#if os(watchOS)
				if let context { self.onReceive?(context) }
			#else
				_ = context
				// Hand the watch the current config straight away, so a fresh install matches the phone.
				self.push(StippleConfig.loadSaved())
			#endif
		}
	}

	nonisolated func session(_: WCSession, didReceiveApplicationContext context: [String: Any]) {
		receive(context["config"] as? Data)
	}

	nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
		receive(message["config"] as? Data)
	}

	nonisolated private func receive(_ data: Data?) {
		#if os(watchOS)
			guard let config = StippleConfig.decode(data) else { return }
			Task { @MainActor in self.onReceive?(config) }
		#endif
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
				self.push(self.pending ?? StippleConfig.loadSaved())
			}
		}
	#endif
}
