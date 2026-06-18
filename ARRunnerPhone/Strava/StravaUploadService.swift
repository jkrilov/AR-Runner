// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import os

/// Result of a successful `POST /api/v3/uploads` call.
///
/// `uploadId` is the handle the queue uses to poll `GET /api/v3/uploads/{id}`.
/// `activityId` is populated once Strava finishes server-side processing
/// (TCX → activity); until then `status` carries Strava's free-form progress
/// string ("Your activity is still being processed.").
struct StravaUploadResult: Sendable, Equatable {
    let uploadId: Int
    let externalId: String?
    let status: String?
    let activityId: Int?
    /// Treated as success by the queue: Strava already has this `external_id`.
    /// Per D-Strava-4 retries are expected, so a 409 → "already uploaded" is
    /// the *correct* idempotent outcome, not an error.
    let isDuplicate: Bool
}

/// Polled status of a previously-started upload.
struct StravaUploadStatus: Sendable, Equatable {
    let id: Int
    let externalId: String?
    let activityId: Int?
    let status: String
    let error: String?

    var isComplete: Bool { activityId != nil }
    var isFailed: Bool {
        if let error, !error.isEmpty { return true }
        return false
    }
}

enum StravaUploadError: Error, Equatable, Sendable {
    case notConnected
    /// Strava returned 429. The queue must pause for at least `retryAfter`
    /// seconds before issuing another request.
    case rateLimited(retryAfter: TimeInterval)
    /// Token store refused or refresh failed during the 401 retry path.
    case authFailed
    case server(statusCode: Int, body: String?)
    case network(String)
    case invalidServerResponse
}

/// Tiny transport seam so tests can swap `URLSession.shared` for a fake
/// without instantiating a real network stack. Mirrors the relevant slice of
/// `URLSession.data(for:)` + `URLSession.upload(for:from:)`.
///
/// `externalID` (= `HKWorkout.uuid`) is threaded into the upload call so a
/// background-session transport can tag the underlying `URLSessionTask`
/// (`taskDescription`) and reconcile it after an app relaunch. In-memory
/// transports ignore it.
protocol StravaUploadTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func upload(for request: URLRequest, from body: Data, externalID: String) async throws -> (Data, URLResponse)
}

extension URLSession: StravaUploadTransport {
    func upload(for request: URLRequest, from body: Data, externalID: String) async throws -> (Data, URLResponse) {
        try await self.upload(for: request, from: body, delegate: nil)
    }
}

