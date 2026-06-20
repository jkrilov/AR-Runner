// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import SwiftUI

/// Glasses Layouts list (custom-HUD Phase B). Three sections:
///   1. read-only system presets (with "Duplicate to customize"),
///   2. the user's custom layouts (tap to edit, swipe to delete),
///   3. the per-workout-type default assignment.
///
/// Reached from Settings → Glasses Layouts. All edits persist to the App Group
/// store and push to the watch; they apply at the wearer's next workout.
@MainActor
struct GlassesLayoutsView: View {
    @State private var viewModel: HUDLayoutsViewModel
    @AppStorage(UnitPreference.storageKey, store: UnitPreference.sharedDefaults)
    private var unitRaw: String = UnitPreference.defaultValue.rawValue

    /// Drives the pushed editor. `nil` when no layout is being edited.
    @State private var editingLayout: HUDLayout?

    init(viewModel: HUDLayoutsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? HUDLayoutsViewModel())
    }

    private var unitSystem: UnitSystem {
        UnitSystem(rawValue: unitRaw) ?? UnitPreference.defaultValue
    }

    var body: some View {
        List {
            presetsSection
            customSection
            defaultsSection
        }
        .navigationTitle("Glasses Layouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingLayout = viewModel.makeDraft()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!viewModel.canAddCustom)
                .accessibilityLabel("New Layout")
            }
        }
        .navigationDestination(item: $editingLayout) { layout in
            HUDLayoutEditorView(
                layout: layout,
                unitSystem: unitSystem,
                existingNames: viewModel.catalog.layouts
                    .filter { $0.id != layout.id }
                    .map(\.name)
            ) { saved in
                viewModel.upsert(saved)
                editingLayout = nil
            }
        }
    }

    // MARK: - Presets

    private var presetsSection: some View {
        Section {
            ForEach(viewModel.presets) { preset in
                layoutRow(preset, badge: "System")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            viewModel.duplicate(preset)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                        .disabled(!viewModel.canAddCustom)
                    }
            }
        } header: {
            Text("System Presets")
        } footer: {
            Text("Swipe a preset to duplicate it into an editable custom layout.")
                .font(.caption2)
        }
    }

    // MARK: - Custom

    @ViewBuilder
    private var customSection: some View {
        Section {
            if viewModel.catalog.layouts.isEmpty {
                Text("No custom layouts yet. Tap + or duplicate a preset to create one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.catalog.layouts) { layout in
                    Button {
                        editingLayout = layout
                    } label: {
                        layoutRow(layout, badge: nil)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { viewModel.deleteCustom(at: $0) }
            }
        } header: {
            Text("My Layouts")
        } footer: {
            if !viewModel.canAddCustom {
                Text("You've reached the limit of \(HUDLayoutsViewModel.maxCustomLayouts) custom layouts. Delete one to add another.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("Changes apply to your next workout.")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Per-type defaults

    private var defaultsSection: some View {
        Section {
            ForEach(WorkoutType.allCases, id: \.rawValue) { type in
                defaultRow(for: type)
            }
        } header: {
            Text("Default Layout per Workout Type")
        } footer: {
            Text("Pick which layout each workout type starts with. Metrics that don't apply to a type appear as “--” on the glasses.")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private func defaultRow(for type: WorkoutType) -> some View {
        let builtIn = HUDLayout.default(for: type)
        Picker(selection: Binding(
            get: { viewModel.defaults.layoutID(for: type) },
            set: { viewModel.assign(layoutID: $0, to: type) }
        )) {
            Text("Default (\(builtIn.name))").tag(String?.none)
            ForEach(viewModel.catalog.layouts) { layout in
                Text(layout.name).tag(Optional(layout.id))
            }
        } label: {
            Label(type.displayName, systemImage: WorkoutTypePreference.symbolName(for: type))
        }

        if let assigned = viewModel.assignedLayout(for: type) {
            let invalid = HUDLayoutsViewModel.invalidMetrics(in: assigned, for: type)
            if !invalid.isEmpty {
                Text("\(invalid.map(HUDLayoutsViewModel.displayLabel(for:)).joined(separator: ", ")) won't show for \(type.displayName) — appears as “--”.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Row

    private func layoutRow(_ layout: HUDLayout, badge: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(layout.name)
                    .font(.body)
                Text(HUDLayoutsViewModel.slotSummary(layout))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        GlassesLayoutsView(
            viewModel: HUDLayoutsViewModel(
                catalog: HUDLayoutCatalog(layouts: [
                    HUDLayout(id: "c1", name: "My Tempo", slots: [.pace, .heartRate, .distance, .duration])
                ]),
                defaults: WorkoutLayoutDefaults(),
                sync: nil,
                persistsToStore: false
            )
        )
    }
}
