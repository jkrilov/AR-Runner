// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation
import SwiftUI

/// iPhone Live tab — single-screen read-only mirror of the active watch
/// workout (v0.2 #3). No controls, no settings (#3 + #6 keep the phone
/// opportunistic and offline-capable).
@MainActor
struct WorkoutMirrorView: View {
    @State private var viewModel: WorkoutMirrorViewModel

    init(service: WatchConnectivityService) {
        _viewModel = State(wrappedValue: WorkoutMirrorViewModel(service: service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            startedRow
            glassesBatteryRow
            metricsGrid
            footer
            Spacer()
        }
        .padding()
        .navigationTitle("Live")
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    /// rc2 — "Started at HH:MM" row above the live metrics. Sourced from
    /// the snapshot's new optional `startedAt` field (WC schema v4). v3
    /// snapshots from older watch builds don't carry it; we fall back to
    /// `timestamp − elapsedSeconds` so the row still shows a sensible time
    /// without forcing a watch upgrade.
    @ViewBuilder
    private var startedRow: some View {
        if let snapshot = currentSnapshot, let started = effectiveStartedAt(of: snapshot) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
                Text("Started")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.startedAtFormatter.string(from: started))
                    .font(.title3.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Started at \(Self.startedAtFormatter.string(from: started))")
        }
    }

    private func effectiveStartedAt(of snapshot: WorkoutTickMessage) -> Date? {
        if let started = snapshot.startedAt { return started }
        // v3 fallback: derive from elapsed for older watch builds. Returns
        // nil only if elapsedSeconds is non-finite, which would already
        // have flagged earlier.
        guard snapshot.elapsedSeconds.isFinite, snapshot.elapsedSeconds >= 0 else { return nil }
        return snapshot.timestamp.addingTimeInterval(-snapshot.elapsedSeconds)
    }

    /// Absolute clock time for "Started" — short style ("3:14 PM"). Locale
    /// aware. Pinned in `WorkoutMirrorStartedRowTests` so a future format
    /// flip is caught.
    private static let startedAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    @ViewBuilder
    private var glassesBatteryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: GlassesBatteryIcon.symbol(for: viewModel.glassesBatteryLevel))
                .foregroundStyle(GlassesBatteryIcon.tint(for: viewModel.glassesBatteryLevel))
                .imageScale(.large)
            Text("Glasses Battery")
                .foregroundStyle(.secondary)
            Spacer()
            Text(viewModel.glassesBatteryLevel.map { "\($0)%" } ?? "—")
                .font(.title3.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            viewModel.glassesBatteryLevel.map { "Glasses battery \($0) percent" }
                ?? "Glasses battery unknown"
        )
    }

    @ViewBuilder
    private var header: some View {
        switch viewModel.status {
        case .idle:
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .foregroundStyle(.secondary)
                Text("Waiting for watch…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        case .live(let snapshot):
            phaseHeader(snapshot: snapshot, label: "Live", color: .green)
        case .stale(let snapshot, _):
            phaseHeader(snapshot: snapshot, label: "Stale", color: .orange)
        case .ended(let snapshot):
            phaseHeader(snapshot: snapshot, label: "Ended", color: .secondary)
        }
    }

    @ViewBuilder
    private func phaseHeader(snapshot: WorkoutTickMessage?, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.headline)
                .foregroundStyle(color)
            if let snapshot {
                Text(snapshot.sport.rawValue.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var metricsGrid: some View {
        let snapshot = currentSnapshot
        VStack(alignment: .leading, spacing: 12) {
            metricRow(
                icon: "clock",
                color: .secondary,
                label: "Time",
                value: snapshot.map { formatElapsed($0.elapsedSeconds) }
            )
            metricRow(
                icon: "heart.fill",
                color: .red,
                label: "Heart Rate",
                value: snapshot?.heartRateBeatsPerMinute.map { "\(Int($0)) bpm" }
            )
            metricRow(
                icon: "ruler",
                color: .blue,
                label: "Distance",
                value: snapshot?.distanceMeters.map { String(format: "%.0f m", $0) }
            )
            metricRow(
                icon: "speedometer",
                color: .purple,
                label: "Pace",
                value: snapshot?.paceSecondsPerKilometer.map { formatPace($0) }
            )
            metricRow(
                icon: "flame.fill",
                color: .orange,
                label: "Energy (est.)",
                value: snapshot?.estimatedActiveKilocalories.map { String(format: "%.0f kcal", $0) }
            )
        }
    }

    @ViewBuilder
    private func metricRow(icon: String, color: Color, label: String, value: String?) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .font(.title3.monospacedDigit())
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let snapshot = currentSnapshot {
            Label(
                snapshot.glassesConnected ? "HUD online" : "HUD offline",
                systemImage: snapshot.glassesConnected ? "eyeglasses" : "eyeglasses.slash"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if case .stale = viewModel.status {
            Text("No update in the last few seconds — the watch may be out of range.")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
        if case .idle = viewModel.status {
            Text("Start a run on your Apple Watch and it will appear here automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var currentSnapshot: WorkoutTickMessage? {
        switch viewModel.status {
        case .idle: return nil
        case .live(let s): return s
        case .stale(let s, _): return s
        case .ended(let s): return s
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

    private func formatPace(_ secondsPerKm: TimeInterval) -> String {
        let m = Int(secondsPerKm) / 60
        let s = Int(secondsPerKm) % 60
        return String(format: "%d:%02d /km", m, s)
    }
}
