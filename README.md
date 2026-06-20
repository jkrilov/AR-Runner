<p align="center">
  <img src="Assets/AppIcon/AppIcon-1024.png" alt="AR-Runner app icon" width="160" />
</p>

<h1 align="center">AR-Runner</h1>

<p align="center">
  <img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" />
  <img src="https://img.shields.io/badge/status-v0.6.4%20(TestFlight%20beta)-brightgreen.svg" alt="Status" />
</p>

A running app for **Apple Watch** that drives a live heads-up display on
**[ActiveLook](https://www.activelook.net) AR glasses (Engo 2)**. Glance at
your time, heart rate, distance, and pace right in your field of view — no
need to look down at your wrist.

The watch is the primary device. The phone is optional.

## ✨ Features

- **Live AR HUD on your glasses** — elapsed time, heart rate, distance, and
  average pace, updated in real time as you run.
- **Multiple workout types** — outdoor and indoor run, walk, and bike,
  selectable on the watch or phone with a configurable default. Cycling shows
  speed; runs and walks show pace, and each type gets a sensible default HUD
  layout.
- **Custom glasses HUD layouts** — build your own 4-slot HUD layouts in the
  iPhone app, choose which metrics appear where, preview them, and assign a
  default layout per workout type. Changes sync to the watch and apply on your
  next run.
- **Metric or imperial units** — pick your preferred units in the phone app;
  the watch UI and the glasses HUD both follow your choice.
- **Icons for quick scanning** — every metric is paired with an icon so you
  can read your stats at a glance, mid-stride.
- **Live route map** — your GPS trace draws in real time on the watch and on
  the iPhone companion, with a follow-mode that keeps your current position
  centered.
- **Splits on demand** — press the Action Button (or tap the splits control)
  to mark a manual split; the HUD briefly flashes your last split's pace.
- **Pause overlay** — pausing surfaces a clear overlay on the watch and a
  matching "PAUSED" indicator on the HUD so you always know the workout's
  state.
- **Glasses battery monitoring** — the watch subscribes to the glasses' BLE
  battery characteristic and surfaces the level on the phone companion.
- **Persistent finish screen** — when you tap Finish, your time and distance
  stay up on the glasses until your next workout.
- **HealthKit workout recording** — runs are saved as standard workouts in
  the Health app, with a GPS route, just like the built-in Workout app.
- **Strava integration** — connect your account once and finished runs upload
  automatically (including the route).
- **Run history with date filter** — browse past runs in the iPhone app,
  filtered to the last 30 days by default (or 60, 90, 365 days, or all time),
  with per-run Strava upload status and manual upload/retry.
- **Action Button support** *(Apple Watch Ultra)* — start a workout, mark
  splits, and pause or resume without touching the screen.
- **Smart Stack widget** — launch straight into a run from your watch face's
  Smart Stack.
- **iPhone companion (optional)** — mirrors live metrics, route map, and
  glasses battery on a bigger screen; also hosts Strava setup and HUD
  preferences. Phone is never required for a workout.

## 📋 Requirements

- **Apple Watch** running watchOS 11 or later
  - Apple Watch Ultra recommended for Action Button support
- **ActiveLook-compatible AR glasses** (tested with [Engo 2](https://engoeyewear.com))
- **iPhone** running iOS 18 or later — *optional*, only needed for the
  companion app and Strava setup

> AR-Runner is currently in **TestFlight beta**. Join the beta to install.

## 🚀 Getting Started

1. **Install from TestFlight** — request access and install AR-Runner on
   your Apple Watch (and optionally your iPhone).
2. **Pair your glasses** — open the watch app, put your Engo 2 in pairing
   mode, and tap your glasses in the list. You only need to do this once.
3. **Start a run** — tap Start (or press the Action Button on Ultra). The
   HUD lights up on your glasses automatically.
4. **Finish when you're done** — tap Finish. Your time and distance stay on
   the glasses, the run lands in Health, and uploads to Strava if connected.

## 🛠 For Developers

Want to build from source or contribute? Start here:

- [Build from source](docs/dev/setup.md)
- [Architecture overview](docs/architecture.md)
- [CI workflows](docs/dev/ci-workflows.md)
- [TestFlight release setup](docs/dev/testflight-setup.md)
- [Contributing guide](CONTRIBUTING.md)

**Stack:** Swift 6 / SwiftUI, HealthKit, MapKit, CoreLocation,
WatchConnectivity, CoreBluetooth (via the ActiveLook iOS SDK). The codebase
is one watchOS app (`ARRunnerWatch`), one iOS companion (`ARRunnerPhone`),
a shared Swift package (`ARRunnerCore`), and a widget bundle
(`ARRunnerWidgets`). Project files are generated from `project.yml` via
XcodeGen — the `.xcodeproj` is gitignored.

## 📄 License

Apache 2.0 — see [LICENSE](LICENSE).

---

<sub>AR-Runner is built by a small AI team coordinated with
[Squad](https://github.com/bradygaster/squad).</sub>
