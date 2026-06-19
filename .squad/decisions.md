# Squad Decisions

> **Archive:** Historical decisions (pre-2026-05-12) logged in `decisions-archive-2026-05-20.md`. Recent inbox entries merged into active file 2026-05-26.

---

## Core Architecture (D1–D9, locked 2026-05-14)

### D1 — BLE ownership
Watch owns the BLE connection to ActiveLook glasses directly. Phone not required during workouts.

### D2 — OS targets
Minimum watchOS 11, iOS 18. Swift 6 strict concurrency.

### D3 — Multi-sport scope
Running-only in v0.1; core data models are sport-agnostic from day one.

### D4 — Glasses disconnect mid-run
Workout continues uninterrupted. Haptic alert, "HUD offline" indicator, auto-reconnect in background, gap logged in metadata.

### D5 — Watch-only mode
Watch + glasses can run full workout without phone. Phone is config cockpit + post-run review.

### D6 — HUD layout model
2–3 curated layout presets baked at build time. Phone picks between presets. Layout editor deferred to v1.

### D7 — Action Button / shortcut launch
Foreground launch to running workout view (matching native Apple Workout UX).

### D8 — Swift 6 strict concurrency
Mandatory from day one. Use `@preconcurrency import` at ActiveLook SDK boundary only. Do NOT add `.enableUpcomingFeature("StrictConcurrency")` flags — CI will reject them.

### D9 — Run history storage
1. **HealthKit** — primary run data (v0.1)
2. **Side store** — AR-specific metadata keyed by HKWorkout UUID (v0.1)
3. **CloudKit** — user config (v1)

---

## User Directives (binding)

| Date | Directive |
|------|-----------|
| 2026-05-14 | **No Direct Main** — all changes via feature branches + PRs. Naming: `feat/`, `spike/`, `fix/`, `chore/`. |
| 2026-05-14 | **Track Squad Logs** — `.squad/log/` and `.squad/orchestration-log/` tracked in git. |
| 2026-05-14 | **XcodeGen** — `project.yml` is source of truth. No `.xcodeproj` committed. |
| 2026-05-14 | **Claude Opus 4.7** — code-writing agents use `claude-opus-4.7-1m-internal`. Scribe/Killian stay on haiku. |
| 2026-05-17 | **Opus 4.7 (reaffirmed)** — any agent touching code must use Opus 4.7 1M context. Fallback: opus-4.6-1m → opus-4.6 → opus-4.5. Never Sonnet/Haiku for code. |
| 2026-05-18 | **Post-release stale-task sweep** — after shipping a pre-release, coordinator sweeps background tasks. |
| 2026-05-19 | **Bundle version bump in work PR** — `CURRENT_PROJECT_VERSION` bump goes in the same PR as the feature/fix. No separate bump PRs. |
| 2026-05-19 | **Phone is NEVER a requirement** — Watch + glasses must function fully without phone. Phone features degrade gracefully when offline. |
| 2026-05-19 | **Auto-release to TestFlight** — after CI green, tag and upload without waiting for explicit approval. Joe validates on TestFlight. |
| 2026-05-19 | **Engo 2 display: 15-level grayscale** — no colors. All HUD design uses intensity levels 0-15 (amber-on-black). |

---

## Standing Rules

1. **No Apple-framework imports in ARRunnerCore** — enforced by Linux CI. Use protocol boundaries.
2. **ActiveLook Visual Assets hard rule** — never commit assets/fonts/configs from `ActiveLook/Activelook-Visual-Assets` or `Config-Generator` (CC BY-NC-ND 4.0). Original art only.
3. **SPDX headers** on all `.swift` files: `// SPDX-FileCopyrightText: 2026 Joe Krilov` / `// SPDX-License-Identifier: Apache-2.0`
4. **AsyncStream over Combine** for cross-module observation. Compiles on Linux, Swift 6 first-class.
5. **Parallel agents use git worktrees** — `git worktree add ../AR-Runner-{agent}-{task}` for isolation.
6. **CI required checks**: `ci-core-tests` (Linux), `ci-build` (4-scheme macOS matrix), `codeql` (security-extended).

---

## Key ADRs

### BLE link lifecycle (locked v0.4+)
The BLE link to ActiveLook glasses is **user-managed, not workout-scoped**. Workout state and link state are independent state machines. Workout-stop does NOT disconnect. Only explicit user action disconnects.

### BLE write serialization (PR #55)
Writes serialize via `didWriteValueFor` callback (CheckedContinuation). Flow-control gate: wait for `isNotifying == true` on flow-control characteristic before sending commands. 2s safety timeout.

### Engo 2 lens-flip formula
`x_wearer = 303 − x_fb`, `y_wearer = 255 − y_fb`. Rotation=4 (topLR) + adjusted coordinates = right-side-up text. All coords must stay in `0..303 × 0..255` framebuffer space (off-screen = silently clipped, no error).

### Font heights (from ActiveLook Visual-Assets README)
F1=24px, F2=38px, F3=64px, F4=75px, F5=82px. Formula: `y_fb = 255 − wearer_top` (topLR anchors at top-right).

### TestFlight CI (release-testflight.yml)
- Tag `v*.*.*-*` auto-triggers; pure `v*.*.*` reserved for App Store (future).
- Also supports `workflow_dispatch` with `version` input.
- Version from tag, build number from `$GITHUB_RUN_NUMBER`.
- Signing: `Config/Signing.xcconfig` is single source of truth. Never pass `CODE_SIGN_STYLE`/`CODE_SIGN_IDENTITY` on CLI.
- Secrets: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_KEY_*` (×3), `BUILD_CERTIFICATE_P12_*` (×2), `KEYCHAIN_PASSWORD`.
- Xcode 16.4 pinned via `maxim-lobanov/setup-xcode@v1`.

### Strava OAuth (v0.5, PR #84)
- Endpoint: `https://www.strava.com/oauth/mobile/authorize`
- redirect_uri: `arrunner://ar-runner.app/callback`
- Authorization Callback Domain (Strava settings): `ar-runner.app`
- Dual-path: try `strava://` deep link first (canOpenURL), fall back to ASWebAuthenticationSession.
- `LSApplicationQueriesSchemes: [strava]` in project.yml.

