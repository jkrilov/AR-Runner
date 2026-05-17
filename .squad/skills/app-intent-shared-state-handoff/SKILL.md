# App Intent → Host App Shared-State Handoff

**Confidence:** Low (first observation — pattern shape is generic but only validated against one use case so far).
**Domain:** watchOS / iOS App Intents, WidgetKit extensions, App Groups.
**Origin:** v0.2 audit P1.1 fix — Smart Stack `StartWorkoutIntent` needed to auto-start a workout in the host app on foreground (commit `2a31b84`).

## Problem

An `AppIntent` invoked from a widget (Smart Stack button, lock-screen widget, etc.) runs in the **widget extension process**, not the host app. It has no access to host singletons, view models, or `@Observable` state. Setting `openAppWhenRun = true` foregrounds the host, but the host has no way to know *why* it was foregrounded — by default it lands on whatever the last-active screen was, ignoring the user's intent.

Naïve approaches that don't work cross-process on watchOS:

- `NotificationCenter.default.post(…)` — not cross-process.
- Direct method call on a host-side singleton — different process, different address space.
- Deep-link URL — watchOS App Intent → host URL routing is awkward and not reliably observable from the host's `.task`.

## Solution

Use **App Group `UserDefaults` as an atomic, timestamped flag**.

### Shape

```swift
public protocol PendingActionStore: Sendable {
    func markPending(at timestamp: Date)
    /// Returns true (and clears the flag) iff a pending action was
    /// recorded within `freshness` seconds of `now`.
    func consumePending(now: Date, freshness: TimeInterval) -> Bool
}

public final class AppGroupPendingActionStore: PendingActionStore, @unchecked Sendable {
    private static let key = "pendingActionTimestamp"
    private let defaults: UserDefaults?

    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName)
    }

    public func markPending(at timestamp: Date) {
        defaults?.set(timestamp.timeIntervalSinceReferenceDate, forKey: Self.key)
    }

    public func consumePending(now: Date, freshness: TimeInterval) -> Bool {
        guard let defaults else { return false }
        let raw = defaults.double(forKey: Self.key)
        guard raw > 0 else { return false }
        defaults.removeObject(forKey: Self.key)              // atomic clear-on-read
        let age = now.timeIntervalSince(Date(timeIntervalSinceReferenceDate: raw))
        return age >= 0 && age <= freshness                  // freshness gate
    }
}
```

### Widget side (`AppIntent.perform`)

```swift
struct StartWorkoutIntent: AppIntent {
    static let openAppWhenRun = true
    var store: any PendingActionStore = AppGroupPendingActionStore(suiteName: "group.com.example.shared")
    var now: @Sendable () -> Date = { Date() }

    func perform() async throws -> some IntentResult {
        store.markPending(at: now())
        return .result()
    }
}
```

### Host side (`SwiftUI` view)

```swift
@Environment(\.scenePhase) private var scenePhase
private let store = AppGroupPendingActionStore(suiteName: "group.com.example.shared")

var body: some View {
    Content()
        .task { await maybeAct() }                              // cold-start path
        .onChange(of: scenePhase) { _, new in                   // warm foreground
            if new == .active { Task { await maybeAct() } }
        }
}

private func maybeAct() async {
    guard store.consumePending(now: Date(), freshness: 60) else { return }
    guard viewModel.isIdle else { return }                      // don't disturb in-flight state
    await viewModel.performAction()
}
```

## Why it works

1. **App Group `UserDefaults` is shared.** Both the widget extension and the host app are entitled to the same App Group (`group.com.…`), and `UserDefaults(suiteName:)` against that identifier maps to the same on-disk plist. Reads from either process see writes from the other within milliseconds (filesystem flush, no IPC needed).
2. **Clear-on-read is atomic enough.** `UserDefaults.removeObject(forKey:)` followed by a re-mark is the standard "consume" idiom. Two concurrent `consumePending` calls *could* both see the value before either clears, but in practice only one process (the host) calls consume — race risk is theoretical.
3. **Freshness window prevents stale-flag surprise.** A tap that fires but never reaches the host (battery die, user dismisses widget before launch, etc.) leaves a flag in the store. Without a freshness check, the *next* time the user opens the host hours/days later they'd get a phantom auto-action. Cap at the order of seconds to minutes depending on use case.
4. **Idle-state guard at the host.** Always re-check the host's current state before acting — the user may have already manually started the action between widget tap and host foreground.

## Tests

The protocol shape gives you full testability **even when the widget target has no test bundle** (common in xcodegen / SwiftPM setups):

- Use a throwaway `UserDefaults` suite per test: `UserDefaults(suiteName: "test.\(UUID().uuidString)")`.
- Mark + consume against the same suite from two different store instances simulates the cross-process flow.
- Stale + clock-skew cases lock the freshness behaviour.

The intent's `perform()` itself is then trivially correct: it makes one call (`store.markPending(at: now())`) which the store tests already cover. If the intent target *does* support testing, inject a mock store via the intent's struct properties.

## Entitlements / build wiring

- All processes (host + widget extension) must declare `com.apple.security.application-groups` with the same identifier in their entitlements file.
- The App Group must be registered at developer.apple.com under the developer team.
- Watch host + watch widget + phone host + phone widget = four entitlements, one App Group ID.

## When NOT to use this

- **Bidirectional state sync** — if the host needs to push back to the widget, use `WidgetCenter.shared.reloadAllTimelines()` instead; the widget then re-reads on its next timeline refresh.
- **High-frequency or large payloads** — `UserDefaults` is for small, infrequent state. For streaming data use `NSFileCoordinator` over an App Group file, or `XPC` on macOS.
- **Cross-device** (watch ↔ phone) — different problem entirely; use `WCSession`.

## Related

- `wcsession-three-tier-delivery` — for watch ↔ phone cross-device messaging.
- `widgetkit-extension-plist-constraints` — for widget bundle structure.
- `xcodegen-shared-widget-per-platform` — for the shared `ARRunnerWidgets` source folder feeding both `ARRunnerWidgetsPhone` and `ARRunnerWidgetsWatch` extension targets.

## References

- `ARRunnerCore/Sources/ARRunnerCore/Workout/PendingWorkoutStart.swift` — production implementation.
- `ARRunnerCore/Tests/ARRunnerCoreTests/PendingWorkoutStartStoreTests.swift` — test coverage.
- `ARRunnerWidgets/StartWorkoutIntent.swift` — intent that marks the flag.
- `ARRunnerWatch/Views/WorkoutView.swift` — host that consumes via `scenePhase`.
