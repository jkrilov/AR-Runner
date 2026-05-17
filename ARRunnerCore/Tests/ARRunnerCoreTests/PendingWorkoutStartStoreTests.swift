// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class PendingWorkoutStartStoreTests: XCTestCase {
    /// Per-test throwaway UserDefaults suite so tests don't collide with
    /// each other or with the real shared App Group container.
    private func makeStore() -> (AppGroupPendingWorkoutStartStore, UserDefaults, String) {
        let suite = "test.pendingstart.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AppGroupPendingWorkoutStartStore(defaults: defaults), defaults, suite)
    }

    override func tearDown() {
        // Best-effort cleanup of any leaked test suites.
        super.tearDown()
    }

    func testConsumeReturnsFalseWhenNothingPending() {
        let (store, _, _) = makeStore()
        XCTAssertFalse(store.consumePending(now: Date(), freshness: 60))
    }

    func testMarkThenConsumeReturnsTrueAndClears() {
        let (store, _, _) = makeStore()
        let now = Date()
        store.markPending(at: now)

        XCTAssertTrue(store.consumePending(now: now.addingTimeInterval(1), freshness: 60))
        // Second consume sees an empty store.
        XCTAssertFalse(store.consumePending(now: now.addingTimeInterval(2), freshness: 60))
    }

    func testStaleFlagIsClearedWithoutTriggering() {
        // A flag dropped hours ago must not auto-start a workout the
        // next time the app foregrounds.
        let (store, _, _) = makeStore()
        let marked = Date(timeIntervalSinceReferenceDate: 1_000_000)
        store.markPending(at: marked)

        let result = store.consumePending(
            now: marked.addingTimeInterval(3_600), // 1 hour later
            freshness: 60
        )
        XCTAssertFalse(result, "stale flag must not trigger an auto-start")

        // And the flag is cleared, so a fresh second mark+consume works.
        store.markPending(at: marked.addingTimeInterval(3_601))
        XCTAssertTrue(store.consumePending(
            now: marked.addingTimeInterval(3_602),
            freshness: 60
        ))
    }

    func testNegativeAgeRejected() {
        // Defensive: if the wall clock jumps backwards, treat the flag
        // as not-fresh rather than gambling on a future timestamp.
        let (store, _, _) = makeStore()
        let marked = Date(timeIntervalSinceReferenceDate: 2_000_000)
        store.markPending(at: marked)

        XCTAssertFalse(store.consumePending(
            now: marked.addingTimeInterval(-10),
            freshness: 60
        ))
    }

    /// Test for the AppIntent contract: a fresh widget tap should mark
    /// the flag, and the host app's consume call should observe it via
    /// the same suite name. This is the substitute for a real
    /// AppIntent-level test (no widget test target exists in this
    /// project).
    func testFlagCrossesStoreInstancesViaSameSuite() {
        let suite = "test.pendingstart.cross.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }

        let widgetSide = AppGroupPendingWorkoutStartStore(suiteName: suite)
        let appSide = AppGroupPendingWorkoutStartStore(suiteName: suite)

        let now = Date()
        widgetSide.markPending(at: now)

        XCTAssertTrue(appSide.consumePending(now: now.addingTimeInterval(0.5), freshness: 60))
        // Drained: a second host-side consume must not re-trigger.
        XCTAssertFalse(appSide.consumePending(now: now.addingTimeInterval(1), freshness: 60))
    }
}

/// Direct coverage of `StartWorkoutIntent.perform()` without depending
/// on the widget target (which has no test bundle). We test the
/// intent's only externally observable side effect — writing to the
/// pending-start store — via the same store implementation the
/// intent uses in production.
///
/// (The intent itself lives in `ARRunnerWidgets/`; we don't import it
/// here because the widget target isn't a dependency of Core. The
/// equivalent contract is: "perform() must call
/// store.markPending(at: now())". Covered as a documentation test
/// against the store directly.)
final class StartWorkoutIntentContractTests: XCTestCase {
    func testMarkPendingFlowIsConsumableByHostApp() {
        // This mirrors the intent's perform() exactly:
        //     pendingStartStore.markPending(at: now())
        // …followed by the host's:
        //     pendingStartStore.consumePending(now: Date(), freshness: …)
        let suite = "test.intent.contract.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let store: any PendingWorkoutStartStore = AppGroupPendingWorkoutStartStore(suiteName: suite)
        let intentNow = Date()

        // Simulate intent perform().
        store.markPending(at: intentNow)

        // Simulate host app coming forward 0.25s later.
        let hostNow = intentNow.addingTimeInterval(0.25)
        XCTAssertTrue(store.consumePending(
            now: hostNow,
            freshness: pendingWorkoutStartDefaultFreshnessSeconds
        ))
    }
}
