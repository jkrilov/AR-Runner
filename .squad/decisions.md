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

## Recent Decisions (Earlier Batch: 2026-05-12 — 2026-05-25)

### 2026-05-20 — Copilot directive: Strava Path B scope locked
From user direct input. Path B (direct Strava OAuth + TCX upload) promoted v0.6→v0.5. Three-PR sequence: Amber (TCX encoder) → Laughlin (OAuth + tokens) → Laughlin (uploader + queue).

### 2026-05-20 — Richards: TCX Encoder Architecture
**Format locked: TCX 2.0** (zero deps, best fidelity-to-complexity). Pure-Swift encoder, locale-safe double formatting (`en_US_POSIX`), XML-escaped text. Delivered `ARRunnerCore/Strava/{TCXEncoder,TCXWorkoutData,ActivityNaming}.swift` + tests. All 215 Core tests pass.

### 2026-05-20 — Laughlin: Strava OAuth + Token Store (v0.5.3)
Phone-side OAuth/token plumbing: `StravaOAuthService` (mobile auth flow with dual-path: Strava app + web fallback), `StravaTokenStore` (keychain + WCSession mirror), Settings tab UI. 39/39 ARRunnerPhoneTests pass.

### 2026-05-21 — Laughlin: Strava API Compliance (v0.5.4)
Button copy locked to exact "Connect with Strava" string, 48pt height requirement, deauth server-side per API agreement. Token-exchange `client_id` fix (was missing from OAuth code exchange). 39/39 tests pass.

### 2026-05-21 — Laughlin: Appearance Settings (Light/Dark/System)
`AppearanceMode` enum (`.system / .light / .dark`), @AppStorage persistence (`"appearanceMode"` key), segmented picker in Settings. `.system` → `colorScheme: nil` (device setting). 39/39 tests pass.

### 2026-05-22 — Laughlin: Apple Watch Action Button Support (v0.5.5)
`ActionButtonMode` enum (off/splits/pauseResume/toggleHUD), `ActionButtonIntent` AppIntent (initial registration), `ActionButtonCoordinator` dispatcher. Process isolation via App Group `PendingActionButtonPressStore`. Haptics on split/pause/HUD toggle. 215 Core tests pass.

### 2026-05-22 → 2026-05-23 — Laughlin: Action Button Surface Correction (v0.5.6)
v0.5.4 bugs: (1) AppShortcutsProvider → wrong picker (Shortcut not Workout). (2) Process isolation — `ActionButtonIntent.perform()` runs in system process, not host. **Fix:** switched to `StartWorkoutIntent` protocol conformance — only surface that populates Settings → Action Button → Workout → App. Cross-process flag pattern preserved + re-validated. Build green.

### 2026-05-23 — Laughlin: Live Route Map Polish (v0.5.17)
Watch map is view-only (Digital Crown reserved for TabView). Phone auto-recenter after 5s pan inactivity. Post-run map persists through `.ending`/`.ended`. Splits track `CLLocationCoordinate2D?` under `#if canImport(CoreLocation)`. Phone split markers deferred to v0.6.

### 2026-05-20 — Richards: Strava API Architecture Plan
Full architecture covering app setup, OAuth options (phone+share recommended; RFC 8628 device-grant not supported by Strava), TCX format, token storage (keychain on watch/phone + Worker proxy). Five architectural decisions locked (D-Strava-1..5). ~850 LOC across 6 files.

### 2026-05-21 — Richards: Cloudflare Worker Source (infrastructure/auth-worker)
Reconstructed Worker source (previously deployed-but-untracked). `wrangler.toml` (`strava-connect.ar-runner.app` custom domain), `src/index.js` (route table, CORS, 400/404/405/500 error envelopes), three endpoints (/token, /refresh, /deauthorize). **Standing rule:** deployed Workers must land source in git (same PR). `/refresh` is load-bearing for 6h token lifecycle.

### 2026-05-20 — Amber: v0.5 PR 1 — TCX Encoder
Built TCX 2.0 encoder per D-Strava-2. Pure Foundation, zero deps, Swift 6 strict-concurrency clean. Determinism pinned via byte-equality test (Strava idempotency contract). Locale-safe formatting validated. 215 total tests pass.

### 2026-05-20 — Amber: v0.5 PR 2 — Strava Uploader + Queue + History
`StravaUploadService` (wire-level), `StravaUploadQueue` (actor-based, Documents/ persistence, 30–900s exponential backoff, 429→queue-pause), `WorkoutTCXBridge` (pure merge over local value types), `AutoUploadCoordinator` (WCMessage listener). 38 phone tests, all pass. HK source-filter in-memory. Auto-trigger on WC + 3s settle.

### 2026-05-20 — Amber: rc2 QA Scenarios (post-rc1 bench feedback)
Five bench-return items: (A) route recording auth + HKSeriesType.workoutRoute() scope, (B) Strava ingestion (pending Richards diagnosis), (C) 3-line finish-screen reflow, (D) discard-gating data-integrity, (E) phone mirror start-time + WC v3→v4 compat. Severity-first bench order. Terminal-path-data-leak-qa skill extracted.

---

## Recent Decisions (Latest: 2026-05-27)

### 2026-05-26 — Laughlin: Release Guard Fix (v0.5.20 chore)
**Status:** SHIPPED — tag-push smoke test validated end-to-end.

**Background:** v0.5.19 shipped via `workflow_dispatch` fallback due to two interacting bugs in `release-testflight.yml`:
1. **Self-collision:** `git tag --list 'v*'` includes the trigger tag, so tag-push triggering the workflow sees its own tag in the candidate list and self-rejects as duplicate.
2. **SemVer misordering:** GNU `sort -V` incorrectly places `0.5.19-1` after `0.5.19` (SemVer 2.0 says pre-release comes before release).

