// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

/// Status of one queued upload. Persisted to disk so the queue survives app
/// restarts (per task spec — phone may be backgrounded mid-retry-backoff).
enum StravaUploadEntryStatus: String, Codable, Sendable {
    case pending
    case uploading
    case completed
    case failed
}

/// One row in the upload queue. The TCX bytes themselves live in a side file
/// (`tcx/{workoutID}.tcx`) so the queue's JSON manifest stays small even after
/// hundreds of historical runs.
struct StravaUploadQueueEntry: Codable, Sendable, Equatable {
    let workoutID: UUID
    /// Workout start time — preserved across restarts so the activity name
    /// ("Morning Run" / "Evening Run") is stable on retry, regardless of when
    /// the retry actually fires.
    let startDate: Date
    var status: StravaUploadEntryStatus
    var retryCount: Int
    var lastAttemptDate: Date?
    var errorMessage: String?
    var stravaUploadID: Int?
    var stravaActivityID: Int?
    let enqueuedAt: Date
}

/// Persistent JSON-backed shape on disk. Versioned so a future migration can
/// be reasoned about without a hard reset.
private struct StravaUploadQueueFile: Codable {
    static let currentVersion = 1
    var version: Int
    var entries: [StravaUploadQueueEntry]

    init(entries: [StravaUploadQueueEntry] = []) {
        self.version = Self.currentVersion
        self.entries = entries
    }
}

