// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerPhone

/// Pure-logic tests for the Strava OAuth URL builder + callback parser.
/// Validates D-Strava-3 plumbing without touching ASWebAuthenticationSession.
final class StravaOAuthURLBuilderTests: XCTestCase {
    private let builder = StravaOAuthURLBuilder(
        clientID: "12345",
        redirectURI: "arrunner://ar-runner.app/callback",
        scope: "activity:write"
    )

    func test_authorizationURL_includesAllRequiredQueryItems() throws {
        let url = try XCTUnwrap(builder.authorizationURL())
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.strava.com")
        XCTAssertEqual(components.path, "/oauth/mobile/authorize")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["client_id"], "12345")
        XCTAssertEqual(items["redirect_uri"], "arrunner://ar-runner.app/callback")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["scope"], "activity:write")
        XCTAssertEqual(items["approval_prompt"], "auto")
    }

    func test_stravaAppAuthorizationURL_usesNativeSchemeAndMobilePath() throws {
        let url = try XCTUnwrap(builder.stravaAppAuthorizationURL())
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "strava")
        XCTAssertEqual(components.host, "oauth")
        XCTAssertEqual(components.path, "/mobile/authorize")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["client_id"], "12345")
        XCTAssertEqual(items["redirect_uri"], "arrunner://ar-runner.app/callback")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["scope"], "activity:write")
        XCTAssertEqual(items["approval_prompt"], "auto")
    }

    func test_parseCallback_success_extractsAuthorizationCode() {
        let url = URL(string: "arrunner://ar-runner.app/callback?state=&code=abc123&scope=activity:write")!
        switch builder.parseCallback(url) {
        case .success(let code): XCTAssertEqual(code, "abc123")
        case .failure(let err): XCTFail("Expected success, got \(err)")
        }
    }

    func test_parseCallback_missingCode_returnsMissingAuthorizationCode() {
        let url = URL(string: "arrunner://ar-runner.app/callback?state=foo")!
        if case .failure(let err) = builder.parseCallback(url) {
            XCTAssertEqual(err, .missingAuthorizationCode)
        } else {
            XCTFail("Expected missingAuthorizationCode")
        }
    }

    func test_parseCallback_userDeniedInBrowser_returnsStravaDeniedAccess() {
        let url = URL(string: "arrunner://ar-runner.app/callback?error=access_denied&state=foo")!
        if case .failure(.stravaDeniedAccess(let reason)) = builder.parseCallback(url) {
            XCTAssertEqual(reason, "access_denied")
        } else {
            XCTFail("Expected stravaDeniedAccess")
        }
    }

    func test_parseCallback_emptyCode_returnsMissingAuthorizationCode() {
        let url = URL(string: "arrunner://ar-runner.app/callback?code=&state=foo")!
        if case .failure(let err) = builder.parseCallback(url) {
            XCTAssertEqual(err, .missingAuthorizationCode)
        } else {
            XCTFail("Expected missingAuthorizationCode")
        }
    }
}
