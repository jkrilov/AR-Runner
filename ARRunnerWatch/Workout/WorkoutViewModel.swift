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

    // MARK: - Action Button state (v0.5.x)

    /// Splits recorded via the Apple Watch Ultra Action Button (mode
    /// `.splits`). Each entry captures the elapsed-time *delta* since the
    /// previous split (or workout start for the first) and the wall-clock
    /// instant of the press, so they can be projected into a TCX-friendly
    /// `WorkoutSplit` at save time without holding the controller hostage.
    ///
    /// Cleared on every `resetLiveCounters()` so a fresh workout starts at
    /// split 1. Read-only from outside the view-model.
    private(set) var actionButtonSplits: [ActionButtonSplit] = []

    /// Tracks the user's intent for the glasses display when toggled via
    /// the Action Button (mode `.toggleHUD`). The actual ActiveLook
    /// `power(on:)` BLE command is queued on the transport from
    /// `toggleHUDFromActionButton()`; this flag lets the UI mirror the
    /// requested state immediately even before the BLE write completes.
    ///
    /// Defaults to `true` (HUD on) so the very first toggle hides the HUD
    /// — matching the user's mental model of "press to turn it off".
    private(set) var hudVisible: Bool = true

    /// Lightweight in-memory record of a split press. `delta` is the
    /// elapsed seconds since the previous split (or workout start), which
    /// is what Strava/TCX consumers actually want; `elapsedAtPress` is the
    /// raw workout clock value for debugging / analytics.
    struct ActionButtonSplit: Equatable, Sendable {
        let index: Int
        let elapsedAtPress: TimeInterval
        let delta: TimeInterval
        let distanceMetersAtPress: Double?
        let wallClock: Date
    }

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
            // rc13 Bug B defensive: a stale push-policy `lastPayload` could
            // gate the first per-tick frame of this workout if the prior
            // workout ended with an identical zero-state payload (e.g.,
            // user starts → immediately cancels → starts again). And the
            // splash path cleared `needsHUDPowerOn` on connect, so the
            // first run after pre-pair would NOT re-assert cfgSet+power.
            // Reset both at every workout start so the first live HUD
            // frame is guaranteed to ship `cfgSet → power(on:true) →
            // holdFlush → clear → 3×txt → flush`, fully restoring the
            // display state regardless of what happened pre-workout.
            hudPushPolicy.reset()
            needsHUDPowerOn = true
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
    ///
    /// **rc17 fix — finish-screen visibility + BLE keep-alive.** Joe reported
    /// (rc16 bench): "The connection drops when I finish a run, I don't see
    /// the finish screen we planned and the connection to the glasses is
    /// lost." Two-part root cause:
    ///
    /// 1. `pushHUDSummaryIfConnected()` ran *after* `controller.end()`, by
    ///    which point `HKWorkoutSession.end()` had already released the
    ///    extended-runtime allowance. The watch app was racing the OS for
    ///    foreground time; on a real Watch the suspend usually wins and the
    ///    finish frame never makes it across BLE.
    /// 2. We then immediately called `teardownTransport()`, which disconnects
    ///    the BLE link — even if the finish frame had been queued, the
    ///    glasses dropped it and the wearer had to manually reconnect.
    ///
    /// Fix: stop the per-tick HUD task first so the live HUD can't race-overwrite
    /// the summary, push the finish frame while the HK session is *still*
    /// running (foreground runtime + radio guaranteed), then end the HK
    /// session, and intentionally leave the BLE transport connected so the
    /// finish screen persists on the glasses for the wearer to read. The
    /// user explicitly disconnects via the existing `disconnectGlasses()`
    /// affordance when they're done.
    func confirmSave() async {
        guard let controller else { return }
        launchState = .ending
        // Stop per-tick HUD pushes BEFORE the finish frame so the live HUD
        // can't race-overwrite the summary. The HK session keeps running
        // until `controller.end()` below.
        // rc3 — `stopRuntimeTasks()` is now workout-scoped (per the
        // post-rc2 BLE-UI-freeze fix on this method's docstring). The
        // glasses observation tasks are intentionally preserved so the
        // post-finish idle screen continues to reflect live BLE state.
        stopRuntimeTasks()
        // Push the finish screen while HK is still active — we still have
        // foreground runtime + BLE radio. Frames go out immediately.
        await pushHUDSummaryIfConnected()
        do {
            let summary = try await controller.end()
            launchState = .ended(summary)
            await mirror?.sendLifecycle(.ended)
        } catch {
            launchState = .failed(String(describing: error))
        }
        // Intentionally NO teardownTransport(). The finish screen must
        // persist on the glasses so the wearer can read final stats post-run.
        // Idle BLE costs ~0 power on Engo 2; user explicitly disconnects
        // from the ended/idle screen via `disconnectGlasses()` (rc17 fix).
    }

    /// Cancel path: discard the underlying HK workout (no `HKWorkout`
    /// sample is written) and mark the local UI as cancelled.
    ///
    /// **rc2 (2026-05-20) bench-feedback fix — data integrity.** Joe ran a
    /// 5K and discarded the run; it still appeared in Apple Fitness. Root
    /// cause: prior to rc2 this method called `controller.end()`, which
    /// goes through `HealthKitWorkoutSubstrate.end(at:)` → `builder
    /// .finishWorkout()` and **always persists** an `HKWorkout`. We now
    /// route through the dedicated `controller.discard()` terminal path
    /// (rc2 — `WorkoutHealthSubstrate.discard(at:)`) which calls
    /// `builder.discardWorkout()` so nothing reaches Health. There is
    /// deliberately NO "save then maybe delete" — a delete-failure on
    /// save-first would leak partial data, which is exactly the class of
    /// bug we're closing.
    ///
    /// rc17 BLE-link contract still holds: stop runtime tasks, but leave
    /// the BLE transport connected. The wearer disconnects explicitly via
    /// `disconnectGlasses()` per ADR-1.
    ///
    /// **rc3 (2026-05-20) bench-feedback fix — discard returns to start.**
    /// Joe reported (v0.4.0-rc2 bench): "Discard a run → glasses disconnect,
    /// stuck state, can't reconnect without killing app." Two coupled issues:
    /// 1. `stopRuntimeTasks()` cancelled the glasses observation tasks,
    ///    so the view-model went blind to subsequent connection-state
    ///    changes — the UI showed stale "connected" but reconnect/disconnect
    ///    operated on a transport whose observer was dead.
    /// 2. Transitioning to `.cancelled` left the watch on a terminal state
    ///    rather than the start screen, so the next workout attempt
    ///    couldn't kick off cleanly.
    /// Fix: now that `stopRuntimeTasks()` is workout-scoped (preserves
    /// glasses observers — see its docstring), `confirmCancel` can safely
    /// use it. Land back on `.idle` with live counters reset so the start
    /// screen is functional with BLE still alive.
    func confirmCancel() async {
        guard let controller else { return }
        launchState = .ending
        stopRuntimeTasks()
        do {
            try await controller.discard()
        } catch {
            launchState = .failed(String(describing: error))
            return
        }
        // Drop the controller so the next `start()` builds a fresh
        // substrate/controller pair (the old streams were finished by
        // `controller.discard()` and would yield nothing).
        self.controller = nil
        resetLiveCounters()
        launchState = .idle
        await mirror?.sendLifecycle(.ended)
    }

    func resumeFromFinish() async {
        await resume()
    }

    // MARK: - Action Button entry points (v0.5.x)

    /// Called by `ActionButtonCoordinator` when the user presses the Apple
    /// Watch Ultra Action Button and `ActionButtonMode == .splits`.
    /// Records a split marker against the live workout clock. Returns
    /// `true` if a split was actually recorded so the coordinator knows to
    /// play the confirmation haptic (no-op presses outside a running
    /// workout return `false` and play nothing).
    @discardableResult
    func markSplitFromActionButton() -> Bool {
        guard launchState == .running else { return false }
        let prev = actionButtonSplits.last?.elapsedAtPress ?? 0
        let delta = max(0, elapsed - prev)
        let split = ActionButtonSplit(
            index: actionButtonSplits.count + 1,
            elapsedAtPress: elapsed,
            delta: delta,
            distanceMetersAtPress: distanceMeters,
            wallClock: now()
        )
        actionButtonSplits.append(split)
        return true
    }

    /// Called by `ActionButtonCoordinator` for `ActionButtonMode
    /// .pauseResume`. Pauses if the workout is running, resumes if paused.
    /// Returns `true` when a toggle actually occurred so the coordinator
    /// can play the haptic; ignored during terminal / pending-finish
    /// states so a stray press can't strand the workout.
    @discardableResult
    func togglePauseResumeFromActionButton() -> Bool {
        switch launchState {
        case .running:
            Task { await pause() }
            return true
        case .paused:
            Task { await resume() }
            return true
        default:
            return false
        }
    }

    /// Called by `ActionButtonCoordinator` for `ActionButtonMode
    /// .toggleHUD`. Flips the in-app `hudVisible` flag and fires the
    /// corresponding ActiveLook `power(on:)` command if a transport is
    /// wired and connected. Safe to call when the transport is offline —
    /// the flag still toggles so the next HUD push picks up the user's
    /// intent (Weiss's BLE layer can additionally gate frame pushes on
    /// `hudVisible` when it lands the richer enable/disable semantics).
    func toggleHUDFromActionButton() {
        hudVisible.toggle()
        let desired = hudVisible
        guard let transport else { return }
        Task { [weak self] in
            guard await transport.connectionState == .connected else { return }
            let frame = ActiveLookCommand.power(on: desired)
            try? await transport.sendCommands([frame])
            if desired {
                // Repaint the live HUD immediately on power-up so the
                // wearer doesn't sit on a blank panel until the next 1Hz tick.
                await self?.pushHUDFrameIfConnected(transport: transport)
            }
        }
    }

    /// Synchronously leave `.pendingFinish` so SwiftUI's
    /// `confirmationDialog` dismissal binding cannot observe the
    /// pre-finish state when the user makes an explicit Save/Discard
    /// choice. Must be called from the Save/Discard button actions
    /// *before* scheduling the async terminal `Task`.
    ///
    /// **rc4 (2026-05-20) bench-feedback fix — discard returns to running
    /// screen instead of start screen.** Joe reported (v0.4.0-rc3 bench):
    /// discarding still doesn't go back to the start screen. Root cause was
    /// a SwiftUI ordering race in `WorkoutView.finishMenuBinding`:
    /// tapping "Discard" enqueued `Task { confirmCancel() }`, and in the
    /// same tick SwiftUI also dismissed the dialog and invoked the
    /// binding's `set(false)`. At that synchronous moment `launchState ==
    /// .pendingFinish` was still true (the Task hadn't started), so the
    /// binding setter spawned a second `Task { resumeFromFinish() }`. The
    /// two terminal actions raced on the same controller; `resume()`
    /// would resolve after `confirmCancel`'s final `.idle` write and
    /// overwrite it with `.running`, stranding the wearer on the live
    /// workout screen post-discard. Same race latently afflicted Save.
    ///
    /// Fix: synchronously transition `.pendingFinish` → `.ending` from the
    /// button action. By the time the binding setter fires synchronously
    /// next, the auto-resume guard (`launchState == .pendingFinish`) is
    /// false and `resumeFromFinish()` is not spawned. `confirmCancel` /
    /// `confirmSave` re-assert `.ending` (idempotent) so their own
    /// preconditions still hold when invoked directly from tests.
    func acknowledgeFinishChoice() {
        if launchState == .pendingFinish {
            launchState = .ending
        }
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

    /// rc4 regression fix: Engo 2 firmware boots with the display in a
    /// low-power state after a fresh BLE connect. The splash text
    /// ("Connection Successful") is visible because the firmware paints
    /// it as part of the link-up sequence, but subsequent `txt` draws
    /// from the host are silently dropped until we send `power(on:true)`
    /// (cmdID 0x00) at least once.
    ///
    /// PR #49 cleared the splash without sending `power(on:true)` first —
    /// which is exactly what put Joe's rc4 device into the "blank screen
    /// on connect, nothing during the run" state. We track per-connection
    /// whether power-on has been sent and prepend it to the very next HUD
    /// frame as a belt-and-braces guarantee. Reset on every disconnect
    /// edge so a reconnect re-sends it.
    private var needsHUDPowerOn: Bool = true

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
                    await self?.markNeedsHUDPowerOn()
                    await self?.pushHUDConnectScreenIfConnected(transport: transport)
                } else if state == .disconnected || state == .reconnecting || state == .failed {
                    await resolvedService.resetThrottle()
                    await self?.resetHUDPushPolicy()
                    await self?.markNeedsHUDPowerOn()
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

    fileprivate func markNeedsHUDPowerOn() {
        needsHUDPowerOn = true
    }

    /// One-shot post-connect screen: `power on → clear → "AR-Runner Ready"`.
    /// Painted as soon as the BLE link comes up so the wearer can confirm
    /// pairing without having to also start a workout. Bypasses the push
    /// policy (which is workout-scoped) and consumes the `needsHUDPowerOn`
    /// flag so the next HUD frame doesn't redundantly re-send power-on.
    fileprivate func pushHUDConnectScreenIfConnected(transport overrideTransport: (any GlassesFrameTransport)? = nil) async {
        guard let transport = overrideTransport ?? self.transport else { return }
        guard await transport.connectionState == .connected else { return }
        let frames = RunningHUDFrame.connectFrames()
        try? await transport.sendCommands(frames)
        // connectFrames already includes power(on:true).
        needsHUDPowerOn = false
        // If a workout is already running when (re)connect lands, also
        // paint the current live HUD so the wearer doesn't sit on the
        // "Ready" splash mid-run. The frame builder is cheap; the push
        // policy was just reset so this will fire immediately.
        if case .running = launchState {
            await pushHUDFrameIfConnected(transport: transport)
        }
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
            distanceMeters: distanceMeters ?? 0,
            heartRate: heartRate
        )
        guard hudPushPolicy.shouldSend(payload, now: now()) else { return }
        guard await transport.connectionState == .connected else { return }
        // rc4 regression: the very first frame of a connection prepends
        // `power(on:true)` so Engo 2's display is guaranteed to be active
        // before any `txt` draws land. Subsequent ticks use plain frames
        // to keep BLE writes minimal.
        let frames: [[UInt8]]
        if needsHUDPowerOn {
            frames = RunningHUDFrame.framesWithPowerOn(for: payload)
            needsHUDPowerOn = false
        } else {
            frames = RunningHUDFrame.frames(for: payload)
        }
        try? await transport.sendCommands(frames)
    }

    /// End-of-workout splash — single fire-and-forget push with the final
    /// stats. Bypasses the throttle (it's a one-shot lifecycle event) but
    /// still no-ops if the link is down.
    fileprivate func pushHUDSummaryIfConnected() async {
        guard let transport else { return }
        guard await transport.connectionState == .connected else { return }
        // rc2: finish-screen reshape (3-line / 4-data layout — "Finished!",
        // distance, time + right-justified pace). The summary builder now
        // uses time, distance, and pace from the payload (rc14's HR/pace
        // drop is superseded — see `RunningHUDFrame.summaryFrames`). HR
        // is still passed through for Payload symmetry but unused.
        let payload = RunningHUDFrame.payload(
            elapsedSeconds: elapsed,
            distanceMeters: distanceMeters ?? 0,
            heartRate: heartRate
        )
        // Same power-on belt-and-braces as the per-tick path: if the
        // display drifted into low-power between the last tick and the
        // save tap, the splash would otherwise render into a dark panel.
        let frames: [[UInt8]]
        if needsHUDPowerOn {
            frames = RunningHUDFrame.summaryFramesWithPowerOn(for: payload)
            needsHUDPowerOn = false
        } else {
            frames = RunningHUDFrame.summaryFrames(for: payload)
        }
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
        case .batteryLevel(let level):
            // v0.4 — forward to the iPhone mirror for the phone-side battery
            // indicator. Phone-optional: the WC layer silently drops when
            // unreachable so the watch is never blocked on phone availability.
            await mirror?.sendGlassesBattery(level)
        case .signalQuality, .reconnectAttemptFailed:
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
        actionButtonSplits = []
        hudVisible = true
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
                await self?.tickElapsed()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tickElapsed() async {
        guard let startedAt else { return }
        if case .running = launchState {
            elapsed = Date().timeIntervalSince(startedAt)
            // v0.3 HUD MVP: render the time/distance/pace HUD at 1Hz off
            // the elapsed ticker. The push policy gates on minimum-interval
            // + payload-change so a frozen pace (`--:--/mi` while distance
            // < 0.01 mi) doesn't generate redundant BLE traffic.
            //
            // rc13 Bug B fix: await the push directly (was previously
            // spawned as a fire-and-forget `Task { … }`). The spawned
            // pattern raced with the `start()`-time explicit push AND
            // with the connect-state-task's `pushHUDConnectScreenIfConnected`
            // → two `sendCommands(_:)` calls could interleave their
            // per-frame `try await write(_:)` loops on the
            // `ActiveLookGlassesAdapter` actor (reentrant between writes),
            // smearing a per-tick `holdFlush → clear → 3×txt → flush`
            // sequence across BLE writes from another sequence. A premature
            // `holdFlush(hold:false)` from one sequence would commit the
            // partial buffer of the other, leaving the display stuck on
            // whatever pre-tick frame was visible (the splash, in Joe's
            // bench scenario). Awaiting serializes per-tick pushes on the
            // MainActor so the BLE actor only ever sees one complete
            // sequence at a time.
            await pushHUDFrameIfConnected()
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
            // rc2 — propagate the workout's wall-clock start time so the
            // phone mirror can show a "Started at …" row. Carried on
            // every tick (not a one-shot lifecycle event) so a phone
            // that wakes mid-run sees it on the first snapshot.
            startedAt: startedAt,
            elapsedSeconds: elapsed,
            heartRateBeatsPerMinute: heartRate,
            distanceMeters: distanceMeters,
            paceSecondsPerKilometer: pace,
            estimatedActiveKilocalories: estimatedActiveKilocalories,
            glassesConnected: glassesConnected
        )
        await mirror.send(snapshot: snapshot)
    }

    /// Cancel workout-scoped observation tasks. Per ADR-1 ("BLE link is
    /// user-managed, not workout-scoped"), the glasses connection-state and
    /// status-event observers are **transport-scoped** and intentionally
    /// excluded — they must outlive every save/discard so the watch UI
    /// continues to reflect the real BLE state on the post-workout screen.
    ///
    /// **rc2 (2026-05-20) bug fix — discard kills the glasses link, UI freezes.**
    /// Joe reported (rc2 bench): discarding a run leaves the watch UI showing
    /// "Glasses: Connected" while the BLE link is dead, and tapping
    /// Disconnect does nothing — only killing the app recovers.
    ///
    /// Root cause: this method previously also cancelled
    /// `glassesStateTask` and `glassesStatusTask`. After a discard those
    /// tasks were torn down and never re-attached (the start path reuses
    /// the existing transport without re-calling `attachGlasses`). The
    /// view-model therefore stopped mirroring transport-state changes into
    /// `glassesLinkState`, so:
    ///   * the UI froze on the last-observed state (stale "connected"),
    ///   * `disconnectGlasses()` actually *did* tear down the link, but the
    ///     UI never saw the resulting `.disconnected` event,
    ///   * `connectGlasses()` early-returned on the stale `.connected` read,
    /// and the only recovery was an app restart, which re-built the
    /// view-model and re-attached the observers.
    ///
    /// Fix: keep the glasses observation tasks alive across workout
    /// terminal states. They are bound to the transport's lifetime (which
    /// matches the view-model's), not the workout's.
    private func stopRuntimeTasks() {
        stateTask?.cancel(); stateTask = nil
        metricTask?.cancel(); metricTask = nil
        elapsedTask?.cancel(); elapsedTask = nil
        tickTask?.cancel(); tickTask = nil
        // glassesStateTask / glassesStatusTask intentionally NOT cancelled —
        // see method docs (rc2 BLE-UI-freeze fix / ADR-1).
    }

}

/// Sendable surface the view-model uses to push live snapshots and lifecycle
/// events at the iPhone mirror. Concrete impl wraps `WatchConnectivityService`
/// so the view-model itself stays free of WCSession dependencies and stays
/// testable on the simulator.
protocol WorkoutMirrorPublisher: Sendable {
    func send(snapshot: WorkoutTickMessage) async
    func sendLifecycle(_ event: LifecycleEvent) async
    /// v0.4 — push the glasses' last-known battery level (0–100) to the
    /// iPhone. Low-frequency (~30 s notify cadence per the Battery Service
    /// spec) and phone-optional: implementations MUST silently drop when
    /// the WC link is unreachable so the watch run is never blocked.
    func sendGlassesBattery(_ level: Int) async
}
