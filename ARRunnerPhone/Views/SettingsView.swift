// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Settings tab (v0.5 PR 2). Owns the Strava connection UI and the
/// auto-upload preference. Per D-Strava-6 the tab is required for the
/// Strava feature to be considered complete.
@MainActor
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SettingsViewModel())
    }

    var body: some View {
        Form {
            stravaSection
            aboutSection
        }
        .navigationTitle("Settings")
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
                Text("Off by default. Runs upload to Strava when you save them.")
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
