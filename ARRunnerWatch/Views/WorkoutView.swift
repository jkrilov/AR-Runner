// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import SwiftUI

@MainActor
struct WorkoutView: View {
    @State private var viewModel = WorkoutViewModel(
        substrateFactory: { HealthKitWorkoutSubstrate() },
        transportFactory: { GlassesTransportFactory.makeDefault() }
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
    }

    @ViewBuilder
    private var controlsSection: some View {
        switch viewModel.launchState {
        case .idle, .ended, .failed:
            Button("Start Run") {
                Task { await viewModel.start() }
            }
            .buttonStyle(.borderedProminent)
        case .starting, .ending:
            ProgressView().controlSize(.small)
        case .running:
            HStack {
                Button("Pause") { Task { await viewModel.pause() } }
                Button("End") { Task { await viewModel.end() } }
                    .tint(.red)
            }
        case .paused:
            HStack {
                Button("Resume") { Task { await viewModel.resume() } }
                Button("End") { Task { await viewModel.end() } }
                    .tint(.red)
            }
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
            Text("Saved · HK ID \(summary.healthKitWorkoutID.uuidString.prefix(8))")
                .font(.caption2)
                .foregroundStyle(.green)
        }
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
