# HealthKit Series-Type Auth (workoutRoute, etc.)

**One-liner:** Every `HKSeriesType` you write through a *builder* (e.g., `HKWorkoutRouteBuilder`) needs its own entry in the share-auth set. Quantity types are not enough.

## When to reach for this skill

You're hitting any of these symptoms on watchOS:

- The CoreLocation permission prompt appears and the user grants it, **but** the resulting `HKWorkout` has no route polyline visible in Apple Fitness.
- Strava (or any auto-importer that reads route series) sees the workout but not the map.
- `HKWorkoutRouteBuilder.insertRouteData(_:completion:)` returns `success=true` for every insert, but `finishRoute(with:metadata:)` produces a route with `count == 0` (or the workout appears in Health without a map).
- Similar pattern on environmental audio exposure or any other future `HKSeriesType`.

If the symptom is "the prompt appears and CoreLocation is delivering fixes but the route never persists," **check this first**, before re-walking the CoreLocation wiring.

## The trap

`HKHealthStore.requestAuthorization(toShare:read:)` takes a `Set<HKSampleType>`. It's natural to fill it with the `HKQuantityType` instances you write (heart rate, distance, energy) plus `HKObjectType.workoutType()`. That's not enough for series data.

A workout-route is a separate sample type — `HKSeriesType.workoutRoute()` — and `HKWorkoutRouteBuilder.insertRouteData` silently accepts the buffer (the completion handler reports `success=true`) but **the route is never persisted** if the user hasn't granted share permission for the series type.

`finishRoute(with:metadata:)` returns an `HKWorkoutRoute` whose `count` is 0 (or the workout-Health association silently fails). Apple Fitness shows no map. The downstream Strava sync sees no route data and skips the auto-import.

The completion handler swallows the error param if you ignore it (`{ _, _ in }`), so production failures look like silent best-effort success. Pre-rc3 we did exactly this — every insert call looked fine in code review, and nothing surfaced in Console.app.

## The fix

Add the series type to your share set explicitly:

```swift
public static var sharedTypes: Set<HKSampleType> {
    var types: Set<HKSampleType> = [HKObjectType.workoutType()]
    if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
    if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
    if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
    types.insert(HKSeriesType.workoutRoute())   // ← REQUIRED for HKWorkoutRouteBuilder.insertRouteData to persist
    return types
}
```

`HKSeriesType` is a subclass of `HKSampleType`, so it fits directly into `Set<HKSampleType>`. Pair this with the Info.plist `NSLocationWhenInUseUsageDescription` string (separate concern — the CoreLocation grant) and the substrate's `CLLocationManager` wiring.

## And: stop swallowing the completion handler

Best-effort logging for a route insert is fine — a single transient I/O failure shouldn't take the workout down. But silent best-effort masks auth/config failures forever. Log the error param at `.error` level:

```swift
routeBuilder.insertRouteData(filtered) { success, error in
    if success {
        Logger.route.debug("insertRouteData OK — count=\(filtered.count)")
    } else {
        Logger.route.error("insertRouteData FAILED — error=\(String(describing: error))")
    }
}
```

And replace `try? await routeBuilder.finishRoute(with: workout, ...)` with an explicit do/catch that logs the error. `try?` makes auth failures permanently invisible.

## Diagnostic checklist (in order)

When a HealthKit-attached series doesn't persist:

1. **Series type in share-auth set?** (`HKSeriesType.workoutRoute()` for routes, etc.) ← Check first. This is the silent failure mode.
2. **Info.plist usage-string for the data source?** (`NSLocationWhenInUseUsageDescription` for routes; series-specific keys for other types.) Without it, the data source itself produces nothing.
3. **Builder lifecycle correct?** Create in `begin(...)`, feed throughout the workout, finalize *after* `HKLiveWorkoutBuilder.finishWorkout()` resolves with the persisted `HKWorkout`. (`HKWorkoutRouteBuilder.finishRoute(with:)` needs the workout sample to attach to.)
4. **Completion handlers logging errors?** Don't `{ _, _ in }` — log at `.error` with `privacy: .public` for non-PII fields.

## Citations

- `ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift` — `sharedTypes` includes `HKSeriesType.workoutRoute()`; `routeLog` traces; `ingest(locations:)`; `end(at:)` finishRoute do/catch.
- Apple docs: `HKWorkoutRouteBuilder` — "The user must authorize your app to save workout routes before you can save data with this builder."
- rc3 (2026-05-20) — Laughlin: route auth was the rc2 missing-route root cause; Info.plist + CoreLocation wiring were both correct but blocked at the persistence boundary.
- `.squad/skills/healthkit-derived-metrics-watchos/` — sibling skill on quantity-type derivation (sum vs. mostRecent). Series-type auth is a separate concern but related surface.
- `.squad/skills/hk-workout-route-builder-lifecycle/` — if present, complements this skill with the builder-lifecycle rules.
