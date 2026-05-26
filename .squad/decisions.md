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

## Recent Decisions (Last 2 Weeks: 2026-05-12 — 2026-05-26)

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

## Current Version: v0.5.17

**Shipped 2026-05-23.** Live route map, Action Button refinements, appearance settings.

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

## Governance

- Decisions inbox: drop files in `.squad/decisions/inbox/{agent}-{slug}.md`; Scribe merges.
- Each agent only edits its own `history.md`.
- Reviewer rejections lock out original author — different agent must revise.
- Coordinator dispatches, never implements domain code.