/// Persisted, rate-limit-aware upload queue.
///
/// Design notes:
/// - **Actor** for thread-safety. Multiple call sites (auto-upload trigger,
///   History "Retry", app-launch resume) all funnel through the same actor.
/// - **Exponential backoff** per entry: 30s, 1m, 2m, 5m, 15m, then give up
///   (max 5 attempts). Rationale: covers a transient Wi-Fi blip but doesn't
///   chew battery if Strava is really down.
/// - **Rate-limit pause** (`pauseUntil`) is *queue-global* because Strava's
///   429s are per-token, not per-request: pausing the whole queue is the only
///   correct response.
/// - **Idempotency** is delegated to the service via `external_id` =
///   `HKWorkout.uuid`, so a duplicate enqueue → 409 → marked completed.
actor StravaUploadQueue {
    static let shared = StravaUploadQueue()

    private let logger = Logger(subsystem: "com.arrunner.phone", category: "StravaUploadQueue")
    private let storage: StravaUploadQueueStorage
    private let service: StravaUploadService
    private let clock: @Sendable () -> Date
    /// Max attempts before an entry is marked `.failed` and dropped from the
    /// active retry rotation (user can still manually retry from History).
    static let maxRetries = 5
    /// Per-attempt backoff schedule (seconds). Index = retryCount.
    static let backoffSchedule: [TimeInterval] = [30, 60, 120, 300, 900]

    private var entries: [StravaUploadQueueEntry] = []
    private var pauseUntil: Date?
    private var processing: Bool = false

    init(
        storage: StravaUploadQueueStorage = FileStravaUploadQueueStorage(),
        service: StravaUploadService = StravaUploadService(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.service = service
        self.clock = clock
        self.entries = (try? storage.loadEntries()) ?? []
    }

    // MARK: - Public surface

    /// Snapshot of current entries (ordered oldest first).
    func snapshot() -> [StravaUploadQueueEntry] {
        entries.sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    /// Add a workout to the queue. `tcxData` is the already-encoded TCX bytes;
    /// the queue takes ownership and writes them to its side-file. Idempotent
    /// on `workoutID` — re-enqueuing a queued/completed workout is a no-op.
    @discardableResult
    func enqueue(workoutID: UUID, startDate: Date, tcxData: Data) throws -> StravaUploadQueueEntry {
        if let existing = entries.first(where: { $0.workoutID == workoutID }) {
            return existing
        }
        try storage.writeTCX(tcxData, for: workoutID)
        let entry = StravaUploadQueueEntry(
            workoutID: workoutID,
            startDate: startDate,
            status: .pending,
            retryCount: 0,
            lastAttemptDate: nil,
            errorMessage: nil,
            stravaUploadID: nil,
            stravaActivityID: nil,
            enqueuedAt: clock()
        )
        entries.append(entry)
        try storage.saveEntries(entries)
        logger.log("Enqueued workout \(workoutID.uuidString, privacy: .public)")
        return entry
    }

    /// Re-arm a failed or completed entry for another attempt. Resets the
    /// retry counter so the schedule starts from scratch.
    func retry(workoutID: UUID) throws {
        guard let idx = entries.firstIndex(where: { $0.workoutID == workoutID }) else { return }
        entries[idx].status = .pending
        entries[idx].retryCount = 0
        entries[idx].errorMessage = nil
        entries[idx].lastAttemptDate = nil
        try storage.saveEntries(entries)
    }

    /// Drop an entry entirely (used by History "remove" — not currently wired
    /// into UI but kept for cleanup paths).
    func remove(workoutID: UUID) throws {
        entries.removeAll { $0.workoutID == workoutID }
        try? storage.deleteTCX(for: workoutID)
        try storage.saveEntries(entries)
    }

    /// Drain everything currently due. Safe to call repeatedly; concurrent
    /// calls collapse to a single in-flight pass via `processing`.
    func process() async {
        guard !processing else { return }
        processing = true
        defer { processing = false }

        while let next = pickNext() {
            await uploadOne(workoutID: next)
        }
    }

    /// Process just one entry (test seam — production code calls `process()`).
    func processOne() async {
        if let next = pickNext() {
            await uploadOne(workoutID: next)
        }
    }

    // MARK: - Loading TCX side-files

    func tcxData(for workoutID: UUID) throws -> Data {
        try storage.readTCX(for: workoutID)
    }

    // MARK: - Private

    private func pickNext() -> UUID? {
        if let pauseUntil, pauseUntil > clock() { return nil }
        let now = clock()
        let candidate = entries
            .filter { $0.status == .pending }
            .filter { entry in
                guard let last = entry.lastAttemptDate else { return true }
                let delay = Self.delay(forRetry: entry.retryCount)
                return last.addingTimeInterval(delay) <= now
            }
            .min(by: { $0.enqueuedAt < $1.enqueuedAt })
        return candidate?.workoutID
    }

    static func delay(forRetry retryCount: Int) -> TimeInterval {
        let idx = max(0, min(retryCount, backoffSchedule.count - 1))
        return backoffSchedule[idx]
    }

    private func uploadOne(workoutID: UUID) async {
        guard let idx = entries.firstIndex(where: { $0.workoutID == workoutID }) else { return }
        let startDate = entries[idx].startDate
        entries[idx].status = .uploading
        entries[idx].lastAttemptDate = clock()
        try? storage.saveEntries(entries)

        let tcx: Data
        do {
            tcx = try storage.readTCX(for: workoutID)
        } catch {
            entries[idx].status = .failed
            entries[idx].errorMessage = "TCX file missing: \(error.localizedDescription)"
            try? storage.saveEntries(entries)
            return
        }

        do {
            let result = try await service.upload(workoutID: workoutID, startDate: startDate, tcx: tcx)
            entries[idx].status = .completed
            entries[idx].stravaUploadID = result.uploadId
            entries[idx].stravaActivityID = result.activityId
            entries[idx].errorMessage = nil
            try? storage.saveEntries(entries)
            logger.log("Upload completed for \(workoutID.uuidString, privacy: .public) (duplicate=\(result.isDuplicate, privacy: .public))")
        } catch StravaUploadError.rateLimited(let retryAfter) {
            pauseUntil = clock().addingTimeInterval(retryAfter)
            // Mark back to pending without consuming a retry attempt — the
            // 429 wasn't this entry's fault.
            entries[idx].status = .pending
            entries[idx].errorMessage = "Rate-limited; paused for \(Int(retryAfter))s"
            try? storage.saveEntries(entries)
            logger.log("Queue paused for \(Int(retryAfter), privacy: .public)s due to 429")
        } catch {
            entries[idx].retryCount += 1
            entries[idx].errorMessage = String(describing: error)
            if entries[idx].retryCount >= Self.maxRetries {
                entries[idx].status = .failed
                logger.error("Giving up on \(workoutID.uuidString, privacy: .public) after \(Self.maxRetries) attempts")
            } else {
                entries[idx].status = .pending
            }
            try? storage.saveEntries(entries)
        }
    }
}

// MARK: - Storage

/// Backing store seam — production writes to the app's documents directory;
/// tests use an in-memory implementation.
protocol StravaUploadQueueStorage: Sendable {
    func loadEntries() throws -> [StravaUploadQueueEntry]
    func saveEntries(_ entries: [StravaUploadQueueEntry]) throws
    func writeTCX(_ data: Data, for workoutID: UUID) throws
    func readTCX(for workoutID: UUID) throws -> Data
    func deleteTCX(for workoutID: UUID) throws
}

/// File-system implementation. Layout:
/// ```
/// Documents/StravaUploadQueue/
///   queue.json
///   tcx/{workoutID}.tcx
/// ```
struct FileStravaUploadQueueStorage: StravaUploadQueueStorage {
    let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            // FileManager.default is thread-safe; documentDirectory is
            // guaranteed-present on iOS so the force-try is fine.
            let docs = try! FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.baseDirectory = docs.appendingPathComponent("StravaUploadQueue", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.baseDirectory.appendingPathComponent("tcx"), withIntermediateDirectories: true)
    }

    private var queueFileURL: URL { baseDirectory.appendingPathComponent("queue.json") }
    private func tcxURL(_ id: UUID) -> URL {
        baseDirectory.appendingPathComponent("tcx/\(id.uuidString).tcx")
    }

    func loadEntries() throws -> [StravaUploadQueueEntry] {
        guard FileManager.default.fileExists(atPath: queueFileURL.path) else { return [] }
        let data = try Data(contentsOf: queueFileURL)
        let file = try JSONDecoder().decode(StravaUploadQueueFile.self, from: data)
        return file.entries
    }

    func saveEntries(_ entries: [StravaUploadQueueEntry]) throws {
        let file = StravaUploadQueueFile(entries: entries)
        let data = try JSONEncoder().encode(file)
        try data.write(to: queueFileURL, options: [.atomic])
    }

    func writeTCX(_ data: Data, for workoutID: UUID) throws {
        try data.write(to: tcxURL(workoutID), options: [.atomic])
    }

    func readTCX(for workoutID: UUID) throws -> Data {
        try Data(contentsOf: tcxURL(workoutID))
    }

    func deleteTCX(for workoutID: UUID) throws {
        let url = tcxURL(workoutID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Bridge fetcher seam
//
// (Removed in favor of bytes-level `service.upload(workoutID:startDate:tcx:)`
//  so retries upload the exact TCX bytes that were on disk at enqueue time.)

