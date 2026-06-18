// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerPhone

/// Queue behavior: enqueue/dedup, persistence, retry/backoff, rate-limit
/// pause, and max-retries → failed transition.
final class StravaUploadQueueTests: XCTestCase {

    // MARK: - In-memory storage

    final class InMemoryStorage: StravaUploadQueueStorage, @unchecked Sendable {
        var entries: [StravaUploadQueueEntry] = []
        var tcx: [UUID: Data] = [:]
        private let queue = DispatchQueue(label: "InMemoryQueueStorage")
        func loadEntries() throws -> [StravaUploadQueueEntry] { queue.sync { entries } }
        func saveEntries(_ e: [StravaUploadQueueEntry]) throws { queue.sync { entries = e } }
        func writeTCX(_ data: Data, for id: UUID) throws { queue.sync { tcx[id] = data } }
        func readTCX(for id: UUID) throws -> Data {
            try queue.sync {
                guard let d = tcx[id] else { throw CocoaError(.fileNoSuchFile) }
                return d
            }
        }
        func deleteTCX(for id: UUID) throws { queue.sync { tcx.removeValue(forKey: id) } }
    }

    // MARK: - Helpers

    private func makeService(
        responses: [(Int, Data, [String: String])] = []
    ) -> (StravaUploadService, StravaUploadServiceTests.StubTransport) {
        let backing = StravaTokenStoreTests.InMemoryBacking()
        let store = StravaTokenStore(backing: backing, refresher: StravaTokenStoreTests.MockRefresher())
        try? store.save(accessToken: "t", refreshToken: "r",
                        expiresAt: Date().timeIntervalSince1970 + 3600,
                        athleteID: 1, athleteFirstName: nil)
        let transport = StravaUploadServiceTests.StubTransport()
        for (status, body, headers) in responses {
            let url = URL(string: "https://www.strava.com/api/v3/uploads")!
            let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            transport.responses.append((body, resp))
        }
        let svc = StravaUploadService(tokenStore: store, transport: transport, multipartBoundary: { "B" })
        return (svc, transport)
    }

    private func uuid(_ s: String) -> UUID {
        UUID(uuidString: s)!
    }

    // MARK: - Enqueue / dedup

    func test_enqueue_addsEntryAndPersists() async throws {
        let storage = InMemoryStorage()
        let (svc, _) = makeService()
        let q = StravaUploadQueue(storage: storage, service: svc)
        let id = uuid("11111111-1111-1111-1111-111111111111")
        let entry = try await q.enqueue(workoutID: id, startDate: Date(), tcxData: Data("<tcx/>".utf8))
        XCTAssertEqual(entry.workoutID, id)
        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(storage.entries.count, 1)
        XCTAssertEqual(storage.tcx[id], Data("<tcx/>".utf8))
    }

    func test_enqueue_deduplicatesByWorkoutID() async throws {
        let storage = InMemoryStorage()
        let (svc, _) = makeService()
        let q = StravaUploadQueue(storage: storage, service: svc)
        let id = uuid("22222222-2222-2222-2222-222222222222")
        _ = try await q.enqueue(workoutID: id, startDate: Date(), tcxData: Data("<a/>".utf8))
        _ = try await q.enqueue(workoutID: id, startDate: Date(), tcxData: Data("<b/>".utf8))
        let snap = await q.snapshot()
        XCTAssertEqual(snap.count, 1)
    }

    // MARK: - Persistence across instances

    func test_entries_loadFromStorage_onInit() async throws {
        let storage = InMemoryStorage()
        let id = uuid("33333333-3333-3333-3333-333333333333")
        storage.entries = [StravaUploadQueueEntry(
            workoutID: id, startDate: Date(), status: .pending,
            retryCount: 0, lastAttemptDate: nil, errorMessage: nil,
            stravaUploadID: nil, stravaActivityID: nil, enqueuedAt: Date())]
        storage.tcx[id] = Data("<tcx/>".utf8)
        let (svc, _) = makeService()
        let q = StravaUploadQueue(storage: storage, service: svc)
        let snap = await q.snapshot()
        XCTAssertEqual(snap.count, 1)
        XCTAssertEqual(snap[0].workoutID, id)
    }

