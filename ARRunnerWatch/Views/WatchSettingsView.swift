// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import SwiftUI

/// Watch-side settings surface. v0.5.3 only owns the Action Button mode
/// picker; future watch-only preferences (haptic intensity, HUD layout)
/// land here so the iPhone Settings tab stays focused on phone-scoped
/// concerns (Strava, appearance).
///
/// Presented from `WorkoutView`'s navigation toolbar via the gear icon.
@MainActor
struct WatchSettingsView: View {
    // Persist to the shared App Group store (NOT `.standard`) so the
    // `ActionButtonIntent` — which may execute in the system Shortcuts
    // process when invoked from the hardware Action Button — observes
    // the same value the wearer just picked. See
    // `ActionButtonMode.sharedDefaults` for the full rationale.
    @AppStorage(ActionButtonMode.storageKey, store: ActionButtonMode.sharedDefaults)
    private var actionButtonRaw: String = ActionButtonMode.defaultMode.rawValue

    // v0.6.0 — default workout type, persisted to the shared App Group store
    // so the Action Button intent and Smart Stack widget read the same value.
    @AppStorage(WorkoutTypePreference.storageKey, store: WorkoutTypePreference.sharedDefaults)
    private var defaultWorkoutRaw: String = WorkoutTypePreference.defaultValue.rawValue

    private var actionButtonMode: ActionButtonMode {
        ActionButtonMode(rawValue: actionButtonRaw) ?? ActionButtonMode.defaultMode
    }

    private var defaultWorkoutType: WorkoutType {
        WorkoutType(rawValue: defaultWorkoutRaw) ?? WorkoutTypePreference.defaultValue
    }

    var body: some View {
        Form {
            defaultWorkoutSection
            actionButtonSection
            aboutSection
        }
        .navigationTitle("Settings")
    }

    private var defaultWorkoutSection: some View {
        Section {
            Picker("Default Workout", selection: Binding(
                get: { defaultWorkoutType },
                set: { newValue in
                    defaultWorkoutRaw = newValue.rawValue
                    // Mirror to the iPhone so its Settings picker reflects
                    // the wearer's choice. Best-effort, phone-optional.
                    Task {
                        await ARRunnerWatchEnvironment.shared.mirror
                            .sendDefaultWorkoutType(newValue)
                    }
                }
            )) {
                ForEach(WorkoutTypePreference.selectable, id: \.rawValue) { type in
                    Label(type.displayName, systemImage: WorkoutTypePreference.symbolName(for: type))
                        .tag(type)
                }
            }
        } header: {
            Text("Workout")
        } footer: {
            Text("The workout type a new run starts as — including from the Action Button or Smart Stack.")
                .font(.caption2)
        }
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
