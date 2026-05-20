// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerPhone

/// Token store tests using an in-memory backing store + mock refresher.
/// Covers save/load/delete, expiration math, and the auto-refresh path.
final class StravaTokenStoreTests: XCTestCase {

    // MARK: - Test doubles (also reused by SettingsViewModelTests).

    final class InMemoryBacking: StravaTokenBackingStore, @unchecked Sendable {
        private var record: StravaTokenRecord?
        private let queue = DispatchQueue(label: "InMemoryBacking")
        func load() throws -> StravaTokenRecord? { queue.sync { record } }
        func save(_ r: StravaTokenRecord) throws { queue.sync { record = r } }
        func delete() throws { queue.sync { record = nil } }
    }

    final class MockRefresher: StravaTokenRefresher, @unchecked Sendable {
        var nextResponse: StravaRefreshResponse?
        var nextError: Error?
        private(set) var callCount = 0
        private(set) var lastRefreshToken: String?
        private let queue = DispatchQueue(label: "MockRefresher")
        func refresh(refreshToken: String) async throws -> StravaRefreshResponse {
            let (err, resp): (Error?, StravaRefreshResponse?) = queue.sync {
                callCount += 1
                lastRefreshToken = refreshToken
                return (nextError, nextResponse)
            }
            if let err { throw err }
            return resp ?? StravaRefreshResponse(
                access_token: "new-access",
                refresh_token: "new-refresh",
                expires_at: Date().timeIntervalSince1970 + 3600)
        }
    }

    // MARK: - Record

    func test_isExpired_treatsTokenWithin60sAsExpired() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let almostExpired = StravaTokenRecord(
            accessToken: "a", refreshToken: "r",
            expiresAt: 1_000_030, athleteID: 1, athleteFirstName: nil)
        XCTAssertTrue(almostExpired.isExpired(now: now))
        let fresh = StravaTokenRecord(
            accessToken: "a", refreshToken: "r",
            expiresAt: 1_000_999, athleteID: 1, athleteFirstName: nil)
        XCTAssertFalse(fresh.isExpired(now: now))
    }

    // MARK: - Save / load / delete

    func test_save_thenIsConnected_returnsTrue() throws {
        let store = StravaTokenStore(backing: InMemoryBacking(), refresher: MockRefresher())
        XCTAssertFalse(store.isConnected)
        try store.save(
            accessToken: "ax", refreshToken: "rx",
            expiresAt: Date().timeIntervalSince1970 + 3600,
            athleteID: 42, athleteFirstName: "Joe")
        XCTAssertTrue(store.isConnected)
        XCTAssertEqual(store.athleteFirstName, "Joe")
        XCTAssertEqual(store.athleteID, 42)
    }

    func test_disconnect_clearsRecord() throws {
        let store = StravaTokenStore(backing: InMemoryBacking(), refresher: MockRefresher())
        try store.save(
            accessToken: "ax", refreshToken: "rx",
            expiresAt: Date().timeIntervalSince1970 + 3600,
            athleteID: 1, athleteFirstName: "x")
        store.disconnect()
        XCTAssertFalse(store.isConnected)
    }

    // MARK: - validAccessToken

    func test_validAccessToken_throwsNotConnected_whenEmpty() async {
        let store = StravaTokenStore(backing: InMemoryBacking(), refresher: MockRefresher())
        do {
            _ = try await store.validAccessToken()
            XCTFail("Expected throw")
        } catch StravaTokenStoreError.notConnected {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_validAccessToken_returnsCurrentToken_whenFresh() async throws {
        let refresher = MockRefresher()
        let store = StravaTokenStore(backing: InMemoryBacking(), refresher: refresher)
        try store.save(
            accessToken: "fresh", refreshToken: "rx",
            expiresAt: Date().timeIntervalSince1970 + 3600,
            athleteID: 1, athleteFirstName: nil)
        let token = try await store.validAccessToken()
        XCTAssertEqual(token, "fresh")
        XCTAssertEqual(refresher.callCount, 0, "Should not have refreshed a fresh token")
    }

    func test_validAccessToken_refreshes_whenExpired() async throws {
        let backing = InMemoryBacking()
        let refresher = MockRefresher()
        refresher.nextResponse = StravaRefreshResponse(
            access_token: "refreshed-access",
            refresh_token: "refreshed-refresh",
            expires_at: Date().timeIntervalSince1970 + 3600)
        let store = StravaTokenStore(backing: backing, refresher: refresher)
        try store.save(
            accessToken: "stale", refreshToken: "old-refresh",
            expiresAt: Date().timeIntervalSince1970 - 10,
            athleteID: 9, athleteFirstName: "Z")
        let token = try await store.validAccessToken()
        XCTAssertEqual(token, "refreshed-access")
        XCTAssertEqual(refresher.callCount, 1)
        XCTAssertEqual(refresher.lastRefreshToken, "old-refresh")
        let persisted = try XCTUnwrap(try backing.load())
        XCTAssertEqual(persisted.accessToken, "refreshed-access")
        XCTAssertEqual(persisted.refreshToken, "refreshed-refresh")
        XCTAssertEqual(persisted.athleteID, 9)
        XCTAssertEqual(persisted.athleteFirstName, "Z")
    }

    func test_validAccessToken_propagatesRefreshError() async throws {
        let refresher = MockRefresher()
        refresher.nextError = StravaTokenStoreError.refreshFailed(statusCode: 401)
        let store = StravaTokenStore(backing: InMemoryBacking(), refresher: refresher)
        try store.save(
            accessToken: "stale", refreshToken: "x",
            expiresAt: Date().timeIntervalSince1970 - 10,
            athleteID: 1, athleteFirstName: nil)
        do {
            _ = try await store.validAccessToken()
            XCTFail("Expected throw")
        } catch StravaTokenStoreError.refreshFailed(let code) {
            XCTAssertEqual(code, 401)
        }
    }
}
