# Skill: Terminal-Path Data-Leak QA Pattern

**Author:** Amber (QA & Fitness Domain)
**Established:** 2026-05-20
**Origin:** AR-Runner rc1 — `confirmCancel` shared code with `confirmSave`, so "discarded" workouts still landed in Apple Fitness/Health.

## Problem

A workflow has **two or more terminal paths** that should produce **mutually exclusive** persistent side effects:

- Save vs. Discard
- Submit vs. Cancel
- Publish vs. Draft-and-close
- Send vs. Delete-draft
- Commit vs. Rollback

When the implementation conflates them — by sharing a "cleanup" helper, by leaving a write call on the "wrong" branch, or by writing optimistically and forgetting to undo on cancel — the **destructive-looking** path silently keeps data. The user believes they discarded; the system kept it. This is a **data-integrity / privacy class bug**, not a UI bug, and it does not surface in normal testing because the user is rarely auditing the persistence layer right after they discarded.

## Why this class of bug is hard to catch

1. **Asymmetry of user attention.** After Save, the user looks for their data. After Discard, the user looks away. The leak survives because nobody checks.
2. **Asymmetry of testing reflex.** "Did it save?" is in every test plan. "Did it *not* save when we said discard?" rarely is.
3. **Refactor amplifier.** A "extract common shutdown logic" refactor is the classic introduction vector. The two paths look symmetric in the editor; the asymmetry that *matters* is which persistence calls each one makes.
4. **Downstream amplification.** If the persisted artifact auto-syncs (HealthKit → Strava, Drafts → Sent folder, local DB → cloud), the discarded data becomes publicly visible. The data-integrity bug becomes a privacy incident.

## The bifurcation rule

**Each terminal path owns its own persistence verb. No shared helper may call either verb.**

```
confirmSave    → save()       [only save() — no discard()]
confirmCancel  → discard()    [only discard() — no save()]
```

Shared helpers may do **idempotent cleanup** (release timers, dismiss UI, log analytics) but must never touch the persistence boundary. If shared cleanup *needs* to know which path was taken, pass it as an explicit parameter or split it into two helpers.

## Required test set (the four invariants)

For any save/discard-style fork, the test suite must pin these four assertions. Failing to ship all four is the leading indicator of the bug class.

1. **Positive save:** `confirmSave` → spy records `save()` exactly once, `discard()` exactly zero times.
2. **Positive discard:** `confirmCancel` → spy records `discard()` exactly once, `save()` exactly zero times.
3. **No cross-call in shared helpers:** any shared cleanup helper, called in isolation, records zero saves and zero discards.
4. **Crash / force-quit during the confirmation prompt is equivalent to discard:** simulate process termination while on the confirm screen; assert no auto-save on next launch. (HealthKit, IndexedDB, Core Data, and many other stores auto-flush on suspend; "do nothing" is not a safe default.)

If the system has **secondary persistence builders** (e.g., HK route builder alongside the workout builder, attached files alongside a draft message), repeat all four invariants for each builder. The leak often hides in the secondary one because tests only cover the primary.

## Required bench checklist (downstream verification)

A unit test against the spy is necessary but not sufficient — the real bug surfaces at the actual persistence layer and at any auto-sync downstream. Bench must include:

1. **Primary store check.** Discard, then open the native data viewer (Health app, file system, DB inspector) and confirm no entry.
2. **Secondary artifacts check.** Discard, then query for any related child objects (routes, attachments, audit-log rows) and confirm no orphans.
3. **Auto-sync downstream check.** Discard, wait for any third-party integration's poll cadence (Strava: ≤15 min, etc.), confirm nothing appears externally. This is the privacy-incident gate.
4. **Sequential mix.** Discard one, save the next, confirm **only one** appears downstream. Catches "session never actually ended" bugs that conflate the two runs.
5. **Mid-stream discard.** Discard while data is actively flowing (HR samples, location updates, keystrokes). Catches builders that auto-flush partial state.
6. **Process-kill discard.** Force-quit during the confirmation prompt; relaunch; confirm no auto-promoted save.

## Anti-patterns (introduction vectors — grep for these in code review)

- A `defer { cleanup() }` block at the top of a terminal-path function where `cleanup()` calls any persistence verb.
- A `switch terminalChoice { case .save: ...; case .discard: ... }` where the **default** or fall-through calls save.
- A "safety net" `try? finishWorkout()` on the discard path "just in case" — this is exactly the bug.
- An optimistic-write pattern (`save eagerly, undo on cancel`) without a matched-pair test that proves the undo runs.
- A shared `private func teardown()` called from both terminal paths that touches the persistence layer at all.
- A persistence call in a deinit or scenePhase handler that fires regardless of which terminal path was chosen.

## When to reuse

Any system with **dual terminal paths over a persistent store**:

- Mobile fitness / health apps (HealthKit save vs. discard)
- Email / messaging clients (send vs. discard draft)
- Form-based applications (submit vs. cancel)
- Document editors (save vs. close-without-saving)
- Transactional systems (commit vs. rollback) — especially where rollback is implicit on path-not-taken
- Any wizard/multi-step flow where "Cancel" appears on the final step

The pattern is store-agnostic; substitute the relevant persistence boundary (HK, Core Data, file write, SQL transaction, HTTP POST) for the save/discard verbs and the same four invariants and bench checklist apply.

## Cross-references

- `phone-optional-companion-qa` — sibling QA skill (different problem class but same "test the negative path, not just the happy path" discipline).
- AR-Runner decisions: `amber-rc2-bench-feedback-qa` §D (the rc2 acceptance criteria that codify this skill on the AR-Runner discard path).
- AR-Runner rc1 (the regression that motivated this skill): `confirmCancel` shared `teardownTransport` / save-adjacent helpers with `confirmSave`, leaking discarded workouts to Apple Fitness and (downstream) Strava.
