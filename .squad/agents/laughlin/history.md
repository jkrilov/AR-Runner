# Laughlin — History (Compacted 2026-06-20)

## Core Context

- **Project:** Apple Watch fitness app + ActiveLook AR glasses integration
- **Role:** watchOS Dev
- **Joined:** 2026-05-14

## Current Work — v0.6 Complete (Multi-Sport + Custom HUD)

### 2026-06-19 — v0.6.5 SHIPPED: Compass + Variable Grid + Editor Icons
PR #132 merged, tagged v0.6.5-1, TestFlight run 27856318322.

**Three features:**
1. **Compass metric** — MetricKind.heading (9th selectable slot). Sourced from CLHeading (magnetometer, indoors-capable, GPS-free). Watch only spins up when layout has .heading slot. Format: 8-point cardinal + degrees ("NE 045°", pure Core ormatHeading). All WorkoutTypes valid. Throttled integer-degree bucketing.
2. **Variable grid** — HUDGridConfig { lines: [Int] } (2–4 lines, 1–2 items each). Optional HUDLayout.grid (nil → legacy [2,1,1] byte-identical to v0.6.4). All pixel geometry in code via HUDGridDefinition.make(for:), never user-editable (regression firewall). Non-[2,1,1] coords marked // TODO(bench) for Engo 2 calibration.
3. **Editor icons** — SF Symbols in phone preview: full-strength for glasses-backed metrics (duration/HR/distance/pace), muted for text-only (speed/cadence/energy/elevation/heading). Line-count/items-per-line controls.

**Verification:** 359 Core tests green (Linux, Swift 6). App-target compiles (4-scheme CI matrix). Exhaustive MetricKind switches forced (caught 2 test-helper gaps). HUDGridConfig Hashable.

**Outstanding:** non-[2,1,1] grid coords EXTRAP, marked for bench validation before releasing to users. Highest-risk: 2-line big-fonts (ALL unbenched), 2-item collisions, 4-line crowding (26px gaps).

## v0.5 Releases (Archived 2026-05-20—2026-05-27)

v0.5.1–v0.5.20: Strava OAuth + TCX + Uploader + Action Button + Appearance. Key fixes: process isolation (AppGroup), wrong API surface (StartWorkoutIntent), missing framework link (AppIntents), dialog message/SemVer bugs. See decisions.md for ADRs.

## Core Learnings (v0.6 Journey)

1. **Lifecycle independence:** Workout end ≠ BLE disconnect; state machines are independent.
2. **Copy audit:** On behavior fixes, scan all user-facing strings (copy is behavior contract).
3. **Schema evolution:** Optional Codable fields + version bump = mixed-version safe (no migration).
4. **Non-terminal states need drivers:** Adding a state without an autonomous advance path creates stalls.
5. **CheckedContinuation always needs timeout guard:** No timeout = latent hang.
6. **Persist-after, not before:** Persist-before-awaiting bypasses atomicity guarantees (dangerous).
7. **Keep pixels in code, shape in model:** Geometry stays in Core code (validated tests); only layout shape is Codable/synced.
8. **Exhaustive switches catch CI-only failures:** Test helpers too; always swift test (Linux builds force every switch).
9. **Thread flags without protocol changes:** setNeedsHeading(_:) substrate method with default no-op, called at VM level before controller.start() (doesn't touch Core protocol or mocks).
10. **Pure formatting = testable:** ormatHeading in Core, sourcing in watch shell; trueHeading preferred, magneticHeading fallback.

## Test Status

- **ARRunnerCore:** 359/359 pass (v0.6.5, 1 skipped)
- **ARRunnerPhone:** 39/39 pass (Strava tests)
- **ARRunnerWatch:** Build green (CI-gated validation)

## Next

On-device bench validation for non-[2,1,1] grid configs before releasing multi-line layouts to users. 2-line font-5 optional follow-up. Phase C (future): CloudKit cross-device sync + custom icon upload.