/// Strava `POST /api/v3/uploads` client.
///
/// D-Strava-1 places the upload on the phone; D-Strava-4 keeps it independent
/// of workout save (the queue absorbs retries). Everything Strava-specific —
/// multipart construction, 401-then-refresh, 409-as-success, 429-as-rate-limit
/// — lives here so the queue can stay generic.
final class StravaUploadService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.arrunner.phone", category: "StravaUpload")
    private let tokenStore: StravaTokenStore
    private let transport: StravaUploadTransport
    private let apiBaseURL: URL
    private let multipartBoundary: () -> String

    init(
        tokenStore: StravaTokenStore = .shared,
        transport: StravaUploadTransport = BackgroundStravaUploadTransport.shared,
        apiBaseURL: URL = URL(string: "https://www.strava.com/api/v3")!,
        multipartBoundary: @escaping () -> String = { "arrunner-\(UUID().uuidString)" }
    ) {
        self.tokenStore = tokenStore
        self.transport = transport
        self.apiBaseURL = apiBaseURL
        self.multipartBoundary = multipartBoundary
    }

    // MARK: - Upload

    /// Encode + upload a single workout. Convenience wrapper around the
    /// bytes-level path below.
    func upload(workout: TCXWorkoutData) async throws -> StravaUploadResult {
        try await upload(
            workoutID: workout.workoutID,
            startDate: workout.startDate,
            tcx: TCXEncoder.encode(workout)
        )
    }

    /// Upload pre-encoded TCX bytes for a workout. The queue uses this
    /// directly so that a retry after app relaunch uploads the *same* bytes
    /// it persisted at enqueue time (no re-encode = no risk of behavioural
    /// drift between the original attempt and the retry).
    func upload(workoutID: UUID, startDate: Date, tcx: Data) async throws -> StravaUploadResult {
        let name = ActivityNaming.name(forStart: startDate)
        let externalID = workoutID.uuidString

        let boundary = multipartBoundary()
        let body = Self.makeMultipartBody(
            boundary: boundary,
            tcx: tcx,
            filename: "\(externalID).tcx",
            fields: [
                "data_type": "tcx",
                "external_id": externalID,
                "activity_type": "run",
                "name": name,
                "description": "via AR-Runner"
            ]
        )

        let request = try await makeUploadRequest(boundary: boundary, body: body)
        do {
            return try await performUpload(request: request, body: body, externalID: externalID)
        } catch StravaUploadError.authFailed {
            // 401 path — force-refresh and retry exactly once.
            let fresh = try await tokenStore.forceRefresh()
            var retry = request
            retry.setValue("Bearer \(fresh)", forHTTPHeaderField: "Authorization")
            return try await performUpload(request: retry, body: body, externalID: externalID)
        }
    }

    /// Poll Strava for the processing status of a previously-started upload.
    func checkUploadStatus(uploadId: Int) async throws -> StravaUploadStatus {
        let token = try await tokenStore.validAccessToken()
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("uploads/\(uploadId)"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw StravaUploadError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw StravaUploadError.invalidServerResponse
        }
        if http.statusCode == 401 {
            throw StravaUploadError.authFailed
        }
        if http.statusCode == 429 {
            throw StravaUploadError.rateLimited(retryAfter: Self.retryAfter(from: http))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StravaUploadError.server(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try Self.decodeStatus(data: data)
    }

    // MARK: - Private

    private func makeUploadRequest(boundary: String, body: Data) async throws -> URLRequest {
        let token: String
        do {
            token = try await tokenStore.validAccessToken()
        } catch StravaTokenStoreError.notConnected {
            throw StravaUploadError.notConnected
        } catch {
            throw StravaUploadError.authFailed
        }
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("uploads"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        return request
    }

    private func performUpload(request: URLRequest, body: Data, externalID: String) async throws -> StravaUploadResult {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await transport.upload(for: request, from: body, externalID: externalID)
        } catch {
            throw StravaUploadError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw StravaUploadError.invalidServerResponse
        }
        switch http.statusCode {
        case 200..<300:
            return try Self.decodeUpload(data: data, isDuplicate: false)
        case 401:
            throw StravaUploadError.authFailed
        case 409:
            // Strava returns 409 + an upload payload describing the duplicate.
            // Treat as success — the canonical activity already exists for
            // this external_id (HKWorkout UUID), which is exactly the contract
            // we promise upstream.
            logger.log("Strava 409 duplicate for external_id=\(externalID, privacy: .public)")
            if let result = try? Self.decodeUpload(data: data, isDuplicate: true) {
                return result
            }
            return StravaUploadResult(uploadId: -1, externalId: externalID, status: "duplicate", activityId: nil, isDuplicate: true)
        case 429:
            throw StravaUploadError.rateLimited(retryAfter: Self.retryAfter(from: http))
        default:
            throw StravaUploadError.server(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    // MARK: - Multipart

    /// RFC 7578 multipart/form-data body. The TCX file is one part; each
    /// scalar field is its own text part. We assemble it manually because
    /// `URLSession` has no first-class multipart helper.
    static func makeMultipartBody(
        boundary: String,
        tcx: Data,
        filename: String,
        fields: [String: String]
    ) -> Data {
        var body = Data()
        // Sort field keys so the body is deterministic — matches D-Strava-8's
        // "byte-identical output for byte-identical input" rule, which lets
        // tests assert exact bodies and lets the queue compare retries.
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(tcx)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }

    // MARK: - Decoding

    private struct UploadJSON: Decodable {
        let id: Int?
        let external_id: String?
        let status: String?
        let activity_id: Int?
        let error: String?
    }

    static func decodeUpload(data: Data, isDuplicate: Bool) throws -> StravaUploadResult {
        do {
            let json = try JSONDecoder().decode(UploadJSON.self, from: data)
            return StravaUploadResult(
                uploadId: json.id ?? -1,
                externalId: json.external_id,
                status: json.status,
                activityId: json.activity_id,
                isDuplicate: isDuplicate
            )
        } catch {
            throw StravaUploadError.invalidServerResponse
        }
    }

    static func decodeStatus(data: Data) throws -> StravaUploadStatus {
        do {
            let json = try JSONDecoder().decode(UploadJSON.self, from: data)
            return StravaUploadStatus(
                id: json.id ?? -1,
                externalId: json.external_id,
                activityId: json.activity_id,
                status: json.status ?? "",
                error: json.error
            )
        } catch {
            throw StravaUploadError.invalidServerResponse
        }
    }

    /// Pull a `Retry-After` header (seconds), falling back to 15 minutes
    /// which is Strava's documented short-window reset.
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval {
        if let raw = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)) {
            return max(seconds, 1)
        }
        return 15 * 60
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
