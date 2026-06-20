// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import SwiftUI

/// Editor for a single custom HUD layout (custom-HUD Phase B).
///
/// A fixed 4-slot grid matching `HUDGridDefinition.standard4`
/// (primary / secondary / line 2 / line 3), an editable name, a metric picker
/// per slot (no duplicate metrics), a static amber-on-black preview with
/// synthetic values, and a best-effort "may be cut off" width hint. Saving is
/// never blocked — it commits through the caller's `onSave`.
@MainActor
struct HUDLayoutEditorView: View {
    let unitSystem: UnitSystem
    let existingNames: [String]
    let onSave: (HUDLayout) -> Void

    @Environment(\.dismiss) private var dismiss

    private let layoutID: String
    @State private var name: String
    @State private var slots: [MetricKind?]
    @State private var pickerSlot: Int?

    init(
        layout: HUDLayout,
        unitSystem: UnitSystem,
        existingNames: [String],
        onSave: @escaping (HUDLayout) -> Void
    ) {
        self.layoutID = layout.id
        self.unitSystem = unitSystem
        self.existingNames = existingNames
        self.onSave = onSave
        // Pad/truncate to the fixed 4-slot grid so the editor is stable even
        // if a future/legacy layout carried a different slot count.
        var seeded = layout.slots
        if seeded.count < 4 { seeded.append(contentsOf: Array(repeating: nil, count: 4 - seeded.count)) }
        _name = State(initialValue: layout.name)
        _slots = State(initialValue: Array(seeded.prefix(4)))
    }

    private var draftLayout: HUDLayout {
        HUDLayoutsViewModel.makeLayout(
            id: layoutID, name: name, slots: slots, existingNames: existingNames
        )
    }

    private var widthWarningSlots: Set<Int> {
        Set(HUDLayoutSamplePreview.widthWarningSlots(for: draftLayout, system: unitSystem))
    }

    var body: some View {
        Form {
            nameSection
            gridSection
            previewSection
        }
        .navigationTitle("Edit Layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draftLayout)
                    dismiss()
                }
            }
        }
        .sheet(item: Binding(
            get: { pickerSlot.map { SlotIndex(id: $0) } },
            set: { pickerSlot = $0?.id }
        )) { slot in
            MetricPickerSheet(
                current: slots[slot.id],
                usedElsewhere: usedMetrics(excluding: slot.id)
            ) { selected in
                slots = HUDLayoutsViewModel.updatedSlots(slots, setting: selected, at: slot.id)
                pickerSlot = nil
            }
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        Section {
            TextField("Layout name", text: $name)
                .autocorrectionDisabled()
        } header: {
            Text("Name")
        } footer: {
            Text("Leave blank to auto-name. Changes apply to your next workout.")
                .font(.caption2)
        }
    }

    // MARK: - Grid

    private var gridSection: some View {
        Section {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    slotCell(0, label: "Primary")
                    slotCell(1, label: "Secondary")
                }
                HStack(spacing: 10) {
                    slotCell(2, label: "Line 2")
                    slotCell(3, label: "Line 3")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Slots")
        } footer: {
            Text("Tap a slot to choose a metric. A metric can appear only once.")
                .font(.caption2)
        }
    }

    private func slotCell(_ index: Int, label: String) -> some View {
        Button {
            pickerSlot = index
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(slots[index].map(HUDLayoutsViewModel.displayLabel(for:)) ?? "Empty")
                    .font(.headline)
                    .foregroundStyle(slots[index] == nil ? .secondary : .primary)
                if widthWarningSlots.contains(index) {
                    Label("May be cut off", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(10)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section {
            HUDLayoutPreviewPanel(slots: slots, unitSystem: unitSystem)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            if !widthWarningSlots.isEmpty {
                Label("Some values may be cut off on the glasses.", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Preview")
        } footer: {
            Text("Approximate. Sample values shown — actual glasses display uses your live metrics.")
                .font(.caption2)
        }
    }

    // MARK: - Helpers

    private func usedMetrics(excluding index: Int) -> Set<MetricKind> {
        var used = Set<MetricKind>()
        for (i, slot) in slots.enumerated() where i != index {
            if let metric = slot { used.insert(metric) }
        }
        return used
    }
}

/// Identifiable wrapper so a plain `Int` slot index can drive `.sheet(item:)`.
private struct SlotIndex: Identifiable {
    let id: Int
}

/// Modal metric picker. Lists all `MetricKind`s plus an "Empty" option;
/// metrics already used in another slot are disabled to prevent duplicates.
@MainActor
private struct MetricPickerSheet: View {
    let current: MetricKind?
    let usedElsewhere: Set<MetricKind>
    let onSelect: (MetricKind?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                    } label: {
                        HStack {
                            Text("Empty")
                            Spacer()
                            if current == nil {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Section("Metrics") {
                    ForEach(MetricKind.allCases, id: \.rawValue) { metric in
                        let disabled = usedElsewhere.contains(metric) && metric != current
                        Button {
                            onSelect(metric)
                        } label: {
                            HStack {
                                Text(HUDLayoutsViewModel.displayLabel(for: metric))
                                    .foregroundStyle(disabled ? .secondary : .primary)
                                Spacer()
                                if metric == current {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                } else if disabled {
                                    Text("In use").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(disabled)
                    }
                }
            }
            .navigationTitle("Choose Metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Static amber-on-black approximation of the 304×256 Engo 2 HUD. Renders the
/// four slots with synthetic sample values + correct unit labels for the
/// active `UnitSystem`. Approximate by design (Killian UX) — pixel-exact
/// lens-flip + live preview are deferred.
@MainActor
private struct HUDLayoutPreviewPanel: View {
    let slots: [MetricKind?]
    let unitSystem: UnitSystem

    private static let amber = Color(red: 1.0, green: 0.75, blue: 0.0)

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                slotText(0, font: .system(size: 26, weight: .semibold, design: .rounded))
                Spacer(minLength: 12)
                slotText(1, font: .system(size: 26, weight: .semibold, design: .rounded))
            }
            slotText(2, font: .system(size: 20, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing)
            slotText(3, font: .system(size: 20, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(16)
        .frame(maxWidth: .infinity)
        .aspectRatio(304.0 / 256.0, contentMode: .fit)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Self.amber.opacity(0.25), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func slotText(_ index: Int, font: Font) -> some View {
        let value: String = {
            guard slots.indices.contains(index), let metric = slots[index] else { return "--" }
            return HUDLayoutSamplePreview.sampleValueWithUnit(for: metric, system: unitSystem)
        }()
        Text(value)
            .font(font)
            .foregroundStyle(Self.amber)
    }
}

#Preview {
    NavigationStack {
        HUDLayoutEditorView(
            layout: HUDLayout(id: "p", name: "Custom Layout 1", slots: [.pace, .heartRate, .distance, .duration]),
            unitSystem: .metric,
            existingNames: []
        ) { _ in }
    }
}
