// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import SwiftUI

/// Settings tab (v0.5 PR 2). Owns the Strava connection UI and the
/// auto-upload preference. Per D-Strava-6 the tab is required for the
/// Strava feature to be considered complete.
@MainActor
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue
    @AppStorage(ActionButtonMode.storageKey) private var actionButtonRaw: String = ActionButtonMode.defaultMode.rawValue
    // v0.6.0 — default workout type + measurement system, persisted to the
    // shared App Group store and mirrored to the watch.
    @AppStorage(WorkoutTypePreference.storageKey, store: WorkoutTypePreference.sharedDefaults)
    private var defaultWorkoutRaw: String = WorkoutTypePreference.defaultValue.rawValue
    @AppStorage(UnitPreference.storageKey, store: UnitPreference.sharedDefaults)
    private var unitRaw: String = UnitPreference.defaultValue.rawValue

    init(viewModel: SettingsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SettingsViewModel())
    }

    var body: some View {
        Form {
            stravaSection
            workoutSection
            unitsSection
            appearanceSection
            actionButtonSection
            aboutSection
        }
        .navigationTitle("Settings")
    }

    // MARK: - Workout

    private var defaultWorkoutType: WorkoutType {
        WorkoutType(rawValue: defaultWorkoutRaw) ?? WorkoutTypePreference.defaultValue
    }

    private var workoutSection: some View {
        Section {
            Picker("Default Type", selection: Binding(
                get: { defaultWorkoutType },
                set: { newValue in
                    defaultWorkoutRaw = newValue.rawValue
                    // Mirror to the paired watch so the wearer's default
                    // stays in sync. Best-effort (no-op if no watch paired).
                    ARRunnerPhoneEnvironment.shared.mirror
                        .sendDefaultWorkoutType(newValue)
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
            Text("The workout type a new run starts as on the watch.")
                .font(.caption2)
        }
    }

    // MARK: - Units

    private var unitSystem: UnitSystem {
        UnitSystem(rawValue: unitRaw) ?? UnitPreference.defaultValue
    }

    private var unitsSection: some View {
        Section {
            Picker("Units", selection: Binding(
                get: { unitSystem },
                set: { newValue in
                    unitRaw = newValue.rawValue
                    ARRunnerPhoneEnvironment.shared.mirror
                        .sendUnitPreference(newValue)
                }
            )) {
                ForEach(UnitSystem.allCases, id: \.rawValue) { system in
                    Text(UnitPreference.title(for: system)).tag(system)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Units")
        } footer: {
            Text("Distance, pace, and speed display in your chosen measurement system.")
                .font(.caption2)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
                set: { appearanceRaw = $0.rawValue }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Action Button

    private var actionButtonMode: ActionButtonMode {
        ActionButtonMode(rawValue: actionButtonRaw) ?? ActionButtonMode.defaultMode
    }

    private var actionButtonSection: some View {
        Section {
            Picker("Behavior", selection: Binding(
                get: { actionButtonMode },
                set: { newValue in
                    actionButtonRaw = newValue.rawValue
                    // Mirror to the paired watch so the wearer doesn't need
                    // to open the watch Settings to change it. Best-effort
                    // (no-op if no watch is paired / WCSession inactive).
                    ARRunnerPhoneEnvironment.shared.mirror
                        .sendActionButtonMode(newValue.rawValue)
                }
            )) {
                ForEach(ActionButtonMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Text(actionButtonMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Action Button")
        } footer: {
            Text("Configures the Action Button on Apple Watch Ultra. On other Apple Watch models this setting has no effect.")
                .font(.caption2)
        }
    }

    // MARK: - Strava

    @ViewBuilder
    private var stravaSection: some View {
        Section("Strava") {
            if viewModel.isConnected {
                connectedRow
                disconnectButton
            } else {
                connectButton
            }
            autoUploadToggle
            if let message = viewModel.lastErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if !viewModel.isConfigured {
                Text("Strava client ID isn't set in this build. Strava actions will fail until STRAVA_CLIENT_ID is wired into the build configuration.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectedRow: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text(viewModel.athleteName.map { "Connected as \($0)" } ?? "Connected")
                    .font(.body)
                Text("Strava")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectButton: some View {
        Button {
            viewModel.connectStrava()
        } label: {
            ZStack {
                Image("ConnectWithStrava")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(viewModel.isAuthenticating ? 0.6 : 1)
                    .accessibilityLabel("Connect with Strava")

                if viewModel.isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isAuthenticating || !viewModel.isConfigured)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var disconnectButton: some View {
        Button(role: .destructive) {
            viewModel.disconnectStrava()
        } label: {
            Text("Disconnect")
        }
    }

    private var autoUploadToggle: some View {
        Toggle(isOn: Binding(
            get: { viewModel.isAutoUploadEnabled },
            set: { _ in viewModel.toggleAutoUpload() }
        )) {
            VStack(alignment: .leading) {
                Text("Auto-upload completed runs")
                Text("Runs upload to Strava when you save them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!viewModel.isConnected)
    }

    // MARK: - About

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

extension Color {
    /// Strava brand orange (#FC4C02). Used only on the "Connect with Strava"
    /// CTA per Strava's brand guidelines (exact button wording + 48pt height
    /// per https://developers.strava.com/guidelines/).
    static let stravaOrange = Color(red: 252.0 / 255.0, green: 76.0 / 255.0, blue: 2.0 / 255.0)
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
