// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import os
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Watch-side WCSession facade. Two roles:
///   1. **Generic message sender** — `send(_:)` for any `WCMessage`.
///   2. **`WorkoutMirrorPublisher`** — the 1 Hz live-tick publisher consumed
///      by `WorkoutViewModel`.
///
/// Watch-first per v0.2 decision #3: every send is best-effort. If WCSession
/// is unsupported, unactivated, or the iPhone is unreachable, sends silently
/// drop — the watch must work fine without the phone.
final class WatchConnectivityService: NSObject, WorkoutMirrorPublisher, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.arrunner.watch", category: "WCSession")
    private let encoder = JSONEncoder()

    #if canImport(WatchConnectivity)
    private let session: WCSession?
    #endif

    override init() {
        #if canImport(WatchConnectivity)
        self.session = WCSession.isSupported() ? .default : nil
        #endif
        super.init()
        #if canImport(WatchConnectivity)
        session?.delegate = self
        #endif
    }

    func activate() {
        #if canImport(WatchConnectivity)
        session?.activate()
        #endif
    }

    func send(_ message: WCMessage) async {
        await transmit(message)
    }

    // MARK: - WorkoutMirrorPublisher

    func send(snapshot: WorkoutTickMessage) async {
        await transmit(.workoutSnapshot(snapshot), preferLatestOnly: true)
    }

    func sendLifecycle(_ event: LifecycleEvent) async {
        // Lifecycle is rare and important: prefer the queued userInfo path so
        // the phone gets it even if it was unreachable at the moment of the
        // transition.
        await transmit(.workoutLifecycle(event), preferQueued: true)
    }

    func sendGlassesBattery(_ level: Int) async {
        // Battery notifications arrive every ~30 s from the glasses' standard
        // Battery Service (0x180F / 0x2A19). Low-frequency, non-critical,
        // phone-optional — route through transferUserInfo so the iPhone
        // picks up the latest value next time it's reachable. If WCSession
        // never activates or the phone is offline, the queued send is a
        // silent no-op and the watch run is unaffected.
        await transmit(.glassesBattery(level: level), preferQueued: true)
    }

    /// Pushes the watch-side `ActionButtonMode` selection to the iPhone via
    /// `updateApplicationContext` so the phone's Settings picker mirrors the
    /// current value. Latest-only, additive-key wire format — see the phone
    /// service for the full rationale on why this lives outside `WCMessage`.
    func sendActionButtonMode(_ rawValue: String) {
        #if canImport(WatchConnectivity)
        guard let session else { return }
        guard session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext([
                Self.actionButtonModeContextKey: rawValue
            ])
        } catch {
            logger.debug("actionButtonMode context push failed: \(String(describing: error), privacy: .public)")
        }
        #else
        _ = rawValue
        #endif
    }

    static let actionButtonModeContextKey = "actionButtonMode"

    /// Distinct `applicationContext` keys for the custom-HUD cold-reconcile
    /// path (phone → watch). Each holds a `WCMessage`-encoded payload. Kept
    /// separate from the `"wcMessage"` slot so a queued catalog/defaults push
    /// doesn't clobber the latest workout snapshot, and vice versa.
    static let layoutCatalogContextKey = "hudLayoutCatalog"
    static let layoutDefaultsContextKey = "hudLayoutDefaults"

    // MARK: - Settings sync (v0.6.0)

    /// Push the user's default `WorkoutType` selection to the iPhone so its
    /// Settings picker mirrors the watch. Routed through the queued userInfo
    /// path (like lifecycle) so the phone still receives it if it was
    /// unreachable at the moment of the change. Best-effort, phone-optional.
    func sendDefaultWorkoutType(_ type: WorkoutType) async {
        await transmit(.defaultWorkoutType(type), preferQueued: true)
    }

    /// Push the user's metric/imperial preference to the iPhone. Queued for
    /// the same reachability reasons as the workout-type sync above.
    func sendUnitPreference(_ system: UnitSystem) async {
        await transmit(.unitPreference(system), preferQueued: true)
    }

    /// Persist an inbound settings-sync message to the shared App Group
    /// store (last-writer-wins). Non-settings messages are ignored on the
    /// watch — it has no live mirror to drive.
    fileprivate func persist(inbound payload: Data) {
        guard let message = try? JSONDecoder().decode(WCMessage.self, from: payload) else { return }
        switch message {
        case .defaultWorkoutType(let type):
            WorkoutTypePreference.store(type)
        case .unitPreference(let system):
            UnitPreference.store(system)
        case .layoutCatalog(let catalog):
            HUDLayoutStore.store(catalog: catalog)
        case .layoutDefaults(let defaults):
            HUDLayoutStore.store(defaults: defaults)
        default:
            break
        }
    }

    // MARK: - Internals

    private func transmit(
        _ message: WCMessage,
        preferLatestOnly: Bool = false,
        preferQueued: Bool = false
    ) async {
        #if canImport(WatchConnectivity)
        guard let session else { return }
        let payload: Data
        do {
            payload = try encoder.encode(message)
        } catch {
            logger.error("encode failed: \(String(describing: error), privacy: .public)")
            return
        }

        // Reachability-aware delivery:
        //   * Live in-foreground tick → sendMessageData (fastest, no queueing)
        //   * Latest-only background fallback (live ticks) → updateApplicationContext
        //   * Important transitions (lifecycle) → transferUserInfo (queued)
        if session.isReachable {
            session.sendMessageData(payload, replyHandler: nil) { [logger] error in
                logger.debug("sendMessageData fallthrough: \(String(describing: error), privacy: .public)")
            }
            return
        }

        do {
            if preferLatestOnly {
                try session.updateApplicationContext(["wcMessage": payload])
            } else if preferQueued {
                session.transferUserInfo(["wcMessage": payload])
            } else {
                session.transferUserInfo(["wcMessage": payload])
            }
        } catch {
            logger.debug("queued transmit failed: \(String(describing: error), privacy: .public)")
        }
        #else
        _ = message
        _ = preferLatestOnly
        _ = preferQueued
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityService: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("activation failed: \(String(describing: error), privacy: .public)")
        }
    }

    #if !os(watchOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let payload = applicationContext["wcMessage"] as? Data {
            persist(inbound: payload)
        }
        // Custom-HUD cold-reconcile: the phone reconciles the latest catalog
        // and per-type assignments under distinct keys so the watch picks
        // them up on next launch even if it was unreachable at send time.
        if let payload = applicationContext[Self.layoutCatalogContextKey] as? Data {
            persist(inbound: payload)
        }
        if let payload = applicationContext[Self.layoutDefaultsContextKey] as? Data {
            persist(inbound: payload)
        }
        if let raw = applicationContext[Self.actionButtonModeContextKey] as? String,
           ActionButtonMode(rawValue: raw) != nil {
            // Mirror the phone-side picker into the shared App Group
            // store so both the watch's `@AppStorage` views AND the
            // `ActionButtonIntent` (potentially running in a separate
            // process) read the latest value. Writing to `.standard`
            // alone would leave the intent process stuck on whatever it
            // last saw, which was the v0.5.4 dispatch-mode-drift bug.
            let store = ActionButtonMode.sharedDefaults
            if store.string(forKey: ActionButtonMode.storageKey) != raw {
                store.set(raw, forKey: ActionButtonMode.storageKey)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        // v0.6.0 — inbound settings-sync (defaultWorkoutType / unitPreference)
        // from the phone when reachable.
        persist(inbound: messageData)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // v0.6.0 — queued settings-sync fallback when the watch was
        // unreachable at send time.
        if let payload = userInfo["wcMessage"] as? Data {
            persist(inbound: payload)
        }
    }
}
#endif