    func test_filePersistence_roundTrips() throws {
        // Use a sandboxed temp dir; not /tmp — we put it under
        // the build's caches via FileManager, which the tooling allows.
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("queue-test-\(UUID().uuidString)")
        let storage = FileStravaUploadQueueStorage(baseDirectory: dir)
        let id = UUID()
        let entry = StravaUploadQueueEntry(
            workoutID: id, startDate: Date(), status: .pending,
            retryCount: 1, lastAttemptDate: Date(), errorMessage: "boom",
            stravaUploadID: nil, stravaActivityID: nil, enqueuedAt: Date())
        try storage.saveEntries([entry])
        try storage.writeTCX(Data("<x/>".utf8), for: id)
        let reload = FileStravaUploadQueueStorage(baseDirectory: dir)
        let loaded = try reload.loadEntries()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].workoutID, id)
        XCTAssertEqual(try reload.readTCX(for: id), Data("<x/>".utf8))
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Process: success

    func test_processOne_success_marksCompleted() async throws {
        let storage = InMemoryStorage()
        let (svc, _) = makeService(responses: [
            (201, Data(#"{"id":11,"external_id":"x","activity_id":555}"#.utf8), [:])
        ])
        let q = StravaUploadQueue(storage: storage, service: svc)
        let id = uuid("44444444-4444-4444-4444-444444444444")
        _ = try await q.enqueue(workoutID: id, startDate: Date(), tcxData: Data("<tcx/>".utf8))
        await q.processOne()
        let snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .completed)
        XCTAssertEqual(snap[0].stravaUploadID, 11)
        XCTAssertEqual(snap[0].stravaActivityID, 555)
    }

    /// Mutable clock wrapper. The queue's clock closure is `@Sendable`, which
    /// rules out capturing a local `var` directly under Swift 6.
    final class MutableClock: @unchecked Sendable {
        private var current: Date
        private let lock = NSLock()
        init(_ start: Date) { self.current = start }
        var now: Date {
            get { lock.lock(); defer { lock.unlock() }; return current }
            set { lock.lock(); defer { lock.unlock() }; current = newValue }
        }
        func advance(by interval: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            current = current.addingTimeInterval(interval)
        }
    }

    // MARK: - Process: rate-limit pause

    func test_processOne_429_marksPendingAndPausesQueue() async throws {
        let storage = InMemoryStorage()
        let (svc, _) = makeService(responses: [
            (429, Data("slow".utf8), ["Retry-After": "30"])
        ])
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let q = StravaUploadQueue(storage: storage, service: svc, clock: { clock.now })
        let id = uuid("55555555-5555-5555-5555-555555555555")
        _ = try await q.enqueue(workoutID: id, startDate: clock.now, tcxData: Data("<tcx/>".utf8))
        await q.processOne()
        let snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .pending)
        XCTAssertEqual(snap[0].retryCount, 0, "429 should not consume a retry attempt")
        clock.advance(by: 60)
        XCTAssertEqual(snap.count, 1)
    }

    // MARK: - Backoff schedule

    func test_delay_forRetry_matchesSchedule() {
        XCTAssertEqual(StravaUploadQueue.delay(forRetry: 0), 30)
        XCTAssertEqual(StravaUploadQueue.delay(forRetry: 1), 60)
        XCTAssertEqual(StravaUploadQueue.delay(forRetry: 2), 120)
        XCTAssertEqual(StravaUploadQueue.delay(forRetry: 3), 300)
        XCTAssertEqual(StravaUploadQueue.delay(forRetry: 4), 900)
        // Past the end clamps to the last bucket — never blows up.
        XCTAssertEqual(StravaUploadQueue.delay(forRetry: 99), 900)
    }

    // MARK: - Max retries → failed

    func test_repeatedServerErrors_eventuallyMarkFailed() async throws {
        let storage = InMemoryStorage()
        let responses = Array(repeating: (500, Data("err".utf8), [String: String]()), count: StravaUploadQueue.maxRetries)
        let (svc, _) = makeService(responses: responses)
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let q = StravaUploadQueue(storage: storage, service: svc, clock: { clock.now })
        let id = uuid("66666666-6666-6666-6666-666666666666")
        _ = try await q.enqueue(workoutID: id, startDate: clock.now, tcxData: Data("<tcx/>".utf8))
        for _ in 0..<StravaUploadQueue.maxRetries {
            await q.processOne()
            clock.advance(by: 2000)
        }
        let snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .failed)
        XCTAssertEqual(snap[0].retryCount, StravaUploadQueue.maxRetries)
    }

    // MARK: - Manual retry

    func test_retry_resetsCounterAndAllowsAnotherAttempt() async throws {
        let storage = InMemoryStorage()
        let (svc, _) = makeService(responses: [
            (500, Data("err".utf8), [:]),
            (201, Data(#"{"id":1,"activity_id":999}"#.utf8), [:])
        ])
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let q = StravaUploadQueue(storage: storage, service: svc, clock: { clock.now })
        let id = uuid("77777777-7777-7777-7777-777777777777")
        _ = try await q.enqueue(workoutID: id, startDate: clock.now, tcxData: Data("<tcx/>".utf8))
        await q.processOne()
        var snap = await q.snapshot()
        XCTAssertEqual(snap[0].retryCount, 1)
        try await q.retry(workoutID: id)
        snap = await q.snapshot()
        XCTAssertEqual(snap[0].retryCount, 0)
        XCTAssertNil(snap[0].lastAttemptDate)
        clock.advance(by: 60)
        await q.processOne()
        snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .completed)
    }

    // MARK: - Part 1: reclaim orphaned `.uploading` entries

    func test_orphanedUploading_isReclaimedToPending_onInit_andPersisted() async throws {
        let storage = InMemoryStorage()
        let id = uuid("88888888-8888-8888-8888-888888888888")
        // Simulate an app killed mid-upload: persisted as `.uploading`.
        storage.entries = [StravaUploadQueueEntry(
            workoutID: id, startDate: Date(), status: .uploading,
            retryCount: 0, lastAttemptDate: Date(), errorMessage: nil,
            stravaUploadID: nil, stravaActivityID: nil, enqueuedAt: Date())]
        storage.tcx[id] = Data("<tcx/>".utf8)
        let (svc, _) = makeService()
        let q = StravaUploadQueue(storage: storage, service: svc)
        let snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .pending, "interrupted upload must be reclaimed")
        XCTAssertEqual(snap[0].retryCount, 0, "reclaim must not consume a retry attempt")
        XCTAssertEqual(storage.entries[0].status, .pending, "reclaim must be persisted")
    }

    func test_reclaimedUploading_isProcessedToCompletion() async throws {
        let storage = InMemoryStorage()
        let id = uuid("99999999-9999-9999-9999-999999999999")
        storage.entries = [StravaUploadQueueEntry(
            workoutID: id, startDate: Date(), status: .uploading,
            retryCount: 0, lastAttemptDate: nil, errorMessage: nil,
            stravaUploadID: nil, stravaActivityID: nil, enqueuedAt: Date())]
        storage.tcx[id] = Data("<tcx/>".utf8)
        let (svc, _) = makeService(responses: [
            (201, Data(#"{"id":11,"activity_id":555}"#.utf8), [:])
        ])
        let q = StravaUploadQueue(storage: storage, service: svc)
        await q.processOne()
        let snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .completed)
        XCTAssertEqual(snap[0].stravaActivityID, 555)
    }

    func test_reclaimOrphans_pureFunction_onlyRewritesUploading() {
        let base = Date()
        let mk: (StravaUploadEntryStatus) -> StravaUploadQueueEntry = { status in
            StravaUploadQueueEntry(
                workoutID: UUID(), startDate: base, status: status,
                retryCount: 2, lastAttemptDate: base, errorMessage: nil,
                stravaUploadID: nil, stravaActivityID: nil, enqueuedAt: base)
        }
        let input = [mk(.pending), mk(.uploading), mk(.processing), mk(.completed), mk(.failed)]
        let out = StravaUploadQueue.reclaimOrphans(input)
        XCTAssertEqual(out.map(\.status), [.pending, .pending, .processing, .completed, .failed])
        XCTAssertEqual(out[1].retryCount, 2, "reclaim preserves retryCount")
    }

    // MARK: - Part 3: confirmation polling

    func test_processing_pollPendingThenActivity_completesWithActivityID() async throws {
        let storage = InMemoryStorage()
        let (svc, _) = makeService(responses: [
            (201, Data(#"{"id":77}"#.utf8), [:]),                       // POST accepted, no activity yet
            (200, Data(#"{"id":77,"status":"processing"}"#.utf8), [:]), // poll #1 — still processing
            (200, Data(#"{"id":77,"activity_id":888}"#.utf8), [:])      // poll #2 — done
        ])
        let clock = MutableClock(Date(timeIntervalSince1970: 2_000_000))
        let q = StravaUploadQueue(storage: storage, service: svc, clock: { clock.now })
        let id = uuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        _ = try await q.enqueue(workoutID: id, startDate: clock.now, tcxData: Data("<tcx/>".utf8))

        await q.processOne()
        var snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .processing)
        XCTAssertEqual(snap[0].stravaUploadID, 77)

        clock.advance(by: 5)
        await q.processOne()
        snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .processing, "still processing after first poll")
        XCTAssertEqual(snap[0].confirmPollCount, 1)

        clock.advance(by: 30)
        await q.processOne()
        snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .completed)
        XCTAssertEqual(snap[0].stravaActivityID, 888)
    }

    func test_processing_pollError_marksFailed() async throws {
        let storage = InMemoryStorage()
        let (svc, _) = makeService(responses: [
            (201, Data(#"{"id":77}"#.utf8), [:]),
            (200, Data(#"{"id":77,"error":"Time data not found"}"#.utf8), [:])
        ])
        let clock = MutableClock(Date(timeIntervalSince1970: 2_000_000))
        let q = StravaUploadQueue(storage: storage, service: svc, clock: { clock.now })
        let id = uuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        _ = try await q.enqueue(workoutID: id, startDate: clock.now, tcxData: Data("<tcx/>".utf8))

        await q.processOne()
        clock.advance(by: 5)
        await q.processOne()
        let snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .failed)
        XCTAssertEqual(snap[0].errorMessage, "Time data not found")
    }

    func test_processing_budgetExceeded_revertsToPending_andStaysReclaimable() async throws {
        let storage = InMemoryStorage()
        // 1 POST + maxConfirmPolls GETs that never produce an activity.
        var responses: [(Int, Data, [String: String])] = [
            (201, Data(#"{"id":77}"#.utf8), [:])
        ]
        responses.append(contentsOf: Array(
            repeating: (200, Data(#"{"id":77,"status":"processing"}"#.utf8), [String: String]()),
            count: StravaUploadQueue.maxConfirmPolls))
        let (svc, _) = makeService(responses: responses)
        let clock = MutableClock(Date(timeIntervalSince1970: 2_000_000))
        let q = StravaUploadQueue(storage: storage, service: svc, clock: { clock.now })
        let id = uuid("cccccccc-cccc-cccc-cccc-cccccccccccc")
        _ = try await q.enqueue(workoutID: id, startDate: clock.now, tcxData: Data("<tcx/>".utf8))

        await q.processOne() // POST → processing
        for _ in 0..<StravaUploadQueue.maxConfirmPolls {
            clock.advance(by: 60)
            await q.processOne()
        }
        let snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .pending, "budget exceeded must revert to a reclaimable .pending, not a stuck state")
        XCTAssertEqual(snap[0].retryCount, 1, "a processing timeout consumes exactly one upload retry")
        XCTAssertEqual(snap[0].confirmPollCount, 0)
    }

    // MARK: - 409 duplicate → completed (idempotency safety net)

    func test_duplicate409_marksCompleted() async throws {
        let storage = InMemoryStorage()
        let (svc, _) = makeService(responses: [
            (409, Data(#"{"id":42,"external_id":"x","status":"duplicate","error":"duplicate of activity"}"#.utf8), [:])
        ])
        let q = StravaUploadQueue(storage: storage, service: svc)
        let id = uuid("dddddddd-dddd-dddd-dddd-dddddddddddd")
        _ = try await q.enqueue(workoutID: id, startDate: Date(), tcxData: Data("<tcx/>".utf8))
        await q.processOne()
        let snap = await q.snapshot()
        XCTAssertEqual(snap[0].status, .completed, "409 duplicate is an idempotent success")
    }

    func test_reEnqueueCompleted_isNoOp() async throws {
        let storage = InMemoryStorage()
        let (svc, _) = makeService(responses: [
            (201, Data(#"{"id":11,"activity_id":555}"#.utf8), [:])
        ])
        let q = StravaUploadQueue(storage: storage, service: svc)
        let id = uuid("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")
        _ = try await q.enqueue(workoutID: id, startDate: Date(), tcxData: Data("<tcx/>".utf8))
        await q.processOne()
        // Re-enqueue the same workout — must not reset the completed entry.
        _ = try await q.enqueue(workoutID: id, startDate: Date(), tcxData: Data("<tcx/>".utf8))
        let snap = await q.snapshot()
        XCTAssertEqual(snap.count, 1)
        XCTAssertEqual(snap[0].status, .completed)
    }
}
