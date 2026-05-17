# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings

(See history-archive.md for learnings from 2026-05-14 through 2026-05-15.)

## 2026-05-16T20:25:00-04:00 — watchOS code-health audit (Opus 4.7-1m re-spawn)

Joe asked all three of us (Richards/me/Weiss) for a fresh 2026 look. Re-spawn on Opus 4.7-1m; overwrote prior claude-sonnet-4.6 audit at `.squad/audits/2026-05-16-laughlin-watchos.md` (intentional per Joe).

**Two real bugs found:**

1. `HealthKitWorkoutSubstrate.metric(for:)` maps `.activeEnergyBurned` to `WorkoutMetric.kind = .duration` (HealthKitWorkoutSubstrate.swift:271-272). Downstream `WorkoutController.ingest` and `WorkoutViewModel.apply(metric:)` both default-case `.duration` → live HK kcal is silently dropped. Saved summary still works because `HKWorkout.totalEnergyBurned` is read directly in `end()`, but the live "flame" metric only shows the local `EnergyAccumulator` estimate. Needs an `.energy` (or `.activeEnergy`) case in `WorkoutMetric.MetricKind` — that's an Amber-owned Core model edit.
2. `StartWorkoutIntent.perform()` (`ARRunnerWidgets/StartWorkoutIntent.swift:11-14`) is a TODO. The widget Start button foregrounds the app but lands on idle WorkoutView — v0.2 Story 1 acceptance ("start from Smart Stack widget") is not actually met. Needs deep-link routing.

**Latent bug:** `switch type { case HKQuantityType.quantityType(forIdentifier:): }` does optional-pattern unwrap against non-optional `type` — works today, silently no-ops if Apple ever returns nil. Better idiom: switch on `type.identifier` string.

**Modernization items (all S effort):**
- `Task.sleep(nanoseconds: 1_000_000_000)` → `.sleep(for: .seconds(1))` in three tickers.
- WidgetKit `TimelineProvider` callback form → async / `AppIntentTimelineProvider`; set policy `.never` while entry is static (currently burning 30-min refresh budget for a constant entry).
- `WorkoutController.metrics` is `.unbounded` — switch to `.bufferingNewest(64)` for live-only data.

**Things that are clean:** zero force-unwraps in app code, zero `try!`, no `ObservableObject`/`@StateObject`/`NavigationView` legacy, `@Observable` used correctly on both view-models, all three `@unchecked Sendable` usages justified (NSObject delegates + lock-protected mutable state), WCSession three-tier delivery matches the skill. Strict-concurrency hygiene from D8 is holding.

**Drop:** considered filing an inbox decision but the energy-routing fix is a Core model change (Amber) and the App Intent stub is mine to schedule — no cross-agent ADR needed. Will tackle both in v0.2 closure work.

### 2026-05-16 — watchOS / Swift / HealthKit Code-Health Audit

**Task:** Full read-only audit of all Swift sources (Watch, Phone, Core, Widgets).

**Key findings:**
- `HKWorkout.totalDistance` + `.totalEnergyBurned` are deprecated iOS 17 / watchOS 10. Still present at `HealthKitWorkoutSubstrate.swift:193–194`. Migration target: `HKWorkout.statistics(for:).sumQuantity()`.
- `activeEnergyBurned` HK sample emitted as `MetricKind.duration` — wrong kind. `MetricKind` has no `.energy` case. Currently silent (view-model ignores it) but will corrupt any future `.duration` consumer.
- `observedMetrics: [WorkoutMetric]` in `WorkoutController` grows without bound and is never read in `makeSummary`. Dead code + memory sink for long workouts.
- `AsyncStream.makeStream()` (Swift 5.9+) should replace `var cont: ...!` pattern — 4 sites across Watch and Core.
- `Task.sleep(nanoseconds:)` — 5 sites; `Task.sleep(for: .seconds(1))` is the modern form and is injectable with a custom `Clock`.
- `TimelineProvider` in widget should migrate to `AppIntentTimelineProvider` (watchOS 10+ preferred API).
- `xcodeVersion: '16.0'` in `project.yml` is stale; should be `'17.0'` for 2026.
- No `ObservableObject`, no `@Published`, no `NavigationView`, zero force-unwraps in production — SwiftUI / concurrency fundamentals are clean.
- Decision drop: `.squad/decisions/inbox/laughlin-audit-hk-deprecated-api.md` (deprecated HK API + MetricKind.energy).
- Audit deliverable: `.squad/audits/2026-05-16-laughlin-watchos.md`.
