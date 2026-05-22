// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Watch-side settings surface. v0.5.3 only owns the Action Button mode
/// picker; future watch-only preferences (haptic intensity, HUD layout)
/// land here so the iPhone Settings tab stays focused on phone-scoped
/// concerns (Strava, appearance).
///
/// Presented from `WorkoutView`'s navigation toolbar via the gear icon.
@MainActor
struct WatchSettingsView: View {
    @AppStorage(ActionButtonMode.storageKey) private var actionButtonRaw: String = ActionButtonMode.defaultMode.rawValue

    private var actionButtonMode: ActionButtonMode {
        ActionButtonMode(rawValue: actionButtonRaw) ?? ActionButtonMode.defaultMode
    }

    var body: some View {
        Form {
            actionButtonSection
            aboutSection
        }
        .navigationTitle("Settings")
    }

    private var actionButtonSection: some View {
        Section {
            Picker("Action Button", selection: Binding(
                get: { actionButtonMode },
                set: { newValue in
                    actionButtonRaw = newValue.rawValue
                    // Mirror to the iPhone so its Settings picker reflects
                    // what the wearer chose. Best-effort — silent no-op if
                    // WCSession isn't active or the phone is uninstalled.
                    ARRunnerWatchEnvironment.shared.mirror
                        .sendActionButtonMode(newValue.rawValue)
                }
            )) {
                ForEach(ActionButtonMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Text(actionButtonMode.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } header: {
            Text("Action Button")
        } footer: {
            Text("Apple Watch Ultra only. Assign \"AR-Runner Action Button\" to the side button in the system Settings app.")
                .font(.caption2)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("AR-Runner")
                Spacer()
                Text(Self.appVersionString)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    static var appVersionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(short) (\(build))"
    }
}

#Preview {
    NavigationStack {
        WatchSettingsView()
    }
}
