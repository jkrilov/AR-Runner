// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
#if canImport(Security)
import Security
#endif

/// Persisted Strava credential bundle. The whole record is encoded as JSON
/// and stored in a single Keychain item under `StravaTokenStore.serviceName`.
/// One item, atomic writes — avoids the partial-state problem of storing
/// access / refresh / metadata as four separate items.
struct StravaTokenRecord: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    /// Seconds since 1970 (matches Strava's `expires_at` field directly).
    var expiresAt: TimeInterval
    var athleteID: Int
    var athleteFirstName: String?

    /// Treat tokens that expire within 60s as already-expired so a refresh
    /// fires before we issue a request that would 401 mid-flight.
    func isExpired(now: Date = Date(), skew: TimeInterval = 60) -> Bool {
        now.timeIntervalSince1970 + skew >= expiresAt
    }
}

/// Network surface the token store uses for refresh. Parameterized so tests
/// can drop in a mock without launching a real URL session.
protocol StravaTokenRefresher: Sendable {
    func refresh(refreshToken: String) async throws -> StravaRefreshResponse
}

struct StravaRefreshResponse: Decodable, Sendable, Equatable {
    let access_token: String
    let refresh_token: String
    let expires_at: TimeInterval
}

enum StravaTokenStoreError: Error, Equatable, Sendable {
    case notConnected
    case keychainFailure(OSStatus)
    case refreshFailed(statusCode: Int)
    case network(String)
    case invalidServerResponse
}

/// Backing store that hides Keychain CRUD behind a tiny interface so tests
/// can substitute an in-memory implementation.
protocol StravaTokenBackingStore: Sendable {
    func load() throws -> StravaTokenRecord?
    func save(_ record: StravaTokenRecord) throws
    func delete() throws
}

/// Default-shared token store. Reads/writes a single JSON blob in the
/// shared App Group keychain so the watch can read the same credentials.
///
/// D-Strava-1 places upload on the phone, but the watch may still want to
/// know "is Strava connected?" for UI hints — sharing through the keychain
/// access group keeps that read cheap and avoids a WC round-trip.
final class StravaTokenStore: @unchecked Sendable {
    static let shared = StravaTokenStore()

    private let logger = Logger(subsystem: "com.arrunner.phone", category: "StravaTokens")
    private let backing: StravaTokenBackingStore
    private let refresher: StravaTokenRefresher
    private let lock = NSLock()

    init(
        backing: StravaTokenBackingStore = KeychainStravaTokenStore(),
        refresher: StravaTokenRefresher = WorkerStravaTokenRefresher()
    ) {
        self.backing = backing
        self.refresher = refresher
    }

    // MARK: - Read

    var isConnected: Bool {
        (try? backing.load()) != nil
    }

    var athleteFirstName: String? {
        try? backing.load()?.athleteFirstName
    }

    var athleteID: Int? {
        try? backing.load()?.athleteID
    }

    /// Cached access token without triggering a refresh. Used by the
    /// disconnect flow to call Strava's `/oauth/deauthorize` on a
    /// best-effort basis — a stale token still identifies the grant, and
    /// failure to revoke must not block local token deletion.
    var currentAccessToken: String? {
        try? backing.load()?.accessToken
    }

    /// Returns an access token valid for at least ~60 seconds. Refreshes
    /// transparently if the current one is expired. Throws `.notConnected`
    /// if there are no tokens at all (caller should prompt the user to
    /// reconnect rather than silently swallow).
    func validAccessToken() async throws -> String {
        guard let record = try backing.load() else {
            throw StravaTokenStoreError.notConnected
        }
        if !record.isExpired() {
            return record.accessToken
        }
        let refreshed = try await refresher.refresh(refreshToken: record.refreshToken)
        var updated = record
        updated.accessToken = refreshed.access_token
        updated.refreshToken = refreshed.refresh_token
        updated.expiresAt = refreshed.expires_at
        try backing.save(updated)
        logger.log("Refreshed Strava access token (new expiry=\(refreshed.expires_at, privacy: .public)).")
        return updated.accessToken
    }