---

## API Contracts (stable on main)

### GlassesFrameTransport protocol

```swift
public protocol GlassesFrameTransport: Sendable {
    var connectionState: GlassesConnectionState { get async }
    func connectionStates() async -> AsyncStream<GlassesConnectionState>
    func statusEvents() async -> AsyncStream<GlassesStatusEvent>
    func connect() async throws
    func disconnect() async throws
    func selectLayout(id: String) async throws
    func updateField(_ update: HUDFieldUpdate) async throws
    func updateFields(_ updates: [HUDFieldUpdate]) async throws
}
```

States: `disconnected | scanning | connecting | connected | reconnecting | failed`
Events: `batteryLevel | signalQuality | dropped | reconnected | reconnectAttemptFailed`
Reconnect: exponential backoff 1s→8s, auto-reapply layout on reconnect.

### WorkoutController actor

```swift
public actor WorkoutController {
    public init(substrate: any WorkoutHealthSubstrate, sessionID: UUID, clock: ...)
    public func start(activityType: SportType = .running) async throws -> WorkoutState
    public func pause() async throws
    public func resume() async throws
    public func end() async throws -> WorkoutSummary
    public func reportGlassesSignal(_ signal: GlassesConnectivitySignal)
    public nonisolated let states: AsyncStream<WorkoutState>
    public nonisolated let metrics: AsyncStream<WorkoutMetric>
}
```

- `reportGlassesSignal(.disconnected)` does NOT pause the workout (D4 enforcement).
- `WorkoutHealthSubstrate` protocol wraps HKWorkoutSession for testability.

---

---

## Recent Decisions (2026-06-18)

### 2026-06-18 — Laughlin: Strava Upload Reliability (v0.6.1)

**Status:** PR open (`fix/strava-upload-reliability`, base main). Phone compile + phone tests CI-gated (no Xcode on the Windows bench); ARRunnerCore untouched.

**The bug (confirmed):** Longer runs (e.g. 3.25 mi) stuck in `.uploading`, present in HealthKit but never reaching Strava; sub-0.1 mi test runs uploaded fine. Root cause: `StravaUploadQueue.uploadOne` persisted the entry as `.uploading` BEFORE awaiting a *foreground* `URLSession.shared.upload`. iOS suspends/kills a backgrounded app mid-upload (far likelier for a large TCX over cellular). The orphaned `.uploading` entry was never reclaimed because `pickNext()` only ever selected `.pending` → stuck forever.

**Fix — three parts:**
1. **Reclaim orphans.** `StravaUploadQueue.reclaimOrphans` (pure, unit-tested) rewrites any persisted `.uploading` → `.pending` at init (no retry consumed) and persists. Idempotency (`external_id` = `HKWorkout.uuid` → Strava 409 → success) is the double-send safety net.
2. **Background URLSession.** New `BackgroundStravaUploadTransport` conforms to `StravaUploadTransport`. Background config `com.arrunner.phone.strava-upload`, `isDiscretionary=false`, `sessionSendsLaunchEvents=true`. File-based body (multipart written to temp file, byte-identical to `makeMultipartBody`, D-Strava-8), `uploadTask(with:fromFile:)`. Delegate bridges callbacks to async via `CheckedContinuation` keyed by `taskIdentifier`; GET polls use a separate ephemeral session. `PhoneAppDelegate` (`@UIApplicationDelegateAdaptor`) captures `handleEventsForBackgroundURLSession` and re-attaches the session on background-launch.
3. **Confirm processing.** New `.processing` state. After a 2xx POST with `activity_id == null`, the queue polls `checkUploadStatus` (previously dead code) with its own bounded backoff `[2,5,10,20,30]s` and `maxConfirmPolls=12`: `activity_id` → `.completed`; non-empty `error` → `.failed`; budget exceeded → `.pending` (re-POST → 409 dup → completed). 409 duplicate with no pollable id → completed.

**State-machine invariant (enforced):** `pickNext()` selects BOTH `.pending` and `.processing`; `.uploading` is reclaimed at init. No persisted state is unreachable.

**Compatibility note:** Added `confirmPollCount: Int? = nil` (optional → `decodeIfPresent`) so queue files persisted before v0.6.1 decode without a reset, and the synthesized memberwise init stays source-compatible. Threaded `externalID` through `StravaUploadTransport.upload(for:from:externalID:)` for background `taskDescription` tagging.

**Version:** MARKETING_VERSION 0.6.0→0.6.1, CURRENT_PROJECT_VERSION 52→53, VERSION 0.6.1, README/architecture/copilot-instructions bumped (bundled-bump convention).

**Tests added** (`StravaUploadQueueTests`): orphan `.uploading`→`.pending` reclaim (+persist) and process-to-completion; pure `reclaimOrphans`; confirmation poll (pending→activity→completed; error→failed; budget-exceeded→reclaimable `.pending`); 409 duplicate→completed; re-enqueue-completed no-op.

---

## v0.6.x Planning (2026-06-17) — Multi-Workout Types + Custom HUD Layouts

### Richards — Architecture Plan

**Composite WorkoutType model recommended** (activity × location, not flat enum):

```swift
public enum ActivityKind: String, Sendable, Codable, CaseIterable {
    case running, walking, cycling
}
public enum LocationKind: String, Sendable, Codable, CaseIterable {
    case outdoor, indoor
}
public struct WorkoutType: Sendable, Codable, Equatable, Hashable {
    public let activity: ActivityKind
    public let location: LocationKind
    // Convenience factories: .outdoorRun, .indoorRun, .outdoorWalk, .outdoorBike, .indoorBike
}
```

**Data model changes:**
- `SportType` deprecated; bridge via `toWorkoutType()` for one release cycle.
- New `WorkoutLayoutDefaults: Codable` maps `WorkoutType → HUDLayout.id`.
- Side-store `ARWorkoutMetadata` already carries `layoutID` — no schema change.
- WCMessage schemaVersion: 5 → 6; `WorkoutTickMessage` accepts both `sport: "running"` (legacy) and `workoutType: {activity, location}` (new) for mixed-version compat.

