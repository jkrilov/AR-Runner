# Amber — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** QA & Fitness Domain
- **Joined:** 2026-05-14T18:30:31.658Z

## Active Learnings

### 2026-05-16T20:36:00-04:00 — v0.2 P1.3 prereq: `MetricKind.energy` (commit 9571e23)

Laughlin's v0.2 audit flagged that `HealthKitWorkoutSubstrate.metric(for:)` was mapping `.activeEnergyBurned` → `WorkoutMetric.kind = .duration` because Core's `MetricKind` enum had no kcal case. Downstream consumers (HUD formatters, controller `ingest`) default-coalesce `.duration` so live HK kcal was being silently dropped on the wire — the saved `HKWorkout` still had it (Laughlin reads it directly in `end()`), but the per-tick "flame" reading only ever showed the local `EnergyAccumulator` estimate. Added `.energy` as a new `MetricKind` case (kcal, mirrors HK units). Laughlin's Phase B work will retarget the HK adapter to emit it.

Bug pattern (file under "Core enum gaps → silent downstream drop"):

- **A `String, Codable, CaseIterable` enum that's missing a case isn't a compile error at the producer site.** The producer just picks the "closest" wrong case (here `.duration`) and the type system has no way to flag it. Downstream switches with a default branch (or `case .pace, .duration: break` collapses) then silently coalesce. The bug only manifests as "the UI never updates" — there's no log, no crash, no warning.
- **Defence:** every time a substrate / adapter writes `WorkoutMetric.kind = .X` for a HealthKit / sensor source, the test target should have a unit test that round-trips a representative value AND asserts the kind matches what the spec says — not just that *some* metric arrived. Worth adding to the substrate test plan when Laughlin's HK adapter lands.
- **Where the enum lives** (for future test authors): `ARRunnerCore/Sources/ARRunnerCore/Models/WorkoutMetric.swift`. Tests: `ARRunnerCore/Tests/ARRunnerCoreTests/WorkoutMetricTests.swift`. NOT under `Packages/` — the repo layout uses a top-level `ARRunnerCore/` SwiftPM package, not the more common nested-`Packages/` form. Task brief had it nested; the search above (`find . -name WorkoutMetric*`) is the reliable locator.
- **Exhaustive-switch sweep is mandatory after adding an enum case.** Adding `.energy` broke compile in two test helpers (`formatMetricImpl` in `WorkoutControllerIntegrationTests`, `formatMetricForResilience` in `DisconnectResilienceTests`) — both had exhaustive switches without default. Also touched `WorkoutController.ingest(metric:)` (folded `.energy` into the no-op `.pace, .duration` arm — controller doesn't track accumulated kcal state; that's substrate territory). The compiler caught every site; ran `swift test` to confirm. 80/80 (1 skipped, the pre-existing v0.2 #5 skip).
- **Test contract added two assertions for the new case:** (a) `MetricKind.allCases.contains(.energy)` + Codable round-trip with `unit = "kcal"`; (b) `MetricKind.energy.rawValue == "energy"` to lock the JSON / WC-payload key (would otherwise silently break already-shipped watch↔phone decode if someone renames it). Pattern: when adding a string-backed Codable enum case, *always* lock the rawValue in a test, especially if it crosses a process boundary (WCSession, persisted JSON, BLE payload).

## Archive

See `history-archive.md` for learnings from 2026-05-14 through 2026-05-15 (scaffold validation, multi-agent merge, anticipatory contract tests, Linux CI debugging).
