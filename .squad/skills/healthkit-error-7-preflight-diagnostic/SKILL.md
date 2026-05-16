# HealthKit `Error(7)` pre-flight diagnostic

## Symptom

`HKLiveWorkoutBuilder` logs (often repeated dozens of times right after `Start`):

```
HKLiveWorkoutBuilder [XXXX]: (#wN) Failed to update target construction state:
  Error Domain=com.apple.healthkit Code=3
  "Unable to transition to the desired state from the Error(7) state (event 1)"
  Allowed transitions = {}
```

The builder lands in the terminal `Error(7)` state **on the first transition attempt** and refuses every subsequent transition. No data is collected. The workout session may also fail silently.

## What `Error(7)` actually means

`Error(7)` is HealthKit's catch-all "pre-flight failure" state. The builder enters it when `beginCollection(at:)` is called but one of the prerequisites is missing. `Allowed transitions = {}` is the telltale: there is no recovery path — the only fix is to satisfy the prerequisite and construct a fresh `HKLiveWorkoutBuilder`.

## Diagnostic order (cheapest → most invasive)

Walk these in order. The first one that's wrong is almost always the culprit.

1. **Authorization was never requested.** Search the codebase for `requestAuthorization(toShare:read:)`. If there are zero call sites, that's the bug — see fix below. Asking for it on first launch is required; the system prompt only appears once the app calls the API.
2. **Authorization was requested but not awaited before `beginCollection`.** A `Task { await healthStore.requestAuthorization(...) }` fired from `onAppear` will race a Start button tap. The Start path must `await` auth completion before constructing the substrate.
3. **Missing Info.plist usage strings.** Watch app needs `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`. Without them, `requestAuthorization` returns synchronously without prompting and the auth status stays `notDetermined` — HealthKit treats that as "denied" at `beginCollection` time.
4. **Missing entitlement.** The watch target must declare `com.apple.developer.healthkit = true` in its `.entitlements`. In XcodeGen this lives under `targets.<name>.entitlements.properties`. Without it, the bundle is rejected and no prompts ever appear.
5. **Type mismatch.** The auth request must cover every `HKQuantityType` the builder collects (and the workout type to write). A builder that publishes heart-rate samples but was authorized only for distance will Error(7) on first sample. Auth set for a running workout substrate:
   - **share:** `HKObjectType.workoutType()`, `heartRate`, `distanceWalkingRunning`, `distanceCycling`, `activeEnergyBurned`
   - **read:** same set
6. **Simulator HealthKit cache stale.** Rare. If everything looks right, `xcrun simctl erase <id>` and rebuild — the cached "denied" verdict from a previous run-without-entitlements survives reinstall.

## Canonical fix

Put authorization in two places:

1. **A static helper on the substrate** that returns once the system has answered:
   ```swift
   public static func requestAuthorization(
       healthStore: HKHealthStore = HKHealthStore()
   ) async throws {
       guard HKHealthStore.isHealthDataAvailable() else {
           throw WorkoutHealthSubstrateError.notAuthorized
       }
       try await healthStore.requestAuthorization(
           toShare: sharedTypes, read: readTypes
       )
   }
   ```
2. **Call it on app launch** via `.task` on the root scene so the system prompt fires before the user can tap Start:
   ```swift
   WindowGroup {
       NavigationStack { WorkoutView() }
           .task { try? await HealthKitWorkoutSubstrate.requestAuthorization() }
   }
   ```
3. **Call it again defensively from `begin(...)`** so a racy first-tap or a user who declined-then-changed-mind via Settings still gets a clean attempt. `requestAuthorization` is idempotent and effectively free once the system has a stored answer.

## Verification checklist

- `xcodebuild ... build` succeeds with no entitlement warnings.
- `xcrun simctl install <udid> ARRunnerWatch.app` succeeds (a bad entitlement string would fail here).
- First launch shows the HealthKit prompt; tapping Start after grant logs `HKWorkoutSession: state preparing → running` instead of `Error(7)`.
- `HKLiveWorkoutBuilder` begins emitting `didCollectDataOf` callbacks within ~3 seconds.

## Source

AR-Runner v0.2 (commit landing 2026-05-15) — discovered while wiring the real watch UI. The substrate's docstring said "authorization is the caller's responsibility" but no caller ever called it; the fix added `HealthKitWorkoutSubstrate.requestAuthorization` plus a `.task` on the root scene.
