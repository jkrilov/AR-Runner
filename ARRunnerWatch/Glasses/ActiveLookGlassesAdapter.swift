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
        backoff: ExponentialBackoff = ExponentialBackoff(),
        scanTimeout: TimeInterval = 15.0,
        knownPeripheralConnectTimeout: TimeInterval = 8.0,
        maxReconnectAttempts: Int = 30,
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
        let frame = ActiveLookCommand.updateWidget(
            layoutID: deviceID,
            fieldIndex: update.fieldIndex,
            value: update.value
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
            case ActiveLookGATT.txCharacteristic.uppercased(),
                 ActiveLookGATT.controlChar.uppercased():
                peripheral?.setNotifyValue(true, for: characteristic)
            case ActiveLookGATT.batteryLevelChar.uppercased():
                // Subscribe to the standard Battery Service so periodic
                // level pushes reach `handleBatteryLevel(_:)` via the
                // coordinator. Without this the battery handler is dead code.
                peripheral?.setNotifyValue(true, for: characteristic)
                peripheral?.readValue(for: characteristic)
            default:
                break
            }
        }

        // Only flip to .connected once the command-service RX characteristic
        // is in hand. Battery characteristics arrive in a later callback;
        // we don't gate readiness on them.
        guard service.uuid == CBUUID(string: ActiveLookGATT.commandService) else { return }

        if rxCharacteristic != nil {
            // Capture name from the peripheral at the moment connection
            // completes — CoreBluetooth may clear `peripheral.name` after a
            // drop, so we snapshot it for the pre-run UI's `Glasses: {name}`
            // display.
            if let name = peripheral?.name, !name.isEmpty {
                lastConnectedName = name
            }
            // Persist the peripheral identifier so the next launch can take
            // the fast-reconnect path (`retrievePeripherals(withIdentifiers:)`
            // → `connect`) and skip scanning entirely. Mirrors ActiveLook's
            // own iOS SDK fast-reconnect (`ActiveLookSDK.swift:368, 240–298`).
            if let id = peripheral?.identifier {
                prefs.pairedPeripheralID = id
                glassesLogger.info("Persisted peripheral identifier \(id.uuidString, privacy: .public) for fast reconnect")
            }
            // If we were reconnecting after a drop, emit a `.reconnected` status.
            if let dropAt = lastDropAt {
                emit(.reconnected(gap: Date().timeIntervalSince(dropAt), at: Date()))
                lastDropAt = nil
            }
            transition(to: .connected)
            // Re-apply layout if we had one selected before the drop.
            if let activeLayoutDeviceID {
                // P1.4 (audit 2026-05-16): guard the reconnect re-apply path
                // too — the placeholder slot was pre-seeded from
                // `RunningHUDPreset.default` in init, so without this trap
                // the very first hardware reconnect would activate the
                // wrong on-device layout silently.
                CuratedLayoutCatalog.assertNotPlaceholder(
                    activeLayoutDeviceID,
                    layoutID: "(re-apply)"
                )
                let frame = ActiveLookCommand.displayLayout(id: activeLayoutDeviceID)
                _ = try? sendRaw(frame)
            }
            resumePendingConnect(.success(()))
        } else {
            failPendingConnect(with: GlassesTransportError.writeFailed(reason: "RX characteristic missing"))
            transition(to: .failed)
        }
    }

    fileprivate func handleDisconnect(error: Error?) {
        peripheral = nil
        rxCharacteristic = nil

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

    fileprivate func handleBatteryLevel(_ level: Int) {
        emit(.batteryLevel(level))
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

    // MARK: - Writes

    private func write(_ bytes: [UInt8]) async throws {
        try sendRaw(bytes)
    }

    @discardableResult
    private func sendRaw(_ bytes: [UInt8]) throws -> Bool {
        guard let peripheral, let rxCharacteristic else {
            throw GlassesTransportError.notConnected
        }
        // Per spike §4: write-with-response is the safer default; switch to
        // .withoutResponse after profiling real hardware.
        peripheral.writeValue(Data(bytes), for: rxCharacteristic, type: .withResponse)
        return true
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
            // Battery level (Standard Battery Service 0x2A19) is the only TX
            // notification we route in v0.1. Other notifications (gesture,
            // touch, control flow) are spec'd but deferred to v1.
            guard
                characteristic.uuid == CBUUID(string: ActiveLookGATT.batteryLevelChar),
                let data = characteristic.value, let firstByte = data.first
            else { return }
            let level = Int(firstByte)
            Task { [weak adapter] in await adapter?.handleBatteryLevel(level) }
        }
    }
}
