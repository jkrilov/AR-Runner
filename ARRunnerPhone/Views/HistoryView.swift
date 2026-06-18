// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// History tab (v0.5 PR 3, D-Strava-6). Lists completed AR-Runner workouts
/// and exposes a per-row manual "Upload to Strava" action.
@MainActor
struct HistoryView: View {
    @State private var viewModel: HistoryViewModel

    init(viewModel: HistoryViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? HistoryViewModel())
    }

    var body: some View {
        List {
            if let message = viewModel.lastErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if viewModel.rows.isEmpty && !viewModel.isLoading {
                Text("No runs yet. Recorded workouts will appear here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.rows) { row in
                rowView(row)
            }
        }
        .navigationTitle("History")
        .overlay {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await viewModel.loadWorkouts()
        }
        .task {
            await viewModel.loadWorkouts()
        }
    }

    @ViewBuilder
    private func rowView(_ row: HistoryViewModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(row.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.body)
                    Text("\(Self.formatDistance(row.distanceMeters)) • \(Self.formatDuration(row.durationSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusIcon(row.upload)
            }
            actionButton(for: row)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusIcon(_ status: HistoryViewModel.UploadDisplay) -> some View {
        switch status {
        case .notUploaded:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        case .pending:
            Image(systemName: "hourglass")
                .foregroundStyle(.orange)
        case .uploading, .processing:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func actionButton(for row: HistoryViewModel.Row) -> some View {
        if !viewModel.isStravaConnected {
            EmptyView()
        } else {
            switch row.upload {
            case .notUploaded:
                Button {
                    Task { await viewModel.uploadWorkout(id: row.id) }
                } label: {
                    Label("Upload to Strava", systemImage: "arrow.up.circle")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .tint(.stravaOrange)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.failedText(message))
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button {
                        Task { await viewModel.retryUpload(id: row.id) }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                }
            case .pending(let message):
                Text(Self.statusText(prefix: "Waiting", message: message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .uploading:
                Text("Uploading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .processing(let message):
                Text(Self.statusText(prefix: "Strava processing", message: message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .completed(let activityID):
                if let activityID,
                   let url = URL(string: "https://www.strava.com/activities/\(activityID)") {
                    Link(destination: url) {
                        Label("View on Strava", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                } else {
                    Text("Uploaded")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    /// Compose a concise status line, appending the queue's diagnostic message
    /// (Strava processing note or last error) when present so a stuck upload
    /// shows *why* instead of an indefinite spinner (Fix D, v0.6.2).
    static func statusText(prefix: String, message: String?) -> String {
        if let message, !message.isEmpty {
            return "\(prefix): \(message)"
        }
        return "\(prefix)…"
    }

    static func failedText(_ message: String?) -> String {
        if let message, !message.isEmpty {
            return "Failed: \(message)"
        }
        return "Upload failed"
    }

    // MARK: - Formatting

    static func formatDistance(_ meters: Double) -> String {
        let miles = meters / 1609.344
        return String(format: "%.2f mi", miles)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
}
