// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import SwiftUI

@MainActor
struct WorkoutView: View {
    @State private var viewModel = WorkoutViewModel(
        substrateFactory: { HealthKitWorkoutSubstrate() },
        transportFactory: { GlassesTransportFactory.makeDefault() },
        mirror: ARRunnerWatchEnvironment.shared.mirror
    )
    @State private var showGlassesSheet = false

    /// Cross-process handoff from `StartWorkoutIntent.perform()` (widget
    /// extension) to the foregrounded host. Consumed below on
    /// `scenePhase == .active`.
    private let pendingStartStore: any PendingWorkoutStartStore = AppGroupPendingWorkoutStartStore()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                hudOfflineBanner
                metricsSection
                Divider()
                controlsSection
                if isPreRun {
                    preRunGlassesRow
                }
                statusFooter
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Run")
        .task {
            // First-launch path — `openAppWhenRun` lands here before the
            // scene phase change fires on a cold start.
            await maybeAutoStartFromIntent()
            // If the user has previously paired their glasses, attempt a
            // reconnect on launch so the pre-run status chip is accurate
            // before they tap Start.
            await viewModel.autoReconnectGlassesOnLaunch()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await maybeAutoStartFromIntent() }
            }
        }
        .sheet(isPresented: $showGlassesSheet) {
            NavigationStack {
                GlassesConnectView(viewModel: viewModel)
            }
        }
        .confirmationDialog(
            "Finish Run?",
            isPresented: finishMenuBinding,
            titleVisibility: .visible
        ) {
            Button("Save Run") { Task { await viewModel.confirmSave() } }
            Button("Discard", role: .destructive) { Task { await viewModel.confirmCancel() } }
            Button("Resume", role: .cancel) { Task { await viewModel.resumeFromFinish() } }
        } message: {
            Text("Saving writes the workout to Health. Discard removes it from this view (it remains in Health and can be deleted there).")
        }
    }

    /// Consume any pending-start flag dropped by the widget AppIntent
    /// and, if fresh, kick off the workout flow automatically. Only
    /// runs from `.idle` / terminal states so an already-running
    /// workout isn't disturbed by a stray foregrounding.
    private func maybeAutoStartFromIntent() async {
        guard pendingStartStore.consumePending(
            now: Date(),
            freshness: pendingWorkoutStartDefaultFreshnessSeconds
        ) else { return }
        switch viewModel.launchState {
        case .idle, .ended, .cancelled, .failed:
            await viewModel.start()
        default:
            break
        }
    }

    /// D4 (decision #2) HUD-offline indicator. Compact, non-modal, sits
    /// above the live metrics and disappears the instant the transport
    /// reports `.reconnected`. Does NOT pause or otherwise gate the workout.
    @ViewBuilder
    private var hudOfflineBanner: some View {
        if viewModel.hudOffline {
            Label("HUD offline", systemImage: "eyeglasses.slash")
                .font(.caption2)
                .foregroundStyle(.orange)
                .accessibilityLabel("Glasses HUD offline. Workout still recording.")
                .transition(.opacity)
        }
    }

    /// True while the workout is not running — i.e. the user is on the
    /// "pre-run" surface (idle or post-run terminal states). The Connect
    /// Glasses row only appears here so it doesn't compete for screen
    /// real estate with live metrics during a run.
    private var isPreRun: Bool {
        switch viewModel.launchState {
        case .idle, .ended, .cancelled, .failed:
            return true
        default:
            return false
        }
    }

    /// Tappable row that shows the live glasses link state and opens the
    /// pairing sheet. Pre-run only — see `isPreRun`. Gives the user a
    /// clear, persistent affordance to pair before tapping Start Run.
    @ViewBuilder
    private var preRunGlassesRow: some View {
        Button {
            showGlassesSheet = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(glassesChipColor)
                    .frame(width: 8, height: 8)
                Image(systemName: "eyeglasses")
                Text(glassesChipText)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Glasses \(glassesChipText). Tap to manage pairing.")
    }

    private var glassesChipText: String {
        switch viewModel.glassesLinkState {
        case .disconnected: return "Glasses: Disconnected"
        case .scanning:     return "Glasses: Scanning…"
        case .connecting:   return "Glasses: Connecting…"
        case .reconnecting: return "Glasses: Reconnecting…"
        case .failed:       return "Glasses: Connection failed"
        case .connected:    return "Glasses: \(viewModel.glassesDeviceName ?? "Connected")"
        }
    }

    private var glassesChipColor: Color {
        switch viewModel.glassesLinkState {
        case .connected: return .green
        case .scanning, .connecting, .reconnecting: return .yellow
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    @ViewBuilder
    private var metricsSection: some View {
        HStack {
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(viewModel.heartRate.map { "\(Int($0)) bpm" } ?? "—")
                .font(.title3.monospacedDigit())
        }
        HStack {
            Image(systemName: "ruler").foregroundStyle(.blue)
            Text(viewModel.distanceMeters.map { RunMetricFormatting.formatMiles(meters: $0) } ?? "—")
                .font(.title3.monospacedDigit())
        }
        HStack {
            Image(systemName: "clock").foregroundStyle(.secondary)
            Text(formatElapsed(viewModel.elapsed))
                .font(.title3.monospacedDigit())
            // Avg pace MM:SS/mi sits next to elapsed time. Placeholder
            // `--:--/mi` until distance is stable — see
            // `RunMetricFormatting.formatAveragePacePerMile`.
            Text(RunMetricFormatting.formatAveragePacePerMile(
                elapsedSeconds: viewModel.elapsed,
                distanceMeters: viewModel.distanceMeters ?? 0
            ))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Average pace")
        }
        HStack {
            Image(systemName: "flame.fill").foregroundStyle(.orange)
            Text(viewModel.estimatedActiveKilocalories.map { String(format: "%.0f kcal", $0) } ?? "—")
                .font(.title3.monospacedDigit())
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        switch viewModel.launchState {
        case .idle, .ended, .cancelled, .failed:
            Button("Start Run") {
                Task { await viewModel.start() }
            }
            .buttonStyle(.borderedProminent)
        case .starting, .ending:
            ProgressView().controlSize(.small)
        case .running:
            HStack {
                Button("Pause") { Task { await viewModel.pause() } }
                Button("Finish") { Task { await viewModel.requestFinish() } }
                    .tint(.red)
            }
        case .paused:
            HStack {
                Button("Resume") { Task { await viewModel.resume() } }
                Button("Finish") { Task { await viewModel.requestFinish() } }
                    .tint(.red)
            }
        case .pendingFinish:
            Text("Choose an action above")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        Label(
            viewModel.glassesConnected ? "HUD online" : "HUD offline",
            systemImage: viewModel.glassesConnected ? "eyeglasses" : "eyeglasses.slash"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)

        if case .failed(let reason) = viewModel.launchState {
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.red)
        }
        if case .ended(let summary) = viewModel.launchState {
            // Decision #4: HK-official kcal lives on the summary; live
            // estimate (above) is replaced post-save.
            let kcal = summary.totalActiveEnergyKilocalories.map { String(format: " · %.0f kcal", $0) } ?? ""
            Text("Saved · HK \(summary.healthKitWorkoutID.uuidString.prefix(8))\(kcal)")
                .font(.caption2)
                .foregroundStyle(.green)
        }
        if case .cancelled = viewModel.launchState {
            Text("Run discarded")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var finishMenuBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchState == .pendingFinish },
            set: { isPresented in
                // Auto-dismiss without an explicit choice resumes the run, so
                // a stray tap-out can't strand the workout in pendingFinish.
                if !isPresented, viewModel.launchState == .pendingFinish {
                    Task { await viewModel.resumeFromFinish() }
                }
            }
        )
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    NavigationStack {
        WorkoutView()
    }
}
