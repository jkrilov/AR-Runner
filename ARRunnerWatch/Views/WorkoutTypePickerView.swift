// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import SwiftUI

/// Pre-workout workout-type picker (v0.6.0). Presented from `WorkoutView`'s
/// idle/pre-run controls when the wearer taps the current-type row. Lists the
/// supported `WorkoutType` combinations with an SF Symbol and a checkmark on
/// the active selection; tapping a row updates the binding and pops back so
/// the Start button immediately reflects the new "Start [Type]" label.
///
/// The selection itself is owned by `WorkoutView` (seeded from
/// `WorkoutTypePreference`), so this view is a pure presenter — it never
/// starts a workout or writes persistence directly.
@MainActor
struct WorkoutTypePickerView: View {
    @Binding var selection: WorkoutType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(WorkoutTypePreference.selectable, id: \.rawValue) { type in
                Button {
                    selection = type
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: WorkoutTypePreference.symbolName(for: type))
                            .frame(width: 24)
                            .foregroundStyle(.green)
                        Text(type.displayName)
                        Spacer()
                        if type == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Selected")
                        }
                    }
                }
                .accessibilityLabel(type.displayName)
                .accessibilityAddTraits(type == selection ? [.isSelected] : [])
            }
        }
        .navigationTitle("Workout Type")
    }
}

#Preview {
    NavigationStack {
        WorkoutTypePickerView(selection: .constant(.outdoorRun))
    }
}
