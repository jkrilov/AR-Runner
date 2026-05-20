// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Errors surfaced by `StravaOAuthService`. Distinguished from the underlying
/// transport / system errors so the Settings VM can show user-meaningful copy
/// without leaking framework types.
enum StravaOAuthError: Error, Equatable, Sendable {
    case notConfigured
    case userCancelled
    case malformedCallback
    case missingAuthorizationCode
    case stravaDeniedAccess(String)
    case tokenExchangeFailed(statusCode: Int)
    case invalidServerResponse
    case network(String)
}

/// Pure-logic URL plumbing for the Strava OAuth dance. Split out from
/// `StravaOAuthService` so the URL construction + callback parsing can be
/// unit-tested without instantiating `ASWebAuthenticationSession` (which is
/// iOS-only and requires a `UIWindow`).
struct StravaOAuthURLBuilder: Sendable {
    let clientID: String
    let redirectURI: String
    let scope: String

    /// Common query items shared by the web (`https://`) and native
    /// (`strava://`) authorize URLs. Strava treats them identically — only
    /// the scheme/host differ.
    private func sharedQueryItems() -> [URLQueryItem] {
        [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "approval_prompt", value: "auto")
        ]
    }

    /// `https://www.strava.com/oauth/mobile/authorize?...` — the page the
    /// user sees in `ASWebAuthenticationSession` when the Strava app is NOT
    /// installed. The `/mobile/authorize` variant (vs `/oauth/authorize`) is
    /// required by Strava's iOS docs — only the mobile endpoint redirects
    /// back to a custom URL scheme. `approval_prompt=auto` lets returning
    /// users skip the consent screen if they've already authorized us.
    func authorizationURL() -> URL? {
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")
        components?.queryItems = sharedQueryItems()
        return components?.url
    }

    /// `strava://oauth/mobile/authorize?...` — opens the installed Strava
    /// iOS app directly so the user authorizes inside their already-signed-in
    /// session (no in-app browser). Strava redirects back to our custom URL
    /// scheme via `redirectURI`, which is handled by `.onOpenURL` in
    /// `ARRunnerPhoneApp`.
    func stravaAppAuthorizationURL() -> URL? {
        var components = URLComponents()
        components.scheme = "strava"
        components.host = "oauth"
        components.path = "/mobile/authorize"
        components.queryItems = sharedQueryItems()
        return components.url
    }

    /// Extract the authorization `code` from the redirect callback. Strava
    /// returns `?state=...&code=...&scope=...` on success and
    /// `?error=access_denied&...` on user-cancel-in-browser. We surface the
    /// `error` case as `.stravaDeniedAccess` — `ASWebAuthenticationSession`'s
    /// own cancellation is a separate code path (`.userCancelled`).
    func parseCallback(_ url: URL) -> Result<String, StravaOAuthError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.malformedCallback)
        }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            return .failure(.stravaDeniedAccess(error))
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return .failure(.missingAuthorizationCode)
        }
        return .success(code)
    }
}

/// Decoded payload from `POST https://strava-connect.ar-runner.app/token`.
/// Mirrors the worker's response shape (which in turn mirrors Strava's, plus
/// the worker passes `athlete` through verbatim).
struct StravaTokenExchangeResponse: Decodable, Sendable {
    struct Athlete: Decodable, Sendable {
        let id: Int
        let firstname: String?
    }
    let access_token: String
    let refresh_token: String
    let expires_at: TimeInterval
    let athlete: Athlete?
}

/// iPhone-side Strava OAuth flow. Presents `ASWebAuthenticationSession`,
/// exchanges the auth code through the Cloudflare Worker proxy, and persists
/// the resulting tokens in the shared Keychain.
///
/// Decisions:
///   * D-Strava-1: phone owns OAuth.
///   * D-Strava-3: Worker holds the `client_secret`; the app NEVER does.
@MainActor
final class StravaOAuthService: NSObject {
    private let logger = Logger(subsystem: "com.arrunner.phone", category: "StravaOAuth")
    private let tokenStore: StravaTokenStore
    private let urlBuilder: StravaOAuthURLBuilder
    private let workerBaseURL: URL
    private let urlSession: URLSession
    private var authSession: Any?

    init(
        tokenStore: StravaTokenStore = .shared,
        workerBaseURL: URL = StravaConfig.baseURL,
        urlSession: URLSession = .shared,
        urlBuilder: StravaOAuthURLBuilder = StravaOAuthURLBuilder(
            clientID: StravaConfig.clientID,
            redirectURI: StravaConfig.redirectURI,
            scope: StravaConfig.scope
        )
    ) {
        self.tokenStore = tokenStore
        self.workerBaseURL = workerBaseURL
        self.urlSession = urlSession
        self.urlBuilder = urlBuilder
    }

