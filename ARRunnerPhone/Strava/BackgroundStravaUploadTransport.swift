// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os

/// Background-`URLSession` implementation of `StravaUploadTransport` (Part 2 of
/// the v0.6.1 upload-reliability fix).
///
/// Why this exists: the original path used a *foreground* `URLSession.shared`
/// upload. iOS readily suspends/kills a backgrounded app mid-request, which for
/// a large TCX over cellular left the queue entry persisted as `.uploading`
/// forever (the original bug). A background-configured session hands the
/// transfer to the system `nsurlsessiond` daemon, which keeps uploading after
/// the app is suspended and relaunches the app to deliver the result.
///
/// Design:
/// - One process-wide session keyed by a fixed identifier (`.shared`). Only one
///   `URLSession` may own a given background identifier per process.
/// - Background sessions require a **file**-based body, so `upload` writes the
///   already-built multipart body (byte-identical to `makeMultipartBody`,
///   D-Strava-8) to a temp file and submits `uploadTask(with:fromFile:)`.
/// - Background sessions cannot run *data* tasks, so the small
///   `GET /uploads/{id}` confirmation polls go through a plain ephemeral
///   session via `data(for:)`.
/// - Delegate callbacks (which arrive on a background queue, possibly in a
///   freshly relaunched process) are bridged back to the `async` caller with a
///   `CheckedContinuation` keyed by `taskIdentifier`. Response bodies are
///   accumulated per task. State is guarded by an `NSLock` (hence
///   `@unchecked Sendable`, matching `StravaUploadService`).
///
/// Cold-start safety: if the app is killed while a task is in flight, the
/// in-process continuation is gone on relaunch. That entry was persisted as
/// `.uploading` and is reclaimed to `.pending` by `StravaUploadQueue` at init,
/// then re-uploaded; Strava's `external_id` idempotency turns the redundant
/// POST into a 409 → treated as success. No double activity is created.
/// Outcome of a background upload task that completed with no in-process
/// `async` waiter — either delivered to a freshly relaunched process, or after
/// the in-app await already timed out (Fix C, v0.6.2). Carries everything the
/// `StravaUploadQueue` needs to reconcile the matching entry by `externalID`.
struct OrphanedUploadOutcome: Sendable {
    let externalID: String
    let statusCode: Int?
    let body: Data
    let errorDescription: String?
}

final class BackgroundStravaUploadTransport: NSObject, StravaUploadTransport, @unchecked Sendable {

    /// Must match `application(_:handleEventsForBackgroundURLSession:…)`.
    static let sessionIdentifier = "com.arrunner.phone.strava-upload"
    static let shared = BackgroundStravaUploadTransport()

    /// Hard ceiling on a single in-app upload await. A background task that
    /// never delivers a completion (suspended daemon, lost callback) must not
    /// pin a queue entry in `.uploading` forever — on timeout we cancel the
    /// task and throw so the queue marks the entry retryable (Fix B, v0.6.2).
    static let uploadTimeout: TimeInterval = 120

    private let logger = Logger(subsystem: "com.arrunner.phone", category: "StravaBGUpload")
    private let lock = NSLock()

    /// Carries the non-`Sendable` UIKit completion closure across the
    /// `DispatchQueue.main.async` hop without tripping Swift 6 strict
    /// concurrency. The closure is only ever invoked once, on the main thread.
    private final class CompletionBox: @unchecked Sendable {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    /// Reconciliation hook the queue registers so orphaned completions advance
    /// a queue entry instead of being dropped (Fix C, v0.6.2).
    typealias OrphanReconciler = @Sendable (OrphanedUploadOutcome) async -> Void

    private var continuations: [Int: CheckedContinuation<(Data, URLResponse), Error>] = [:]
    private var buffers: [Int: Data] = [:]
    private var tempFiles: [Int: URL] = [:]
    /// In-flight upload tasks, keyed by `taskIdentifier`, so the timeout
    /// watchdog can cancel a task without capturing the non-`Sendable`
    /// `URLSessionTask` in its closure.
    private var tasks: [Int: URLSessionTask] = [:]
    /// Per-task timeout watchdogs, cancelled when a completion lands first.
    private var timeoutWorkItems: [Int: DispatchWorkItem] = [:]
    private var orphanReconciler: OrphanReconciler?
    /// System-provided completion handler from the background-launch event.
    private var systemCompletionHandler: CompletionBox?

    /// The background session. Lazily created so merely referencing the type in
    /// tests (which never touch `.shared`) doesn't spin up a daemon session.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Confirmation polls are GETs; background sessions can't do data tasks.
    private let pollSession = URLSession(configuration: .ephemeral)

