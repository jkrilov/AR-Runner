# Skill: Paired-Hardware Lifecycle Contract

**Domain:** System architecture / device integration
**Applies to:** Any project that pairs a host (phone, watch, laptop) with a peripheral (BLE accessory, USB device, HID controller, AR/VR display, hearing aid, dock).
**Origin:** AR-Runner ADR 2026-05-19 — "BLE link is user-managed, not workout-scoped."

## The Pattern

When a peripheral is **paired** (not just transiently connected), its lifecycle MUST be orthogonal to any application-domain session that happens to use it. Two state machines, mutually observing, neither commanding:

```
peripheral_session  ⊥  application_session
   |                       |
   user toggle             user starts/stops feature
   range / power           feature lifecycle events
   system unpair           (workout, call, game, edit, ...)
```

Either machine may *read* the other's state to decide its own behavior, but neither may *drive* the other's transitions.

## Required Contract Elements

Any paired-hardware integration MUST document, with this structure:

1. **Bring-up triggers** — the exhaustive list of events that connect the peripheral. (Typically: explicit user action; re-attach on app launch; auto-reconnect on transient drop.)
2. **Tear-down triggers** — the exhaustive list of events that disconnect. (Typically: explicit user action; physical absence; system unpair. **Never** application-feature lifecycle events.)
3. **Negative space** — explicit list of events that MUST NOT tear down. Anti-patterns to forbid by name: feature-stop, app-background, screen-off, host wrist-down/lid-close, downstream-host disconnect.
4. **Invariants** — what's true at all times, independent of application state. At minimum:
   - "If paired AND present AND powered, link SHOULD be up."
   - "Subscriptions / capabilities are per-link, not per-feature-session."
5. **Reconnect policy** — backoff schedule, cap, termination condition. (Common: exponential 1s→60s cap, no attempt limit; "fast" schedule while user is actively engaged, "slow" schedule after N minutes idle.)
6. **Subscription lifecycle** — characteristics / endpoints / streams MUST be established per-link (on every successful connect), never per-application-session.
7. **Downstream-host optionality** — if the architecture has a tertiary host (phone behind watch, cloud behind phone), state explicitly whether it's required or "nice if present." Default to optional; routing peripheral I/O through a tertiary host promotes it to required by accident.

## How to Spot the Anti-Pattern

In code review, flag any of these:

- A `disconnect()` / `close()` / `release()` / `teardownTransport()` call inside an application-feature shutdown path (workout-stop, call-end, game-quit, document-close).
- A subscription / `addObserver` / `notify(true)` call inside an application-feature startup path. (Test: does this device have anything meaningful to report when no feature is active? If yes — battery, presence, errors — the subscription belongs to the link.)
- A code path that resubscribes characteristics from scratch on every feature-start. (Symptom: 2-5 second user-visible lag at feature start that "we just have to live with.")
- A tertiary-host code path on the critical path of any peripheral operation. (Test: kill the tertiary host. Does the primary host + peripheral still work fully? If no, the optionality contract is broken.)

## The Diagnostic Question

When you find a tear-down in an application-domain shutdown path, ask:

> **"Who else needs this resource after the application event?"**

If anyone — UI for post-feature dwell time, telemetry, user attention, another feature about to start — the resource is mis-scoped. Promote it to user-managed.

## Why Not Workout/Feature-Scoped?

The recurring temptation is "save battery / radio time by disconnecting when the feature ends." This is almost always wrong:

- **Reconnect cost dominates idle-link cost.** A full handshake (scan, connect, discovery, gate, subscribe) typically burns more energy than minutes-to-hours of idle GATT-connected link, and is user-visible lag.
- **User mental model: paired devices stay paired.** AirPods, Apple Watch, CarPlay, mice, keyboards — none tear down because an app closed. A peripheral that uniquely does so violates the principle of least surprise.
- **Real battery savings come from *rate throttling*, not *link teardown*.** Drop notification frequency in background; keep the link.

## Required Tests

- **No-teardown regression:** Assert peripheral remains connected after every application-feature shutdown path (stop, cancel, save, discard, error). One test per shutdown path.
- **Reconnect schedule:** Inject simulated drops; assert backoff matches policy and respects the cap.
- **Subscription idempotency:** Force multiple `.connected` transitions; assert all subscriptions are re-established each time, exactly once each.
- **Tertiary-host optionality:** Disable tertiary host entirely; assert all primary-host + peripheral operations still complete.

## Concrete Application: AR-Runner

- Peripheral: ActiveLook AR glasses (Engo 2) over BLE
- Primary host: Apple Watch
- Tertiary host (optional): iPhone
- Canonical contract: `.squad/decisions.md` → "ADR — BLE link to ActiveLook glasses is user-managed, not workout-scoped" (2026-05-19)
- Implementation reference: `ARRunnerWatch/Workout/WorkoutViewModel.swift` `confirmSave` / `confirmCancel` (rc17+)
- Related skills: `activelook-ble-adapter-pitfalls` (connect-path serialization), `dead-code-after-connect` (idempotency on reconnect)

## Heuristic Summary

> Peripheral lifecycle is owned by the user and physics. Application lifecycle is owned by features. They observe each other across a contract boundary; they never reach across it.