**Fix design:** Inline `semver_gt` bash function (~30 lines, self-testing with 11 fixtures on every CI run), trigger-tag exclusion via `grep -vFx`, highest-tag selection by reduction. Updated misleading comment.

**Validation:** PR #117 (merge `13c8f7a`), tag `v0.5.20-1` pushed, `release-testflight.yml` run 26511705252 passed monotonicity guard on first try. Version 0.5.20 build 50 shipped to TestFlight.

**Outcome:** First v0.5.x pre-release to traverse tag-push cleanly. All future pre-release tag-pushes will auto-trigger without `workflow_dispatch` workaround.

---

### 2026-05-26 — Amber: Terminal-Path Data-Leak Audit — v0.5.18
**Status:** Code paths correct; UX message bug identified.

Joe reported: "When I discard a run on the watch it shouldn't save to Apple Fitness."

**Findings:** Code is correct. `WorkoutHealthSubstrate.discard()` calls `builder.discardWorkout()` exclusively. Tests pass and are untouched since rc2. **But a critical UX message misleads users.**

**The actual bug:** `ARRunnerWatch/Views/WorkoutView.swift:117` says "Discard removes it from this view (it remains in Health and can be deleted there)." This text was written in v0.2 when discard didn't work. The rc2 fix changed the code but never updated the message.

**Decision:** Fix the message to "Discard permanently removes it — nothing is saved to Health or Strava."

**Bench check for Joe:** (1) Run 30s, (2) Tap Finish → Discard, (3) Open Health app → verify NO NEW WORKOUT, (4) Check Strava → verify NO UPLOAD.

---

### 2026-05-26 — Laughlin: Discard Regression Investigation — v0.5.18
**Status:** No code regression. The bug is the dialog message.

Full investigation of the discard path from v0.4.0 (rc2) through v0.5.18 confirms the rc2 fix is intact. `WorkoutController.discard()` calls `substrate.discard(at:)`, never `substrate.end(at:)`. `WorkoutDiscardTerminalPathTests` covers all invariants.

**The bug is the misleading confirmation dialog at `WorkoutView.swift:117`.** Current message contradicts actual behavior.

**Decision:** (1) Update `WorkoutView.swift:117` message text. (2) Update stale doc-comment on `.cancelled` enum case in `WorkoutViewModel.swift:41`. (3) No logic changes required.

---

### 2026-05-26 — Laughlin: Decision Packet — v0.5.19 Discard Dialog Fix
**Status:** SHIPPED (PR #116 merged, dispatched to TestFlight).

**Fix deployed:** PR #116 (`fix/discard-dialog-message`, merged squash → `25ee63a`):
1. `ARRunnerWatch/Views/WorkoutView.swift:117` — replaced misleading message.
2. `ARRunnerWatch/Workout/WorkoutViewModel.swift:41` — updated stale doc-comment on `.cancelled` case.
3. `VERSION + project.yml` — `0.5.18`(48) → `0.5.19`(49) per bundled-bump convention.

No logic changes. CI: all four required checks green.

**TestFlight workflow note:** The pre-release tag push triggered `release-testflight.yml` and failed the monotonicity guard. Root cause: guard runs `git tag --list 'v*' | sort -V | tail -n 1`, which includes the trigger tag itself, so `LATEST_TAG` always equals `RAW_VERSION` on a fresh tag push. Recovered by deleting `v0.5.19-1` from origin and re-dispatching via `workflow_dispatch` with `version=0.5.19`.

**Recommend a v0.5.20 chore PR:** Fix the guard step to exclude the trigger tag from its own monotonicity calculation (e.g. `git tag --list 'v*' | grep -vFx "v${RAW_VERSION}"`) AND switch the sort-order comparison to semver-correct ordering (pre-release suffix < bare release).

---

### 2026-05-26T17:00:37-04:00: User Directive — Code-Writing Agents on Opus 4.7+
**By:** Joe Krilov (via Copilot)  
**What:** Any agent editing/writing code (Laughlin, Weiss, Amber, Richards on code-review) MUST run `claude-opus-4.7-1m-internal` or better. The `.squad/config.json` agentModelOverrides already pin these four — the coordinator must honor Layer 0 of the model-selection hierarchy and NOT fall through to task-aware auto-selection (Sonnet) for these agents, even on investigation-only work.  
**Why:** User request — Joe wants code-touching agents at maximum capability. Captured for team memory and to enforce config compliance on every spawn.

---

## Current Version: v0.5.20

**Shipped 2026-05-27.** Release guard chore (monotonicity bugs fixed), tag-push smoke test validated end-to-end. Build 50, TestFlight processing.

### v0.5 Scope (delivered 2026-05-20 — 2026-05-23)
- Strava OAuth connect button on phone (mobile auth flow)
- Token exchange via Cloudflare Worker (`strava-connect.ar-runner.app`)
- TCX encoder (pure Swift, zero deps)
- Upload queue with exponential backoff
- Appearance mode (Light/Dark/System)
- Apple Watch Action Button support (splits, pause/resume, HUD toggle)
- Live route map (watch view-only, phone pan/zoom + auto-recenter)

### Backlog (not yet scheduled)
- Battery level from glasses → phone display (BLE 0x180F, 30s notify)
- HR zone brightness on HUD (deferred to v0.4.1)
- Gesture-driven layout switch (Weiss needs bench time)
- Phone split markers on map (split lat/lon over WC, v0.6)
- App Attest (issue #80)

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

## Governance

- Decisions inbox: drop files in `.squad/decisions/inbox/{agent}-{slug}.md`; Scribe merges.
- Each agent only edits its own `history.md`.
- Reviewer rejections lock out original author — different agent must revise.
- Coordinator dispatches, never implements domain code.

