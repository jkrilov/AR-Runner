# Skill: Phone-Optional Companion App QA Pattern

**Author:** Amber (QA & Fitness Domain)
**Established:** 2026-05-19

## Problem

A wearable (watch / glasses / sensor) integrates with a companion phone app. The companion is **enhancement**, not requirement: every feature must work fully when the phone is off, in airplane mode, rebooting, or has never been paired. It is easy to write code where `session.isReachable == false` quietly becomes a gate rather than a transport hint — the bug only surfaces in the field when the user leaves their phone at home.

## The three-state test matrix

Every feature that *touches* the companion must be tested in **three** companion states, not two:

| State | How to reproduce | Why it differs from the others |
|---|---|---|
| **Reachable** | Phone foregrounded, BT on, near watch | Happy path; `sendMessageData` works |
| **Unreachable but present** | Phone in airplane mode, or backgrounded out of range | `isReachable == false` BUT the WC framework is still alive on the phone side and may reactivate |
| **Absent** | Phone powered off entirely (or never paired) | The OS-level peer doesn't exist; queued transfers may pile up; reachability callbacks never fire |

The third state is the load-bearing test. **Reachable** and **unreachable** must be **indistinguishable** to watch-side code; **unreachable** and **absent** must be **indistinguishable** to *behavior* (the user must not be able to tell which one is happening).

## Diagnostic anti-test

Declare the phone permanently absent. Run an **entire** end-to-end feature cycle from the wearable. **Any** of the following is a bug, regardless of which feature surfaces it:

- A "waiting for phone" indicator that doesn't time out
- A retry/backoff spinner visible to the user
- A feature gracefully "off" that should work standalone
- A code path that throws because the peer never replied
- Tick / frame cadence stuttering at the moment phone-state changes

## Required wiring checks

1. **No `guard isReachable else { return }` in feature code.** Reachability is a *transport hint* for the WC layer, never a gate on user-facing functionality. A grep for `isReachable` outside the WC transport file is a code smell.
2. **WC send must be non-blocking.** Test with a fake `WCSession` whose send never returns; assert the timer / animation / UI keeps running. If the wearable freezes when the phone freezes, the wearable is not standalone.
3. **Transport-tier selection per data class.** See sibling skill `wcsession-three-tier-delivery`:
   - **Latest-only telemetry** (battery %, current pace) → `updateApplicationContext`. Doesn't queue; doesn't grow unbounded; survives phone reboot with last value.
   - **Lifecycle / cannot-lose events** (workout started, workout ended) → `transferUserInfo`. FIFO queue.
   - **Live high-frequency reachable-only** (1 Hz ticks while peer is foregrounded) → `sendMessageData`. Drops silently if unreachable — that's fine, the latest-only tier catches the next one.
4. **Phone activation = read latest-only contexts, don't wait for a notification.** When the phone app comes back online after a long offline window, it should pick up the last `applicationContext` immediately and render; falling back to "—" until the next 30 s notification arrives is acceptable, displaying a 5-minute-old `transferUserInfo` payload is not.

## Bench-test scenarios (template)

For each companion-touching feature `F`, add at minimum:

- `F-phone-off`: full feature cycle with phone powered off. Pass criteria: identical to phone-on cycle.
- `F-phone-airplane`: full feature cycle with phone in airplane mode. Pass criteria: identical to phone-on cycle.
- `F-phone-reboot-mid`: trigger `F`, reboot phone mid-cycle, complete `F`. Pass criteria: no stall at the moment of disappearance, no retry storm at the moment of return.
- `F-phone-returns`: complete `F` with phone offline; bring phone online; foreground phone app. Pass criteria: phone shows the latest known state within a defined SLO (e.g., 3 s for `applicationContext`-backed data).

## Unit-test recommendations (companion-touching code)

- **Non-blocking send:** inject a fake session that never returns; assert callers do not block.
- **Tier routing:** call the send function for each data class with mock sessions in each reachability state; assert which transport path was chosen.
- **No reachability gate in feature code:** snapshot test that with `isReachable = false`, the feature's observable state matches `isReachable = true`.
- **Phone activation handler:** simulate `didReceiveApplicationContext` with a payload → assert UI renders. Simulate activation with no payload → assert UI shows placeholder, not crash.

## Common failure modes (and what they tell you)

| Symptom | Likely cause |
|---|---|
| Watch UI stutters when phone airplane-modes mid-workout | WC send is on the timer's critical path (await blocking) |
| Phone shows a 5-minute-old battery value forever | Telemetry routed through `transferUserInfo` instead of `updateApplicationContext` |
| Phone shows blank for 30 s after returning online, then updates | No `applicationContext` published — phone is waiting for next notification only |
| Feature appears "off" when phone is absent | A `guard isReachable` somewhere in feature code |
| Hundreds of pending transfers after a 5-min offline window | High-frequency data was queued instead of latest-only |
| Watch crashes when phone never replies | WC `replyHandler` callback unwrapped or assumed |

## When to reuse

Any project where:
- Wearable + companion phone (Apple Watch + iPhone; Wear OS + Android phone; sensor + phone)
- Companion is enhancement, not requirement
- Multi-transport messaging exists (WC, Bluetooth GATT mirror, BLE+phone bridge)

The pattern is transport-agnostic; substitute Bluetooth / WebSocket / gRPC peer for `WCSession` and the same three-state matrix and same wiring checks apply.

## Cross-references

- `wcsession-three-tier-delivery` — implementation of the transport-tier selection this skill validates.
- AR-Runner decisions: 2026-05-19T18:20 user directive ("the phone can't be a requirement") and `amber-rc17-qa-scenarios` §D.