**Phasing:**
- **Phase 1 (v0.6.0):** Data model, watch/phone type picker, HealthKit mapping for indoor/outdoor, Strava TCX sport-string mapping. No custom layouts yet.
- **Phase 2 (v0.6.1):** Phone layout editor UI (depends on Weiss feasibility).

**Open questions for jkrilov:**
- Indoor walking in scope (6 types) or just 5?
- CloudKit sync for custom layouts in v0.6, or local UserDefaults + WCSession sufficient?
- Default-layout inheritance semantics?

---

### Laughlin — watchOS + HealthKit Implementation (v0.6.0)

**Recommended decisions (WD-1 through WD-10):**

1. **SportType enum:** Add `.indoorRun`, `.indoorWalk`, `.indoorBike` cases; keep outdoor variants as-is.
2. **HealthKit locationType:** `sport.isIndoor ? .indoor : .outdoor`; suppress GPS/routeBuilder for indoor.
3. **MetricKind.speed:** Add `case speed` for cycling (m/s → km/h or mph formatting).
4. **WorkoutSummary:** Add optional `averageSpeedMetersPerSecond: Double?` for cycling; branch on sport in `makeSummary`.
5. **WorkoutView:** Pre-workout type selector row + scrollable List picker (5 items); state machine prevents mid-workout changes.
6. **Default type preference:** `Shared/Settings/WorkoutTypePreference.swift` (App Group UserDefaults, key `"defaultWorkoutType"`).
7. **Action Button:** Expand `ARRunnerWorkoutStyleEnum` to 5 cases; `perform()` carries sport through app-group flag or preference.
8. **HealthKit cycling cadence:** Add `.cyclingCadence` to authorized types in `sharedTypes` and `readTypes`.
9. **WCMessage v6:** New case `defaultWorkoutType(SportType)` for phone → watch sync.
10. **Files to touch:** SportType.swift (add cases), WorkoutMetric.swift (add .speed), WorkoutSummary.swift (add speed field), WorkoutController.swift (branch makeSummary), WCMessage.swift (schema v6), HealthKitWorkoutSubstrate.swift (locationType gate, cycling cadence), WorkoutView.swift (type picker), ActionButtonIntent.swift (enum expansion), WorkoutTypePreference.swift (new).

---

### Killian — UX Plan

**Workout-type selection (watch pre-workout):**
- Flat list of 5 items (Outdoor Run, Outdoor Walk, Outdoor Bike, Indoor Run, Indoor Bike).
- Tappable row with chevron → crown-scrollable picker → checkmark on current.
- 2 taps to select non-default type.
- Dynamic navigation title: "Outdoor Run", "Outdoor Walk", etc.

**Default type discovery:**
- Persisted via App Group UserDefaults (same pattern as Action Button mode).
- Watch Settings: gear icon → "Default Workout" picker.
- Phone Settings: new "Workout" section → "Default Type" picker.
- WCSession mirrors phone → watch.

**Action Button & Smart Stack:**
- Action Button: 5 types in system Settings picker; independent of app default.
- Smart Stack widget: type-aware (shows default type name + icon, not hardcoded "Run").

**Custom layout editor UX (phone, v0.6.1):**
- Settings → new "Glasses Layouts" section (not a new tab yet).
- System layouts non-editable; custom editable + swipe-to-delete.
- Per-workout-type default layout assignment rows.
- 4-slot editor (6-slot deferred to v0.7): tap slot → metric picker → save → assign to sport.
- HUD preview: black rectangle (304×256) with amber text, correct lens-flip coords, synthetic values.
- Layout sync watch ↔ phone (WCMessage), applied at next workout start, queued if glasses offline.

**Default layouts per type (v0.6.0):**

| Type | Slots | Rationale |
|---|---|---|
| Outdoor Run | pace, heartRate, distance, duration | Current balanced run |
| Outdoor Walk | pace, heartRate, distance, duration | Same structure |
| Outdoor Bike | speed, heartRate, distance, duration | Speed ≠ pace for cycling |
| Indoor Run | pace, heartRate, cadence, duration | No GPS; cadence for form signal |
| Indoor Bike | cadence, heartRate, duration, energy | No GPS; energy replaces distance |

**Open questions for jkrilov:**
- Q1: Flat list vs. 3-item + toggle? (Recommend flat)
- Q2: Smart Stack widget type-aware? (Recommend yes)
- Q3: Layout editor 4-slot only (v0.6.1) or 6-slot from start?
- Q4: MetricKind.speed in v0.6.0 or defer to v0.6.1?
- Q5: Indoor distance hide or show pedometer estimate?
- Q6: Layouts in Settings section or dedicated tab?
- Q7: Action Button all 5 types or default only?
- Q8: Layout name required or auto-generated?

---

### Amber — Fitness-Domain Correctness Plan

**Per-type metric validity matrix:**
- Pace (min/km) ✅ for run/walk; ❌ wrong for cycling (speed in km/h required instead).
- Pace formatter: currently miles-only, needs km/h speed path.
- Elevation: ✅ outdoor; ❌ meaningless indoors (barometric noise).
- Indoor cycling distance: ⚠️ absent without Bluetooth sensor.
- Cadence: semantics differ (steps/min for running, RPM for cycling); formatter must branch.

**11 correctness risks identified (R1–R11):**
- R1: No `.speed` MetricKind (blocker for cycling).
- R2: Pace formatter miles-only, no km/h path.
- R3: GlassesService pace formatter assumes sec/km for all sports.
- R4: WorkoutController cadence var names "steps/min" even for cycling.
- R5: WorkoutViewModel pace computation carries running semantics (paceSecondsPerKilometer for all).
- R6: HealthKit substrate never emits cadence or elevation samples.
- R7: All HUDLayout presets named `*Run`, include `.pace` (no cycling default).
- R8: EnergyEstimator Keytel formula validated for running; may over-estimate for cycling/walking.
- R9: SportType has no indoor/outdoor distinction (WCMessage schema bump needed).
- R10: TCX sport field defaults to "Running" for all workouts.
- R11: RunningHUDPreset name + tests are running-specific.

