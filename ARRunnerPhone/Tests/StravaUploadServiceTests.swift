// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
import ARRunnerCore
@testable import ARRunnerPhone

/// Covers multipart construction, 401-retry, 409-duplicate, and 429-rate-limit
/// behavior of `StravaUploadService`. Uses an in-memory transport so no real
/// URLSession is involved.
final class StravaUploadServiceTests: XCTestCase {

    // MARK: - Doubles

    final class StubTransport: StravaUploadTransport, @unchecked Sendable {
        struct Recorded {
            let request: URLRequest
            let body: Data
        }
        var responses: [(Data, URLResponse)] = []
        var errors: [Error] = []
        private(set) var calls: [Recorded] = []
        private let queue = DispatchQueue(label: "StubTransport")

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            try next(request: request, body: Data())
        }
        func upload(for request: URLRequest, from body: Data) async throws -> (Data, URLResponse) {
            try next(request: request, body: body)
        }
        private func next(request: URLRequest, body: Data) throws -> (Data, URLResponse) {
            try queue.sync {
                calls.append(.init(request: request, body: body))
                if !errors.isEmpty { throw errors.removeFirst() }
                guard !responses.isEmpty else {
                    fatalError("StubTransport ran out of responses")
                }
                return responses.removeFirst()
            }
        }
    }

    private func makeTokenStore(token: String = "tok-abc", expiresAt: TimeInterval = Date().timeIntervalSince1970 + 3600)
    -> (StravaTokenStore, StravaTokenStoreTests.MockRefresher, StravaTokenStoreTests.InMemoryBacking) {
        let backing = StravaTokenStoreTests.InMemoryBacking()
        let refresher = StravaTokenStoreTests.MockRefresher()
        let store = StravaTokenStore(backing: backing, refresher: refresher)
        try? store.save(
            accessToken: token, refreshToken: "rfx",
            expiresAt: expiresAt, athleteID: 7, athleteFirstName: nil)
        return (store, refresher, backing)
    }

    private func makeWorkout() -> TCXWorkoutData {
        TCXWorkoutData(
            workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_001_800),
            totalDistanceMeters: 5000,
            totalDurationSeconds: 1800
        )
    }

    private func okResponse(status: Int, body: String, headers: [String: String] = [:]) -> (Data, URLResponse) {
        let url = URL(string: "https://www.strava.com/api/v3/uploads")!
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (Data(body.utf8), resp)
    }

    // MARK: - Multipart

    func test_makeMultipartBody_includesAllRequiredFields() {
        let tcx = Data("<TCX/>".utf8)
        let body = StravaUploadService.makeMultipartBody(
            boundary: "BOUNDARY",
            tcx: tcx,
            filename: "abc.tcx",
            fields: [
                "data_type": "tcx",
                "external_id": "abc",
                "activity_type": "run",
                "name": "Morning Run",
                "description": "via AR-Runner"
            ])
        let text = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("name=\"data_type\""))
        XCTAssertTrue(text.contains("tcx"))
        XCTAssertTrue(text.contains("name=\"external_id\""))
        XCTAssertTrue(text.contains("name=\"activity_type\""))
        XCTAssertTrue(text.contains("name=\"name\""))
        XCTAssertTrue(text.contains("Morning Run"))
        XCTAssertTrue(text.contains("name=\"description\""))
        XCTAssertTrue(text.contains("via AR-Runner"))
        XCTAssertTrue(text.contains("filename=\"abc.tcx\""))
        XCTAssertTrue(text.hasSuffix("--BOUNDARY--\r\n"))
    }

    func test_makeMultipartBody_isDeterministic_forSameInput() {
        // Mirrors D-Strava-8 (TCX encoder determinism) — important so the
        // queue can compare retries byte-for-byte and the test matrix is stable.
        let tcx = Data("<TCX/>".utf8)
        let a = StravaUploadService.makeMultipartBody(boundary: "B", tcx: tcx, filename: "x.tcx", fields: ["a": "1", "b": "2"])
        let b = StravaUploadService.makeMultipartBody(boundary: "B", tcx: tcx, filename: "x.tcx", fields: ["b": "2", "a": "1"])
        XCTAssertEqual(a, b)
    }

    // MARK: - Success

    func test_upload_200_returnsResult() async throws {
        let (store, _, _) = makeTokenStore()
        let transport = StubTransport()
        transport.responses = [okResponse(status: 201, body: #"{"id":99,"external_id":"abc","status":"processing"}"#)]
        let svc = StravaUploadService(tokenStore: store, transport: transport, multipartBoundary: { "B" })
        let result = try await svc.upload(workout: makeWorkout())
        XCTAssertEqual(result.uploadId, 99)
        XCTAssertEqual(result.status, "processing")
        XCTAssertFalse(result.isDuplicate)
        let auth = transport.calls.first?.request.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(auth, "Bearer tok-abc")
    }

    // MARK: - 409 duplicate

    func test_upload_409_treatedAsSuccessAndMarkedDuplicate() async throws {
        let (store, _, _) = makeTokenStore()
        let transport = StubTransport()
        transport.responses = [okResponse(status: 409, body: #"{"id":42,"external_id":"abc","status":"duplicate","error":"duplicate of activity"}"#)]
        let svc = StravaUploadService(tokenStore: store, transport: transport, multipartBoundary: { "B" })
        let result = try await svc.upload(workout: makeWorkout())
        XCTAssertTrue(result.isDuplicate)
        XCTAssertEqual(result.uploadId, 42)
    }

    // MARK: - 401 retry

    func test_upload_401_thenRefresh_thenRetry_succeeds() async throws {
        let (store, refresher, _) = makeTokenStore(token: "stale-token")
        refresher.nextResponse = StravaRefreshResponse(
            access_token: "refreshed",
            refresh_token: "new-rf",
            expires_at: Date().timeIntervalSince1970 + 3600)
        let transport = StubTransport()
        transport.responses = [
            okResponse(status: 401, body: "unauthorized"),
            okResponse(status: 201, body: #"{"id":7,"external_id":"abc"}"#)
        ]
        let svc = StravaUploadService(tokenStore: store, transport: transport, multipartBoundary: { "B" })
        let result = try await svc.upload(workout: makeWorkout())
        XCTAssertEqual(result.uploadId, 7)
        XCTAssertEqual(transport.calls.count, 2)
        XCTAssertEqual(transport.calls[0].request.value(forHTTPHeaderField: "Authorization"), "Bearer stale-token")
        XCTAssertEqual(transport.calls[1].request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed")
        XCTAssertEqual(refresher.callCount, 1)
    }

    // MARK: - 429 rate-limit

    func test_upload_429_throwsRateLimitedWithRetryAfter() async throws {
        let (store, _, _) = makeTokenStore()
        let transport = StubTransport()
        transport.responses = [okResponse(status: 429, body: "slow down", headers: ["Retry-After": "120"])]
        let svc = StravaUploadService(tokenStore: store, transport: transport, multipartBoundary: { "B" })
        do {
            _ = try await svc.upload(workout: makeWorkout())
            XCTFail("Expected rateLimited")
        } catch StravaUploadError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 120)
        }
    }

    func test_upload_429_withoutRetryAfter_defaultsTo15Minutes() async throws {
        let (store, _, _) = makeTokenStore()
        let transport = StubTransport()
        transport.responses = [okResponse(status: 429, body: "")]
        let svc = StravaUploadService(tokenStore: store, transport: transport, multipartBoundary: { "B" })
        do {
            _ = try await svc.upload(workout: makeWorkout())
            XCTFail("Expected rateLimited")
        } catch StravaUploadError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 15 * 60)
        }
    }

    // MARK: - notConnected

    func test_upload_whenNotConnected_throwsNotConnected() async {
        let backing = StravaTokenStoreTests.InMemoryBacking()
        let store = StravaTokenStore(backing: backing, refresher: StravaTokenStoreTests.MockRefresher())
        let transport = StubTransport()
        let svc = StravaUploadService(tokenStore: store, transport: transport)
        do {
            _ = try await svc.upload(workout: makeWorkout())
            XCTFail("Expected notConnected")
        } catch StravaUploadError.notConnected {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}
