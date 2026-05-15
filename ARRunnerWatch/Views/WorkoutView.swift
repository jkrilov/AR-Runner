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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metricsSection
            Divider()
            controlsSection
            statusFooter
        }
        .padding()
        .navigationTitle("Run")
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

    @ViewBuilder
    private var metricsSection: some View {
        HStack {
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(viewModel.heartRate.map { "\(Int($0)) bpm" } ?? "—")
                .font(.title3.monospacedDigit())
        }
        HStack {
            Image(systemName: "ruler").foregroundStyle(.blue)
            Text(viewModel.distanceMeters.map { String(format: "%.0f m", $0) } ?? "—")
                .font(.title3.monospacedDigit())
        }
        HStack {
            Image(systemName: "clock").foregroundStyle(.secondary)
            Text(formatElapsed(viewModel.elapsed))
                .font(.title3.monospacedDigit())
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
