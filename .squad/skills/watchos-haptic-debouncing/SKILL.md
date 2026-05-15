# Skill: watchOS Haptic Debouncing for Status-Event Alerts

**Author:** Laughlin (watchOS Dev)
**Established:** 2026-05-15

## Problem

A watch UI that fires a haptic on every transport-level status event (e.g., `.dropped`, low-battery, signal-quality drop) will spam the user's wrist when the underlying signal flaps. Examples observed during D4 design:

- BLE link-loss flapping at the edge of range can fire `.dropped` 3–5x in a few seconds before settling.
- A glasses peer that power-cycles produces `.dropped` → `.reconnected` → `.dropped` in rapid succession.
- Two upstream sources (transport status + connection-state stream) can each report a logical drop, doubling the would-be alert count.

You can't fix this at the transport level — the events are correct; they're just too granular for haptics.

## Pattern

A two-gate, MainActor-isolated debouncer that lives in the view-model:

```swift
@MainActor @Observable
final class SomeViewModel {
    private static let hapticDebounceInterval: TimeInterval = 10
    private var lastHapticAt: Date?
    private let hapticPlayer: @Sendable () -> Void
    private let now: @Sendable () -> Date

    init(
        hapticPlayer: (@Sendable () -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.hapticPlayer = hapticPlayer ?? Self.defaultHapticPlayer
        self.now = now
    }

    private static let defaultHapticPlayer: @Sendable () -> Void = {
        #if canImport(WatchKit) && os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }

    private func handle(statusEvent event: SomeStatusEvent) async {
        switch event {
        case .dropped:
            fireAlertHapticIfEligible()
        case .recovered:
            // CRITICAL: reset so a fresh outage after recovery alerts immediately.
            lastHapticAt = nil
        default:
            break
        }
    }

    private func fireAlertHapticIfEligible() {
        // Phase gate: only alert when alert is contextually useful.
        guard launchState == .running else { return }

        // Time gate: suppress within debounce window.
        let timestamp = now()
        if let lastHapticAt,
           timestamp.timeIntervalSince(lastHapticAt) < Self.hapticDebounceInterval {
            return
        }
        lastHapticAt = timestamp
        hapticPlayer()
    }
}
```

## Why each piece

- **`@Sendable () -> Void` haptic player closure with a default.** Production code calls real WatchKit; tests pass a counter closure. The view-model itself stays buildable on Linux SPM (the closure default is gated behind `#if canImport(WatchKit) && os(watchOS)` — the symbol is missing on Linux but the closure body never runs there).
- **`now: @Sendable () -> Date` clock injection.** Lets unit tests step the clock deterministically through the debounce window. Default `{ Date() }` keeps production callers ergonomic.
- **`lastHapticAt: Date?`** — `nil` means "fire-eligible immediately". Set on each successful fire; reset on the recovery event so a fresh outage isn't accidentally suppressed by the previous outage's debounce.
- **Phase gate** (e.g., `launchState == .running`). Drops while idle / paused / ending should be visible (banner) but not haptic. This is decision-driven, not a debounce concern, but it lives in the same eligibility check because both gates compose to "should I haptic now?".
- **MainActor isolation.** `lastHapticAt` is mutated only here; running on MainActor avoids any actor-hop subtlety. The status-event subscriber loop awaits this method, which serializes fire decisions naturally.

## Picking the haptic and the interval

- **Haptic style:** `WKInterfaceDevice.current().play(.notification)` is the right "subtle but noticed" call for status-change alerts where the underlying system is still functional. Avoid `.failure` for non-failure events (e.g., HUD drop while workout keeps recording) — it reads as "your run is broken" to the user.
- **Debounce interval:** 10 s for D4-class outages (BLE link-loss is bursty over seconds, not sub-second). Tune per signal: a heart-rate-zone-crossing alert might want 30–60 s; a low-battery alert might want a single fire per session and never repeat.

## Anti-patterns observed

- **Fire on every event, no debounce.** Spams the wrist during link flapping; users disable workout haptics in Settings to escape.
- **Debounce without reset on recovery.** A drop → reconnect → drop sequence within the window silently swallows the second alert; the user thinks the second outage went unnoticed.
- **Debounce in the producer (transport).** Couples policy to a layer that shouldn't have an opinion on UX. Different consumers (haptic, banner, side-store telemetry) have different gating needs — keep policy at each consumer.
- **Skip the phase gate.** Alerting on a drop while the workout is `.idle` (pre-start) or `.ended` (post-save) confuses users. The transport doesn't know the workout phase; the view-model does.
- **Inline `WKInterfaceDevice.current().play(.notification)` in the handler.** Makes the view-model untestable on Linux and impossible to verify trigger semantics without a real watch. Closure injection costs nothing.

## Reference implementation

`ARRunnerWatch/Workout/WorkoutViewModel.swift` — `handle(statusEvent:)` and `fireDisconnectHapticIfEligible()`. Shipped in PR #13 (v0.2 #4).
