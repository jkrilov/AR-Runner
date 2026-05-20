# Skill: HKWorkoutRouteBuilder Lifecycle on watchOS

**Author:** Laughlin (watchOS Dev)
**Established:** 2026-05-20 (rc2 — `v0.4.0-rc2`, in response to Joe's 5K bench: workouts arrived in Apple Health with HR/distance but **no route polyline**)

## When to use

You are building a watchOS app that runs `HKWorkoutSession` + `HKLiveWorkoutBuilder` and wants the resulting `HKWorkout` to carry a GPS route polyline (visible in Apple Health, exported via Health → Strava / other fitness platforms). Without the route builder the workout exists in Health but the map is empty and most third-party importers (Strava in particular) reject it.

## The pattern

Treat the route builder as **workout-scoped**, not session-scoped. It lives inside your `WorkoutHealthSubstrate`-style abstraction alongside the live builder and is wired into both terminal paths (save **and** discard) so route samples follow the same data-integrity contract as the workout itself.

### Required pieces

1. **`NSLocationWhenInUseUsageDescription`** in the watch's Info.plist. Without it, the system never prompts and `CLLocationManager` silently rejects every fix — `HKWorkoutRouteBuilder` stays empty.
   - **Gotcha (AR-Runner-specific):** if you use xcodegen, edit `project.yml`'s `targets.*.info.properties` block. Editing `Config/*-Info.plist` directly doesn't persist (Config/ is gitignored and regenerated).
2. **`CLLocationManager` configured for fitness:** `desiredAccuracy = kCLLocationAccuracyBest`, `activityType = .fitness`, `distanceFilter = kCLDistanceFilterNone` (report every fix so the polyline is dense).
3. **`HKWorkoutRouteBuilder` instance created in `begin(...)`** alongside the live builder, before `session.startActivity` so first-second fixes are captured.
4. **Location delegate** (separate `NSObject` class, weakly held by the substrate to avoid retain cycles) calls back into `substrate.ingest(locations:)`, which filters quality (`horizontalAccuracy >= 0 && <= 50`) and forwards to `routeBuilder.insertRouteData(_:)`.
5. **`end(at:)`** stops the location manager, finalizes the workout via `builder.finishWorkout()`, and **then** calls `routeBuilder.finishRoute(with: workout, metadata: nil)`. Order matters: `finishRoute` needs the persisted `HKWorkout` to attach to.
6. **`discard(at:)`** stops the location manager and calls `builder.discardWorkout()` — **must NOT call `finishRoute`**. Without the call, route samples drop with the builder. This is the discard-vs-save isolation extended to GPS data.

### Reference implementation sketch

```swift
private struct MutableState {
    var session: HKWorkoutSession?
    var builder: HKLiveWorkoutBuilder?
    var routeBuilder: HKWorkoutRouteBuilder?
    var startedAt: Date?
}

public func begin(sport: SportType, startedAt: Date) async throws {
    // … usual session + builder setup …
    let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
    state.withLock { mutable in
        mutable.session = session
        mutable.builder = builder
        mutable.routeBuilder = routeBuilder
        mutable.startedAt = startedAt
    }
    if locationManager.authorizationStatus == .notDetermined {
        locationManager.requestWhenInUseAuthorization()
    }
    locationManager.startUpdatingLocation()
    // …
}

public func end(at date: Date) async throws -> WorkoutHealthResult {
    locationManager.stopUpdatingLocation()
    session.end()
    try await builder.endCollection(at: date)
    let workout = try await builder.finishWorkout()
    if let workout, let routeBuilder {
        _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
    }
    // …
}

public func discard(at date: Date) async throws {
    locationManager.stopUpdatingLocation()
    session.end()
    builder.discardWorkout()
    // routeBuilder is intentionally NOT finished — samples drop with it.
}
```

## Gotchas

* **Info.plist key is mandatory.** Missing `NSLocationWhenInUseUsageDescription` → no prompt → CLLocationManager `authorizationStatus = .denied` → silent fix rejection. There is no runtime error to surface; the workout just persists without a route. **Always grep your Info.plist for the key after touching location code.**
* **Authorization must be `.whenInUse` (not `.always`).** Workouts are foreground sessions; `.always` triggers an extra prompt that users decline at higher rates.
* **Quality filter is non-optional.** Apple's HK route guidance: drop fixes with `horizontalAccuracy > 50 m` or negative (sentinel for "invalid"). Including them makes the polyline look like the wearer teleported.
* **finishRoute order matters.** Call it AFTER `builder.finishWorkout()` resolves. If the workout sample is nil (zero-length workout), skip finishRoute — there's nothing to attach to.
* **Test the negative side too.** A "GPS recording works" test that only checks the save path leaves the discard-side data leak open. Pin that `discard(at:)` does NOT call `routeBuilder.finishRoute` (assert by recording the substrate calls or by checking the route builder's state post-discard).

## Related

* **Skill `terminal-path-data-leak-qa`** (Amber, 2026-05-20) — same principle applied at the QA level: every terminal path with mutually-exclusive persistent side effects needs absence-of-call assertions, not just presence-of-call ones.
* **Skill `release-mechanics-bundle-bump`** (Laughlin, rc12+) — when a release adds an Info.plist key, the bundled-bump PR includes both the project.yml change AND the regenerated plist in the same commit so reviewers see the whole surface.

## When NOT to use

* Indoor workouts (gym, yoga) — set `HKWorkoutConfiguration.locationType = .indoor` and skip the route builder entirely. The location prompt is user-hostile if you can't actually use the GPS.
* Apps where the user explicitly opts out of route recording — gate the route builder on a UserDefaults preference; `begin(...)` can skip the `routeBuilder` allocation and the location manager start.
