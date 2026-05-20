// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Strava integration build-time configuration (v0.5 PR 2).
///
/// Decisions in play:
///   * D-Strava-1: OAuth on phone, upload on phone (phone is the gateway).
///   * D-Strava-3: Cloudflare Worker proxy at `strava-connect.ar-runner.app`
///     handles the `client_secret` — never shipped in the binary.
///
/// `clientID` is the only Strava-controlled value the app itself needs to know
/// (it's the *public* half of the OAuth credential pair). It's safe to ship,
/// but we read it from the `STRAVA_CLIENT_ID` env var at build time (falling
/// back to `Info.plist` so release archives don't depend on env state). The
/// placeholder string makes a misconfigured build fail loudly the first time
/// `authorizationURL()` is invoked rather than silently producing a malformed
/// URL the user can't recover from.
enum StravaConfig {
    static let clientID: String = {
        if let env = ProcessInfo.processInfo.environment["STRAVA_CLIENT_ID"],
           !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "StravaClientID") as? String,
           !plist.isEmpty,
           plist != "$(STRAVA_CLIENT_ID)" {
            return plist
        }
        return placeholderClientID
    }()

    static let placeholderClientID = "YOUR_STRAVA_CLIENT_ID"

    /// Cloudflare Worker proxy. Owns the `client_secret`; exchanges auth
    /// codes for tokens and refreshes expired access tokens.
    static let baseURL = URL(string: "https://strava-connect.ar-runner.app")!

    /// Redirect URI handed to Strava's mobile authorize endpoint.
    ///
    /// Strava's iOS guidance (https://developers.strava.com/docs/authentication/)
    /// requires the form `YourScheme://your.real.domain/path` — the host
    /// segment MUST be a real domain that matches the "Authorization Callback
    /// Domain" set in the Strava API console (here: `ar-runner.app`). The
    /// previous form `arrunner://strava/callback` was rejected with
    /// "Bad Request: redirect_uri invalid" because `strava` is not a domain.
    ///
    /// The custom scheme `arrunner` is registered in
    /// `Config/ARRunnerPhone-Info.plist` (via `project.yml` → `CFBundleURLTypes`)
    /// so iOS routes the redirect back into this app.
    static let redirectURI = "arrunner://ar-runner.app/callback"

    /// `activity:write` is the minimum scope required to upload activities.
    /// Per Strava docs: implies `activity:read`, sufficient for our flow.
    static let scope = "activity:write"

    /// Shared Keychain access group. Matches the App Group declared in
    /// `Config/ARRunnerPhone.entitlements` / `Config/ARRunnerWatch.entitlements`.
    /// The leading `$(AppIdentifierPrefix)` is substituted by the OS at
    /// runtime; we pass the literal team-prefixed form to `SecItem*` APIs
    /// via `StravaTokenStore.keychainAccessGroup`.
    static let appGroup = "group.com.arrunner.shared"

    /// `true` when the build has a real `clientID` wired up. Used by the UI
    /// to surface a "Connect Strava" button that explains the misconfig
    /// instead of dead-ending in Safari.
    static var isConfigured: Bool { clientID != placeholderClientID }
}
