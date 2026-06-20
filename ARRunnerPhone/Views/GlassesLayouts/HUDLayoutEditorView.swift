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
    @State private var gridConfig: HUDGridConfig
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
        let config = layout.resolvedGrid.validated()
        _gridConfig = State(initialValue: config)
        // Pad/truncate to the grid's slot count so the editor is stable even
        // if a legacy layout carried a different slot count.
        _name = State(initialValue: layout.name)
        _slots = State(initialValue: HUDLayoutsViewModel.resizedSlots(
            layout.slots, toSlotCount: config.slotCount
        ))
    }

    private var draftLayout: HUDLayout {
        HUDLayoutsViewModel.makeLayout(
            id: layoutID, name: name, slots: slots, grid: gridConfig, existingNames: existingNames
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
                current: slots.indices.contains(slot.id) ? slots[slot.id] : nil,
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
            // Line-count selector.
            Picker("Lines", selection: Binding(
                get: { gridConfig.lines.count },
                set: { setLineCount($0) }
            )) {
                ForEach(2...4, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)

            // Per-line items + the editable slot cells, grouped by line.
            ForEach(Array(gridConfig.lines.enumerated()), id: \.offset) { lineIndex, items in
                VStack(spacing: 8) {
                    HStack {
                        Text("Line \(lineIndex + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Items", selection: Binding(
                            get: { items },
                            set: { setItems($0, line: lineIndex) }
                        )) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 96)
                    }
                    HStack(spacing: 10) {
                        ForEach(0..<items, id: \.self) { item in
                            slotCell(flatIndex(line: lineIndex, item: item))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Grid")
        } footer: {
            Text("Choose 2–4 lines and 1–2 metrics per line. Tap a slot to pick a metric — a metric can appear only once.")
                .font(.caption2)
        }
    }

    private func slotCell(_ index: Int) -> some View {
        Button {
            pickerSlot = index
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text((slots.indices.contains(index) ? slots[index] : nil)
                    .map(HUDLayoutsViewModel.displayLabel(for:)) ?? "Empty")
                    .font(.headline)
                    .foregroundStyle((slots.indices.contains(index) ? slots[index] : nil) == nil ? .secondary : .primary)
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

    // MARK: - Grid edits

    /// Flat (row-major) slot index for the `item`-th metric on `line`.
    private func flatIndex(line: Int, item: Int) -> Int {
        var idx = 0
        for l in 0..<line where gridConfig.lines.indices.contains(l) { idx += gridConfig.lines[l] }
        return idx + item
    }

    private func setLineCount(_ count: Int) {
        gridConfig = HUDLayoutsViewModel.updatedGrid(gridConfig, lineCount: count)
        slots = HUDLayoutsViewModel.resizedSlots(slots, toSlotCount: gridConfig.slotCount)
    }

    private func setItems(_ items: Int, line: Int) {
        gridConfig = HUDLayoutsViewModel.updatedGrid(gridConfig, items: items, atLine: line)
        slots = HUDLayoutsViewModel.resizedSlots(slots, toSlotCount: gridConfig.slotCount)
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section {
            HUDLayoutPreviewPanel(slots: slots, gridConfig: gridConfig, unitSystem: unitSystem)
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
                                Image(systemName: HUDLayoutsViewModel.iconSymbol(for: metric))
                                    .frame(width: 22)
                                    .foregroundStyle(disabled ? .secondary : .primary)
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
/// configured grid (line count + items-per-line) with synthetic sample values,
/// approximate adaptive font sizes, and SF-Symbol icons paired with each value
/// — full-strength for metrics with a real glasses glyph, muted for the rest.
/// Approximate by design (Killian UX) — pixel-exact lens-flip + live preview
/// are deferred.
@MainActor
private struct HUDLayoutPreviewPanel: View {
    let slots: [MetricKind?]
    let gridConfig: HUDGridConfig
    let unitSystem: UnitSystem

    private static let amber = Color(red: 1.0, green: 0.75, blue: 0.0)

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(Array(gridConfig.validated().lines.enumerated()), id: \.offset) { lineIndex, items in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if items == 1 {
                        slotItem(flatIndex(line: lineIndex, item: 0), fontSize: fontSize(items: 1))
                    } else {
                        slotItem(flatIndex(line: lineIndex, item: 0), fontSize: fontSize(items: 2))
                        Spacer(minLength: 8)
                        slotItem(flatIndex(line: lineIndex, item: 1), fontSize: fontSize(items: 2))
                    }
                }
                .frame(maxWidth: .infinity, alignment: items == 1 ? .trailing : .center)
            }
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

    /// Approximate point size from the adaptive font hierarchy: fewer
    /// lines/items → taller font.
    private func fontSize(items: Int) -> CGFloat {
        switch gridConfig.validated().lines.count {
        case 2: return items == 1 ? 30 : 24
        case 4: return 16
        default: return items == 1 ? 24 : 18   // 3-line — the standard4 hierarchy
        }
    }

    private func flatIndex(line: Int, item: Int) -> Int {
        let lines = gridConfig.validated().lines
        var idx = 0
        for l in 0..<line where lines.indices.contains(l) { idx += lines[l] }
        return idx + item
    }

    @ViewBuilder
    private func slotItem(_ index: Int, fontSize: CGFloat) -> some View {
        let metric: MetricKind? = slots.indices.contains(index) ? slots[index] : nil
        let value = metric.map {
            HUDLayoutSamplePreview.sampleValueWithUnit(for: $0, system: unitSystem)
        } ?? "--"
        HStack(spacing: 4) {
            if let metric {
                Image(systemName: HUDLayoutsViewModel.iconSymbol(for: metric))
                    .font(.system(size: fontSize * 0.8))
                    // Metrics without a real glasses glyph render muted so the
                    // preview doesn't over-promise an on-glass icon.
                    .foregroundStyle(Self.amber.opacity(
                        HUDLayoutsViewModel.hasGlassesIcon(for: metric) ? 1.0 : 0.4
                    ))
            }
            Text(value)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.amber)
        }
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
