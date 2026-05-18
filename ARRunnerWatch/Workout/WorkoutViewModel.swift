// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

/// `@MainActor` view model that owns a `WorkoutController` and republishes its
/// state + metrics for SwiftUI consumption. The controller itself is the
/// authoritative actor — this layer only mirrors observable state.
///
/// **v0.2 additions:**
/// - **Finish menu (decision #5):** `requestFinish()` pauses the workout and
///   transitions to `.pendingFinish`. The view shows Save / Cancel / Resume.
/// - **Hybrid energy (decision #4):** `EnergyAccumulator` produces a live kcal
///   estimate for display. The official number comes from HealthKit on save
///   and is published on the resulting `WorkoutSummary`.
/// - **iPhone live mirror (#3):** a 1 Hz tick publisher pushes
///   `WorkoutTickMessage` snapshots over `WatchConnectivityService`. Sends
///   are best-effort; if the phone is unreachable the watch keeps running.
@MainActor
@Observable
final class WorkoutViewModel {
    enum LaunchState: Equatable {
        case idle
        case starting
        case running
        case paused
        /// User tapped Finish — workout is paused awaiting Save/Cancel/Resume.
        case pendingFinish
        case ending
        case ended(WorkoutSummary)
        /// User chose Cancel from the Finish menu. The on-device summary is
        /// discarded; the HKWorkout is still finalized (the substrate
        /// protocol does not expose a discard path in v0.2 — users can
        /// delete the workout from the Health app).
        case cancelled
        case failed(String)
    }

    private(set) var launchState: LaunchState = .idle
    private(set) var heartRate: Double?
    private(set) var distanceMeters: Double?
    private(set) var elapsed: TimeInterval = 0
    private(set) var glassesConnected: Bool = false
    /// Live glasses link state — observed by the pre-run "Connect Glasses"
    /// UI to surface `Disconnected / Connecting… / Connected`. The
    /// `glassesConnected` Bool above stays for the in-run HUD-offline
    /// indicator; this exposes the finer-grained state for the pairing UX.
    private(set) var glassesLinkState: GlassesConnectionState = .disconnected
    /// Human-readable name of the currently connected pair (e.g. "Engo 2").
    /// `nil` until the transport reports `.connected` and supplies a name.
    private(set) var glassesDeviceName: String?
    /// Last pairing error surfaced from `connectGlasses()`. Cleared on the
    /// next successful connect or explicit dismissal.
    private(set) var glassesPairingError: String?
    /// True while the glasses transport is in a dropped state. Mirrors the
    /// inverse of `glassesConnected` for state-driven UI; published as its
    /// own field so the view can react to the side-channel `.dropped` /
    /// `.reconnected` events from the transport directly (D4).
    private(set) var hudOffline: Bool = false
    /// Live local kcal estimate (decision #4 hybrid). Replaced by the
    /// HealthKit-official figure inside `WorkoutSummary` on Save.
    ///
    /// v0.2 audit P1.3: once HK starts emitting a live `.energy` metric
    /// (which it does as soon as the user has authorized active energy
    /// share/read), the substrate's value overrides the local
    /// `EnergyAccumulator` estimate. The `hasLiveHKEnergy` latch below
    /// prevents subsequent `.heartRate` samples from clobbering the
    /// authoritative HK reading back to the estimate.
    private(set) var estimatedActiveKilocalories: Double?
    private var hasLiveHKEnergy: Bool = false

    private var controller: WorkoutController?
    private var transport: (any GlassesFrameTransport)?
    private var glasses: GlassesService?
    private var stateTask: Task<Void, Never>?
    private var metricTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var glassesStateTask: Task<Void, Never>?
    private var glassesStatusTask: Task<Void, Never>?
    private var startedAt: Date?
    private var sport: SportType = .running
    private var sessionID: UUID?
    private var energy: EnergyAccumulator?

    private let substrateFactory: @Sendable () -> any WorkoutHealthSubstrate
    private let transportFactory: (@Sendable () -> any GlassesFrameTransport)?
    private let mirror: WorkoutMirrorPublisher?
    private let bodyProfile: BodyProfile?
    private let hapticPlayer: @Sendable () -> Void
    private let now: @Sendable () -> Date

