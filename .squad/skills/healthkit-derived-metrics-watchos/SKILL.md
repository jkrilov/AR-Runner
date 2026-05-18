# Skill: HealthKit derived metrics on watchOS

**Class:** trap + pattern
**Surface:** `HKLiveWorkoutBuilder` ↔ SwiftUI in-run display
**First learned:** 2026-05-18 (Joe's v0.2.0 device test feedback)
**Owner:** laughlin

## The trap (cumulative vs sample)

`HKLiveWorkoutBuilder.statistics(for:)` exposes two readings that look
interchangeable in autocomplete but mean very different things:

| Method                          | Returns                                  | Right for…                                     |
| ------------------------------- | ---------------------------------------- | ---------------------------------------------- |
| `stats.mostRecentQuantity()`    | the latest individual sample value       | instantaneous (`heartRate`)                    |
| `stats.sumQuantity()`           | cumulative sum since `beginCollection`   | cumulative (`distance*`, `activeEnergyBurned`) |
| `stats.averageQuantity()`       | mean across the session                  | average metrics on summary                     |

The substrate originally used `mostRecentQuantity()` for everything.
The watch UI bound to that and showed distance "jumping around" — each
new sample (a few meters) was being rendered as if it were the total.
Joe caught it on his first real-world run.

**Rule:** for any cumulative HK quantity type, always source the live
value from `sumQuantity()`. `mostRecentQuantity()` is for
instantaneous-state metrics only (heart rate, current cadence, current
power). When in doubt, check Apple's "Cumulative" vs "Discrete"
classification on the quantity type's documentation page.

## The pattern (derived metrics in pure Core)

HealthKit does **not** store derived metrics like avg pace. You must
compute them: `secondsPerMile = elapsedSeconds / distanceMiles`. Two
non-obvious requirements:

1. **Guard against divide-by-zero.** A run that has just started has
   `distanceMiles == 0`; naive division gives `+inf`, formats as
   `"inf:00/mi"`, looks broken on-wrist. Return a placeholder
   (`"--:--/mi"`) instead.
2. **Guard against the first-sample spike.** Even after the first
   distance sample lands (say 5m in 8s), naive pace is wild (~42:00/mi)
   and the on-watch number flickers for the first few seconds. Use a
   small distance threshold (e.g. `>= 0.01 mi`) before showing a
   number. Below the threshold, keep the placeholder.

Put the helper in **`ARRunnerCore`**, not the watch target. The watch
test scheme has no good Linux/macOS test host, but Core does — pure
formatters live in Core and get full `XCTest` coverage there. See
`RunMetricFormatting` + `RunMetricFormattingTests` for the canonical
pattern (covered: meters-to-miles, 2-decimal mile formatting, pace
MM:SS + H:MM:SS branches, divide-by-zero, first-sample spike,
non-finite inputs).

## Quick checklist before binding a HK metric to SwiftUI

- [ ] Is this metric **cumulative** or **instantaneous**? Pick
      `sumQuantity()` vs `mostRecentQuantity()` accordingly.
- [ ] Is the display unit different from the HK storage unit? Convert
      at the formatter boundary (`HKUnit.mile()` on the substrate side,
      or a pure Core helper if no HK types should leak into the view).
- [ ] Is this a **derived** metric (pace, splits, calories/hour)? Build
      a pure Core formatter with explicit guards for the
      run-just-started case, and unit-test it in `ARRunnerCoreTests`.
- [ ] Does the view re-render on metric updates? Confirm the
      view-model's `apply(metric:)` actually mutates the published
      property the view reads — silent stream subscriptions that never
      update state are a recurring bug class.

## Related

- `.squad/skills/healthkit-error-7-preflight-diagnostic/SKILL.md` —
  authorization-side traps with the same builder.
- `.squad/decisions/inbox/laughlin-watch-display-feedback-fixes.md` —
  the v0.2.0 device-feedback decision that produced this skill.