    private let tempDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("strava-upload-bodies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - App lifecycle wiring

    /// Re-create/attach the background session on a background-launch so its
    /// delegate can drain finished events. Calling this just forces the lazy
    /// `session` to materialise.
    func reattach() {
        _ = session
    }

    /// Store the system completion handler delivered by
    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    /// It is invoked once the session reports it has finished its events.
    func setSystemCompletionHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        systemCompletionHandler = CompletionBox(handler)
        lock.unlock()
    }

    /// Register the queue's reconciliation hook for orphaned completions
    /// (Fix C, v0.6.2). Wired once at app launch.
    func setOrphanReconciler(_ reconciler: @escaping OrphanReconciler) {
        lock.lock()
        orphanReconciler = reconciler
        lock.unlock()
    }

    // MARK: - StravaUploadTransport

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await pollSession.data(for: request)
    }

    func upload(for request: URLRequest, from body: Data, externalID: String) async throws -> (Data, URLResponse) {
        let fileURL = try writeBodyFile(body, externalID: externalID)
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: fileURL)
            task.taskDescription = externalID
            let id = task.taskIdentifier
            lock.lock()
            continuations[id] = continuation
            buffers[id] = Data()
            tempFiles[id] = fileURL
            tasks[id] = task
            lock.unlock()
            scheduleTimeout(taskID: id)
            task.resume()
        }
    }

    // MARK: - Timeout watchdog (Fix B)

    /// Arm a timeout for the in-app await. Captures only `Sendable` values
    /// (`self`, the `Int` id) so the watchdog block stays Swift 6 clean.
    private func scheduleTimeout(taskID id: Int) {
        let work = DispatchWorkItem { [weak self] in
            self?.fireTimeout(taskID: id)
        }
        lock.lock()
        timeoutWorkItems[id] = work
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.uploadTimeout, execute: work)
    }

    /// Resolve a stalled upload exactly once. The `continuations` dict is the
    /// single-resume guard: whichever of `fireTimeout` / `didCompleteWithError`
    /// removes the continuation first wins; the other no-ops.
    private func fireTimeout(taskID id: Int) {
        lock.lock()
        let cont = continuations.removeValue(forKey: id)
        buffers.removeValue(forKey: id)
        let task = tasks.removeValue(forKey: id)
        timeoutWorkItems.removeValue(forKey: id)
        lock.unlock()
        guard let cont else { return }
        task?.cancel()
        cleanupTempFile(taskID: id)
        logger.error("Background upload task \(id) timed out after \(Int(Self.uploadTimeout))s; resuming as retryable failure")
        cont.resume(throwing: StravaUploadError.network("Upload timed out"))
    }

    // MARK: - Temp file

    private func writeBodyFile(_ body: Data, externalID: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent("\(externalID)-\(UUID().uuidString).body")
        try body.write(to: url, options: [.atomic])
        return url
    }

    private func cleanupTempFile(taskID: Int) {
        lock.lock()
        let url = tempFiles.removeValue(forKey: taskID)
        lock.unlock()
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: - URLSession delegates

extension BackgroundStravaUploadTransport: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        lock.lock()
        buffers[id, default: Data()].append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        lock.lock()
        let continuation = continuations.removeValue(forKey: id)
        let body = buffers.removeValue(forKey: id) ?? Data()
        tasks.removeValue(forKey: id)
        let timeout = timeoutWorkItems.removeValue(forKey: id)
        let reconciler = orphanReconciler
        lock.unlock()
        timeout?.cancel()
        cleanupTempFile(taskID: id)

        guard let continuation else {
            // No in-process waiter — this task completed in a relaunched
            // process, or the in-app await already timed out. Do NOT drop it:
            // hand it to the queue's reconciler keyed by `externalID`
            // (`taskDescription`) so the matching entry advances. Idempotency
            // (external_id → Strava 409 → success) is the backstop.
            let externalID = task.taskDescription
            let statusCode = (task.response as? HTTPURLResponse)?.statusCode
            if let error {
                logger.error("Orphaned bg upload task \(id) failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.log("Orphaned bg upload task \(id) completed without an in-process waiter; reconciling queue entry.")
            }
            guard let externalID, let reconciler else { return }
            let outcome = OrphanedUploadOutcome(
                externalID: externalID,
                statusCode: statusCode,
                body: body,
                errorDescription: error?.localizedDescription
            )
            Task { await reconciler(outcome) }
            return
        }

        if let error {
            continuation.resume(throwing: error)
            return
        }
        guard let response = task.response else {
            continuation.resume(throwing: StravaUploadError.invalidServerResponse)
            return
        }
        continuation.resume(returning: (body, response))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let box = systemCompletionHandler
        systemCompletionHandler = nil
        lock.unlock()
        guard let box else { return }
        // UIKit requires the completion handler be called on the main thread.
        DispatchQueue.main.async { box.run() }
    }
}
