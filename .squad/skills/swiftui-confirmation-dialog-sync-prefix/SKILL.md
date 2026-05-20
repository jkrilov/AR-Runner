# Skill: SwiftUI `confirmationDialog` Synchronous-Prefix Pattern

**Author:** Laughlin (watchOS Dev)
**Established:** 2026-05-20
**Origin:** AR-Runner rc4 — discard tap returned the wearer to the live workout screen instead of the start screen, because the `confirmationDialog`'s dismissal binding raced the Discard Task and auto-spawned `resumeFromFinish()`.

## Problem

`SwiftUI.confirmationDialog` (and `alert`, and `.sheet` with `isPresented:`) fires TWO things synchronously in the SAME runloop tick when the user taps an action button:

1. The Button's `action:` closure executes.
2. The `isPresented` binding receives `set(false)` to dismiss the dialog.

When the Button action schedules async work (`Task { await viewModel.someAction() }`), the Task body has NOT executed by the time the binding setter runs synchronously next. If the binding setter has a state-gated side effect — a common pattern for recovering from stray tap-out dismissals — that side effect fires UNINTENTIONALLY on explicit-choice taps too, because the gated state hasn't changed yet.

In AR-Runner's case the side effect was "if `launchState == .pendingFinish` and the dialog is being dismissed, the user must have tapped outside — auto-resume the workout." The auto-resume is correct for swipe-dismiss but catastrophic for explicit Discard: it races the discard task and overwrites the final `.idle` state with `.running`.

## Why this class of bug is hard to catch

1. **Sync→async refactor silently breaks the invariant.** The pattern works when buttons synchronously mutate view-model state. Convert the buttons to `Task { await viewModel.action() }` and the invariant is gone — no compiler warning, no test failure (the SwiftUI binding ordering isn't reachable from a unit test that doesn't render the dialog).
2. **The first symptom is delayed.** The race only manifests on whichever specific terminal action carries observably-broken UI consequences. Save also races, but the post-save `.ended` state is briefly correct and the running screen is rarely noticed in a save flow. Discard's symptom — stranded on the live screen — is much louder because the wearer fully expects to leave it.
3. **Unit tests rarely cover the boundary.** `WorkoutViewModel.confirmCancel()` in isolation behaves perfectly. The race lives at the SwiftUI ↔ view-model boundary, which most SPM test packages can't reach.
4. **MainActor isolation is mistaken for serialization.** Engineers reading `@Observable final class ViewModel` and `@MainActor func confirmCancel() async` assume the two tasks can't interleave. They can — at every `await` suspension point.

## The synchronous-prefix rule

**Every button action that schedules async work inside a `confirmationDialog` (or any presentation with a `set`-side-effect binding) MUST synchronously transition the view-model out of the gated state BEFORE scheduling the Task.**

```swift
// ❌ WRONG — race with the binding setter
Button("Discard", role: .destructive) {
    Task { await viewModel.confirmCancel() }
}

// ✅ CORRECT — sync pre-transition + async work
Button("Discard", role: .destructive) {
    viewModel.acknowledgeFinishChoice()   // sync — leaves .pendingFinish
    Task { await viewModel.confirmCancel() }  // async — does the real work
}
```

The view-model exposes a `@MainActor` sync helper:

```swift
/// Synchronously leave `.pendingFinish` so SwiftUI's
/// `confirmationDialog` dismissal binding cannot observe the
/// pre-finish state on an explicit choice. Must be called from
/// the button action *before* scheduling the async terminal Task.
@MainActor
func acknowledgeFinishChoice() {
    if launchState == .pendingFinish {
        launchState = .ending
    }
}
```

The async terminal method (`confirmCancel`, `confirmSave`) idempotently re-asserts the transition on its first line, so direct callers (tests, future intents) get the same precondition without needing to call the sync helper.

The dismissal-binding setter retains its `launchState == .pendingFinish` guard — this is what distinguishes explicit-choice dismissals (state is now `.ending` → no auto-resume) from stray tap-out dismissals (state still `.pendingFinish` → auto-resume, correct UX).

## Diagnostic signature

You are looking at this bug if:

- A `confirmationDialog` button "appears to do nothing" or "leaves the user in the wrong state."
- Code inspection of the async action shows correct state writes (`launchState = .idle` etc.).
- Adding `print` statements shows the action runs, sets the right final state, AND ALSO shows a second action (often a `.cancel`-role resume) running in parallel.
- The dismissal binding has a state-gated side effect.

The fix is one-line per button.

## When the rule does NOT apply

- Dismissal binding has no side effects at all — `set:` is empty or only handles the closure's `isPresented` bool. The sync prefix is unnecessary (but harmless).
- The button's action is itself synchronous (rare in modern SwiftUI MVVM, but it does happen). No race possible.
- The `confirmationDialog`'s `isPresented:` is a `@State` bool with no view-model coupling. The two-tick gap doesn't matter.

## Code-review checklist

When reviewing a PR that adds or modifies a `confirmationDialog` / `alert` / `sheet`:

- [ ] Does the dismissal binding have a `set:` with side effects?
- [ ] If yes: do those side effects read view-model state?
- [ ] If yes: do the button actions schedule async work via `Task { await … }`?
- [ ] If yes: does each button action synchronously pre-transition the view-model out of the read state BEFORE the Task?
- [ ] Is the sync pre-transition idempotent (guarded on the gated state) so it's safe to call from non-dialog entry points too?
- [ ] Does the async terminal method also assert the transition (so direct callers work)?

If all six are yes, the dialog is race-free.

## Related patterns

- **`terminal-path-data-leak-qa`** — sister skill from rc2. That one ensures the DATA half of a terminal action is correct (Save persists, Discard doesn't); this one ensures the UI half (Save lands on `.ended`, Discard lands on `.idle`) actually sticks.
- **Bifurcated terminal paths** — both skills share the underlying principle: when a UI surface has multiple terminal outcomes, each path must own its full effect chain end-to-end, with no shared mutable state that the other path can race or clobber.

## Reusability

This pattern applies anywhere SwiftUI dispatches an `isPresented` binding's setter alongside a Button action's closure. Not Swift- or watchOS-specific in concept; the same race appears in any UI framework that fires "dismiss" and "button action" synchronously and where one of them schedules async work. On macOS and iOS the pattern is identical. For non-Apple UI toolkits the same diagnostic ("explicit choice ALSO runs the auto-dismiss recovery") applies — the fix is always "make the state mutation synchronous from the user's action."
