// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
import os

/// Drives the Settings tab. Owns:
///   * the Strava connection lifecycle (delegated to `StravaOAuthService`)
///   * the auto-upload preference (UserDefaults, defaults OFF per D-Strava-5)
@MainActor
@Observable
final class SettingsViewModel {
    static let autoUploadDefaultsKey = "strava_auto_upload_enabled"

    private(set) var isConnected: Bool
    private(set) var athleteName: String?
    private(set) var isAuthenticating: Bool = false
    private(set) var lastErrorMessage: String?
    var isAutoUploadEnabled: Bool {
        didSet {
            defaults.set(isAutoUploadEnabled, forKey: Self.autoUploadDefaultsKey)
        }
    }
    let isConfigured: Bool

    private let oauth: StravaOAuthService
    private let tokenStore: StravaTokenStore
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.arrunner.phone", category: "Settings")

    init(
        oauth: StravaOAuthService? = nil,
        tokenStore: StravaTokenStore = .shared,
        defaults: UserDefaults = .standard,
        isConfigured: Bool = StravaConfig.isConfigured
    ) {
        self.tokenStore = tokenStore
        self.oauth = oauth ?? StravaOAuthService(tokenStore: tokenStore)
        self.defaults = defaults
        self.isConfigured = isConfigured
        self.isConnected = tokenStore.isConnected
        self.athleteName = tokenStore.athleteFirstName
        // D-Strava-5: auto-upload defaults OFF.
        self.isAutoUploadEnabled = defaults.bool(forKey: Self.autoUploadDefaultsKey)
    }

    func connectStrava() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        lastErrorMessage = nil
        Task { [oauth, tokenStore] in
            defer { self.isAuthenticating = false }
            do {
                try await oauth.connect()
                self.isConnected = tokenStore.isConnected
                self.athleteName = tokenStore.athleteFirstName
            } catch StravaOAuthError.userCancelled {
                // User backed out — not an error worth surfacing.
                self.logger.log("Strava OAuth cancelled by user.")
            } catch let error as StravaOAuthError {
                self.lastErrorMessage = Self.userMessage(for: error)
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func disconnectStrava() {
        // Strava API agreement requires we revoke the grant server-side,
        // not just drop local tokens. Fire-and-forget: the local
        // disconnect MUST succeed even if the network call fails or the
        // token is already invalid — otherwise the user is stranded in a
        // "connected" UI with no way out.
        if let token = tokenStore.currentAccessToken {
            // Plain Task inherits the current MainActor isolation, avoiding
            // a Sendable capture of the @MainActor oauth service. Not awaited
            // — the local clear below must run regardless.
            Task { await self.oauth.deauthorize(accessToken: token) }
        }
        tokenStore.disconnect()
        isConnected = false
        athleteName = nil
        // Per D-Strava-5 reset auto-upload too: a freshly disconnected
        // account shouldn't silently re-arm next time the user reconnects.
        isAutoUploadEnabled = false
    }

    func toggleAutoUpload() {
        isAutoUploadEnabled.toggle()
    }

    static func userMessage(for error: StravaOAuthError) -> String {
        switch error {
        case .notConfigured:
            return "Strava integration is not configured in this build."
        case .userCancelled:
            return "Sign-in was cancelled."
        case .malformedCallback, .missingAuthorizationCode, .invalidServerResponse:
            return "Strava returned an unexpected response. Please try again."
        case .stravaDeniedAccess:
            return "Strava denied access. Please try connecting again."
        case .tokenExchangeFailed(let code):
            return "Couldn't complete Strava sign-in (HTTP \(code))."
        case .network(let detail):
            return "Network error: \(detail)"
        }
    }
}
