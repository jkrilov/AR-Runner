// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@main
@MainActor
struct ARRunnerPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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
