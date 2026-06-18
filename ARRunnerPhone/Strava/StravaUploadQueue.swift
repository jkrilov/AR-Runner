// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

/// Status of one queued upload. Persisted to disk so the queue survives app
/// restarts (per task spec — phone may be backgrounded mid-retry-backoff).
///
/// State machine (v0.6.1 — robust uploads). Every non-terminal state is
/// reachable by `pickNext()` or reclaimed at init, so nothing can get stuck:
/// ```
///   pending ──upload POST──▶ uploading ──2xx, activity pending──▶ processing
///      ▲  ▲                     │  │                                  │
///      │  └──reclaim at init────┘  ├──2xx + activity_id / 409─────────┼──▶ completed
///      │                           └──transient error / 429───────────┘
///      └──poll budget exceeded (re-POST → 409 dup → completed)◀── processing
///                                  poll error / activity_id pending ──┘
/// ```
/// - `.uploading` is transient (POST in flight). At process start nothing is
///   actually in flight, so any persisted `.uploading` is an interrupted
///   attempt and is reclaimed to `.pending` on init (Part 1 of the fix).
/// - `.processing` means Strava accepted the upload but hasn't finished the
///   server-side TCX→activity conversion yet; the queue polls
///   `GET /uploads/{id}` until `activity_id` appears or `error` is set
///   (Part 3). It is fully reclaimable by `pickNext()`.
enum StravaUploadEntryStatus: String, Codable, Sendable {
    case pending
    case uploading
    case processing
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
    /// Number of `GET /uploads/{id}` polls spent confirming server-side
    /// processing (Part 3). Separate from `retryCount` so confirmation polling
    /// has its own bounded budget and never burns an upload retry. Optional so
    /// queue files persisted before v0.6.1 decode without a hard reset.
    var confirmPollCount: Int? = nil
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
    /// Confirmation-poll backoff schedule (seconds). Index = confirmPollCount.
    /// Short and bounded — Strava usually finishes TCX processing in seconds.
    static let pollBackoffSchedule: [TimeInterval] = [2, 5, 10, 20, 30]
    /// Max confirmation polls before giving up on the *current* upload handle
    /// and re-POSTing (which 409-dedups to `.completed`). Keeps `.processing`
    /// from looping forever while never leaving the entry unreachable.
    static let maxConfirmPolls = 12

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
        let loaded = (try? storage.loadEntries()) ?? []
        // Part 1 — reclaim orphaned uploads. At process start nothing is
        // actually in flight, so a persisted `.uploading` entry is by
        // definition an interrupted attempt. Reset it to `.pending` WITHOUT
        // consuming a retry (the interruption isn't the entry's fault) so
        // `process()` picks it up again. Idempotency (external_id = workout
        // UUID → Strava 409 → success) covers any rare double-send if a
        // background task did happen to land.
        let reclaimed = Self.reclaimOrphans(loaded)
        self.entries = reclaimed
        if reclaimed != loaded {
            try? storage.saveEntries(reclaimed)
        }
    }

    /// Pure, testable reclaim pass: any `.uploading` entry → `.pending`.
    /// `.processing` entries are left untouched because `pickNext()` already
    /// reclaims them (they carry a pollable upload handle).
    static func reclaimOrphans(_ entries: [StravaUploadQueueEntry]) -> [StravaUploadQueueEntry] {
        entries.map { entry in
            guard entry.status == .uploading else { return entry }
            var fixed = entry
            fixed.status = .pending
            fixed.errorMessage = "Reclaimed after interrupted upload"
            return fixed
        }
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
        entries[idx].confirmPollCount = 0
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
            await advance(workoutID: next)
        }
    }

    /// Process just one entry (test seam — production code calls `process()`).
    func processOne() async {
        if let next = pickNext() {
            await advance(workoutID: next)
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
            // Both `.pending` (needs a POST) and `.processing` (needs a
            // confirmation poll) are actionable. `.uploading` is never selected
            // — it is transient and reclaimed at init.
            .filter { $0.status == .pending || $0.status == .processing }
            .filter { entry in
                guard let last = entry.lastAttemptDate else { return true }
                return last.addingTimeInterval(Self.delay(for: entry)) <= now
            }
            .min(by: { $0.enqueuedAt < $1.enqueuedAt })
        return candidate?.workoutID
    }

    /// Due-delay for an entry, branching on which phase it's in.
    static func delay(for entry: StravaUploadQueueEntry) -> TimeInterval {
        switch entry.status {
        case .processing:
            return pollDelay(forPoll: entry.confirmPollCount ?? 0)
        default:
            return delay(forRetry: entry.retryCount)
        }
    }

    static func delay(forRetry retryCount: Int) -> TimeInterval {
        let idx = max(0, min(retryCount, backoffSchedule.count - 1))
        return backoffSchedule[idx]
    }

    static func pollDelay(forPoll pollCount: Int) -> TimeInterval {
        let idx = max(0, min(pollCount, pollBackoffSchedule.count - 1))
        return pollBackoffSchedule[idx]
    }

    /// Route an entry to the right phase: upload (POST) or confirm (poll).
    private func advance(workoutID: UUID) async {
        guard let idx = entries.firstIndex(where: { $0.workoutID == workoutID }) else { return }
        switch entries[idx].status {
        case .processing:
            await confirmOne(workoutID: workoutID)
        default:
            await uploadOne(workoutID: workoutID)
        }
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
            guard let idx = entries.firstIndex(where: { $0.workoutID == workoutID }) else { return }
            entries[idx].errorMessage = nil
            entries[idx].stravaUploadID = result.uploadId
            if result.isDuplicate {
                // 409 — the activity already exists for this external_id. There
                // may be no pollable upload id; treat as completed (Part 3).
                entries[idx].status = .completed
                entries[idx].stravaActivityID = result.activityId
                logger.log("Upload duplicate (409) → completed for \(workoutID.uuidString, privacy: .public)")
            } else if let activityID = result.activityId {
                // Strava already finished processing — straight to completed.
                entries[idx].status = .completed
                entries[idx].stravaActivityID = activityID
            } else if result.uploadId > 0 {
                // Accepted but processing server-side: enter the poll phase.
                entries[idx].status = .processing
                entries[idx].confirmPollCount = 0
                entries[idx].lastAttemptDate = clock()
                logger.log("Upload accepted, awaiting processing for \(workoutID.uuidString, privacy: .public) (id=\(result.uploadId, privacy: .public))")
            } else {
                // No activity id and no pollable handle — nothing more we can
                // do; accept it rather than leaving it stuck.
                entries[idx].status = .completed
            }
            try? storage.saveEntries(entries)
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

    /// Confirmation phase (Part 3): poll `GET /uploads/{id}` until Strava has
    /// finished server-side processing. Every outcome keeps the entry
    /// reachable by `pickNext()` until it reaches a terminal state.
    private func confirmOne(workoutID: UUID) async {
        guard let idx = entries.firstIndex(where: { $0.workoutID == workoutID }) else { return }
        entries[idx].lastAttemptDate = clock()

        guard let uploadID = entries[idx].stravaUploadID, uploadID > 0 else {
            // Nothing pollable (e.g. a duplicate with no id) — accept it.
            entries[idx].status = .completed
            try? storage.saveEntries(entries)
            return
        }

        do {
            let status = try await service.checkUploadStatus(uploadId: uploadID)
            guard let idx = entries.firstIndex(where: { $0.workoutID == workoutID }) else { return }
            if status.isFailed {
                entries[idx].status = .failed
                entries[idx].errorMessage = status.error
                logger.error("Strava processing failed for \(workoutID.uuidString, privacy: .public): \(status.error ?? "", privacy: .public)")
            } else if let activityID = status.activityId {
                entries[idx].status = .completed
                entries[idx].stravaActivityID = activityID
                entries[idx].errorMessage = nil
                logger.log("Strava processing confirmed for \(workoutID.uuidString, privacy: .public) → activity \(activityID, privacy: .public)")
            } else {
                bumpPollOrReupload(idx: idx, message: "Awaiting Strava processing")
            }
            try? storage.saveEntries(entries)
        } catch StravaUploadError.rateLimited(let retryAfter) {
            // Pause the queue but keep the entry in `.processing` so it resumes.
            pauseUntil = clock().addingTimeInterval(retryAfter)
            entries[idx].errorMessage = "Rate-limited; paused for \(Int(retryAfter))s"
            try? storage.saveEntries(entries)
        } catch {
            // Transient poll failure — count it against the poll budget, but
            // never lose the entry.
            guard let idx = entries.firstIndex(where: { $0.workoutID == workoutID }) else { return }
            bumpPollOrReupload(idx: idx, message: "Poll failed: \(String(describing: error))")
            try? storage.saveEntries(entries)
        }
    }

    /// Increment the confirmation-poll counter; once the budget is exceeded,
    /// drop back to `.pending` so the entry re-POSTs (which 409-dedups to
    /// completed). This consumes one upload retry so a permanently-stuck
    /// processing entry still terminates at `.failed` after `maxRetries`.
    private func bumpPollOrReupload(idx: Int, message: String) {
        let next = (entries[idx].confirmPollCount ?? 0) + 1
        entries[idx].errorMessage = message
        if next >= Self.maxConfirmPolls {
            entries[idx].confirmPollCount = 0
            entries[idx].retryCount += 1
            entries[idx].lastAttemptDate = clock()
            if entries[idx].retryCount >= Self.maxRetries {
                entries[idx].status = .failed
            } else {
                entries[idx].status = .pending
            }
        } else {
            entries[idx].confirmPollCount = next
            entries[idx].status = .processing
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