**Recommended test strategy:**
- `SportTypeExtendedTests.swift` — Codable round-trip, `isIndoor` computed property, `requiresGPS`.
- `MetricValidityTests.swift` — cycling rejects pace, elevation invalid indoors, cadence unit per sport.
- `MetricFormattingExtendedTests.swift` — speed formatter (25 km/h → "25.0 km/h"), pace km variant.
- `HUDLayoutDefaultTests.swift` — per-type defaults all contain correct metrics, no duplicates.
- `MetricLayoutValidationTests.swift` — invalid metric/sport combos detected; graceful "--" rendering.
- `EnergyEstimatorCrossSportTests.swift` — walking/cycling kcal ranges plausible.
- `WCMessageSchemaVersionTests.swift` — old sport enum decodes without crash, unknown sport falls back safely.
- Device bench: indoor distance, cadence sensor, elevation indoors, energy reconciliation.

**Action assignments:**
- Richards: Add `.speed` to MetricKind, `formatSpeedKilometersPerHour`, `formatAveragePacePerKilometer`.
- Richards: Add `MetricKind.isValid(for: SportType)` validator.
- Richards: Add indoor/outdoor to SportType (pending Q3 answer from jkrilov: flat enum or composite).
- Richards: Expand sport-type in TCX encoder.
- Laughlin: Fix WorkoutViewModel pace computation to branch on sport.
- Laughlin: HealthKit substrate add cadence + speed type mappings.
- Laughlin: Phone layout picker validate metric/sport compatibility on save.
- Amber: Write all Core unit tests (post-model changes).
- Amber: Device bench tests (indoor distance, cadence sensor, etc.).

**Open questions for jkrilov:**
- Q1: Indoor walk in scope?
- Q2: Units (km vs. mi): always metric, always imperial, or locale-driven?
- Q3: Indoor/outdoor model: flat enum (A) or composite (B)?
- Q4: Cycling cadence on Apple Watch SE without sensor: always show with "--" or only if sensor detected?
- Q5: EnergyEstimator formula: accept Keytel as-is or add activity-specific scaling?
- Q6: TCX walking sport string: "Other" (standard) or non-standard "Walking"?

---

### Weiss — Custom Layouts Feasibility + Design

**Feasibility verdict: Constrained-custom via parameterized raw `txt` rendering.**

Why NOT layoutSave: The command exists but requires `cfgWrite` + font/icon uploads (cf. icon spike), loses access to preloaded fonts 1–5 and stock icons, and burns 3MB flash pool with no automatic cleanup. Wrong for v0.6.x.

Why raw `txt` works: `RunningHUDFrame.frames(for:)` already renders any string at any (x, y, font) on Engo 2; bench-validated rc16 coordinates; wraps in `holdFlush` for atomic commits; called via `GlassesFrameTransport.sendCommands`.

**Recommended approach:**
- Fixed-slot grid model: compile-time geometry constants extracted to `HUDGridDefinition` (new type, Core-resident, NOT Codable).
- Four slots: x=243/y=240 (line 1 left), x=83/y=240 (line 1 right), x=243/y=170 (line 2), x=243/y=77 (line 3) — all from bench-validated rc16.
- `HUDLayout` (existing type) unchanged: `id, name, slots: [MetricKind?]`. Slot index → grid geometry lookup.
- `RunningHUDFrame.frames(for metricValues: [MetricKind: String], layout: HUDLayout, grid: HUDGridDefinition)` new signature; backward compatible via convenience wrapper.
- Geometry stays in code (validated in unit tests) — not user-editable — to prevent coordinate regression class of bugs.

**Per-workout-type default layouts (curated, code-defined):**

| Type | Slots | Rationale |
|---|---|---|
| Outdoor Run | pace, heartRate, distance, duration | Current balanced |
| Indoor Run | pace, heartRate, cadence, duration | No GPS; cadence signals form |
| Outdoor Walk | pace, duration, distance, heartRate | Slower pace focus |
| Outdoor Bike | pace, cadence, distance, duration | Speed + cadence core (but needs `.speed` MetricKind first) |
| Indoor Bike | cadence, heartRate, duration, energy | No GPS; energy signals burn |

**Watch applies defaults at workout start:** `WorkoutViewModel` looks up `WorkoutLayoutDefaults.typeToLayoutID[workoutType]` → resolves `HUDLayout` → `GlassesService.selectLayout(layout:grid:)`.