    // MARK: - Write

    func save(
        accessToken: String,
        refreshToken: String,
        expiresAt: TimeInterval,
        athleteID: Int,
        athleteFirstName: String?
    ) throws {
        let record = StravaTokenRecord(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            athleteID: athleteID,
            athleteFirstName: athleteFirstName
        )
        try backing.save(record)
    }

    /// Force a refresh regardless of the cached `expiresAt`. Used by the
    /// upload service when Strava returns 401 even though our cached token
    /// looked fresh — the only recovery path is to swap it for a new one and
    /// retry the request once.
    func forceRefresh() async throws -> String {
        guard let record = try backing.load() else {
            throw StravaTokenStoreError.notConnected
        }
        let refreshed = try await refresher.refresh(refreshToken: record.refreshToken)
        var updated = record
        updated.accessToken = refreshed.access_token
        updated.refreshToken = refreshed.refresh_token
        updated.expiresAt = refreshed.expires_at
        try backing.save(updated)
        logger.log("Force-refreshed Strava access token after 401.")
        return updated.accessToken
    }

    func disconnect() {
        do {
            try backing.delete()
            logger.log("Strava disconnected — token record deleted.")
        } catch {
            logger.error("Failed to delete Strava token record: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Keychain backing

/// `Security.framework` wrapper. One item, identified by service+account,
/// scoped to the App Group access group so the watch can read it.
struct KeychainStravaTokenStore: StravaTokenBackingStore {
    static let serviceName = "com.arrunner.strava"
    static let account = "tokens"
    let accessGroup: String?

    init(accessGroup: String? = nil) {
        // App Group keychain items need the *team-prefixed* access group,
        // which Xcode synthesizes at runtime as `$(AppIdentifierPrefix)<group>`.
        // Passing the entitlement's raw group value works on device because
        // SecItem resolves it through the entitlement plist — no manual
        // team-ID prefix needed in client code.
        self.accessGroup = accessGroup ?? StravaConfig.appGroup
    }

    private func baseQuery() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: Self.account
        ]
        if let accessGroup {
            q[kSecAttrAccessGroup as String] = accessGroup
        }
        return q
    }

    func load() throws -> StravaTokenRecord? {
        #if canImport(Security)
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw StravaTokenStoreError.keychainFailure(status)
        }
        return try JSONDecoder().decode(StravaTokenRecord.self, from: data)
        #else
        return nil
        #endif
    }

    func save(_ record: StravaTokenRecord) throws {
        #if canImport(Security)
        let data = try JSONEncoder().encode(record)
        var query = baseQuery()
        // Update first; if absent, add. Cheaper than always delete+add and
        // avoids a window where another reader sees "no tokens".
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw StravaTokenStoreError.keychainFailure(addStatus)
            }
            return
        }
        throw StravaTokenStoreError.keychainFailure(updateStatus)
        #else
        throw StravaTokenStoreError.keychainFailure(-1)
        #endif
    }

    func delete() throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw StravaTokenStoreError.keychainFailure(status)
        #endif
    }
}

// MARK: - Refresher

/// Default refresher: POST to the Cloudflare Worker (D-Strava-3) so the
/// `client_secret` never has to travel through the app.
struct WorkerStravaTokenRefresher: StravaTokenRefresher {
    let baseURL: URL
    let urlSession: URLSession

    init(baseURL: URL = StravaConfig.baseURL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func refresh(refreshToken: String) async throws -> StravaRefreshResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw StravaTokenStoreError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw StravaTokenStoreError.invalidServerResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw StravaTokenStoreError.refreshFailed(statusCode: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(StravaRefreshResponse.self, from: data)
        } catch {
            throw StravaTokenStoreError.invalidServerResponse
        }
    }
}
