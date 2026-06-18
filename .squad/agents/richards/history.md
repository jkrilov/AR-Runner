# Richards — History (Compacted 2026-06-18)

## Core Context

- **Project:** Apple Watch fitness app + ActiveLook AR glasses integration
- **Role:** Lead / Architect
- **Joined:** 2026-05-14

## Current Release: v0.6.1 Shipped

### 2026-06-18 — v0.6.1 Released to TestFlight
Laughlin shipped Strava upload reliability fix (PR #123, merged 6d56cd3, tagged v0.6.1-1, TestFlight run 27767550622). Three-part fix: (1) reclaim orphaned `.uploading` at init, (2) background URLSession with file body + PhoneAppDelegate hook, (3) new `.processing` state polling `checkUploadStatus`. v0.6.1 baseline for post-release stale-task sweep.

## v0.6.0 Work (Current Baseline)

### 2026-06-18 — v0.6.0 Core Foundation — SHIPPED
PR #121 merged (commit 91c6860), tagged v0.6.0-1, TestFlight build 52. Orthogonal `WorkoutType` (activity × environment composite), custom Codable for wire backward-compat, `UnitSystem` + unit-aware formatters, `MetricKind.speed`, per-type `HUDLayout.default(for:)`, WCMessage v6 with lenient decode. 259 Core tests executed (1 skipped, 0 failures). 

**API surface:**
- `WorkoutType(activity:ActivityKind, environment:WorkoutEnvironment)` with 6 factories + `.fallback`
- `UnitSystem {metric, imperial}`
- `RunMetricFormatting` parameterized by `UnitSystem`
- `WCMessage` v6: `.defaultWorkoutType`, `.unitPreference`, `.unknown` fallback
- `HUDLayout.default(for:)` per-type presets
- `WorkoutSummary.averageSpeedMetersPerSecond: Double?`

**Downstream:** Laughlin app-shell migration + Weiss command fixes merged in same PR; Coordinator resolved 3 app-target compile errors before test.

## v0.6 Planning (2026-06-17)

### v0.6.x Architecture Plan — COMPLETED
Comprehensive planning for multi-sport (outdoor/indoor × running/walking/cycling) + custom HUD layouts. **Key decision:** Activity × Location composite model (not flat 6-case enum) — mirrors HealthKit, scales for future sports, avoids enum explosion.

**Decisions captured:**
- Richards: Core foundation (WorkoutType, UnitSystem, v6 schema)
- Weiss: ActiveLook command fixes (#120)
- Laughlin: App-shell migration (type picker, preferences, HealthKit mapping)
- Amber: Fitness-domain correctness matrix + test strategy
- Copilot directives: data model + units toggle scope

**Phasing:**
- v0.6.0: Types + defaults + HealthKit mapping + units toggle (shipped)
- v0.6.1: Custom layout editor UI (pending Weiss feasibility)

## v0.5 Releases (Archived 2026-05-19 — 2026-05-27)

**Shipped:** v0.5.5–v0.5.20 (Strava OAuth, TCX, Uploader, Action Button, Appearance, Release-guard chore). Key learnings documented; see `.squad/decisions.md` and `.squad/log/`.

## Core Architecture Decisions (Locked)

- **D1–D9:** Core architecture (BLE ownership, targets, scope, disconnect handling, watch-only, layout model, Action Button, Swift 6, storage)
- **D-Strava-1–5:** Strava direct integration (OAuth path, token storage, TCX format, Worker proxy, refresh lifecycle)
- **BLE Link Lifecycle (ADR):** User-managed, not workout-scoped. Disconnect user-action-only.
- **BLE Write Serialization (PR #55):** Gate on flow-control notify confirmation, serialize via CheckedContinuation, 2s timeout.
- **Engo 2 Lens-Flip Formula:** `x_wearer = 303 − x_fb`, `y_wearer = 255 − y_fb`, rotation=4 (topLR).

## Test Status

- **Core:** 259 tests (v0.6.0 baseline, all pass)
- **Signoff:** Joe bench-validated v0.5.20, v0.6.0, v0.6.1 on device

---

## Learnings

### 2026-06-18 — v0.6.1 Released

v0.6.1 shipped without issues. v0.6.1 now baseline for stale-task sweep (post-release directive 2026-05-18). No blocking follow-ups; field validation ready.

### 2026-06-17 — v0.6.x Architecture Plan: Multi-Workout Types + Custom HUD Layouts

**Key data-model files:**
- `ARRunnerCore/.../Models/SportType.swift` — current flat enum, deprecated in favor of WorkoutType
- `ARRunnerCore/.../Models/HUDLayout.swift` — layout struct (id, name, slots); sufficient for custom layouts
- `ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift:200-201` — locationType now derived from WorkoutType
- `ARRunnerWatch/Workout/HealthKitWorkoutSubstrate.swift:495-500` — activityType(for:) maps activities to HKWorkoutActivityType
- `ARRunnerCore/.../Messaging/WCMessage.swift:28` — schema v6 (v5→v6)
- `ARRunnerCore/.../Strava/TCXWorkoutData.swift:25-27` — TCX sport string (running/walking/biking)

**Rationale:** HealthKit's model is `activityType + locationType`. Mirroring that factoring means HealthKit mapping is trivial, scales for future sports (swimming/hiking), avoids enum explosion.

**Phasing insight:** Workout types (Phase 1) ship independently of custom layouts (Phase 2). Custom layouts blocked on Weiss feasibility study.

**Migration pattern:** Dual-key JSON (both `sport` and `workoutType` in v0.6.0 payloads) handles mixed-version pairs; drop legacy in v0.7.

### 2026-06-17 — Strava OAuth 401 Diagnosis

The user-facing "Couldn't complete Strava sign-in (HTTP 401)" comes only from `SettingsViewModel.userMessage(for:)` mapping `StravaOAuthError.tokenExchangeFailed`, so this identifies the code-to-token exchange, not TCX upload.

iOS app posts auth `code` + public client ID to `https://strava-connect.ar-runner.app/token`; Worker forwards to Strava's `/oauth/token` with client ID, Worker-held `STRAVA_CLIENT_SECRET`, `code`, `grant_type=authorization_code`.

Most likely bench failure: app's `STRAVA_CLIENT_ID` and Worker's `STRAVA_CLIENT_SECRET` are not the same Strava API app, or Worker secret is absent/stale. Redirect domain matters but successful code return makes it less likely.

### 2026-05-21 — Cloudflare Worker Source Landed

Reconstructed Worker source (previously deployed-but-untracked) at `infrastructure/auth-worker/`. Key decisions:
1. Three POST endpoints (`/token`, `/refresh`, `/deauthorize`), route-table dispatcher, error envelopes.
2. **Standing rule:** Deployed Workers must land source in git (same PR).
3. **`/refresh` is load-bearing** for 6h token lifecycle; keeps secret on Worker.
4. **`/deauthorize` Bearer header form** to avoid logging secrets if request-body logging enabled.
5. **Route dispatcher over if/else** — 3 endpoints is inflection point; adds 405 handling free, makes 404 obvious.

### 2026-05-20 — Strava Architecture Plan

Full plan covering API app setup, OAuth analysis (Option A=phone+share recommended), TCX format (zero deps), token storage (shared keychain + WatchConnectivity mirror), 5 ADRs, scope/effort (~850 LOC, ~1 week, no deps), three-PR sequence (Amber: TCX → Laughlin: OAuth+tokens → Laughlin: uploader+queue).

**Architect learnings:**
1. **Scope qualifiers on invariants** — "phone-optional" needs "during workouts" qualifier, else future decisions overconstrain.
2. **Watch is a full HTTPS client** — distinguish "can't render UI" from "can't do network".
3. **Scope estimates need per-file enumeration** — round numbers lie by 2x; 200–500 LOC estimate was actually 850 LOC.
4. **`client_secret` on watch is right for personal-tier app** — secret rotates easily, attacker payoff near-zero, alternative (server proxy) adds runtime dependency.
5. **TCX deserves closer look** — FIT wins (developer fields, training-effect) are fields we don't capture; TCX has all we need, zero deps.