    /// Minimum gap between two haptic alerts for the same disconnect cycle.
    /// Prevents spam if the transport rapid-fires multiple `.dropped` events
    /// (e.g., link flapping). Reset to "fire-eligible" on `.reconnected` so a
    /// new outage after a recovery alerts immediately.
    private static let hapticDebounceInterval: TimeInterval = 10
    private var lastHapticAt: Date?

    init(
        substrateFactory: @escaping @Sendable () -> any WorkoutHealthSubstrate,
        transportFactory: (@Sendable () -> any GlassesFrameTransport)? = nil,
        mirror: WorkoutMirrorPublisher? = nil,
        bodyProfile: BodyProfile? = nil,
        hapticPlayer: (@Sendable () -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.substrateFactory = substrateFactory
        self.transportFactory = transportFactory
        self.mirror = mirror
        self.bodyProfile = bodyProfile
        self.hapticPlayer = hapticPlayer ?? Self.defaultHapticPlayer
        self.now = now
    }

    private static let defaultHapticPlayer: @Sendable () -> Void = {
        #if canImport(WatchKit) && os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }

    func start(activity: SportType = .running) async {
        guard isStartable() else { return }
        launchState = .starting
        sport = activity
        resetLiveCounters()

        let controller = WorkoutController(substrate: substrateFactory())
        self.controller = controller
        attachStreams(to: controller)

        // v0.2 #1: bring up the glasses link alongside the workout. Per D4
        // the connect attempt is opportunistic — we never block the workout
        // start on its outcome. If the user pre-paired from the Connect
        // Glasses sheet, the transport is already built and (likely)
        // already connected; reuse it rather than rebuilding.
        if let transportFactory {
            let transport: any GlassesFrameTransport
            let glasses: GlassesService
            if let existing = self.transport, let existingService = self.glasses {
                transport = existing
                glasses = existingService
            } else {
                transport = transportFactory()
                self.transport = transport
                glasses = GlassesService(transport: transport)
                self.glasses = glasses
                attachGlasses(transport: transport, service: glasses)
            }
            // If the pre-paired link is already up we skip a redundant
            // connect; otherwise (cold start, or post-failure retry) kick
            // the scan off without blocking workout start.
            Task.detached { [transport] in
                let state = await transport.connectionState
                guard state != .connected, state != .connecting, state != .scanning else { return }
                try? await transport.connect()
            }
        }

        do {
            let state = try await controller.start(activityType: activity)
            startedAt = state.startedAt
            sessionID = state.sessionID
            launchState = .running
            startElapsedTicker()
            startMirrorTicker()
            await mirror?.sendLifecycle(.started(activity))
            // v0.3 HUD MVP: paint the first frame so the wearer sees
            // `0:00 / 0.00 mi / --:--/mi` immediately instead of the
            // lingering "Connection Successful" splash. Safe to call when
            // glasses are disconnected — pushHUDFrameIfConnected no-ops.
            await pushHUDFrameIfConnected()
        } catch {
            launchState = .failed(String(describing: error))
        }
    }

    func pause() async {
        guard let controller else { return }
        do {
            try await controller.pause()
            launchState = .paused
            await mirror?.sendLifecycle(.paused)
        } catch {
            launchState = .failed(String(describing: error))
        }
    }

    func resume() async {
        guard let controller else { return }
        do {
            try await controller.resume()
            launchState = .running
            await mirror?.sendLifecycle(.resumed)
        } catch {
            launchState = .failed(String(describing: error))
        }
    }

    /// User tapped Finish on the live workout view. Per decision #5 the
    /// workout pauses immediately and the view presents Save / Cancel /
    /// Resume; the controller is *not* ended yet.
    func requestFinish() async {
        guard let controller else { return }
        if case .running = launchState {
            try? await controller.pause()
            await mirror?.sendLifecycle(.paused)
        }
        launchState = .pendingFinish
    }

    /// Save path: end the controller, write the HKWorkout, surface the
    /// `WorkoutSummary`. Pushes a final lifecycle event over the mirror.
    func confirmSave() async {
        guard let controller else { return }
        launchState = .ending
        do {
            let summary = try await controller.end()
            launchState = .ended(summary)
            await mirror?.sendLifecycle(.ended)
            // v0.3 HUD MVP: end-of-workout splash on the glasses before we
            // tear the transport down. Best-effort — no-op if disconnected.
            await pushHUDSummaryIfConnected()
            stopRuntimeTasks()
            await teardownTransport()
        } catch {
            launchState = .failed(String(describing: error))
            stopRuntimeTasks()
            await teardownTransport()
        }
    }

    /// Cancel path: end the underlying HK session (the protocol does not
    /// support a discard in v0.2) and mark the local UI as cancelled so no
    /// summary is shown.
    func confirmCancel() async {
        guard let controller else { return }
        launchState = .ending
        do {
            _ = try await controller.end()
        } catch {
            launchState = .failed(String(describing: error))
            stopRuntimeTasks()
            await teardownTransport()
            return
        }
        launchState = .cancelled
        await mirror?.sendLifecycle(.ended)
        stopRuntimeTasks()
        await teardownTransport()
    }

    func resumeFromFinish() async {
        await resume()
    }

    /// Legacy entry point preserved for any callers that still issue an
    /// immediate end. v0.2 default flow is `requestFinish` → `confirmSave`.
    func end() async {
        await confirmSave()
    }

    func reportGlasses(_ signal: GlassesConnectivitySignal) async {
        guard let controller else { return }
        await controller.reportGlassesSignal(signal)
    }

    // MARK: - Pre-run glasses pairing (Joe's v0.2.0 device-test feedback)

    /// Build the transport and attach streams without starting a scan. Safe
    /// to call repeatedly; subsequent calls are no-ops. Used by the pre-run
    /// "Connect Glasses" sheet so the status chip reflects live state before
    /// the workout starts, and so a user-pre-paired transport survives into
    /// `start()` (reused there rather than rebuilt).
    func prepareGlassesIfNeeded() {
        guard transport == nil, let transportFactory else { return }
        let transport = transportFactory()
        self.transport = transport
        let glasses = GlassesService(transport: transport)
        self.glasses = glasses
        attachGlasses(transport: transport, service: glasses)
    }

    /// User tapped "Connect Glasses" on the pre-run screen. Builds the
    /// transport if needed, kicks off a scan/connect, surfaces errors via
    /// `glassesPairingError`, and on success flips a one-shot
    /// `hasPairedGlasses` UserDefaults flag so subsequent app launches can
    /// auto-attempt a connect on appear.
    func connectGlasses() async {
        prepareGlassesIfNeeded()
        guard let transport else { return }
        glassesPairingError = nil
        let current = await transport.connectionState
        if current == .connected || current == .connecting || current == .scanning {
            return
        }
        do {
            try await transport.connect()
            GlassesPairingPreferences.shared.markPaired()
        } catch {
            glassesPairingError = Self.describePairingError(error)
        }
    }

    /// User tapped "Disconnect" / "Cancel" from the pre-run sheet. Tears down
    /// the active link but keeps the transport instance around so a retry
    /// doesn't have to rebuild it.
    func disconnectGlasses() async {
        guard let transport else { return }
        try? await transport.disconnect()
    }

    /// Called by the WorkoutView on first appear. If the user has
    /// successfully paired before, opportunistically attempt to reconnect.
    /// No-op if the user has never paired (we don't want to consume battery
    /// scanning for nothing) or if the link is already up.
    func autoReconnectGlassesOnLaunch() async {
        guard GlassesPairingPreferences.shared.hasPaired else { return }
        prepareGlassesIfNeeded()
        guard let transport else { return }
        let current = await transport.connectionState
        guard current == .disconnected || current == .failed else { return }
        try? await transport.connect()
    }

    /// Clear a pairing error after the user dismisses it.
    func dismissGlassesPairingError() {
        glassesPairingError = nil
    }

    private static func describePairingError(_ error: Error) -> String {
        if let typed = error as? GlassesTransportError {
            switch typed {
            case .notConnected:
                return "Not connected. Try again."
            case .bluetoothUnavailable:
                return "Bluetooth is unavailable. Check Settings."
            case .scanTimeout:
                return "No glasses found. Make sure they're powered on and nearby."
            case .writeFailed(let reason):
                return "Pairing failed: \(reason)"
            case .unknownLayout:
                return "Pairing failed: layout mismatch"
            }
        }
        return "Pairing failed: \(error.localizedDescription)"
    }

    /// MainActor-isolated bridge to update `glassesLinkState` +
    /// `glassesDeviceName` whenever the transport's connection state
    /// changes. Runs alongside the existing controller-signal hop in
    /// `attachGlasses`'s state task.
    fileprivate func updateGlassesLinkState(
        _ state: GlassesConnectionState,
        transport: any GlassesFrameTransport
    ) async {
        glassesLinkState = state
        if state == .connected {
            glassesDeviceName = await transport.connectedDeviceName
            glassesPairingError = nil
        } else if state == .disconnected || state == .failed {
            glassesDeviceName = nil
        }
    }

    // v0.3 HUD push policy — 1Hz minimum + change detection. Reset on
    // (re)connect so the first frame after the link comes up always ships.
    private var hudPushPolicy = RunningHUDPushPolicy()

    func attachGlasses(transport: any GlassesFrameTransport, service: GlassesService? = nil) {
        glassesStateTask?.cancel()
        glassesStatusTask?.cancel()

        // If the caller didn't bring their own service (the default `start()`
        // path always does), build one so the per-tick fan-out still works.
        let resolvedService = service ?? GlassesService(transport: transport)
        if self.glasses == nil { self.glasses = resolvedService }

        glassesStateTask = Task { [weak self] in
            let stream = await transport.connectionStates()
            for await state in stream {
                await self?.updateGlassesLinkState(state, transport: transport)
                await self?.reportGlasses(.from(state))
                if state == .connected {
                    // v0.3 HUD MVP: skip `selectLayout(preset: .default)` —
                    // the curated catalog only ships placeholder slot IDs
                    // (see ReconnectPolicy.swift `placeholderDeviceIDs`),
                    // which is exactly why Joe's bench test saw the glasses
                    // freeze on "Connection Successful". Instead, push an
                    // initial raw-text HUD frame so the wearer immediately
                    // sees live stats (or the zero-state if no workout is
                    // active yet — gated inside `pushHUDFrameIfConnected`).
                    await self?.resetHUDPushPolicy()
                    await self?.pushHUDFrameIfConnected(transport: transport)
                } else if state == .disconnected || state == .reconnecting || state == .failed {
                    await resolvedService.resetThrottle()
                    await self?.resetHUDPushPolicy()
                }
            }
        }
        glassesStatusTask = Task { [weak self] in
            let stream = await transport.statusEvents()
            for await event in stream {
                await self?.handle(statusEvent: event)
            }
        }
    }

    fileprivate func resetHUDPushPolicy() {
        hudPushPolicy.reset()
    }

    /// Build the v0.3 raw-text HUD payload from current state and push it
    /// to the glasses if (a) a transport is wired, (b) the link is up, and
    /// (c) the push policy says we're due for a frame. Silent no-op
    /// otherwise — never blocks the workout pipeline (D4). Called every
    /// second from `tickElapsed` plus once on workout start, on glasses
    /// (re)connect, and on workout end.
    fileprivate func pushHUDFrameIfConnected(transport overrideTransport: (any GlassesFrameTransport)? = nil) async {
        guard let transport = overrideTransport ?? self.transport else { return }
        let payload = RunningHUDFrame.payload(
            elapsedSeconds: elapsed,
            distanceMeters: distanceMeters ?? 0
        )
        guard hudPushPolicy.shouldSend(payload, now: now()) else { return }
        guard await transport.connectionState == .connected else { return }
        let frames = RunningHUDFrame.frames(for: payload)
        try? await transport.sendCommands(frames)
    }

    /// End-of-workout splash — single fire-and-forget push with the final
    /// stats. Bypasses the throttle (it's a one-shot lifecycle event) but
    /// still no-ops if the link is down.
    fileprivate func pushHUDSummaryIfConnected() async {
        guard let transport else { return }
        guard await transport.connectionState == .connected else { return }
        let payload = RunningHUDFrame.payload(
            elapsedSeconds: elapsed,
            distanceMeters: distanceMeters ?? 0
        )
        let frames = RunningHUDFrame.summaryFrames(for: payload)
        try? await transport.sendCommands(frames)
    }


    /// MainActor-isolated handler for transport status events. Per D4:
    /// * `.dropped` during an active workout → forward signal to the
    ///   controller (counter + state flag), surface the HUD-offline UI hint,
    ///   and play a debounced subtle haptic.
    /// * `.reconnected` → clear the HUD-offline hint and reset the haptic
    ///   debounce so a fresh outage alerts immediately. The connection-state
    ///   stream separately re-flips `glassesConnected` via the controller.
    /// * `.reconnectAbandoned` → BLE layer gave up after exhausting its
    ///   reconnect budget. Mirror `.dropped` UX (HUD-offline hint + debounced
    ///   haptic); no further reconnect will be attempted this workout.
    /// Other status events (battery, RSSI, reconnect-attempt failures) are
    ///   side-channel telemetry only — no UX side effects in v0.2.
    private func handle(statusEvent event: GlassesStatusEvent) async {
        switch event {
        case .dropped(let reason, _):
            hudOffline = true
            await reportGlasses(.from(droppedReason: reason))
            fireDisconnectHapticIfEligible()
        case .reconnected:
            hudOffline = false
            lastHapticAt = nil
        case .reconnectAbandoned:
            // BLE layer exhausted its reconnect budget — HUD is down for the
            // remainder of this workout. Mirror `.dropped` UX (offline hint +
            // debounced haptic); no further reconnect will be attempted.
            hudOffline = true
            fireDisconnectHapticIfEligible()
        case .batteryLevel, .signalQuality, .reconnectAttemptFailed:
            break
        }
    }

    /// Trigger the watchOS haptic for a glasses drop, subject to D4 rules:
    /// only while the workout is actively running (not idle / paused /
    /// pendingFinish / ending / ended), and only once per debounce window so
    /// a flapping link does not spam the user's wrist.
    private func fireDisconnectHapticIfEligible() {
        guard launchState == .running else { return }
        let timestamp = now()
        if let lastHapticAt, timestamp.timeIntervalSince(lastHapticAt) < Self.hapticDebounceInterval {
            return
        }
        lastHapticAt = timestamp
        hapticPlayer()
    }

    private func isStartable() -> Bool {
        switch launchState {
        case .idle, .ended, .cancelled, .failed: return true
        case .starting, .running, .paused, .pendingFinish, .ending: return false
        }
    }

    private func resetLiveCounters() {
        heartRate = nil
        distanceMeters = nil
        elapsed = 0
        estimatedActiveKilocalories = nil
        hasLiveHKEnergy = false
        hudOffline = false
        lastHapticAt = nil
        if let bodyProfile {
            energy = EnergyAccumulator(estimator: EnergyEstimator(profile: bodyProfile))
        } else {
            energy = nil
        }
    }

    private func attachStreams(to controller: WorkoutController) {
        stateTask?.cancel()
        metricTask?.cancel()

        stateTask = Task { [weak self] in
            for await state in controller.states {
                self?.apply(state: state)
            }
        }
        metricTask = Task { [weak self] in
            for await metric in controller.metrics {
                self?.apply(metric: metric)
            }
        }
    }

    private func apply(state: WorkoutState) {
        glassesConnected = state.glassesConnected
        switch state.phase {
        case .running:
            // Don't clobber the Finish-menu state — the user could be in
            // `.pendingFinish` while the controller is paused, and a stray
            // resume from elsewhere shouldn't drop them out of the menu.
            if launchState == .running || launchState == .paused {
                launchState = .running
            }
        case .paused:
            if launchState == .running { launchState = .paused }
        case .failed:
            launchState = .failed(state.failureReason ?? "Unknown failure")
        default: break
        }
    }

    private func apply(metric: WorkoutMetric) {
        switch metric.kind {
        case .heartRate:
            heartRate = metric.value
            energy?.ingest(heartRate: metric.value, at: metric.timestamp)
            // Only use the local estimate while HK hasn't started
            // emitting live `.energy` samples. Once HK is the source of
            // truth we stop overwriting its reading with the estimate.
            if !hasLiveHKEnergy {
                estimatedActiveKilocalories = energy?.totalKilocalories
            }
        case .distance:
            distanceMeters = metric.value
        case .energy:
            // v0.2 audit P1.3: live HK kcal now reaches the UI. Latch
            // so subsequent heart-rate ticks don't overwrite the HK
            // value with the local estimator.
            hasLiveHKEnergy = true
            estimatedActiveKilocalories = metric.value
        default: break
        }
        // P1.2 (audit 2026-05-16): fan the controller's metric stream out to
        // the glasses adapter. The service itself enforces connected-state +
        // 1Hz-per-field throttle, so this is a fire-and-forget hop and never
        // back-pressures the workout pipeline.
        if let glasses {
            Task { await glasses.apply(metric: metric) }
        }
    }

    private func startElapsedTicker() {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tickElapsed()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tickElapsed() {
        guard let startedAt else { return }
        if case .running = launchState {
            elapsed = Date().timeIntervalSince(startedAt)
            // v0.3 HUD MVP: render the time/distance/pace HUD at 1Hz off
            // the elapsed ticker. The push policy gates on minimum-interval
            // + payload-change so a frozen pace (`--:--/mi` while distance
            // < 0.01 mi) doesn't generate redundant BLE traffic.
            Task { [weak self] in await self?.pushHUDFrameIfConnected() }
        }
    }

    /// Push a `WorkoutTickMessage` over WCSession at ~1 Hz. Best-effort —
    /// the watch keeps recording whether or not the phone is reachable
    /// (decisions #3 + #6).
    private func startMirrorTicker() {
        guard let mirror else { return }
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.publishMirrorTick(via: mirror)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func publishMirrorTick(via mirror: WorkoutMirrorPublisher) async {
        guard let sessionID else { return }
        let phase: WorkoutPhase
        switch launchState {
        case .running: phase = .running
        case .paused, .pendingFinish: phase = .paused
        case .ending, .ended, .cancelled: phase = .ended
        case .failed: phase = .failed
        case .idle, .starting: return
        }
        let pace: Double? = {
            guard let distanceMeters, distanceMeters > 0, elapsed > 0 else { return nil }
            return elapsed / (distanceMeters / 1000.0)
        }()
        let snapshot = WorkoutTickMessage(
            sessionID: sessionID,
            sport: sport,
            phase: phase,
            timestamp: Date(),
            elapsedSeconds: elapsed,
            heartRateBeatsPerMinute: heartRate,
            distanceMeters: distanceMeters,
            paceSecondsPerKilometer: pace,
            estimatedActiveKilocalories: estimatedActiveKilocalories,
            glassesConnected: glassesConnected
        )
        await mirror.send(snapshot: snapshot)
    }

    private func stopRuntimeTasks() {
        stateTask?.cancel(); stateTask = nil
        metricTask?.cancel(); metricTask = nil
        elapsedTask?.cancel(); elapsedTask = nil
        tickTask?.cancel(); tickTask = nil
        glassesStateTask?.cancel(); glassesStateTask = nil
        glassesStatusTask?.cancel(); glassesStatusTask = nil
    }

    private func teardownTransport() async {
        guard let transport else { return }
        try? await transport.disconnect()
        self.transport = nil
        self.glasses = nil
    }
}

/// Sendable surface the view-model uses to push live snapshots and lifecycle
/// events at the iPhone mirror. Concrete impl wraps `WatchConnectivityService`
/// so the view-model itself stays free of WCSession dependencies and stays
/// testable on the simulator.
protocol WorkoutMirrorPublisher: Sendable {
    func send(snapshot: WorkoutTickMessage) async
    func sendLifecycle(_ event: LifecycleEvent) async
}
