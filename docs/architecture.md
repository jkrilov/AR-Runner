# AR-Runner Architecture

**Current as of v0.6.0.** For user-facing features see
[`../README.md`](../README.md). For build/CI ops see
[`dev/`](./dev/).

## Targets

| Target              | Platform | Role                                                          |
| ------------------- | -------- | ------------------------------------------------------------- |
| `ARRunnerWatch`     | watchOS 11+ | The primary runtime: HealthKit workout + BLE link to glasses. |
| `ARRunnerPhone`     | iOS 18+  | Optional companion: live mirror, map, Strava setup, settings. |
| `ARRunnerWidgets`   | watchOS + iOS | Smart Stack widget (launches into a run from the watch face). |
| `ARRunnerCore`      | Swift package | Shared, framework-free domain code. Linux-CI compatible.      |

The watch never depends on the phone for a workout. The phone degrades
gracefully when not reachable.

## State ownership

| State                              | Owner   | Mechanism                                |
| ---------------------------------- | ------- | ---------------------------------------- |
| Workout session + live metrics     | Watch   | `HKWorkoutSession` + `HKLiveWorkoutBuilder` |
| GPS route                          | Watch   | `CLLocationManager` → `HKWorkoutRouteBuilder` |
| BLE link to glasses                | Watch   | `CoreBluetooth` central (user-managed lifecycle) |
| HUD layout (baked presets)         | Core    | Static factories on `HUDLayout`          |
| Historical runs                    | HealthKit | Phone reads via Health sharing           |
| AR-specific run metadata           | Side-store | Keyed by `HKWorkout.UUID`                |
| Strava OAuth tokens                | Phone   | Keychain                                 |
| User preferences (units, etc.)     | Per-device `UserDefaults` (synced via WCSession) |

## Data flow

```
┌──────────────────────────────────┐
│        Apple Watch (primary)      │
│  ┌────────────────────────────┐  │
│  │  WorkoutController (actor) │  │  HK metrics + route
│  │   HKWorkoutSession         │──┼──▶  HealthKit
│  │   HKLiveWorkoutBuilder     │  │
│  │   CLLocationManager        │  │
│  └────────────┬───────────────┘  │
│               │ WorkoutMetric    │
│               ▼ (AsyncStream)    │
│  ┌────────────────────────────┐  │
│  │  HUD FrameBuilder          │  │
│  │  GlassesFrameTransport     │──┼──▶  ActiveLook glasses (BLE)
│  └────────────────────────────┘  │       (battery, status events
│               │                  │        flow back the same way)
│               ▼                  │
│  ┌────────────────────────────┐  │
│  │  WatchConnectivityService  │──┼──▶  iPhone (live mirror,
│  └────────────────────────────┘  │       map, settings, Strava)
└──────────────────────────────────┘
```

## Key abstractions in `ARRunnerCore`

- **`GlassesFrameTransport`** (protocol) — async BLE link abstraction.
  States: `disconnected | scanning | connecting | connected | reconnecting | failed`.
  Status events: `batteryLevel`, `signalQuality`, `dropped`, `reconnected`,
  `reconnectAttemptFailed`. Exponential reconnect backoff 1s → 8s, auto
  re-apply layout on reconnect.
- **`WorkoutController`** (actor) — wraps an `HKWorkoutSession` behind a
  `WorkoutHealthSubstrate` protocol so it's testable on Linux. Exposes
  `states` and `metrics` as `AsyncStream`s. Glasses disconnect signals
  never auto-pause the workout (binding decision D4).
- **`WCMessage`** envelope — every WCSession payload is a versioned
  Codable struct with `schemaVersion: Int`. Receivers must handle unknown
  versions gracefully (log + ignore, never crash).
- **`HUDLayout`** — 2–3 curated layout presets baked at build time. The
  phone picks between presets; the editor is deferred to v1.
- **`ARMetadataStore`** — side-store of AR-specific metadata
  (glasses-on-time, HUD layout used, disconnect gaps) keyed by HKWorkout UUID.

## BLE link to glasses (ActiveLook Engo 2)

- **Watch owns the link directly** — no phone tethering during workouts.
- **Link lifecycle is user-managed, not workout-scoped.** Workout state
  and BLE state are independent state machines. Stopping the workout
  doesn't disconnect; only an explicit user action does.
- **Write serialization:** writes serialize via the `didWriteValueFor`
  callback (CheckedContinuation). A flow-control gate waits for
  `isNotifying == true` on the flow-control characteristic before sending
  commands; 2s safety timeout.
- **Reconnect:** if the link drops mid-run, a subtle haptic fires, the
  HUD displays "offline", and the watch auto-reconnects in the background.
  The disconnect gap is logged in the run's AR metadata.
- **Engo 2 display:** 15-level grayscale (amber on black). All HUD design
  uses intensity levels 0–15 — no color.
- **Lens-flip formula** (Engo 2 wears the display rotated): coords are
  flipped via `x_wearer = 303 − x_fb`, `y_wearer = 255 − y_fb`, with
  rotation=4 (`topLR`). All coords must stay in `0..303 × 0..255` (off-screen
  is silently clipped).
- **Battery:** subscribe to the standard BLE battery service (0x180F),
  notify every 30s; forwarded to the phone via WCSession for display.

## Strava integration (v0.5)

- **OAuth endpoint:** `https://www.strava.com/oauth/mobile/authorize`
- **Redirect URI:** `arrunner://ar-runner.app/callback`
- **Authorization Callback Domain** (Strava settings): `ar-runner.app`
- **Dual-path:** try `strava://` deep link first (`canOpenURL`), fall back
  to `ASWebAuthenticationSession`. Requires
  `LSApplicationQueriesSchemes: [strava]` in `project.yml`.
- **Token exchange** runs through a small Cloudflare Worker
  (`strava-auth-worker.jkrilov.workers.dev`) so the client secret never
  ships in the app binary.
- **Upload:** after a workout ends, the phone uploads the GPX-equivalent
  route + summary to Strava if the user is connected.

## Locked decisions

The decisions ledger in `.squad/decisions.md` is the source of truth.
The most load-bearing entries:

- **D1** Watch owns BLE to the glasses directly.
- **D2** watchOS 11 / iOS 18 minimums; Swift 6 strict concurrency.
- **D3** Running-only in v0.x, but the core data models are sport-agnostic.
- **D4** Glasses disconnect mid-run: workout continues uninterrupted.
- **D5** Phone is never a workout-time requirement.
- **D6** 2–3 baked HUD layout presets; layout editor deferred to v1.
- **D7** Action Button does foreground launch (matches native Workout app).
- **D8** Swift 6 strict concurrency from day one.
- **D9** HealthKit + side-store in v0.x; CloudKit user config in v1.
- **Phone is NEVER a requirement** (user directive, 2026-05-19).
- **Auto-release to TestFlight** after CI green (user directive, 2026-05-19).
