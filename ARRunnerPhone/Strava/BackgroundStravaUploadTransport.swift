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
final class BackgroundStravaUploadTransport: NSObject, StravaUploadTransport, @unchecked Sendable {

    /// Must match `application(_:handleEventsForBackgroundURLSession:…)`.
    static let sessionIdentifier = "com.arrunner.phone.strava-upload"
    static let shared = BackgroundStravaUploadTransport()

    private let logger = Logger(subsystem: "com.arrunner.phone", category: "StravaBGUpload")
    private let lock = NSLock()

    /// Carries the non-`Sendable` UIKit completion closure across the
    /// `DispatchQueue.main.async` hop without tripping Swift 6 strict
    /// concurrency. The closure is only ever invoked once, on the main thread.
    private final class CompletionBox: @unchecked Sendable {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    private var continuations: [Int: CheckedContinuation<(Data, URLResponse), Error>] = [:]
    private var buffers: [Int: Data] = [:]
    private var tempFiles: [Int: URL] = [:]
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
            lock.unlock()
            task.resume()
        }
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
        lock.unlock()
        cleanupTempFile(taskID: id)

        guard let continuation else {
            // No in-process waiter — this task completed in a relaunched
            // process. The queue already reclaimed the entry to `.pending`
            // (idempotent re-upload covers it), so just log.
            if let error {
                logger.error("Orphaned bg upload task \(id) failed: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.log("Orphaned bg upload task \(id) completed without an in-process waiter; queue will reconcile via reclaim/idempotency.")
            }
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
