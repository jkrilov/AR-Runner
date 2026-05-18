// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import SwiftUI

/// Pre-run pairing sheet. Surfaced from `WorkoutView` when the workout is
/// idle. Lets Joe initiate a BLE scan + connect to ActiveLook-compatible
/// glasses (Engo 2) before tapping Start Run, with a clear status line and
/// a retry path on failure.
///
/// v0.2.0 scope (post-device-test feedback): single-device auto-grab.
/// The underlying `ActiveLookGlassesAdapter` connects to the first
/// peripheral advertising the ActiveLook command service UUID. A device
/// picker for users with multiple pairs nearby is a follow-up.
@MainActor
struct GlassesConnectView: View {
    let viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                statusBlock
                if let error = viewModel.glassesPairingError {
                    errorBlock(error)
                }
                actions
                helpText
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Glasses")
        .task {
            viewModel.prepareGlassesIfNeeded()
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "eyeglasses")
            Text("AR Glasses")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Glasses status: \(statusLine)")
    }

    @ViewBuilder
    private func errorBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch viewModel.glassesLinkState {
        case .disconnected, .failed:
            Button(viewModel.glassesPairingError == nil ? "Scan & Connect" : "Retry") {
                Task { await viewModel.connectGlasses() }
            }
            .buttonStyle(.borderedProminent)
        case .scanning, .connecting, .reconnecting:
            HStack {
                ProgressView().controlSize(.small)
                Button("Cancel") {
                    Task { await viewModel.disconnectGlasses() }
                }
            }
        case .connected:
            Button("Disconnect", role: .destructive) {
                Task { await viewModel.disconnectGlasses() }
            }
        }

        Button("Done") { dismiss() }
            .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var helpText: some View {
        Text("You can start a run without glasses — the HUD just won't show. The run still records to Health.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var statusLine: String {
        switch viewModel.glassesLinkState {
        case .disconnected:
            return "Disconnected"
        case .scanning:
            return "Scanning…"
        case .connecting:
            return "Connecting…"
        case .reconnecting:
            return "Reconnecting…"
        case .failed:
            return "Connection failed"
        case .connected:
            return viewModel.glassesDeviceName ?? "Connected"
        }
    }

    private var statusColor: Color {
        switch viewModel.glassesLinkState {
        case .connected: return .green
        case .scanning, .connecting, .reconnecting: return .yellow
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        GlassesConnectView(viewModel: WorkoutViewModel(
            substrateFactory: { InMemoryWorkoutHealthSubstrate() },
            transportFactory: { StubGlassesTransport() },
            mirror: nil
        ))
    }
}
#endif
