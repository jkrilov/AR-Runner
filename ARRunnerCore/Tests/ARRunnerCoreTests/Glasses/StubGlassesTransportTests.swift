// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerCore

final class StubGlassesTransportTests: XCTestCase {
    func testConnectTransitionsThroughLifecycle() async throws {
        let transport = StubGlassesTransport()
        let stream = await transport.connectionStates()
        var iterator = stream.makeAsyncIterator()

        // First yielded value is the snapshot at subscription time.
        let initial = await iterator.next()
        XCTAssertEqual(initial, .disconnected)

        try await transport.connect()

        var observed: [GlassesConnectionState] = []
        for _ in 0..<3 {
            if let value = await iterator.next() {
                observed.append(value)
            }
        }
        XCTAssertEqual(observed, [.scanning, .connecting, .connected])
        let finalState = await transport.connectionState
        XCTAssertEqual(finalState, .connected)
    }

    func testConnectIsIdempotent() async throws {
        let transport = StubGlassesTransport()
        try await transport.connect()
        try await transport.connect()
        let count = await transport.connectCallCount
        let state = await transport.connectionState
        XCTAssertEqual(count, 2)
        XCTAssertEqual(state, .connected)
    }

    func testConnectedDeviceNameIsNilWhenDisconnected() async {
        let transport = StubGlassesTransport(simulatedDeviceName: "Engo 2")
        let name = await transport.connectedDeviceName
        XCTAssertNil(name)
    }

    func testConnectedDeviceNameIsExposedWhenConnected() async throws {
        let transport = StubGlassesTransport(simulatedDeviceName: "Engo 2")
        try await transport.connect()
        let name = await transport.connectedDeviceName
        XCTAssertEqual(name, "Engo 2")
    }

    func testConnectedDeviceNameClearsAfterDisconnect() async throws {
        let transport = StubGlassesTransport(simulatedDeviceName: "Engo 2")
        try await transport.connect()
        try await transport.disconnect()
        let name = await transport.connectedDeviceName
        XCTAssertNil(name)
    }

    func testFieldUpdateRequiresConnection() async {
        let transport = StubGlassesTransport()
        let update = HUDFieldUpdate(layoutID: "balanced-run", fieldIndex: 0, value: "5:42")
        do {
            try await transport.updateField(update)
            XCTFail("expected notConnected error")
        } catch let error as GlassesTransportError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSelectLayoutRejectsUnknownID() async throws {
        let transport = StubGlassesTransport()
        try await transport.connect()
        do {
            try await transport.selectLayout(id: "does-not-exist")
            XCTFail("expected unknownLayout error")
        } catch let error as GlassesTransportError {
            XCTAssertEqual(error, .unknownLayout(id: "does-not-exist"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFieldUpdatesAreRecordedInOrder() async throws {
        let transport = StubGlassesTransport()
        try await transport.connect()
        try await transport.selectLayout(id: "balanced-run")

        let updates = [
            HUDFieldUpdate(layoutID: "balanced-run", fieldIndex: 0, value: "5:42"),
            HUDFieldUpdate(layoutID: "balanced-run", fieldIndex: 1, value: "142"),
            HUDFieldUpdate(layoutID: "balanced-run", fieldIndex: 3, value: "00:42:11")
        ]
        try await transport.updateFields(updates)

        let received = await transport.receivedUpdates
        XCTAssertEqual(received, updates)
    }

    func testSimulateDropEmitsStatusEventAndReconnectingState() async throws {
        let transport = StubGlassesTransport()
        let statusStream = await transport.statusEvents()
        let stateStream = await transport.connectionStates()
        var statusIter = statusStream.makeAsyncIterator()
        var stateIter = stateStream.makeAsyncIterator()

        // Drain the snapshot.
        _ = await stateIter.next()

        try await transport.connect()
        // Drain scanning/connecting/connected
        _ = await stateIter.next(); _ = await stateIter.next(); _ = await stateIter.next()

        await transport.simulateDrop()

        let event = await statusIter.next()
        switch event {
        case .dropped(let reason, _):
            XCTAssertEqual(reason, .linkLoss)
        default:
            XCTFail("expected dropped event, got \(String(describing: event))")
        }

        let next = await stateIter.next()
        XCTAssertEqual(next, .reconnecting)
    }

    func testSimulateReconnectRestoresConnectedState() async throws {
        let transport = StubGlassesTransport()
        try await transport.connect()
        await transport.simulateDrop()

        let statusStream = await transport.statusEvents()
        var statusIter = statusStream.makeAsyncIterator()

        await transport.simulateReconnect(after: 3.5)

        let event = await statusIter.next()
        switch event {
        case .reconnected(let gap, _):
            XCTAssertEqual(gap, 3.5, accuracy: 1e-9)
        default:
            XCTFail("expected reconnected event, got \(String(describing: event))")
        }

        let state = await transport.connectionState
        XCTAssertEqual(state, .connected)
    }

    func testHUDFieldUpdateCodableRoundTrip() throws {
        let original = HUDFieldUpdate(layoutID: "telemetry-run", fieldIndex: 4, value: "412 ft")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HUDFieldUpdate.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
