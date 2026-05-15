// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import ARRunnerCore
import Foundation

/// Factory that picks the right `GlassesFrameTransport` for the current build.
///
/// - **Release / TestFlight on real hardware:** real `ActiveLookGlassesAdapter`
///   driving CoreBluetooth. The adapter starts disconnected; `connect()` is
///   driven from `WorkoutViewModel.start(...)`.
/// - **DEBUG (Simulator / SwiftUI previews):** in-memory `StubGlassesTransport`
///   so the workout flow boots end-to-end without a peripheral nearby.
///
/// Centralising the choice here keeps the SwiftUI layer free of `#if DEBUG`
/// and keeps the adapter swap a one-line change for hardware bring-up.
enum GlassesTransportFactory {
    static func makeDefault() -> any GlassesFrameTransport {
        #if targetEnvironment(simulator) || DEBUG
        return StubGlassesTransport()
        #else
        return ActiveLookGlassesAdapter()
        #endif
    }
}
