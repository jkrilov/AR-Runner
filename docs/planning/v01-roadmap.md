# AR-Runner v0.1 Roadmap

Status as of 2026-05-14: foundation scaffolding + BLE feasibility spike landed on `feat/v01-foundation`. After this PR merges, the v0.1 implementation work begins.

## Locked decisions (see `.squad/decisions.md`)
- D1: Watch owns BLE directly to glasses
- D2: watchOS 11 / iOS 18 minimums
- D3: Running v0.1, sport-agnostic core models
- D4: Workout continues if glasses drop; subtle haptic alert
- D5: Watch-only mode supported (phone optional during runs)
- D6: 2–3 baked HUD layout presets in v0.1; editor in v1
- D7: Foreground launch (workout takeover, like Apple Workout)
- D8: Swift 6 strict concurrency from day one
- D9: HealthKit + side-store v0.1; CloudKit added in v1 for config

## v0.1 implementation work items (post-scaffold)

| # | Owner | Item | Depends on | Notes |
|---|---|---|---|---|
| 1 | 🕶️ Weiss | ActiveLook watchOS BLE wrapper | scaffold | Per `docs/research/activelook/watchos-ble-spike.md`. ~2–3 wks. Conforms to `GlassesFrameTransport` protocol from `ARRunnerCore`. Hardware testing on real Watch + glasses on Mac. |
| 2 | ⌚ Laughlin | `WorkoutController` actor real impl | scaffold | `HKWorkoutSession` + `HKLiveWorkoutBuilder` lifecycle. Foreground takeover UI. Auto-pause. Lock-screen behavior. |
| 3 | ⌚ Laughlin | `WatchConnectivityService` real impl (watch + phone) | scaffold | Implement the `WCMessage` contract: `layoutConfig` (phone→watch infrequent), `workoutTick` (watch→phone ~1Hz during run), `workoutLifecycle` events. Versioning. |
| 4 | ⌚ Laughlin | App Intents wired (Action Button + Smart Stack + Siri) | #2 | Per D7, foreground launch. Test each surface on real Watch. |
| 5 | ⌚ Laughlin | HUD layout presets (2–3) baked | scaffold | Use ActiveLook Config-Generator outputs (see Weiss's research). Static factory methods on `HUDLayout`. |
| 6 | ⌚ Laughlin | iPhone companion app live mirror | #3 | Live metric tiles, post-run summary. SwiftUI. |
| 7 | 🧪 Amber | Unit + integration tests | #1–#3 | `ARRunnerCore` unit tests; mock `GlassesFrameTransport` for workflow tests. Future: Linux CI lane for core. |
| 8 | 🕶️ Weiss | Glasses pairing UX (phone-side config cockpit) | #1 | Phone app discovers/pairs glasses, lists known devices, picks default HUD layout. |
| 9 | 🧪 Amber | Beta build + TestFlight | #1–#8 | Joe's own glasses + Watch for first real-run testing. |

## Open product questions (non-blocking)
- ActiveLook Visual Assets are CC BY-NC-ND — if AR-Runner is ever monetized, need original glasses graphics. Currently fine for personal/non-commercial use.
- Customizable HUD layouts → v1 (per D6).
- iCloud sync of preferences → v1 via CloudKit (per D9).

## Working agreement reminders
- No work on `main`. All changes via `feat/`, `spike/`, `fix/`, or `chore/` branches → PR → review → merge.
- Dev split: Windows for Squad-driven code generation + docs + reviews; Mac for build/simulate/test/deploy.
- Project files generated via `xcodegen generate`; never commit `.xcodeproj`.
- Squad runtime state in `.squad/` is part of the repo (decisions, agent history, orchestration log, session log all tracked).
