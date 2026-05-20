// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// rc2 (2026-05-20) — regression guard for Joe's 5K bench feedback item #4:
///   "I discarded a run. It still showed up in Apple Fitness."
///
/// Root cause: `WorkoutViewModel.confirmCancel` was calling
/// `controller.end()`, which delegates to `substrate.end(at:)`, which on
/// the real HealthKit substrate ends with `builder.finishWorkout()` and
/// persists an `HKWorkout` regardless of user intent. rc2 splits save and
/// discard onto **distinct** terminal substrate methods (`end` vs
/// `discard`) and a new `controller.discard()` so `confirmCancel` can
/// route through the no-save path.
///
/// These tests pin the contract at the substrate seam where the bug lived:
///   * Save terminal path → `substrate.end(at:)` called exactly once,
///     `substrate.discard(at:)` NEVER called.
///   * Discard terminal path → `substrate.discard(at:)` called exactly
///     once, `substrate.end(at:)` NEVER called.
/// If a future refactor re-introduces "save then maybe delete", or
/// reroutes cancel through `end()` again, one of these tests trips.
final class WorkoutDiscardTerminalPathTests: XCTestCase {
    // MARK: - Save path

    func test_save_callsSubstrateEndOnce_andNeverDiscard() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate)

        _ = try await controller.start()
        _ = try await controller.end()

        let calls = await substrate.recordedCalls
        let endCount = calls.filter {
            if case .end = $0 { return true } else { return false }
        }.count
        let discardCount = calls.filter {
            if case .discard = $0 { return true } else { return false }
        }.count

        XCTAssertEqual(endCount, 1, "save terminal path must call substrate.end exactly once")
        XCTAssertEqual(discardCount, 0, "save terminal path must NEVER call substrate.discard")
    }

    // MARK: - Discard path

    func test_discard_callsSubstrateDiscardOnce_andNeverEnd() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate)

        _ = try await controller.start()
        try await controller.discard()

        let calls = await substrate.recordedCalls
        let endCount = calls.filter {
            if case .end = $0 { return true } else { return false }
        }.count
        let discardCount = calls.filter {
            if case .discard = $0 { return true } else { return false }
        }.count

        XCTAssertEqual(discardCount, 1, "discard terminal path must call substrate.discard exactly once")
        XCTAssertEqual(endCount, 0,
                       "discard terminal path must NEVER call substrate.end — that is the bug item #4 closed")
    }

    func test_discard_doesNotEmitSummary_andTransitionsToEnded() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate)
        _ = try await controller.start()

        // Discard returns Void — no `WorkoutSummary` is produced because
        // no `HKWorkout` was created. State machine still transitions to
        // .ended (the workout is over), distinct from .failed.
        try await controller.discard()
        let phase = await controller.currentPhase()
        XCTAssertEqual(phase, .ended)
    }

    func test_discard_fromIdleThrowsNotStarted() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate)
        do {
            try await controller.discard()
            XCTFail("expected notStarted")
        } catch let error as WorkoutController.Error {
            XCTAssertEqual(error, .notStarted)
        }
    }

    func test_discard_afterEndThrowsNotStarted() async throws {
        let substrate = InMemoryWorkoutHealthSubstrate()
        let controller = WorkoutController(substrate: substrate)
        _ = try await controller.start()
        _ = try await controller.end()
        do {
            try await controller.discard()
            XCTFail("expected notStarted")
        } catch let error as WorkoutController.Error {
            XCTAssertEqual(error, .notStarted)
        }
    }

    // MARK: - Cross-substrate (FakeHealthKitSubstrate also conforms)

    func test_fakeSubstrate_discardCallSurfaces() async throws {
        let substrate = FakeHealthKitSubstrate(scenario: .ended)
        let controller = WorkoutController(substrate: substrate)
        _ = try await controller.start()
        try await controller.discard()

        let calls = await substrate.recordedCalls
        let hasDiscard = calls.contains {
            if case .discard = $0 { return true } else { return false }
        }
        let hasEnd = calls.contains {
            if case .end = $0 { return true } else { return false }
        }
        XCTAssertTrue(hasDiscard, "FakeHealthKitSubstrate must record .discard on cancel terminal path")
        XCTAssertFalse(hasEnd, "FakeHealthKitSubstrate must NOT record .end on cancel terminal path")
    }
}
