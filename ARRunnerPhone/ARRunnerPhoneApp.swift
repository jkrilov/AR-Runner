// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit

/// Bridges UIKit app-lifecycle callbacks that SwiftUI's `App` doesn't expose.
///
/// The only thing it does today is re-attach the Strava background upload
/// session when iOS relaunches the app to deliver finished background transfer
/// events (`sessionSendsLaunchEvents = true`). Without capturing this
/// completion handler the system would treat the app as hung and may throttle
/// future background uploads.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundStravaUploadTransport.sessionIdentifier else {
            completionHandler()
            return
        }
        BackgroundStravaUploadTransport.shared.setSystemCompletionHandler(completionHandler)
        BackgroundStravaUploadTransport.shared.reattach()
        // Drain any entries the just-finished background uploads moved forward
        // (e.g. `.processing` confirmations) now that we're awake.
        Task { await StravaUploadQueue.shared.process() }
    }
}

@main
@MainActor
struct ARRunnerPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate
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
