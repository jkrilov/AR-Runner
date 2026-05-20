// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerPhone

@MainActor
final class SettingsViewModelTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test.settings.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func makeVM(connected: Bool = false) -> (SettingsViewModel, StravaTokenStore, UserDefaults) {
        let backing = StravaTokenStoreTests.InMemoryBacking()
        if connected {
            try? backing.save(StravaTokenRecord(
                accessToken: "a", refreshToken: "r",
                expiresAt: Date().timeIntervalSince1970 + 3600,
                athleteID: 7, athleteFirstName: "Joe"))
        }
        let store = StravaTokenStore(backing: backing, refresher: StravaTokenStoreTests.MockRefresher())
        let defaults = makeDefaults()
        let vm = SettingsViewModel(
            oauth: StravaOAuthService(tokenStore: store),
            tokenStore: store,
            defaults: defaults,
            isConfigured: true
        )
        return (vm, store, defaults)
    }

    func test_initialState_reflectsConnectedTokenStore() {
        let (vm, _, _) = makeVM(connected: true)
        XCTAssertTrue(vm.isConnected)
        XCTAssertEqual(vm.athleteName, "Joe")
    }

    func test_initialState_autoUploadDefaultsOff() {
        // D-Strava-5: explicit opt-in.
        let (vm, _, _) = makeVM(connected: false)
        XCTAssertFalse(vm.isAutoUploadEnabled)
    }

    func test_toggleAutoUpload_persistsToUserDefaults() {
        let (vm, _, defaults) = makeVM(connected: true)
        vm.toggleAutoUpload()
        XCTAssertTrue(vm.isAutoUploadEnabled)
        XCTAssertTrue(defaults.bool(forKey: SettingsViewModel.autoUploadDefaultsKey))
        vm.toggleAutoUpload()
        XCTAssertFalse(vm.isAutoUploadEnabled)
        XCTAssertFalse(defaults.bool(forKey: SettingsViewModel.autoUploadDefaultsKey))
    }

    func test_disconnect_clearsTokensAndResetsAutoUpload() {
        let (vm, store, defaults) = makeVM(connected: true)
        vm.toggleAutoUpload()
        XCTAssertTrue(vm.isAutoUploadEnabled)
        vm.disconnectStrava()
        XCTAssertFalse(vm.isConnected)
        XCTAssertNil(vm.athleteName)
        XCTAssertFalse(store.isConnected)
        XCTAssertFalse(vm.isAutoUploadEnabled)
        XCTAssertFalse(defaults.bool(forKey: SettingsViewModel.autoUploadDefaultsKey))
    }

    func test_userMessage_mapsKnownErrors() {
        XCTAssertEqual(SettingsViewModel.userMessage(for: .userCancelled), "Sign-in was cancelled.")
        XCTAssertEqual(SettingsViewModel.userMessage(for: .notConfigured),
                       "Strava integration is not configured in this build.")
        XCTAssertTrue(SettingsViewModel.userMessage(for: .tokenExchangeFailed(statusCode: 503)).contains("503"))
    }
}