    /// Drive the full OAuth round-trip. On success the tokens are already
    /// in the shared Keychain — caller just refreshes its UI from
    /// `tokenStore.isConnected`.
    func connect() async throws {
        guard StravaConfig.isConfigured else {
            logger.error("Strava clientID is the placeholder — refusing to start OAuth.")
            throw StravaOAuthError.notConfigured
        }
        let code = try await presentAuthorizationFlow()
        let response = try await exchangeCodeForTokens(code: code)
        try tokenStore.save(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: response.expires_at,
            athleteID: response.athlete?.id ?? 0,
            athleteFirstName: response.athlete?.firstname
        )
        logger.log("Strava connected (athlete=\(response.athlete?.id ?? 0, privacy: .public)).")
    }

    // MARK: - Authorization (browser or native Strava app)

    /// Pending continuation for the native-app (`strava://`) path. When the
    /// Strava iOS app finishes auth it redirects to `arrunner://...` which
    /// SwiftUI surfaces via `.onOpenURL` in `ARRunnerPhoneApp`; that handler
    /// calls `handleIncomingURL(_:)` which resumes this continuation.
    ///
    /// Static because `.onOpenURL` doesn't have a handle to the live service
    /// instance — and there can only ever be one OAuth attempt in flight.
    private static var pendingAppContinuation: CheckedContinuation<URL, Error>?

    /// Forward an incoming `arrunner://` URL to the in-flight OAuth attempt.
    /// Returns `true` if the URL was consumed (an OAuth attempt was waiting),
    /// `false` otherwise so the caller can hand the URL to another router.
    @discardableResult
    static func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "arrunner" else { return false }
        guard let continuation = pendingAppContinuation else { return false }
        pendingAppContinuation = nil
        continuation.resume(returning: url)
        return true
    }

    private func presentAuthorizationFlow() async throws -> String {
        #if canImport(UIKit)
        // Path A: Strava iOS app installed → hand off via the `strava://`
        // scheme. Requires `LSApplicationQueriesSchemes` to include `strava`
        // in Info.plist (iOS 9+); without it `canOpenURL` always returns
        // false. See project.yml.
        if let probe = URL(string: "strava://"),
           UIApplication.shared.canOpenURL(probe),
           let appURL = urlBuilder.stravaAppAuthorizationURL() {
            return try await presentNativeStravaAppFlow(appURL: appURL)
        }
        #endif
        // Path B: Strava app not installed → ASWebAuthenticationSession.
        return try await presentWebAuthenticationFlow()
    }

    #if canImport(UIKit)
    private func presentNativeStravaAppFlow(appURL: URL) async throws -> String {
        // If a previous attempt was abandoned without callback, clear it so
        // we don't strand the new attempt's continuation.
        if let stale = Self.pendingAppContinuation {
            Self.pendingAppContinuation = nil
            stale.resume(throwing: StravaOAuthError.userCancelled)
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            Self.pendingAppContinuation = continuation
            UIApplication.shared.open(appURL, options: [:]) { opened in
                if !opened {
                    if let pending = Self.pendingAppContinuation {
                        Self.pendingAppContinuation = nil
                        pending.resume(throwing: StravaOAuthError.network("Failed to open Strava app"))
                    }
                }
            }
        }
        switch urlBuilder.parseCallback(callbackURL) {
        case .success(let code): return code
        case .failure(let err): throw err
        }
    }
    #endif

    private func presentWebAuthenticationFlow() async throws -> String {
        #if canImport(AuthenticationServices)
        guard let url = urlBuilder.authorizationURL() else {
            throw StravaOAuthError.notConfigured
        }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "arrunner"
            ) { [urlBuilder] callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: StravaOAuthError.userCancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: StravaOAuthError.network(error.localizedDescription))
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: StravaOAuthError.malformedCallback)
                    return
                }
                switch urlBuilder.parseCallback(callbackURL) {
                case .success(let code):
                    continuation.resume(returning: code)
                case .failure(let err):
                    continuation.resume(throwing: err)
                }
            }
            session.presentationContextProvider = self
            // Ephemeral session keeps the user's Safari cookies out of our
            // flow — important so a logged-in Strava user still sees the
            // consent screen the first time they connect.
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                continuation.resume(throwing: StravaOAuthError.network("Failed to start ASWebAuthenticationSession"))
            }
        }
        #else
        throw StravaOAuthError.notConfigured
        #endif
    }

    // MARK: - Code → tokens (worker)

    private func exchangeCodeForTokens(code: String) async throws -> StravaTokenExchangeResponse {
        let url = workerBaseURL.appendingPathComponent("token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw StravaOAuthError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw StravaOAuthError.invalidServerResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            logger.error("Token exchange failed: \(http.statusCode, privacy: .public)")
            throw StravaOAuthError.tokenExchangeFailed(statusCode: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(StravaTokenExchangeResponse.self, from: data)
        } catch {
            throw StravaOAuthError.invalidServerResponse
        }
    }
}

#if canImport(AuthenticationServices) && canImport(UIKit)
extension StravaOAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Hop to the main actor on the synchronous return path. The first
        // foreground window scene's keyWindow is the standard anchor.
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
            let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
                ?? scenes.flatMap(\.windows).first
            return window ?? ASPresentationAnchor()
        }
    }
}
#endif