**Sync path (phone → watch):** `WCMessage.layoutCatalog([HUDLayout])` + `layoutDefaults(WorkoutLayoutDefaults)` (per Richards' WCMessage v6 plan).

**Two pre-existing bugs in dormant curated path (DO NOT SHIP):**
- Bug 1: `widgetUpdate(0x3A)` is phantom (not in spec). Sending it → 0xE2 protocol error.
- Bug 2: `displayLayout(0x62)` payload wrong — missing text_string. Correct primitive is `layoutClearAndDisplay(0x69)`.
- These only matter if curated path activates (Config-Generator bake). Feature 2 uses raw txt, bypasses these bugs.

**Phasing:**
- **v0.6.0:** Per-workout-type default factories (code-defined presets), `HUDGridDefinition` geometry extraction, parameterized rendering, WCMessage v6 layout/defaults cases. No phone editor. Can land with Phase 1 (types).
- **v0.6.1:** Phone layout editor UI (slot metric picker), constrained-custom UX.
- **v1+:** Freeform positioning, `layoutSave` dynamic upload, custom icons.

**Constraints:**
- Display: 304 × 256 px, 15-level grayscale (no color).
- Font heights: F1=24, F2=38, F3=64, F4=75, F5=82 px.
- Max lines (F3): 3; (F2): 4.
- Practical 4-slot grid matches rc16 bench; 6-slot (F2) possible but tight.
- BLE payload ~280 bytes/tick for 4 slots — well within bandwidth.
- Non-standard metric assignments (e.g., cadence) have no preloaded icon; render text-only (acceptable for v0.6.x).

**Open questions for jkrilov:**
- Q1: Constrained-custom (fixed grid, user picks metrics per slot) acceptable for v1 of editor?
- Q2: How many grid definitions? (4-slot standard + 2-slot minimal + 6-slot training, or just 4-slot?)
- Q3: Icons for non-standard assignments? (text-only preferred for v0.6.x)
- Q4: Metric availability per sport — editor gray-out unavailable metrics, watch render "--"?
- Q5: CloudKit sync for layouts in v0.6.x, or local+WCSession only?

---

## Recent Decisions (0.6.0 Build-Out: 2026-06-17 — 2026-06-18)

### 2026-06-17 — Copilot: Data Model for 0.6.x Workout Types — DECIDED
**By:** jkrilov (via Copilot coordinator)  
**What:** Model workout type with an ORTHOGONAL activity × environment design (activity {running, walking, cycling} × environment {indoor, outdoor}), implemented with a CUSTOM Codable that preserves the existing raw strings "running"/"walking"/"cycling" for the outdoor variants so shipped v0.5.20 wire/side-store data stays decodable. New combos (indoorRun, indoorWalk, outdoorBike/cycling, indoorBike) encode as new stable raw values. Reconciles Richards' composite `WorkoutType` with Amber's "Option B" orthogonal model and Laughlin's wire-compat requirement.  
**Why:** Clean, HealthKit-mirroring model AND backward-compatible persistence; avoids a breaking schema migration while still bumping WCMessage to v6 with an `.unknown` fallback.

---

### 2026-06-17 — Copilot: Add Metric/Imperial Units Toggle to 0.6.0 — REQUESTED
**By:** jkrilov (via Copilot coordinator)  
**What:** Add a user-facing Metric/Imperial units toggle in the PHONE Settings, scoped into 0.6.0 (it couples tightly with the new cycling speed + per-type formatters).
- New `Shared/Settings/` unit preference (e.g. `UnitSystem {metric, imperial}`), stored in App Group `group.com.arrunner.shared` (same pattern as ActionButtonMode / the new default-workout-type preference). Default derived from `Locale.current.measurementSystem`.
- Phone Settings UI: a Units row (Metric / Imperial) in ARRunnerPhone SettingsView.
- Syncs watch↔phone via WCMessage v6 (the watch needs it for the HUD + watch UI).
- `RunMetricFormatting` (currently miles-only) must be parameterized by unit system for pace (min/km vs min/mi), speed (km/h vs mph), distance (km vs mi), elevation (m vs ft). Folds into Amber's new speed/cadence formatter work. The glasses HUD consumes the already-formatted strings, so it inherits the preference for free.  
**Why:** Resolves the units open question raised by Amber/Killian/Laughlin; user wants explicit control rather than locale-only.

---

### 2026-06-17 — Weiss: Correct the Two Dormant ActiveLook Layout Commands — FIXED (PR #120)
**Agent:** Weiss (AR Integration)  
**Branch / PR:** `fix/activelook-dormant-layout-cmds` → PR #120 (base `main`)  
**Scope:** `ARRunnerCore/Sources/ARRunnerCore/Glasses/ActiveLookCommand.swift`, `ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift`, + Core encoder tests.

**Context:** During 0.6.x custom-layout feasibility planning two latent bugs in the curated-layout BLE command path were documented (dormant since v0.3 — production renders the live HUD via raw `txt` 0x37). They are independent of the 0.6.0 model work, so fixed now to de-risk the curated path before it ships.

**Decisions:**
1. **Phantom `widgetUpdate` (0x3A) — removed, not patched in place.** The command ID does not exist in `ActiveLook_API.md`; sending it returns a `0xE2` protocol-decode error (code 4). Removed the `0x3A` enum case and the `updateWidget(...)` encoder. Per-tick layout text updates now use the documented **`layoutClearAndDisplay` (0x69)** `[id, text, 0x00]` — atomic clear+draw (spec §4.9), which prevents ghosting when a new value is shorter than the previous one.
2. **`displayLayout` (0x62) — append the NUL-terminated text.** Encoder now emits `[id, text, 0x00]` per spec §4.9 / §5.11 (was `[id]` only). `text` defaults to `""`, so the two activation call sites (`selectLayout`, reconnect re-apply) stay source-compatible and now send the spec-correct `[id, 0x00]` activation frame.

**Validation:** `ARRunnerCore` `swift test` on `swift:6.0-jammy`: **218 tests, 1 skipped, 0 failures.** Added byte-exact encoder tests for `layoutClearAndDisplay(id:text:)` and `displayLayout(id:text:)` (empty and non-empty text) plus a regression guard that no command ID maps to `0x3A`.

---

### 2026-06-17 — Richards: v0.6.0 Core Foundation — Implementation (PR #121)
**Author:** Richards (Lead/Architect)  
**Branch:** `feat/0.6.0-core-foundation`  
**Status:** Implemented, tests green (259 executed, 1 skipped, 0 failures — `cd ARRunnerCore && swift test`, Swift 6.0.3 Linux).

**Decisions:**
1. **`WorkoutType` is a struct, not a flat enum.** `activity: ActivityKind` ({running, walking, cycling}) × `environment: WorkoutEnvironment` ({outdoor, indoor}). `CaseIterable.allCases` = the 6 supported combos (indoor walk included — approved). Mirrors HealthKit's own `activityType + locationType` factoring; scales without enum explosion.
2. **Single legacy-preserving `sport` field on the wire — NOT dual-key.** Custom `Codable` encodes the three outdoor variants as unchanged raw strings `"running"`/`"walking"`/`"cycling"`, and the indoor combos as new stable strings `"indoor_running"`/`"indoor_walking"`/`"indoor_cycling"`. A v0.5.20 peer's `sport:"running"` still decodes; an unknown raw value decodes to `WorkoutType.fallback` (`.outdoorRun`) instead of throwing. **Trade-off:** a v0.5.20 phone mirror cannot decode a *new* indoor type. Accepted because the phone mirror is optional and the watch is the BLE owner — the workout is never blocked.
3. **`SportType` removed (no deprecation shim).** All Core call sites moved to `WorkoutType`. Downstream shells (watch `begin(sport:)` + pickers, phone mirror) must migrate — owned by Laughlin.
4. **`WCMessage` schema 6 with lenient decode.** Added `.defaultWorkoutType(WorkoutType)` and `.unitPreference(UnitSystem)` for settings sync; unrecognized `kind` now decodes to a decode-only `.unknown` case instead of throwing. Hard schema-version incompatibility (version above current) still throws. Layout catalog/defaults payloads deferred to v6.1.
5. **`UnitSystem` + unit-aware formatters live in Core.** Pure Swift, no `Locale`/`Measurement` coupling. Phone UI + App-Group persistence are Laughlin's later scope.
6. **Metric correctness:** `MetricKind.speed` added; `WorkoutSummary` gains additive `averageSpeedMetersPerSecond: Double?`; `WorkoutController` branches in `makeSummary` (run/walk → pace, cycling → average speed, the other left nil). `HUDLayout.default(for:)` gives per-type defaults (cycling uses `.speed` not `.pace`; indoor never shows `.elevation`).

---

### 2026-06-18 — Laughlin: v0.6.0 App-Shell Migration to WorkoutType — (PR #121)
**Agent:** Laughlin (watchOS Dev)  
**Branch / PR:** `feat/0.6.0-core-foundation` / PR #121  
**Scope:** ARRunnerWatch, ARRunnerPhone, ARRunnerWidgets, Shared (Core untouched)

**Decisions:**
1. **New preference types live in `Shared/Settings/`, wrapping Core types.** `WorkoutTypePreference` (default `WorkoutType`) and `UnitPreference` (`UnitSystem`) follow the existing `ActionButtonMode.swift` `sharedDefaults` pattern over App Group `group.com.arrunner.shared`. They wrap the Core enums rather than redefining them. `WorkoutTypePreference` default = outdoor run; `UnitPreference` default = `Locale.current.measurementSystem`-derived.
2. **Widget targets get `WorkoutTypePreference.swift` added explicitly in `project.yml`.** The widget extensions only source the `ARRunnerWidgets` path, not all of `Shared/`. Added `Shared/Settings/WorkoutTypePreference.swift` to both `ARRunnerWidgetsPhone` and `ARRunnerWidgetsWatch` sources. `UnitPreference` is intentionally NOT added (widgets don't render units). The same file compiled into multiple target modules is safe — separate modules, interoperating only through the shared UserDefaults key.
3. **`activityType(for:)` returns a tuple** `(HKWorkoutActivityType, HKWorkoutSessionLocationType)` — one source of truth for the HK config's activity AND location type. Indoor gates both `HKWorkoutRouteBuilder` creation and `locationManager.startUpdatingLocation()` on `!sport.isIndoor`.
4. **Running cadence is NOT implemented (HealthKit limitation).** No public `runningCadence` quantity type exists. Implemented cycling speed (`.cyclingSpeed` → `MetricKind.speed`) and cycling cadence (`.cyclingCadence` → `.cadence`). Running cadence would require derived step-rate math — deferred to a follow-up. **Flagging for the team.**
5. **Settings sync is bidirectional, last-writer-wins.** New `WCMessage.unitPreference` / `.defaultWorkoutType` are sent from both watch and phone; the receiver persists to the App Group store. Watch send methods are `async` (queued); phone send methods are sync.
6. **Action Button enum keeps legacy raw value.** `ARRunnerWorkoutStyleEnum` expanded to all 6 `WorkoutType` cases, but the original case retains raw value `"run"` so existing Action Button assignments survive. `perform()` writes `WorkoutTypePreference.current` before signaling start.

**Caveats / unverified:** App-target compilation (watchOS + iOS) is **CI-only** — no Xcode on the Windows bench. AppEnum `caseDisplayRepresentations`, SwiftUI `Picker` `.tag(WorkoutType)` matching, and the `NavigationLink` type-picker push are all compile-pending CI on PR #121. Core was not modified, so no local `swift test` was required.

---

---

## Recent Decisions (2026-06-18)

### 2026-06-18 — Laughlin: Strava Upload Autonomous Scheduling Fix (v0.6.2)

**Status:** SHIPPED — PR #125 merged (d01b033), tag v0.6.2-1.

**The problem (confirmed in field):** v0.6.1 lacked autonomous re-scheduling of queued uploads. The `StravaUploadQueue` persisted entries as `.uploading` BEFORE the upload completed, but if the upload succeeded or the app backgrounded mid-operation, the entry was never re-driven while the app stayed open. Result: a 3.25mi run stuck showing "uploading" forever even when the app was foregrounded, even though the upload had completed on the server (Strava confirmed receipt, no duplicate).

**Root cause:** `StravaUploadQueue.pickNext()` only selected `.pending` entries. Entries stuck in `.uploading` were unreachable by the queue's re-drive loop — no watchdog, no autonomous re-attempt trigger, no visibility into the stuck state.

**Fix — four parts:**
1. **Autonomous self-rescheduling drain.** `process()` now computes `nextDueDate` based on backoff and success state, arms exactly one follow-up `Task` via `scheduleNextDrain()`, cancels+replaces on each pass, and cancels in `deinit`. Pattern: `[async Task] private var drainTask`, store + cancel on every entry transition.
2. **Upload watchdog.** New 120s timeout on `.uploading` state. If the URLSession upload doesn't call back within 120s, a timer fires, transitions to `.pending`, and the next `process()` cycle re-attempts.
3. **Reconcile orphaned entries.** `StravaUploadQueue.reclaimOrphans()` (pure, unit-tested) rewrites any persisted `.uploading` → `.pending` at init (consumes no retry budget). Idempotency via `external_id` (HKWorkout UUID) → Strava 409 on duplicate → accepted as success.
4. **Visible status/error in History UI.** New `.processing` state visible in the UI. History row shows "Uploading…", "Retrying…", "Failed: <error>", or the success timestamp. Users see the state without guessing.

**State-machine invariant (enforced):** `pickNext()` selects both `.pending` and `.processing`. No persisted state is unreachable. Queue files persisted before v0.6.1 decode without a reset via optional `confirmPollCount: Int? = nil`.

**Version:** MARKETING_VERSION 0.6.0 → 0.6.2, CURRENT_PROJECT_VERSION 51 → 53, VERSION 0.6.2. README + architecture + copilot-instructions bumped (bundled-bump convention).

**Validation:** StravaUploadQueueTests cover orphan reclaim, process-to-completion, confirmation polling, 409 duplicate handling, and re-enqueue no-ops. Core tests: 218 executed, all pass.

---

## Recent Decisions (0.6.x HUD Planning: 2026-06-19) — CONSOLIDATED

### 2026-06-19 — Weiss: Custom HUD Layout Editor — Glasses Rendering + Data-Model Plan

**Agent:** Weiss (AR Integration)  
**Status:** PLANNING ONLY — no code changes. Builds on constrained-custom feasibility verdict from earlier planning (decisions.md §"Weiss — Custom Layouts Feasibility").

**Scope:** Establishes the Core data types for custom layouts + the watch apply path.

**Key Recommendations:**
1. Custom layouts encoded via reused `HUDLayout` (Codable, already carries `[MetricKind?]`). New type `HUDLayoutCatalog` wraps the catalog of user-created customs (system presets are code-only, not stored). `WorkoutLayoutDefaults` maps `WorkoutType → HUDLayout.id`.
2. Slot→geometry stays an index lookup into `HUDGridDefinition` (no geometry in the payload). Editor is constrained to `standard4` only (4 fixed slots), avoiding coordinate-regression risk class.
3. Watch apply: swap hardcoded `HUDLayout.default(for: sport)` + `HUDGridDefinition.standard4` with a resolver chain: `layoutDefaults.layoutID(for: type)` → `catalog.layout(id:)` → else `HUDLayout.default(for: type)`. Everything downstream (render, throttle, fonts) **unchanged**.
4. `HUDLayout.validated(for: WorkoutType)` sanitizes a custom layout at apply time — invalid metrics for the active type become `nil` (renders `--`), preventing crashes + incorrect derivations.
5. **Slot 1 (secondary line-1-right) overflow risk:** budget ≈4 font-2 glyphs. Editor must warn (not hard-block) when an assignment exceeds the threshold, computed via `ALookFontMetrics.width(of:fontSize:)`. Mitigation: guidance + worst-case bench spike (0.5 day) to lock the threshold.
6. **WCMessage schema bump to 7** for new `.layoutCatalog(HUDLayoutCatalog)` + `.layoutDefaults(WorkoutLayoutDefaults)` cases (additive; lenient decode already in place so v6 peers gracefully ignore). Schema stays lenient and forward-compatible.

**Effort:** Core types + validated + v7 + tests ≈1.5 days (S/M). Watch resolver + tests ≈1 day (S). Phone UI (Killian) ≈3–4 days (L).

**Risks:** R1 (medium) line-1-right overflow — mitigate with editor warning + bench spike. R2–R4 (low): text-only metrics, `--` density, v6 watch ignores catalog.

**Open questions deferred to jkrilov:**
- OQ1: 4-slot only (recommend yes)?
- OQ2: Soft warn vs hard-block on slot-1 overflow?
- OQ3: Custom-icon support confirmed deferred?
- OQ4: Per-type default fallback semantics confirmed?
- OQ5: CloudKit sync (App-Group + WCMessage only in v1)?
- OQ6: Global or per-type-scoped custom layouts?

---

### 2026-06-19 — Richards: Custom HUD Layout Persistence + Watch↔Phone Sync Architecture

**Agent:** Richards (Lead/Architect)  
**Status:** PLANNING ONLY — no code. Targets v0.6.1 phone editor (Phase B). Builds on v0.6.0 Core foundation.

**Scope:** Wire protocol, persistence layer, and watch-side resolution for custom layouts.

**Key Recommendations:**
1. **Two new Core Codable types** (versioned independently of WCMessage):
   - `HUDLayoutCatalog(schemaVersion, custom: [HUDLayout])` — stores user layouts only; system presets are code.
   - `WorkoutLayoutDefaults(schemaVersion, assignments: [String: String])` — maps WorkoutType raw key → chosen HUDLayout.id.
   Keys are `WorkoutType.rawValue` (legacy-preserving strings) to stay stable on the wire.

2. **Messaging — additive within WCMessage v6, NOT a bump to v7.** Add two cases:
   - `case layoutCatalog(HUDLayoutCatalog)` (phone → watch state, latest-only)
   - `case layoutDefaults(WorkoutLayoutDefaults)`
   Stamp `currentSchemaVersion` remains **6** (envelope structure unchanged; only new optional keys populated). Backward-compat: v7 watch's catalog → old v6 phone gets `schemaVersion: 6, kind: "layoutCatalog"` → phone decodes as `.unknown` → silently ignored. No regression of the live mirror.

3. **Persistence:** App Group `UserDefaults` suite, keys `"hudLayoutCatalog"` / `"workoutLayoutDefaults"`, holding JSON `Data`. New `Shared/Settings/HUDLayoutStore.swift` wraps it. Max-layout cap (propose **16**) keeps the blob a few KB — well within `applicationContext` limits. If ever outgrows, swap backing to a JSON file behind the same API.

4. **Sync semantics:**
   - Full-catalog replace (not incremental — complexity not worth it).
   - Phone-authoritative (editing phone-only in 0.6.1).
   - Watch persistence: on receipt, decode and write via `HUDLayoutStore` to the App Group, so next workout resolves customs with **no phone present**.
   - Transport: reachable → immediate `sendMessageData` (snappy). Not reachable → `updateApplicationContext` OR two ordered `transferUserInfo` messages (catalog + defaults on cold reconcile).

5. **Resolution at workout start:** Pure, Linux-testable Core resolver:
   ```swift
   public enum HUDLayoutResolver {
       public static func activeLayout(for type: WorkoutType,
           defaults: WorkoutLayoutDefaults, catalog: HUDLayoutCatalog) -> HUDLayout
   }
   ```
   Watch `WorkoutViewModel` replaces its hardcoded `HUDLayout.default(for: sport)` with a call to the resolver. Dangling-reference safety: if an assignment points to a deleted/missing id, resolver falls through to the built-in default — no crash.

6. **Phasing & dependencies:**
   - **Phase A — Persistence + Sync (can land BEFORE editor UI):** Core types + resolver + additive WCMessage cases + store + watch persistence + watch resolution swap + phone send/reconcile. Fully shippable and **inert for users with no custom layouts** (resolver returns built-ins). No dependency on editor. Owners: Richards (Core/messaging) + Laughlin (watch/phone plumbing).
   - **Phase B — Phone editor UI (depends on A):** Killian (UX) + Weiss (validation) + Laughlin (phone impl).

7. **Open questions for jkrilov:**
   - Q1: CloudKit in 0.6.1 (recommend no, local + WCSession only)?
   - Q2: Max custom layouts cap (propose 16)?
   - Q3: Confirm 4-slot only in 0.6.1?
   - Q4: One-directional sync (phone→watch) acceptable for 0.6.1?
   - Q5: Prune orphaned assignments on delete?
   - Q6: Confirm additive-within-v6 over v7 bump?

---

### 2026-06-19 — Killian: Phone Custom HUD Layout Editor UX (Phone) — Buildable v1 Plan

**Agent:** Killian (UX Lead)  
**Status:** PLANNING ONLY — no code. Refined from earlier sketch now that foundation shipped in 0.6.0–0.6.2. Coordinated with Weiss (renderability) and Richards (sync).

**Scope:** Phone Settings editor UI, 4-slot grid, metric picker, per-type default assignment.

**Navigation:**
- Settings → "Glasses Layouts" disclosure row (new section between Workout and Units).
- Screen hierarchy: Settings → Glasses Layouts (list) → Layout Editor (CRUD one custom) → Metric Picker (modal sheet).

**Glasses Layouts list screen (3 sections):**
1. **Presets (read-only):** 3 curated presets (`HUDLayout.curatedPresets()`), rows show slot summary. Tap → read-only detail + "Duplicate" button. System badge. No delete.
2. **My Layouts (custom):** Tap → Layout Editor. Swipe-to-delete with confirm if assigned. `+` toolbar creates new custom (seeded by duplicating current default for user's default type).
3. **Defaults per workout type:** 6 rows (one per `WorkoutType.allCases`), each showing type + assigned layout name. Tap → picker of {presets ∪ custom layouts valid for that type}. Invalid-metric layouts still selectable but show warning (see validation below).
4. **Empty-state / first-run:** Explain feature + "New Layout" CTA. Until user assigns, all types read "Default (preset name)" — byte-identical to today.

**Layout editor screen:**
- Fixed 4-slot grid matching `HUDGridDefinition.standard4` exactly. Render as 2×2 visual grid: top-left (slot 0, primary, font 2), top-right (slot 1, secondary, font 2), bottom-left (slot 2, font 3), bottom-right (slot 3, font 3).
- Empty slots allowed (`nil`). No variable 2–6 count in v1.
- Tap-slot → modal metric picker. All 8 `MetricKind`s, grouped Valid/Unavailable for layout's context. Selecting assigns; "Clear slot" empties. **Prevent duplicate metrics in two slots.**
- **Naming:** text field + auto-generate from filled slots (e.g. "Pace · HR · Dist"). Auto-name never blocks.
- **Validity = warn, not block (v1).** A custom layout is not tied to one type (can be assigned to several), so hard validity can't be enforced at edit time. For each slot with an invalid metric for any *assigned* type, show inline caption ("Speed isn't shown for runs — appears as `--`"). Editor grey-out uses `MetricKind.isValid(for:)`. Watch already renders invalid/missing as `--`, so assignment is allowed.

**Preview:**
- Inline amber-panel approximation, 304×256 aspect, amber-on-black (15-level grayscale).
- Synthetic sample values (pace 5:30/km, HR 152 bpm, dist 4.2 km, time 23:18) formatted via real `unitLabel(for:in:)` so units track user's metric/imperial setting.
- Approximate font-size hierarchy, correct metric order, correct unit labels, correct empty-slot blanks. **Deferred (v0.7+):** pixel-exact lens-flip coords, real font glyph metrics, live "push to glasses now."

**Apply semantics:**
- Changes apply at **NEXT workout, never mid-run.** Watch reads layout once at start; editing mid-run doesn't reflow live HUD.
- Footer message: "Changes apply to your next workout." If workout active, "Your current run keeps its layout — this applies next time."
- **Richards dependency:** persist customs + assignment in App Group store; sync via deferred `WCMessage.layoutCatalog` + `layoutDefaults` cases (not shipped yet). Mirror call via `sendX` pattern.

**v1 scope (minimum lovable):**
- Glasses Layouts entry + list (presets, custom CRUD).
- 4-slot editor, empty-slot support, tap→metric-picker, no-duplicate rule, auto-name + override.
- Per-type default assignment (6 rows).
- Validity = warn (not block).
- Static synthetic-value amber preview (approximate).
- Apply-at-next-workout + sync via new v6.x cases (Richards dependency).

**Deferred (v0.7+):**
- Variable slot counts / 2-slot + 6-slot grids.
- Freeform metric positioning, `layoutSave`, custom icons.
- Pixel-exact lens-flip preview + real font metrics.
- Live "preview on glasses now."
- CloudKit cross-device sync.
- Per-type editing of same layout.
- Multiple presets beyond curated 3.

**Open questions for jkrilov:**
- Q1: Fixed 4-cell grid (recommend yes)?
- Q2: Unlimited custom layouts or cap (e.g. 8)?
- Q3: Auto-name-with-override (recommend) or require name?
- Q4: Warn-and-allow (recommend) vs hard-block invalid assignments?
- Q5: Global layout assignable to multiple types (recommend) or per-type instances?
- Q6: Approximate static preview (recommend) or pixel-exact lens-flip?
- Q7: Per-type "Reset to default" + global "Restore all defaults" affordances?
- Q8: Settings disclosure row (recommend) vs dedicated tab?

---

## Governance

- Decisions inbox: drop files in `.squad/decisions/inbox/{agent}-{slug}.md`; Scribe merges.
- Each agent only edits its own `history.md`.
- Reviewer rejections lock out original author — different agent must revise.
- Coordinator dispatches, never implements domain code.

