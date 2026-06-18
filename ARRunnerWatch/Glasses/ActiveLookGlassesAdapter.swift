// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
@preconcurrency import CoreBluetooth
import Foundation
import os

/// watchOS-native implementation of `GlassesFrameTransport` for ActiveLook
/// glasses, built directly on CoreBluetooth (no vendor SDK — none ships for
/// watchOS as of v0.1; see `docs/research/activelook/watchos-ble-spike.md`).
///
/// Decisions referenced:
///   * **D1** — Watch owns the BLE link directly.
///   * **D4** — Workout continues if glasses drop. Auto-reconnect with
///              exponential backoff, drop events surfaced via status stream.
///   * **D6** — Runtime traffic is field-value updates only (~20–40 bytes/tick).
///   * **D7** — Foreground operation; HKWorkoutSession provides the BLE
///              background-execution privilege at the workout layer.
///   * **D8** — Swift 6 strict concurrency. CoreBluetooth is imported
///              `@preconcurrency` because `CBPeripheral` / `CBCharacteristic`
///              are not formally `Sendable`.
///
/// Threading model:
///   * The actor owns all mutable state.
///   * A nested `Coordinator: NSObject` implements the CoreBluetooth
///     delegate methods on a private dispatch queue and forwards each event
///     into the actor via `Task { await … }`.
///   * Continuation hand-off into the actor is the only place we cross the
///     CB → Swift-concurrency boundary.
public actor ActiveLookGlassesAdapter: GlassesFrameTransport {
    // MARK: - Public surface

    public private(set) var connectionState: GlassesConnectionState = .disconnected

    public func connectionStates() -> AsyncStream<GlassesConnectionState> {
        let snapshot = connectionState
        let id = UUID()
        return AsyncStream { continuation in
            self.attachStateContinuation(continuation, id: id, snapshot: snapshot)
        }
    }

    public func statusEvents() -> AsyncStream<GlassesStatusEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.attachStatusContinuation(continuation, id: id)
        }
    }

    // MARK: - Configuration

    private let backoff: ExponentialBackoff
    private let scanTimeout: TimeInterval
    private let knownPeripheralConnectTimeout: TimeInterval
    private let maxReconnectAttempts: Int
    private let defaultPreset: RunningHUDPreset?
    private let prefs: GlassesPairingPreferences
    private let logger = Logger(subsystem: "com.arrunner.watch", category: "ActiveLookGlasses")
    /// Dedicated category for the scan-filter + fast-reconnect logs added
    /// alongside the manufacturer-data fix. Keeps the firehose searchable
    /// (`category:Glasses`) without mixing into the broader adapter log.
    private let glassesLogger = Logger(subsystem: "com.arrunner.watch", category: "Glasses")

    public init(
        backoff: ExponentialBackoff = .adrV04,
        scanTimeout: TimeInterval = 15.0,
        knownPeripheralConnectTimeout: TimeInterval = 8.0,
        maxReconnectAttempts: Int = .max,
        defaultPreset: RunningHUDPreset? = nil,
        prefs: GlassesPairingPreferences = .shared
    ) {
        self.backoff = backoff
        self.scanTimeout = scanTimeout
        self.knownPeripheralConnectTimeout = knownPeripheralConnectTimeout
        self.maxReconnectAttempts = maxReconnectAttempts
        self.defaultPreset = defaultPreset
        self.prefs = prefs
        // v0.3 HUD MVP: do NOT auto-pre-seed `activeLayoutDeviceID` from
        // `RunningHUDPreset.default` any more. The curated catalog only
        // ships placeholder slot IDs (0x01–0x03) — activating one on real
        // hardware is exactly the bug Joe's bench test hit (glasses stuck
        // on "Connection Successful"). The v0.3 raw-text HUD renders via
        // `sendCommands(_:)` and does not depend on a pre-baked layout.
        // Callers that want the curated path back (once Config-Generator
        // bakes real slots) pass an explicit `defaultPreset:` again.
        if let preset = defaultPreset,
           let id = preset.deviceLayoutID,
           !CuratedLayoutCatalog.placeholderDeviceIDs.contains(id) {
            self.activeLayoutDeviceID = id
        }
    }

    deinit {
        // Cancel any in-flight reconnect loop so it doesn't keep a strong
        // reference to peripherals after the actor is gone. `Task.cancel()`
        // is nonisolated so it is legal from `deinit`.
        reconnectTask?.cancel()
    }

    // MARK: - Private state

    private var coordinator: Coordinator?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    /// Set when we attempted a known-peripheral direct connect (without
    /// scanning) via `retrievePeripherals(withIdentifiers:)`. If the
    /// connect doesn't complete within `knownPeripheralConnectTimeout`,
    /// we drop the peripheral and fall back to the manufacturer-data
    /// scan path.
    private var fastReconnectAttempted = false
    /// Captured peripheral name at successful connect time. Held independently
    /// of `peripheral` so the pre-run UI can keep showing
    /// `Glasses: {name}` between auto-reconnect attempts when `peripheral`
    /// has been nilled out by `handleDisconnect`.
    private var lastConnectedName: String?

    public var connectedDeviceName: String? {
        get async {
            guard case .connected = connectionState else { return nil }
            return lastConnectedName
        }
    }

    private var stateContinuations: [UUID: AsyncStream<GlassesConnectionState>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<GlassesStatusEvent>.Continuation] = [:]

    private var pendingConnect: CheckedContinuation<Void, Error>?
    private var reconnectTask: Task<Void, Never>?
    private var lastDropAt: Date?
    private var activeLayoutDeviceID: UInt8?
    private var userDisconnectRequested = false

    /// Standard BLE Battery Service (0x180F / 0x2A19) filter — clamps
    /// out-of-range bytes and suppresses identical consecutive
    /// notifications (the firmware re-publishes the same percent every
    /// ~30 s). Reset on every transition out of `.connected` so the first
    /// post-reconnect read always lands.
    private var batteryFilter = BatteryLevelFilter()

    // MARK: - Write serialization (ActiveLook protocol requirement)
    //
    // The ActiveLook SDK gates every BLE write on:
    //   1. Flow control characteristic confirming "ready" (notification subscription active)
    //   2. Previous write acknowledged via `didWriteValueFor`
    //
    // Without this, commands written immediately after connect are silently
    // dropped by the glasses' firmware — the root cause of the rc4/rc5
    // blank-screen regression.

    /// Whether the flow control characteristic's notification subscription
    /// has been confirmed by CoreBluetooth. The glasses are not ready to
    /// accept commands until this is true. Mirrors the ActiveLook SDK's
    /// `isReady()` gate in `GlassesInitializer.swift`.
    private var flowControlNotifyConfirmed = false

    /// Runtime flow-control state. The control characteristic (0xCB9)
    /// publishes `0x01` (ON — buffer OK) and `0x02` (OFF — buffer 75% full,
    /// client MUST stop). PRs #49/#53/#55 never read this characteristic's
    /// value — only the notification *subscription* — so a runtime "OFF"
    /// from the glasses would be silently dropped while writes kept landing
    /// at the GATT layer. Default: true (assume OK until told otherwise).
    private var flowControlAllowsWrite: Bool = true

    /// Continuation awaiting the next `0x01` (ON) signal on the control
    /// characteristic. Populated when `write(_:)` finds flow control OFF;
    /// resumed by `handleControlValue(0x01)`.
    private var flowControlContinuation: CheckedContinuation<Void, Never>?

    /// Per-connection queryID counter. Every ActiveLook application command
    /// frame includes a 1-byte queryID that the firmware echoes in error and
    /// response notifications. The encoder emits `0x00` as a placeholder;
    /// `write(_:)` stamps the next ID here just before
    /// `peripheral.writeValue`. Wraps 0xFF → 0x01 (0x00 is reserved as the
    /// encoder's placeholder so accidental skips remain debuggable).
    private var nextQueryID: UInt8 = 0x01

    /// Continuation awaiting the current write's `didWriteValueFor` callback.
    /// Only one write is in-flight at a time — the ActiveLook protocol
    /// requires serial command delivery.
    private var pendingWrite: CheckedContinuation<Void, Error>?

    // MARK: - Lifecycle

    public func connect() async throws {
        if case .connected = connectionState { return }
        if case .connecting = connectionState { return }

        userDisconnectRequested = false
        try await beginConnect()
    }

    public func disconnect() async throws {
        userDisconnectRequested = true
        reconnectTask?.cancel()
        reconnectTask = nil

        // Cancel any in-flight write.
        pendingWrite?.resume(throwing: GlassesTransportError.notConnected)
        pendingWrite = nil
        flowControlContinuation?.resume()
        flowControlContinuation = nil
        flowControlAllowsWrite = true
        flowControlNotifyConfirmed = false
        nextQueryID = 0x01
        batteryFilter.reset()

        if let central, let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        rxCharacteristic = nil
        central = nil
        coordinator = nil

        transition(to: .disconnected)
    }

    public func selectLayout(id: String) async throws {
        guard case .connected = connectionState else {
            throw GlassesTransportError.notConnected
        }
        guard let deviceID = CuratedLayoutCatalog.deviceID(for: id) else {
            throw GlassesTransportError.unknownLayout(id: id)
        }
        // P1.4 (audit 2026-05-16): trap in debug if we're about to ship a
        // pre-bake placeholder slot to real hardware. Release builds get a
        // silent fault log via the adapter logger below so a leaked build
        // is at least observable in the side store, never silent UX.
        CuratedLayoutCatalog.assertNotPlaceholder(deviceID, layoutID: id)
        if CuratedLayoutCatalog.placeholderDeviceIDs.contains(deviceID) {
            logger.fault("Activating placeholder layout slot 0x\(String(deviceID, radix: 16), privacy: .public) for \(id, privacy: .public) — Config-Generator bake step has not run. See .squad/audits/2026-05-16-weiss-ar-ble.md (P1.4).")
        }
        activeLayoutDeviceID = deviceID
        try await write(ActiveLookCommand.displayLayout(id: deviceID))
    }

    public func updateField(_ update: HUDFieldUpdate) async throws {
        guard case .connected = connectionState else {
            throw GlassesTransportError.notConnected
        }
        guard let deviceID = CuratedLayoutCatalog.deviceID(for: update.layoutID) else {
            throw GlassesTransportError.unknownLayout(id: update.layoutID)
        }
        // P1.4 — same guard at the per-tick write site.
        CuratedLayoutCatalog.assertNotPlaceholder(deviceID, layoutID: update.layoutID)
        // ActiveLook layouts are one-field-per-slot (spec §4.9); the device
        // layout ID *is* the slot identity. Push the new value via the
        // atomic clear+draw primitive (0x69) — the phantom 0x3A widgetUpdate
        // command was removed (it does not exist in the ActiveLook spec).
        let frame = ActiveLookCommand.layoutClearAndDisplay(
            id: deviceID,
            text: update.value
        )
        try await write(frame)
    }

    /// v0.3 raw-text HUD path. Writes pre-encoded ActiveLook frames straight
    /// to the RX characteristic in order. No `CuratedLayoutCatalog` lookup —
    /// these frames are already complete `[clear, txt, txt, txt]` sequences
    /// produced by `RunningHUDFrame.frames(for:)`. If a write fails mid-batch
    /// we surface the error to the caller (the workout pipeline swallows it
    /// per D4 — BLE noise stays in BLE).
    public func sendCommands(_ frames: [[UInt8]]) async throws {
        guard case .connected = connectionState else {
            throw GlassesTransportError.notConnected
        }
        for frame in frames {
            try await write(frame)
        }
    }

    // MARK: - Internal

    private func beginConnect() async throws {
        let coordinator = Coordinator(adapter: self)
        self.coordinator = coordinator
        let queue = DispatchQueue(label: "com.arrunner.watch.activelook.ble")
        let central = CBCentralManager(delegate: coordinator, queue: queue)
        self.central = central

        transition(to: .scanning)

        // The actual scanForPeripherals call has to wait for the central to
        // reach `.poweredOn`. The coordinator drives that transition via
        // `centralManagerDidUpdateState(_:)`.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.pendingConnect = continuation
        }
    }

    fileprivate func handleCentralStateUpdate(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            if tryRetrieveKnownPeripheral() { return }
            startScan()
        case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
            failPendingConnect(with: GlassesTransportError.bluetoothUnavailable)
            transition(to: .failed)
        @unknown default:
            failPendingConnect(with: GlassesTransportError.bluetoothUnavailable)
            transition(to: .failed)
        }
    }

    /// Fast-reconnect path mirroring ActiveLook's own iOS SDK (lines 368,
    /// 240–298 in `ActiveLookSDK.swift`). When we have a persisted
    /// `peripheral.identifier` from a prior successful pair AND the system
    /// still knows that peripheral, we can skip scanning entirely and go
    /// straight to `connect(peripheral)`.
    ///
    /// Returns `true` if we kicked off a known-peripheral connect (caller
    /// must not also start a scan). Returns `false` to mean "no saved
    /// peripheral OR the system has evicted it from its cache — fall back
    /// to the scan path."
    private func tryRetrieveKnownPeripheral() -> Bool {
        guard let central, let savedID = prefs.pairedPeripheralID else {
            return false
        }
        let known = central.retrievePeripherals(withIdentifiers: [savedID])
        guard let peripheral = known.first else {
            glassesLogger.info("Known peripheral \(savedID.uuidString, privacy: .public) not in system cache; falling back to scan")
            return false
        }

        glassesLogger.info("Fast-reconnect: retrieved known peripheral \(savedID.uuidString, privacy: .public); skipping scan")
        self.peripheral = peripheral
        peripheral.delegate = coordinator
        transition(to: .connecting)
        fastReconnectAttempted = true
        central.connect(peripheral, options: nil)

        // Safety net: if the system never delivers `didConnect` (e.g.
        // glasses are powered off / out of range), don't hang forever —
        // tear this attempt down and fall back to the scan-with-filter
        // path so the user still sees a result within ~scanTimeout.
        Task { [weak self, knownPeripheralConnectTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(knownPeripheralConnectTimeout * 1_000_000_000))
            await self?.timeoutFastReconnectIfStillConnecting()
        }
        return true
    }

    private func timeoutFastReconnectIfStillConnecting() {
        guard fastReconnectAttempted else { return }
        guard case .connecting = connectionState else { return }
        fastReconnectAttempted = false
        glassesLogger.warning("Fast-reconnect timed out after \(self.knownPeripheralConnectTimeout, privacy: .public)s; falling back to manufacturer-data scan")
        if let central, let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        transition(to: .scanning)
        startScan()
    }

    private func startScan() {
        guard let central else { return }
        // ActiveLook / Engo 2 glasses do NOT advertise their 128-bit
        // command service UUID — it lives only on the GATT table after
        // connect — so a `withServices: [commandServiceUUID]` filter
        // would never match. Scan with nil services and filter by
        // manufacturer-data company-ID (`0xFA 0xDA`) inside
        // `handleDiscovered`. Mirrors ActiveLook's own iOS SDK
        // (`Sources/Classes/Public/ActiveLookSDK.swift:192`).
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        Task { [weak self, scanTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(scanTimeout * 1_000_000_000))
            await self?.timeoutScanIfStillScanning()
        }
    }

    private func timeoutScanIfStillScanning() {
        guard case .scanning = connectionState else { return }
        central?.stopScan()
        failPendingConnect(with: GlassesTransportError.scanTimeout)
        transition(to: .failed)
    }

    fileprivate func handleDiscovered(_ peripheral: CBPeripheral, manufacturerData: Data?) {
        guard self.peripheral == nil else { return }

        guard GlassesAdvertisementFilter.isActiveLookPeripheral(manufacturerData: manufacturerData) else {
            glassesLogger.info("Discovery filter rejected peripheral \(peripheral.identifier.uuidString, privacy: .public) — manufacturer data did not match Microoled 0xFA 0xDA prefix")
            return
        }

        glassesLogger.info("Discovery filter accepted ActiveLook peripheral \(peripheral.identifier.uuidString, privacy: .public)")
        central?.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = coordinator
        transition(to: .connecting)
        central?.connect(peripheral, options: nil)
    }

    fileprivate func handleConnected(_ peripheral: CBPeripheral) {
        // Successful connect cancels any pending fast-reconnect timeout
        // (it's now this peripheral's job to drive the rest of the
        // handshake via service/characteristic discovery).
        fastReconnectAttempted = false
        peripheral.discoverServices([
            CBUUID(string: ActiveLookGATT.commandService),
            CBUUID(string: ActiveLookGATT.batteryService)
        ])
    }

    fileprivate func handleServicesDiscovered(_ peripheral: CBPeripheral) {
        guard let services = peripheral.services else {
            failPendingConnect(with: GlassesTransportError.writeFailed(reason: "no services"))
            transition(to: .failed)
            return
        }

        var sawCommandService = false
        for service in services {
            if service.uuid == CBUUID(string: ActiveLookGATT.commandService) {
                sawCommandService = true
                peripheral.discoverCharacteristics([
                    CBUUID(string: ActiveLookGATT.rxCharacteristic),
                    CBUUID(string: ActiveLookGATT.txCharacteristic),
                    CBUUID(string: ActiveLookGATT.controlChar)
                ], for: service)
            } else if service.uuid == CBUUID(string: ActiveLookGATT.batteryService) {
                peripheral.discoverCharacteristics(
                    [CBUUID(string: ActiveLookGATT.batteryLevelChar)],
                    for: service
                )
            }
        }

        if !sawCommandService {
            failPendingConnect(with: GlassesTransportError.writeFailed(reason: "command service missing"))
            transition(to: .failed)
        }
    }

    fileprivate func handleCharacteristicsDiscovered(_ service: CBService) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid.uuidString.uppercased() {
            case ActiveLookGATT.rxCharacteristic.uppercased():
                rxCharacteristic = characteristic
            case ActiveLookGATT.txCharacteristic.uppercased():
                peripheral?.setNotifyValue(true, for: characteristic)
            case ActiveLookGATT.controlChar.uppercased():
                peripheral?.setNotifyValue(true, for: characteristic)
            case ActiveLookGATT.batteryLevelChar.uppercased():
                peripheral?.setNotifyValue(true, for: characteristic)
                peripheral?.readValue(for: characteristic)
            default:
                break
            }
        }

        // Only flip to .connected once the command-service RX characteristic
        // is in hand AND the flow control notification subscription is
        // confirmed. The ActiveLook SDK's `GlassesInitializer.isReady()`
        // polls for `flowControlCharacteristic!.isNotifying == true` before
        // allowing any commands — without this gate, writes land before the
        // glasses' command processor is ready and are silently dropped.
        guard service.uuid == CBUUID(string: ActiveLookGATT.commandService) else { return }

        if rxCharacteristic != nil {
            // Snapshot peripheral name before any post-connect state changes.
            if let name = peripheral?.name, !name.isEmpty {
                lastConnectedName = name
            }
            if let id = peripheral?.identifier {
                prefs.pairedPeripheralID = id
                glassesLogger.info("Persisted peripheral identifier \(id.uuidString, privacy: .public) for fast reconnect")
            }

            // If flow control notifications are already confirmed (unlikely
            // on first discover, but possible on a fast re-pair where the
            // delegate fires before this path), we can go straight to ready.
            // Otherwise, `handleNotificationStateChanged` will call
            // `completeConnectionIfReady()` when the subscription confirms.
            completeConnectionIfReady()

            // Safety: if flow control never confirms (firmware quirk), don't
            // hang — force-complete after 2s. The SDK's own poll timeout was
            // also bounded. At worst we're back to the pre-fix behavior of
            // writing without flow control confirmation.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.forceFlowControlIfNeeded()
            }
        } else {
            failPendingConnect(with: GlassesTransportError.writeFailed(reason: "RX characteristic missing"))
            transition(to: .failed)
        }
    }

    /// Called when a characteristic's notification subscription state changes.
    /// We specifically care about the flow control characteristic: the glasses
    /// are not ready to accept commands until this subscription is active.
    fileprivate func handleNotificationStateChanged(_ characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.warning("Notification subscription failed for \(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        if characteristic.uuid == CBUUID(string: ActiveLookGATT.controlChar), characteristic.isNotifying {
            logger.debug("Flow control notifications confirmed active")
            flowControlNotifyConfirmed = true
            completeConnectionIfReady()
        }
    }

    /// Transition to `.connected` only when both the RX characteristic is
    /// discovered AND the flow control notification subscription is confirmed.
    /// This mirrors the ActiveLook SDK's `GlassesInitializer.isReady()` gate.
    private func completeConnectionIfReady() {
        // Already connected — don't re-enter.
        if case .connected = connectionState { return }
        guard rxCharacteristic != nil, flowControlNotifyConfirmed else {
            logger.debug("Not yet ready: rx=\(self.rxCharacteristic != nil), flowCtrl=\(self.flowControlNotifyConfirmed)")
            return
        }
        logger.info("Glasses ready: RX characteristic + flow control confirmed. Transitioning to .connected")
        if let dropAt = lastDropAt {
            emit(.reconnected(gap: Date().timeIntervalSince(dropAt), at: Date()))
            lastDropAt = nil
        }
        transition(to: .connected)
        // Re-apply layout if we had one selected before the drop.
        if let activeLayoutDeviceID {
            CuratedLayoutCatalog.assertNotPlaceholder(
                activeLayoutDeviceID,
                layoutID: "(re-apply)"
            )
            let frame = ActiveLookCommand.displayLayout(id: activeLayoutDeviceID)
            Task { try? await write(frame) }
        }
        resumePendingConnect(.success(()))
    }

    /// Safety fallback: force the flow control gate open after timeout.
    private func forceFlowControlIfNeeded() {
        guard !flowControlNotifyConfirmed, rxCharacteristic != nil else { return }
        logger.warning("Flow control notify not confirmed within 2s — forcing ready state")
        flowControlNotifyConfirmed = true
        completeConnectionIfReady()
    }

    fileprivate func handleDisconnect(error: Error?) {
        peripheral = nil
        rxCharacteristic = nil
        flowControlNotifyConfirmed = false
        // The battery characteristic is per-link (ADR I3) — its
        // subscription dies with the link. Clearing the dedup memory means
        // the first post-reconnect notify (or the explicit initial read)
        // always lands so the UI doesn't sit on a stale percent while the
        // link is recovering.
        batteryFilter.reset()
        // Cancel any in-flight write so it doesn't hang forever.
        pendingWrite?.resume(throwing: GlassesTransportError.notConnected)
        pendingWrite = nil
        // Release any caller blocked on flow control so they error out
        // through the next-write `notConnected` path instead of stalling.
        flowControlContinuation?.resume()
        flowControlContinuation = nil
        flowControlAllowsWrite = true
        nextQueryID = 0x01

        if userDisconnectRequested {
            transition(to: .disconnected)
            return
        }

        let reason: GlassesDisconnectReason
        if let nsError = error as NSError? {
            switch nsError.code {
            case 6, 7: reason = .linkLoss
            case 10:   reason = .peerPoweredOff
            default:   reason = .unknown(code: nsError.code)
            }
        } else {
            reason = .linkLoss
        }
        let now = Date()
        lastDropAt = now
        emit(.dropped(reason: reason, at: now))
        transition(to: .reconnecting)
        scheduleReconnect()
    }

    /// Battery Service (0x180F) → Battery Level (0x2A19) notification.
    /// Spec: single `uint8` percent in `[0, 100]`. The firmware fires every
    /// ~30 s after `setNotifyValue(true, ...)`; we also issue an explicit
    /// `readValue(for:)` on subscribe so the first value lands within
    /// seconds of pairing instead of waiting a full notify interval.
    ///
    /// Routed through `BatteryLevelFilter` (Core) so:
    ///   * out-of-range bytes drop with a warning (firmware bug; do not
    ///     forward to the UI),
    ///   * identical consecutive percents drop silently (no need to spam
    ///     the WC sender / on-watch indicator with redundant updates).
    fileprivate func handleBatteryLevel(_ rawByte: UInt8) {
        switch batteryFilter.process(byte: rawByte) {
        case .emit(let level):
            emit(.batteryLevel(level))
        case .dropDuplicate:
            // Hot path — quiet by design.
            break
        case .dropInvalid(let raw):
            logger.warning(
                "Battery characteristic published out-of-range byte 0x\(String(raw, radix: 16), privacy: .public) (>100). Dropping."
            )
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            await self?.runReconnectLoop()
        }
    }

    private func runReconnectLoop() async {
        var attempt = 0
        while !Task.isCancelled, !userDisconnectRequested {
            if attempt >= maxReconnectAttempts {
                // D4: terminal — stop spamming the radio. Workout keeps going;
                // caller may invoke `connect()` again to retry from scratch.
                emit(.reconnectAbandoned(attempts: attempt))
                transition(to: .failed)
                return
            }
            do {
                let delay = backoff.delay(forAttempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            do {
                try await beginConnect()
                return
            } catch {
                attempt += 1
                emit(.reconnectAttemptFailed(
                    attempt: attempt,
                    nextDelay: backoff.delay(forAttempt: attempt)
                ))
            }
        }
    }

    // MARK: - Writes (serialized per ActiveLook protocol)

    /// Serialized write: gates on runtime flow control, stamps a unique
    /// queryID, sends bytes to the RX characteristic, and waits for the
    /// `didWriteValueFor` callback before returning. Ensures only one BLE
    /// write is in-flight at a time, matching the ActiveLook SDK's
    /// `sendBytes()` → `rxCharacteristicState` gate.
    ///
    /// **queryID stamping** is done here (not in the encoder) so unit tests
    /// can keep pinning deterministic byte sequences while the live wire is
    /// always uniquely-correlatable with TX-channel responses/errors.
    private func write(_ bytes: [UInt8]) async throws {
        guard let peripheral, let rxCharacteristic else {
            throw GlassesTransportError.notConnected
        }
        // Runtime flow-control gate. PRs #49/#53/#55 only honored the
        // notification *subscription* (`flowControlNotifyConfirmed`) and
        // ignored the actual 0x01/0x02 value the glasses publish, so a
        // mid-burst "buffer 75% full" would silently drop writes.
        await awaitFlowControlAllowsWrite()
        var stamped = bytes
        stampNextQueryID(into: &stamped)
        // Wait for any prior write to complete (serialization).
        // In practice, `sendCommands` already serializes via `for frame in
        // frames { try await write(frame) }`, but this guards against any
        // concurrent caller.
        assert(pendingWrite == nil, "Concurrent write detected — ActiveLook requires serial writes")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.pendingWrite = continuation
            let data = Data(stamped)
            logger.debug("BLE write \(stamped.count) bytes: cmd=0x\(stamped.count > 1 ? String(stamped[1], radix: 16) : "?", privacy: .public) queryID=0x\(stamped.count > 4 ? String(stamped[4], radix: 16) : "?", privacy: .public)")
            peripheral.writeValue(data, for: rxCharacteristic, type: .withResponse)
        }
    }

    /// Block the current `write(_:)` until flow control reports ON. No-op
    /// if writes are already allowed (the hot path). Only one waiter is
    /// supported at a time, which is the only configuration `write(_:)`
    /// ever produces because writes are serialized via `pendingWrite`.
    private func awaitFlowControlAllowsWrite() async {
        if flowControlAllowsWrite { return }
        logger.warning("Write gated by flow control = OFF; awaiting ON before sending")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.flowControlContinuation = cont
        }
    }

    /// Stamp the next queryID into a fully-encoded frame. The encoder
    /// always emits `0x00` as a placeholder at the queryID position; this
    /// method overwrites it with a unique value and bumps the counter.
    ///
    /// Frame layout this method assumes:
    ///   * `frame[2] & 0x0F` is the queryID byte count (0 for DFU opt-out)
    ///   * `frame[2] & 0x10` is the 2-byte-length flag
    ///   * queryID byte sits at index 4 (1-byte len) or 5 (2-byte len)
    ///
    /// `withoutQueryId` frames (DFU ops) pass through untouched.
    private func stampNextQueryID(into frame: inout [UInt8]) {
        guard frame.count >= 5 else { return }
        let format = frame[2]
        let queryLen = Int(format & 0x0F)
        guard queryLen >= 1 else { return } // DFU opt-out — no queryID byte
        let twoByteLen = (format & 0x10) != 0
        let queryIDIndex = twoByteLen ? 5 : 4
        guard frame.count > queryIDIndex else { return }
        frame[queryIDIndex] = nextQueryID
        nextQueryID = nextQueryID == 0xFF ? 0x01 : nextQueryID &+ 1
    }

    /// Routed from the Coordinator's `didUpdateValueFor` for the control
    /// characteristic (0xCB9). Single-byte value per the ActiveLook spec.
    ///
    ///   * `0x01` — flow control ON, buffer OK, host may send
    ///   * `0x02` — flow control OFF, buffer 75% full, host MUST stop
    ///   * `0x03` — control error: corrupt/incomplete command (ignored by glasses)
    ///   * `0x04` — control error: receive queue overflow
    ///   * `0x06` — control error: missing `cfgWrite` before config modification
    fileprivate func handleControlValue(_ byte: UInt8) {
        switch byte {
        case 0x01:
            logger.info("ActiveLook flow control: ON (buffer OK)")
            flowControlAllowsWrite = true
            if let cont = flowControlContinuation {
                flowControlContinuation = nil
                cont.resume()
            }
        case 0x02:
            logger.warning("ActiveLook flow control: OFF (buffer ≥75% full — halting writes until ON)")
            flowControlAllowsWrite = false
        case 0x03:
            logger.error("ActiveLook control: 0x03 corrupt/incomplete command (firmware ignored last frame)")
        case 0x04:
            logger.error("ActiveLook control: 0x04 receive queue overflow")
        case 0x06:
            logger.error("ActiveLook control: 0x06 missing cfgWrite before config modification")
        default:
            logger.warning("ActiveLook control: unknown value 0x\(String(byte, radix: 16), privacy: .public)")
        }
    }

    /// Routed from the Coordinator's `didUpdateValueFor` for the TX
    /// characteristic (0xCB8). Parses 0xE2 error notification frames per
    /// spec §4.15 and logs at error level so an on-device console capture
    /// can confirm whether the queryID fix worked.
    ///
    /// Frame layout for 0xE2: `0xFF | 0xE2 | format | length(1-2) | queryID?
    /// | cmdId(u8) | error(u8) | subError(u8) | 0xAA`.
    /// Error codes: 1=generic, 2=missing cfgWrite, 3=memory rw error,
    /// 4=protocol decoding error (malformed frame / unknown cmd).
    fileprivate func handleTXNotification(_ data: Data) {
        guard data.count >= 5,
              data.first == 0xFF,
              data.last == 0xAA
        else { return }
        let bytes = Array(data)
        guard bytes[1] == 0xE2 else {
            // Other TX traffic (battery response, vers, etc.) — not surfaced
            // in v0.3. The battery path runs off the dedicated 0x2A19 char.
            return
        }
        let format = bytes[2]
        let queryLen = Int(format & 0x0F)
        let twoByteLen = (format & 0x10) != 0
        let dataStart = 3 + (twoByteLen ? 2 : 1) + queryLen
        guard bytes.count >= dataStart + 3 + 1 else {
            logger.error("ActiveLook 0xE2 error frame truncated (\(bytes.count, privacy: .public) bytes)")
            return
        }
        let cmdId = bytes[dataStart]
        let error = bytes[dataStart + 1]
        let subError = bytes[dataStart + 2]
        logger.error("ActiveLook 0xE2 error: cmdId=0x\(String(cmdId, radix: 16), privacy: .public) error=\(error, privacy: .public) subError=\(subError, privacy: .public)")
    }

    /// Called by the Coordinator when CoreBluetooth confirms a write completed.
    fileprivate func handleWriteCompleted(error: Error?) {
        guard let continuation = pendingWrite else {
            // Spurious callback (e.g., from a write issued before we added
            // serialization). Log but don't crash.
            if let error {
                logger.warning("Unmatched didWriteValueFor error: \(error.localizedDescription, privacy: .public)")
            }
            return
        }
        pendingWrite = nil
        if let error {
            logger.error("BLE write failed: \(error.localizedDescription, privacy: .public)")
            continuation.resume(throwing: GlassesTransportError.writeFailed(reason: error.localizedDescription))
        } else {
            continuation.resume()
        }
    }

    // MARK: - Continuation plumbing

    private func transition(to newState: GlassesConnectionState) {
        connectionState = newState
        for continuation in stateContinuations.values {
            continuation.yield(newState)
        }
        logger.debug("glasses state -> \(newState.rawValue, privacy: .public)")
    }

    private func emit(_ event: GlassesStatusEvent) {
        for continuation in statusContinuations.values {
            continuation.yield(event)
        }
    }

    private func attachStateContinuation(
        _ continuation: AsyncStream<GlassesConnectionState>.Continuation,
        id: UUID,
        snapshot: GlassesConnectionState
    ) {
        stateContinuations[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.dropStateContinuation(id: id) }
        }
    }

    private func attachStatusContinuation(
        _ continuation: AsyncStream<GlassesStatusEvent>.Continuation,
        id: UUID
    ) {
        statusContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.dropStatusContinuation(id: id) }
        }
    }

    private func dropStateContinuation(id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }

    private func dropStatusContinuation(id: UUID) {
        statusContinuations.removeValue(forKey: id)
    }

    private func resumePendingConnect(_ result: Result<Void, Error>) {
        guard let continuation = pendingConnect else { return }
        pendingConnect = nil
        switch result {
        case .success: continuation.resume()
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    private func failPendingConnect(with error: Error) {
        resumePendingConnect(.failure(error))
    }
}

// MARK: - CoreBluetooth coordinator

extension ActiveLookGlassesAdapter {
    /// Bridge object that absorbs CoreBluetooth's NSObject delegate callbacks
    /// and forwards them onto the actor. Kept private to the adapter.
    fileprivate final class Coordinator: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
        private weak var adapter: ActiveLookGlassesAdapter?

        init(adapter: ActiveLookGlassesAdapter) {
            self.adapter = adapter
        }

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            let state = central.state
            Task { [weak adapter] in await adapter?.handleCentralStateUpdate(state) }
        }

        func centralManager(
            _ central: CBCentralManager,
            didDiscover peripheral: CBPeripheral,
            advertisementData: [String: Any],
            rssi RSSI: NSNumber
        ) {
            // Extract the manufacturer-data blob on the CB delegate queue so
            // we only ship a `Data?` (Sendable) across the actor boundary —
            // the full `[String: Any]` advertisementData dictionary is not
            // Sendable under Swift 6 strict concurrency.
            let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
            Task { [weak adapter] in
                await adapter?.handleDiscovered(peripheral, manufacturerData: manufacturerData)
            }
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            Task { [weak adapter] in await adapter?.handleConnected(peripheral) }
        }

        func centralManager(
            _ central: CBCentralManager,
            didFailToConnect peripheral: CBPeripheral,
            error: Error?
        ) {
            Task { [weak adapter] in await adapter?.handleDisconnect(error: error) }
        }

        func centralManager(
            _ central: CBCentralManager,
            didDisconnectPeripheral peripheral: CBPeripheral,
            error: Error?
        ) {
            Task { [weak adapter] in await adapter?.handleDisconnect(error: error) }
        }

        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            Task { [weak adapter] in await adapter?.handleServicesDiscovered(peripheral) }
        }

        func peripheral(
            _ peripheral: CBPeripheral,
            didDiscoverCharacteristicsFor service: CBService,
            error: Error?
        ) {
            Task { [weak adapter] in await adapter?.handleCharacteristicsDiscovered(service) }
        }

        func peripheral(
            _ peripheral: CBPeripheral,
            didUpdateValueFor characteristic: CBCharacteristic,
            error: Error?
        ) {
            let uuid = characteristic.uuid
            // Control characteristic (0xCB9): runtime flow-control values
            // (0x01 ON / 0x02 OFF) and control-side error codes (0x03 / 0x04 /
            // 0x06). PRs #49/#53/#55 silently dropped these — the resulting
            // blind-flight is the secondary root cause of the blank-screen
            // regression series. Now routed to the adapter for observability
            // + runtime write gating.
            if uuid == CBUUID(string: ActiveLookGATT.controlChar) {
                if let data = characteristic.value, let byte = data.first {
                    Task { [weak adapter] in await adapter?.handleControlValue(byte) }
                }
                return
            }
            // TX characteristic (0xCB8): command responses including 0xE2
            // error notifications (`cmdId | error | subError`). Logged at
            // error level so an on-device console capture immediately reveals
            // whether the glasses are rejecting any of our frames.
            if uuid == CBUUID(string: ActiveLookGATT.txCharacteristic) {
                if let data = characteristic.value {
                    let payload = Data(data) // detach from CB ownership for actor hop
                    Task { [weak adapter] in await adapter?.handleTXNotification(payload) }
                }
                return
            }
            // Battery level (Standard Battery Service 0x2A19).
            if uuid == CBUUID(string: ActiveLookGATT.batteryLevelChar),
               let data = characteristic.value, let firstByte = data.first {
                Task { [weak adapter] in await adapter?.handleBatteryLevel(firstByte) }
                return
            }
        }

        func peripheral(
            _ peripheral: CBPeripheral,
            didWriteValueFor characteristic: CBCharacteristic,
            error: Error?
        ) {
            let writeError = error
            Task { [weak adapter] in await adapter?.handleWriteCompleted(error: writeError) }
        }

        func peripheral(
            _ peripheral: CBPeripheral,
            didUpdateNotificationStateFor characteristic: CBCharacteristic,
            error: Error?
        ) {
            let notifyError = error
            Task { [weak adapter] in
                await adapter?.handleNotificationStateChanged(characteristic, error: notifyError)
            }
        }
    }
}
