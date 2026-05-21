// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@main
@MainActor
struct ARRunnerPhoneApp: App {
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { url in
                    // Forward `arrunner://...` redirects from the native
                    // Strava app's `/oauth/mobile/authorize` flow into the
                    // OAuth service. ASWebAuthenticationSession handles its
                    // own callback internally, so this only matters when the
                    // user has the Strava iOS app installed.
                    StravaOAuthService.handleIncomingURL(url)
                }
        }
    }
}
