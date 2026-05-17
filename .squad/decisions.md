# Squad Decisions

## Active Decisions (Locked — D1–D9)

### 2026-05-14T15:12:57-04:00: AR-Runner v0.1 architecture decisions (D1–D9)

**By:** Joe (via Copilot, decision walkthrough with full squad input)  
**Source:** Synthesis of planning docs from Richards, Laughlin, Weiss, Killian — walked through 1-by-1 with user.

#### D1 — BLE ownership for v0.1
**Decision:** Watch owns the BLE connection to the ActiveLook glasses directly. Phone is not required during workouts.  
**Implication:** No official watchOS SDK exists from ActiveLook — we will build a watchOS BLE wrapper from the iOS SDK's GATT profile. Weiss owns the spike to scope this.  
**Rejected:** B (iPhone-only BLE with watch proxy) — too phone-dependent for the desired "leave phone home" UX.

#### D2 — OS targets
**Decision:** Minimum **watchOS 11** and **iOS 18**.  
**Why:** App Intents on the Action Button require watchOS 11. Xcode 16 + Swift 6 native.  
**Rejected:** B (watchOS 10) — would weaken the Action Button launch experience.

#### D3 — Multi-sport scope
**Decision:** Running-only feature surface in v0.1, but core data models and HUD layout system are **sport-agnostic** from day one. Cycling/walking added in v1 via config, not refactor.  
**Rejected:** A (running-only with no scaffolding) — too narrow given likely v1 expansion.

#### D4 — Glasses disconnect mid-run
**Decision:** Workout continues uninterrupted; subtle haptic alert; "HUD offline" indicator on watch; auto-reconnect in background; gap is logged in run metadata.  
**Rejected:** B (auto-pause) — workout truth lives in HealthKit, not glasses.

#### D5 — Watch-only mode (no phone present)
**Decision:** Supported. Watch + glasses can run a full workout without phone present. Phone is the configuration cockpit + post-run review tool, not a runtime requirement. Config syncs via WCSession when in range.  
**Enabled by:** D1=A.

#### D6 — HUD layout model
**Decision:** Bake 2–3 curated layout presets at build time using ActiveLook Config-Generator. v0.1 phone app lets users PICK between presets; layout editor is a v1 feature.  
**Implication:** Runtime BLE traffic is just field-value updates (~20–40 bytes/tick).  
**Rejected:** Full editor at v0.1 — too much UI scope.

#### D7 — Action Button / shortcut launch behavior
**Decision:** Foreground launch — app opens to the running workout view, matching native Apple Workout UX.  
**Rationale (Joe):** "Most workout apps stay in the foreground."  
**Rejected:** Background-only intent — not worth the spike risk; foreground is the expected behavior.

#### D8 — Swift 6 strict concurrency
**Decision:** Adopt Swift 6 strict concurrency from day one. Use @preconcurrency import at the ActiveLook SDK boundary to escape-hatch any non-Sendable types in the vendor SDK.  
**Rejected:** Swift 5 mode — retrofitting Swift 6 later is significantly more expensive than building strict from the start.

#### D9 — Run history storage
**Decision:** Three-tier storage:  
1. **HealthKit** — primary run data (workouts, HR, distance, splits). v0.1.  
2. **Side store** — minimal AR-specific per-run metadata (layout ID used, BLE drop count, glasses battery at end), keyed by HealthKit workout UUID. v0.1. Implementation TBD — likely JSON in app group container or UserDefaults.  
3. **CloudKit** — user config tier (custom layouts, preferences, defaults). v1, when layout editor lands.  
**Rejected at v0.1:** Full Core Data + CloudKit stack — premature complexity.

**Derived next-step decisions (implied, not yet explicitly confirmed):**
- Phone-initiated workouts: **watch-initiated only** for v1 (phone is mirror/config, not workout-starter). Matches Apple Workout app behavior.
- Customizable HUD: **No** at v0.1; preset selection only. **Yes** in v1 (per D6).

**Open product questions (non-blocking for scaffolding — flagged for Joe later):**
1. **Visual Assets license** — ActiveLook's Activelook-Visual-Assets repo is CC BY-NC-ND. If AR-Runner is ever monetized, we need original art. Currently fine for personal/non-commercial use.
2. **iCloud sync of preferences** — confirmed via D9 (CloudKit in v1 for config tier).
3. **Action Button hardware** — D7 chose foreground, which sidesteps the spike risk entirely. No further test needed.

---

## Planning Session Input (Planning artifacts; D1–D9 supersedes any conflicts)

### Architectural Decisions — Richards (2026-05-14T15:03:23-04:00)
**Status:** Input to D1-D9; see ADR-001 through ADR-007 in docs/planning/architecture.md

**ADR-001: SPM-Shared Core (ARRunnerCore) + Thin App Shells** — Shared ARRunnerCore SPM package consumed by both watchOS and iOS app targets.

**ADR-002: WCSession Typed Message Contract (Codable + schemaVersion)** — All WCSession messages are Codable structs in ARRunnerCore with a schemaVersion: Int field.

**ADR-003: BLE Ownership** — *Superseded by D1.* Planning proposed phone-only; Joe locked watch-primary (D1).

**ADR-004: Minimum OS Targets — watchOS 11 / iOS 18 / Swift 6** — *Locked by D2.* Confirmed watchOS 11, iOS 18, Swift 6 strict concurrency.

**ADR-005: User Preferences — iCloud KV (v0.1), not CloudKit Core Data** — UserPreferences and LayoutConfig persisted via iCloud Key-Value Store.

**ADR-006: Historical Run Storage — HealthKit-only for v0.1** — *Locked by D9.* Rely solely on HealthKit for v0.1; side store for AR-specific metadata.

**ADR-007: GlassesFrameProtocol Abstracted Behind Protocol Boundary** — GlassesFrameProtocol defined as a Swift protocol, not concrete.

Full details in docs/planning/architecture.md.

---

### watchOS Architecture — Laughlin (2026-05-14T15:03:23-04:00)
**Status:** Input to D1-D9; planning doc at docs/planning/watchos-architecture.md

**Key planning points:**
- App shape, workout lifecycle, launch surfaces (Smart Stack, Action Button, Siri, complications)
- Watch–phone sync contract (WatchConnectivity)
- BLE ownership tradeoffs — *Resolved by D1 (watch primary).*
- HKWorkoutSession lifecycle integration

Blocking items flagged: Weiss coordination (D1 requires watchOS BLE wrapper spike), hardware integration testing (Action Button).

Full details in docs/planning/watchos-architecture.md.

---

### ActiveLook Integration Strategy — Weiss (2026-05-14T15:03:23-04:00)
**Status:** Input to D1-D9; research at docs/research/activelook/

**Key planning points:**
- iOS SDK as SPM dependency (tag 4.5.5 or stable)
- Graphics configuration: build-time baked binary via Config-Generator — *Locked by D6.*
- BLE connection ownership: iPhone vs. Watch — *Superseded by D1 (watch primary); Weiss owns watchOS BLE wrapper spike.*
- Metric update rates: 1 Hz HR/pace, 2–5 Hz cadence, 0.2 Hz elevation, 1 Hz timer

Open questions: Watch BLE autonomy (answered by D1), licensing (CC BY-NC-ND), runtime config, real-world BLE latency.

Full details in docs/research/activelook/README.md.

---

### Product Scope: v0.1 MVP Definition — Killian (2026-05-14T15:03:23-04:00)
**Status:** Input to D1-D9; product brief at docs/planning/product-brief.md

**Key planning points:**
- MVP locked to running — *Locked by D3 (running-only feature surface; sport-agnostic core).*
- Three watch launch surfaces (app icon, Smart Stack, Action Button) — *Matched D7 (foreground launch).*
- HUD minimalism v0.1 → customization v1 — *Locked by D6 (curated presets, no editor at v0.1).*
- Offline-first, no cloud accounts — *Matched D9 (HealthKit primary, CloudKit in v1).*
- Phone secondary (live mirror, not control) — *Matched D5 (watch-initiated workouts).*
- HealthKit mandatory for v0.1 — *Locked by D9.*

Open questions answered by Joe walkthrough (D1-D9).

Full details in docs/planning/product-brief.md.

---

## Session 2026-05-14: Foundation Scaffold & BLE Spike (Laughlin, Weiss)

### 2026-05-14T15:41:26-04:00: User directive — Track Squad Logs
**By:** Joe (via Copilot)

`.squad/log/` and `.squad/orchestration-log/` are tracked in git going forward — NOT gitignored. This aligns with the `merge=union` drivers in `.gitattributes` for those paths. The previous gitignore exclusion was inherited boilerplate and is incorrect for this project. Scribe should stage these files normally (no `-f` flag needed once `.gitignore` is fixed).

**Rationale:** User request — captured for team memory. Resolves contradiction between `.gitignore` and `.gitattributes`.

---

### 2026-05-14T15:44:37-04:00: User directive — No Direct Main
**By:** Joe (via Copilot)

From now on, NO work happens directly on `main`. All changes — code, docs, squad state — land via feature branches and pull requests. `main` is the protected integration line.

Branch naming convention: `feat/{slug}` for features, `spike/{slug}` for research, `fix/{slug}` for bug fixes, `chore/{slug}` for maintenance.

**Rationale:** User request — captured for team memory. Standard branch hygiene.

---

### 2026-05-14T15:44:37-04:00: Laughlin — v0.1 Scaffolding Implementation Note

**Decision:** Use a **single-target watchOS app** (`ARRunnerWatch`) for the foundation scaffold instead of adding a separate watch extension target, and place the foreground `StartWorkoutIntent` inside the shared WidgetKit extension (`ARRunnerWidgets`) rather than creating a standalone `ARRunnerAppIntents` target.

**Why:**
- Modern SwiftUI watchOS apps no longer need a separate extension target for basic lifecycle scaffolding.
- The watch workout is foreground-launched per D7, so a dedicated intents extension is unnecessary at v0.1 scaffold depth.
- Keeping the intent in the widget target keeps the launch surfaces together for Smart Stack and quick-start flows while the core app shells remain thin.
- This keeps `project.yml` smaller and easier for Joe to generate and inspect on macOS before real capabilities and signing are finalized.

**Follow-up:** If Action Button or Shortcuts integration later needs a separately signed intent surface, split `StartWorkoutIntent` into a dedicated app intents target after hardware validation.

---

### 2026-05-14T15:44:37-04:00: Weiss — Spike Verdict: watchOS BLE for ActiveLook Glasses (D1 Implementation)

**Status:** Spike Complete — Ready for Build Phase  
**Related Decision:** D1 (Watch owns BLE connection directly)

**Verdict: 🟢 YES — Feasible to Proceed with v0.1**

**Summary:**
Decision D1 locked watch-primary BLE ownership. This spike confirms: **watchOS 11 CoreBluetooth can successfully wrap the ActiveLook GATT profile for v0.1 ARRunner workouts.**

- **Feasibility:** 🟢 Confirmed
- **Scope:** Medium (~2–3 weeks)
- **Risks:** Manageable; no blockers
- **Recommendation:** Proceed with watchOS BLE wrapper build in v0.1

**Key Findings:**

1. **GATT Profile:** ActiveLook uses standard BLE GATT with 5 characteristics in a custom service (`0783B03E-8535-B5A0-7140-A304D2495CB7`). RX (write) and TX (notify) are the primary paths; Control characteristic handles flow control. No proprietary extensions block watchOS.

2. **CoreBluetooth Availability:** `CBCentralManager`, `CBPeripheral`, and `CBCharacteristic` are fully available on watchOS 11+. Central role (client) is fully functional. No restore identifiers on watchOS (reconnection must be explicit).

3. **Background Privilege:** BLE scanning and connection persist **only during active HKWorkoutSession**. This is the critical dependency: BLE lifecycle ties directly to workout lifecycle (owned by Laughlin's `WorkoutSessionManager`).

4. **Protocol Budget:** Binary framing is simple (`0xFF + CommandID + Length + Data + 0xAA`). Command size ~20–40 bytes; sustainable rate is 1–2 Hz for metrics (~100 bytes/sec, ~7% of BLE practical limit). MTU negotiation tested; fragmentation fallback works.

5. **Risks & Mitigations:**
   - MTU negotiation (Medium): Implement chunked writes; early hardware stress-test
   - HKWorkoutSession drops (Low): Auto-reconnect with exponential backoff; log in metadata
   - Latency > 200ms (Low): Profile on real hardware (Watch SE + glasses); fallback to write-without-response
   - No deadlock risks (Low): Use continuation bridge for CB delegates; follow Swift 6 actor isolation rules

**Effort Estimate:**

| Phase | Effort | Timeline |
|-------|--------|----------|
| **Week 1:** BLE discovery, connection state machine, TX/RX wiring | 200–250 LOC | Core plumbing |
| **Week 2:** Command framing, flow control, reconnection, error handling | 250–300 LOC | Protocol impl |
| **Week 3:** Integration with `WorkoutSessionManager`, metrics pipeline, stress-test | 100–150 LOC | Integration & validation |
| **Total** | ~600 LOC | 2–3 weeks |

**Integration Points:**

1. **Tie to HKWorkoutSession:** BLE manager must start when workout starts, stop when session ends.
2. **Define `GlassesFrameTransport` protocol** in ARRunnerCore (placeholder in architecture ADR-007).
3. **Wire metrics pipeline:** `WorkoutTick` (1 Hz from HealthKit) → `updateField(layoutId:fieldIndex:value:)` → BLE write.
4. **Log BLE drops** in run metadata (per D9, side store for AR-specific data).

**Next Steps (Handoff to Build Phase):**

1. **Laughlin:** `WorkoutSessionManager` owns HKWorkoutSession lifecycle; expose hooks for BLE start/stop.
2. **Weiss:** Implement `ActiveLookGlasses` actor (stub provided in spike memo) + command framing + reconnection logic.
3. **Richards:** Define `GlassesFrameTransport` protocol boundary in ARRunnerCore; align with metrics pipeline.
4. **All:** Hardware validation in week 3 — profile latency, stress-test battery impact, measure round-trip delays.

**Detailed findings:** See `docs/research/activelook/watchos-ble-spike.md`

---

## Session 2026-05-14: Foundation Smoke Test & Development Operations

### 2026-05-14T16:28:08-04:00: Amber — macOS Build Validation (v0.1 scaffold)

**Date:** 2026-05-14T16:28:08-04:00  
**Author:** Amber (QA & Fitness Domain)  
**Branch / PR:** `chore/macos-build-validation` (commit ecb8179, pushed)  
**Verdict:** 🟢 **Green — scaffold ships clean on macOS after surgical fixes.**

**Summary:** First macOS build of the v0.1 scaffold (authored on Windows). All four xcodebuild targets and the `swift test` suite are green. Three scaffold bugs caught and fixed before Weiss / Laughlin / metrics work stacks on top.

**Test results:**
- ARRunnerCore unit tests: 6/6 pass (`swift test`).
- App builds: ARRunnerWatch, ARRunnerPhone, ARRunnerWidgetsPhone, ARRunnerWidgetsWatch — all 🟢 with `CODE_SIGNING_ALLOWED=NO`.
- Swift 6 strict concurrency: zero warnings across scaffold. D8 is in good shape.

**Fixes landed:**
1. ARRunnerWatch: `application.watchapp2` (legacy) → `application` + `WKApplication: true`.
2. ARRunnerWidgets: split single shared appex into per-platform `ARRunnerWidgetsPhone` + `ARRunnerWidgetsWatch`, sharing one `ARRunnerWidgets/` source directory (required by app-extension parent-prefix rule; preserves Laughlin's single-codebase intent).
3. `StartWorkoutWidget.supportedFamilies`: gated `.systemSmall` behind `#if !os(watchOS)`.
4. `.gitignore`: added `*.xcodeproj/`, `Config/`, `.build/`, `DerivedData/`, `.swiftpm/`, etc. (xcodegen-derived).
5. `docs/dev/setup.md`: corrected workspace reference (no `.xcworkspace` produced; `.xcodeproj` only).

**Follow-up items (not blockers):**
- **Joe — signing/capabilities:** Wire `DEVELOPMENT_TEAM` and confirm HealthKit / Bluetooth / app-group entitlements before on-device run.
- **Laughlin — AppIntents framework link:** Build warning goes away once parent target imports AppIntents or wires intent into launch flow.
- **Weiss — BLE wrapper:** D8 surface is clean; recommend `@preconcurrency import` at ActiveLook iOS SDK boundary. No scaffold-level concerns.
- **Watch Smart Stack:** currently `[.accessoryRectangular]` only on watchOS. Re-check against D7 launch surfaces when Laughlin wires Action Button / Smart Stack flow.

**Artifacts:** 
- Findings: `docs/dev/macos-build-validation.md`
- Reusable pattern: `.squad/skills/xcodegen-shared-widget-per-platform/SKILL.md`
- Related decisions: D2 (watchOS 11 / iOS 18), D7 (foreground intent launch), D8 (Swift 6 strict concurrency)

---

## Session 2026-05-14: Foundation & Development Operations (cont.)

### 2026-05-14T16:09:31-04:00: User directive — dev workflow split

**By:** Joe (via Copilot)

**What:** AR-Runner development is split across two environments:
- **Windows** — Squad coordination, agent-driven code generation, editing Swift source / project.yml / docs / Markdown, git operations, PR review on GitHub.
- **Mac** — Running `xcodegen generate`, compiling Swift against Apple frameworks (HealthKit/WatchKit/WidgetKit/CoreBluetooth), running Simulator, BLE testing against real ActiveLook glasses, code signing, TestFlight, App Store.

Cadence: spawn agents → review PR → switch to Mac → build/run/verify → repeat.

**Why:** User request — practical operational pattern for the project. ARRunnerCore is theoretically Linux-compileable (pure Swift, no Apple frameworks), so future CI could `swift test` on Linux, but Mac is the current build authority.

---

### 2026-05-14T16:09:31-04:00: Tooling decision — XcodeGen for project generation

**By:** Joe (via Copilot) — codified during v0.1 foundation scaffolding

**What:** The Xcode workspace and project files are GENERATED from `project.yml` via XcodeGen (`brew install xcodegen` on Mac). The repo does NOT commit `.xcodeproj` or `.xcworkspace` bundles. Source of truth is `project.yml` + Swift sources + `Package.swift` files.

To work locally:
1. Clone repo
2. On Mac, run `xcodegen generate` from repo root
3. Open `AR-Runner.xcworkspace`

**Why:** (1) Editable from non-Mac environments (Squad on Windows). (2) Eliminates `.xcodeproj` merge conflicts. (3) Reproducible: anyone running `xcodegen generate` gets identical project. (4) Reviewable: `project.yml` diffs make sense in PRs. Standard pattern for 2026-era Swift mixed-environment projects.

---

### 2026-05-14T16:32:00-04:00: User directive — Claude Opus 4.7 for code-writing agents

**By:** Joe Krilov (via Copilot)

**What:** Code-writing agents (Laughlin, Weiss, Amber, Richards) must use `claude-opus-4.7-1m-internal` as their default model. Persistent across sessions via `.squad/config.json` → `agentModelOverrides`. Scribe and Ralph remain on `claude-haiku-4.5` (mechanical ops). Killian remains on auto/haiku.

**Why:** User request — captured for team memory. Opus 4.7 1M-context is the top tier currently available; Joe wants highest quality on actual code production.

---

---

## 2026-05-14T16:51:53-04:00: CI / Security Workflow Architecture (Richards, Lead / Architect)

**Branch:** `chore/ci-workflows` (off `chore/macos-build-validation`)
**Status:** Proposed — pending merge of PR
**Related:** D1–D9, "No Direct Main" directive (2026-05-14T15:44:37-04:00), Amber's macOS build validation (2026-05-14T16:28:08-04:00), XcodeGen tooling decision (2026-05-14T16:09:31-04:00)

### What

Add three CI workflows to `.github/workflows/`, sitting alongside the Squad orchestration workflows but reserved under their own naming prefix (`ci-*.yml` for build/test, `codeql.yml` for security; `squad-*.yml` remains orchestration-only):

1. **`ci-core-tests.yml`** — Linux runner, `swift:6.0-jammy` container, `swift test` on `ARRunnerCore`.
2. **`ci-build.yml`** — macOS-15 runner, 4-way matrix, `xcodegen generate` + `xcodebuild` for `ARRunnerWatch`, `ARRunnerPhone`, `ARRunnerWidgetsPhone`, `ARRunnerWidgetsWatch`.
3. **`codeql.yml`** — macOS-15 runner, GitHub CodeQL Swift analysis with `security-extended` queries on PR + weekly schedule.

Full operational documentation is in `docs/dev/ci-workflows.md`.

### Why

Two real-code branches are about to land (Weiss's BLE wrapper, Laughlin's `WorkoutController`). Without CI, those PRs go in on the strength of one local macOS build per author. Amber's validation pass found three real scaffold bugs that would have shipped silently — every subsequent PR has the same exposure. CI is the cheapest insurance we'll ever buy on this project.

### The decisions, with trade-offs

#### ADR — Runner mix: Linux for Core, macOS for shells

**Decision:** Split `swift test` (Linux) from `xcodebuild` (macOS).

**Spike result:** `ARRunnerCore` imports only `Foundation` (sources) and `XCTest` + `Foundation` (tests). No HealthKit, CoreBluetooth, WatchKit, WatchConnectivity, UIKit, AppKit. `SwiftPM`'s `platforms:` block is a minimum-Apple-version declaration — it doesn't gate Linux compilation. The pure-Swift Core compiles and tests cleanly on Linux Swift 6.

**Alternatives considered:**
- **All-macOS.** Simpler — one runner type, one mental model. Costs ~10x per minute. With macOS billed at 10x Linux and core tests being the most-frequently-failing job (every PR exercises model serialization), the rational answer is to keep the fast-iterating job on the cheap runner.
- **All-Linux.** Impossible — app shells need Apple SDKs (WatchKit, HealthKit, WidgetKit, UIKit).

**Cost of the chosen split:** ARRunnerCore *must* stay platform-agnostic. The moment someone imports HealthKit into Core, this job fails on Linux. **That cost is actually a feature** — it enforces ADR-001 (SPM-shared Core) and ADR-007 (`GlassesFrameProtocol` behind a protocol boundary) mechanically. Trade named, accepted.

#### ADR — Trigger strategy: PR + push-to-main only

**Decision:** Workflows run on `pull_request` (any base) and `push` to `main`. Never on branch pushes outside of a PR.

**Alternative:** Run on every branch push. Faster feedback for devs working locally, but Apple-Watch devs already have a Mac on their desk (D-2026-05-14T16:09:31-04:00 dev workflow split) — they get faster feedback running `xcodebuild` directly. Branch-push CI would burn macOS minutes for marginal value.

**Cost:** A dev who pushes a branch without opening a PR gets no signal until they file the PR. Acceptable — opening a PR is one click.

#### ADR — Concurrency cancellation on PRs, not on main

**Decision:** All three workflows use `concurrency: { group: ..., cancel-in-progress: ${{ github.event_name == 'pull_request' }} }`. Rapid pushes to a PR branch cancel in-flight runs; pushes to `main` are never cancelled.

**Why:** macOS minutes are the budget. A dev rebasing or force-pushing a PR five times shouldn't cost five full matrix builds. But on `main`, we want a clean, linear, never-cancelled history of green/red. Different audiences, different policies.

#### ADR — Caching strategy

**Decision:**
- Linux: cache `ARRunnerCore/.build` + `~/.cache/org.swift.swiftpm`, keyed on `Package.swift` + `Package.resolved`.
- macOS: cache `~/Library/Caches/org.swift.swiftpm`, `DerivedData/**/SourcePackages`, and `DerivedData` itself, keyed on `project.yml` + `Package.swift`.

**Trade-off named:** DerivedData caches are large (hundreds of MB) and frequently invalidated by Xcode version drift. They will sometimes miss; that's fine — they're an optimization, not correctness. If cache restore costs ever exceed cache-hit savings, drop the DerivedData cache and keep only the SPM caches.

#### ADR — CodeQL builds only ARRunnerWatch

**Decision:** CodeQL drives off a single `xcodebuild` of `ARRunnerWatch` (the largest single dependency closure — pulls Core + watch shell + widget extension). Not the full matrix.

**Alternative:** Build all four schemes under CodeQL. Marginal coverage gain (CodeQL re-analyses the same Swift sources), large minute cost (CodeQL Swift is the slowest of the three workflows).

**Cost:** If a phone-only or widget-only file is somehow never visited by the watch build's compile, CodeQL won't analyze it. In practice, Core is the only shared compile unit and it's visited. Acceptable.

#### ADR — `security-extended` queries

**Decision:** Use the `security-extended` CodeQL query suite, not just the default.

**Trade-off:** ~30% more analysis time, broader rule coverage. For a security-sensitive surface (BLE pairing, HealthKit data handling, App Group sharing), the extra signal is worth the minutes.

### Punt list — what we are deferring and why

| Concern | Status | Rationale |
| --- | --- | --- |
| Lint (swiftlint vs swift-format) | **Deferred** | Joe + Richards to pick a tool with intent, not under deadline. No code has been written yet that exercises the difference. TODO captured in `docs/dev/ci-workflows.md`. |
| Code coverage | **Deferred** | Coverage on a scaffold-only test suite (6 Codable round-trips) is theatre. Re-evaluate after Weeks 1–3 of Weiss + Laughlin land real logic. |
| Release / TestFlight | **Out of scope** | Requires signing identity + secrets management. Separate workflow, separate decision. |
| Dependabot | **Deferred** | Zero external SPM deps today. Enable when ActiveLook SDK or any other vendor SPM dep lands. |
| Branch protection / required checks | **Manual** | Joe needs to toggle "Require status checks to pass before merging" on `main` after first green run. Workflows are designed to be the contract. |
| Linux build of app shells | **Not viable** | App shells depend on WatchKit / UIKit / HealthKit / WidgetKit — Apple-only. |

### What Weiss and Laughlin need to know

1. **Don't import Apple-framework code into `ARRunnerCore`.** It will fail the Linux core-tests job and block your PR. Concrete Apple-framework code lives in the app/extension targets. Use protocol boundaries in Core (ADR-007).
2. **Your PR must pass three required check sets**: `ci-core-tests`, all 4 `ci-build` matrix jobs, and `codeql`. Plan for ~15 min of CI time per PR after cache warm-up.
3. **Local validation matches CI 1:1.** See the repro block in `docs/dev/ci-workflows.md`. If it builds locally, it builds in CI — and vice versa.
4. **`@preconcurrency import` of the ActiveLook SDK stays in the watch/phone targets**, not Core. This was already the D8 plan; it's now mechanically enforced by the Linux core-tests job.

### Verification

This branch (`chore/ci-workflows`) sits on top of `chore/macos-build-validation` (Amber's three scaffold fixes), so the workflows are validated against the post-fix scaffold. When `chore/macos-build-validation` merges to `main`, this branch rebases cleanly.

### Files

- `.github/workflows/ci-core-tests.yml`
- `.github/workflows/ci-build.yml`
- `.github/workflows/codeql.yml`
- `docs/dev/ci-workflows.md`
- `.squad/skills/swift-linux-macos-runner-split/SKILL.md` (reusable pattern)

---

---

## 2026-05-14T17:08:00-04:00: StrictConcurrency Upcoming-Feature Flag Cleanup (Richards)

**Status:** Implementation Complete — D8 Reinforced  
**PR:** #3 (chore/ci-workflows)  
**Commits:** 350eae0, 39bfa07

### Context

PR #3 failed all 5 CI checks with:
> error: upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6

Two redundant declarations were found:
1. `ARRunnerCore/Package.swift` — `.enableUpcomingFeature("StrictConcurrency")`
2. `project.yml` — `SWIFT_STRICT_CONCURRENCY: complete`

Both are unnecessary under Swift 6 language mode. Swift 6.0 CI treats the flag as an error; Swift 6.3.2 locally tolerated it silently — the classic toolchain-version gap.

### Decision

Removed both redundant declarations. Swift 6 language mode (`swift-tools-version: 6.0` + `.swiftLanguageMode(.v6)` + `SWIFT_VERSION: 6.0`) is the single source of truth.

**D8 unchanged.** Strict concurrency remains mandatory — it's just implicit now, not explicit.

### Standing rule for team

- **Do NOT** add `.enableUpcomingFeature("StrictConcurrency")`, `SWIFT_UPCOMING_FEATURE_STRICT_CONCURRENCY`, or `SWIFT_STRICT_CONCURRENCY` flags.
- **DO** ensure new packages declare `swift-tools-version: 6.0` (or higher) + `.swiftLanguageMode(.v6)`.
- **DO** ensure new Xcode targets inherit `SWIFT_VERSION: '6.0'` from project.yml.
- CI is the authoritative compiler; local toolchains run ahead — deprecated flags may silently pass locally but hard-fail CI.

### For Laughlin & Weiss

When importing Apple samples or third-party SDK examples (especially ActiveLook), strip `.enableUpcomingFeature("StrictConcurrency")` lines on import — it's a CI-breaker under Swift 6.0 even though local builds may pass.
## Session 2026-05-15: Public-Repo Preparation & Review

### 2026-05-15: Richards & Joe — ActiveLook Visual Assets Hard Rule (Permanent Decision)

**Author:** Richards (Lead / Architect)  
**Date:** 2026-05-15  
**Status:** Approved by Joe Krilov 2026-05-15. Lock as permanent decision.

**Decision:** AR-Runner will not commit any asset, font, layout template, or generated config from the `ActiveLook/Activelook-Visual-Assets` or `ActiveLook/Config-Generator` repositories. Original art only.

This applies to icons, fonts, PNGs, prebuilt layouts, `cfgDescriptor/` files, and any binary configs produced by `Config-Generator`. Any HUD layouts, glyphs, or visual presets that AR-Runner ships must be authored from scratch under the project's Apache 2.0 outbound license.

**Rationale:** The two ActiveLook visual-asset repositories are licensed **CC BY-NC-ND 4.0** (Attribution-NonCommercial-NoDerivatives). That license is **incompatible** with AR-Runner's Apache 2.0 outbound license on three axes:
1. **NonCommercial (NC):** Apache 2.0 permits commercial use; CC BY-NC-ND forbids it.
2. **NoDerivatives (ND):** Apache 2.0 permits modification; CC BY-NC-ND forbids derivative works.
3. **Sub-licensability:** Apache 2.0 is freely sub-licensable; CC BY-NC-ND is not.

The ActiveLook **iOS SDK** itself (`ActiveLook/ios-sdk`) is Apache 2.0 and is fine to consume via SPM — this rule is strictly about visual/config assets from the other two repos.

**Enforcement:** Killian (product) and Weiss (ActiveLook integration) are the natural owners of any future "should we ship layout X?" call. Code reviewers should reject PRs that add files from those two upstream repos.

---

### 2026-05-15: Richards & Joe — Public-Repo Prep Locked

**Author:** Richards (Lead / Architect)  
**Date:** 2026-05-15  
**Status:** Approved by Joe Krilov 2026-05-15. Implementation in PR `chore/public-repo-prep`.

**Context:** Richards delivered a public-repo readiness audit recommending 14 cleanup items before flipping `jkrilov/AR-Runner` from private to public. The audit closed with 5 open questions for Joe. Joe answered all 5 verbatim on 2026-05-15. This entry locks those answers into the ledger.

**Joe's 5 answers:**
1. **License:** Apache 2.0
2. **Copyright holder:** Joe Krilov
3. **ActiveLook visual-assets hard rule:** YES, lock as permanent decision. (See sibling entry above.)
4. **Outside-PR posture in CONTRIBUTING.md:** Paused until v0.1 lands (issues for discussion welcome; PRs paused so foundation can settle)
5. **Squad-system in README:** Light footnote (credit + brief explanation, doesn't lead the README)

**Implementation in `chore/public-repo-prep` (PR #4):**
| Item | File(s) |
|------|---------|
| Apache 2.0 LICENSE with `Copyright 2026 Joe Krilov` footer | `LICENSE` (new) |
| SPDX two-line headers on all 23 committed `.swift` files | `ARRunnerCore/`, `ARRunnerWatch/`, `ARRunnerPhone/`, `ARRunnerWidgets/` |
| Light SECURITY.md (PVR pointer, best-effort, no SLA) | `SECURITY.md` (new) |
| CONTRIBUTING.md (paused-until-v0.1) | `CONTRIBUTING.md` (new) |
| README status callout + Squad footnote + license line | `README.md` (modified) |

| ActiveLook visual-assets hard rule decision drop | Above |
| This decision drop | This entry |

**Locked downstream policies:**
- **Outside PRs paused until v0.1.** CONTRIBUTING.md is the canonical statement; revisit when v0.1 ships.
- **SPDX header pattern is locked** as the project convention for any new `.swift` source file:
  ```swift
  // SPDX-FileCopyrightText: 2026 Joe Krilov
  // SPDX-License-Identifier: Apache-2.0
  ```
  New files added in any future PR must include this header. Reviewers should reject PRs that add untagged Swift sources.
- **README's primary job remains explaining AR-Runner the product.** The Squad footnote is a footer-level credit, not a framing device.
- **Vulnerability reports route through GitHub Private Vulnerability Reporting** once the repo is public and PVR is enabled in repo settings.

**Not yet done (deferred to Joe + post-merge):** Flip visibility, apply repo-settings changes (branch protection, PVR, Dependabot alerts, secret scanning, Discussions), tag `v0.1.0-pre`, open welcome Discussion.

---

### 2026-05-15: Killian — PR #4 Review Verdict (Public-Repo Prep)

**Author:** Killian (Product Strategist)  
**Date:** 2026-05-15  
**Status:** 🟡 Approved with non-blocking nits  
**PR:** https://github.com/jkrilov/AR-Runner/pull/4

**Verdict:** PR #4 is approved to merge. Richards's implementation matches the 5 locked answers from Joe and the audit's 14-step checklist. No material issues found.

**Nits (non-blocking — for Joe to decide: fold in or punt):**
- **Nit A:** Add a hyperlink to ActiveLook (website or GitHub org) on first mention in README so strangers can orient.
- **Nit B:** CONTRIBUTING.md doesn't tell outside readers how to know when v0.1 ships. One-liner pointing to the Releases page would help.
- **Nit C:** No CODE_OF_CONDUCT.md. GitHub's community profile will flag it once public. A minimal file would close the gap.

---

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
# Amber — CI: Apple-platform runtime install on GitHub-hosted macOS runners

**Date:** 2026-05-14T17:33:30-04:00
**Author:** Amber (QA & Fitness Domain)
**Branch:** `chore/ci-workflows`
**PR:** #3
**Status:** Applied — workflow change in `.github/workflows/ci-build.yml`; doc + skill updates landed in same commit.

## Context

PR #3 (CI workflows) had three failing checks after Richards's runtime-install attempt (commit `079cb73`): `ARRunnerWatch`, `ARRunnerWidgetsWatch`, and `ARRunnerWidgetsPhone`. Only `ARRunnerPhone` and the Linux `ci-core-tests` were green.

Two distinct symptoms; **one underlying cause**:

1. **Both watchOS cells** failed at the new `Install watchOS simulator runtime` step:
   ```
   Finding content...Unable to connect to simulator.
   ##[error]Process completed with exit code 70.
   ```
   `xcodebuild -downloadPlatform watchOS` cannot run unattended on GitHub-hosted runners — exit 70 is Apple's "this command needs an interactive Apple ID auth session" error.

2. **`ARRunnerWidgetsPhone`** (which had been passing) failed destination resolution:
   ```
   xcodebuild: error: Unable to find a destination matching the provided destination specifier:
     { generic:1, platform:iOS Simulator }
   Ineligible destinations for the "ARRunnerWidgetsPhone" scheme:
     { platform:iOS, ..., name:Any iOS Device, error:iOS 18.0 is not installed }
   ```
   The destination string in the workflow was `generic/platform=iOS Simulator` — correct, unchanged from the prior passing run. The actual cause was the **iOS 18.0 simulator runtime missing on the macos-15 image** under the pinned `Xcode_16.app` (16.0). `ARRunnerPhone` happens to pass under the app-scheme destination resolver while the widget-extension scheme is stricter (mirror of the watchOS asymmetry Richards already documented).

> Note for the record: the original task brief told me `name:Any iOS Device` was a smoking gun that Richards had edited the destination to `generic/platform=iOS` (real device). It wasn't. `Ineligible destinations:` is xcodebuild's enumeration of destinations it considered and rejected; when no simulator runtime is installed, the only candidate that survives enumeration is the device placeholder. The destination string was correct; the runtime was missing. Reading the full xcodebuild error block (not just the `name:` field) is what caught this.

## Decision

**Pin Xcode 16.4 via `maxim-lobanov/setup-xcode@v1` and remove the `xcodebuild -downloadPlatform` step entirely.**

```yaml
- name: Select Xcode
  uses: maxim-lobanov/setup-xcode@v1
  with:
    xcode-version: '16.4'
```

Rationale:

- Per the [`actions/runner-images` macos-15 manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md), Xcode 16.4 is the **default** Xcode on the current macos-15 image and ships with **iOS 18.5 + watchOS 11.5 simulator runtimes pre-installed** — both ≥ our D2 minimums (iOS 18 / watchOS 11).
- xcodebuild builds against the newest installed SDK ≥ deployment target, so iOS 18.5 / watchOS 11.5 SDKs are fine for our iOS 18 / watchOS 11 minimums.
- No download step needed → no auth problem, no exit-70 failure mode, ~3–5 min wall-clock saved per watchOS cell.
- Skips an entire failure surface: when the runner image rotates and the `Xcode_16.app` symlink shifts under us, the explicit `xcode-version: '16.4'` pin keeps behavior stable as long as 16.4 stays on the image.

## Lessons

1. **`xcodebuild -downloadPlatform` does not work unattended on CI.** It needs Apple ID auth and exits 70 on GitHub-hosted runners. Anyone who reaches for it in CI will hit this wall. Use a Xcode-pin or `xcrun simctl runtime add`-with-cached-DMG instead.

2. **Pinning Xcode by symlink path (`/Applications/Xcode_16.app`) is brittle.** That symlink can shift across runner image revisions, and the simulator runtimes that ship with a given Xcode can change between point releases. Pin explicitly via `setup-xcode@v1` + `xcode-version`.

3. **Cross-check both "Installed SDKs" and "Installed Simulators" in the runner image manifest.** An SDK without a matching simulator runtime is a destination-resolution trap. The manifest is the source of truth — check it before pinning.

4. **`Ineligible destinations:` is an enumeration, not a destination-spec diagnosis.** The `name:Any iOS Device` line in the error block is not evidence the destination string was wrong; it's evidence no simulator runtimes are installed for the target platform.

## Trade-offs named

- **Lock-in to Xcode 16.4 / iOS 18.5 / watchOS 11.5 image revision.** When GitHub eventually deprecates 16.4 from the macos-15 image (or moves to macos-26 default), CI breaks loudly. The fix at that point is a one-line bump. Documented in the workflow comment.
- **One additional first-party action dependency** (`maxim-lobanov/setup-xcode@v1`). Widely used, MIT-licensed, no secrets required. Acceptable.
- **Runtime-install workflows that genuinely need a runtime not pre-baked into any image** would still need Option B (cached `.dmg` + `xcrun simctl runtime add`) or Option C (`mxcl/xcodes-action@v1`). For AR-Runner today, neither is needed.

## Files changed

- `.github/workflows/ci-build.yml` — replaced `xcode-select` step with `maxim-lobanov/setup-xcode@v1` pinned to 16.4; removed `Install watchOS simulator runtime` step.
- `docs/dev/ci-workflows.md` — added "Why pin Xcode 16.4" paragraph to the `ci-build.yml` section.
- `.squad/skills/swift-linux-macos-runner-split/SKILL.md` — extended the watchOS-runtime gotcha section with the `-downloadPlatform` failure mode and the right fix.

## Lockout note (for Scribe)

Richards owns the original CI implementation and the StrictConcurrency fix. His most recent fix (the `-downloadPlatform` step) introduced these regressions; Joe routed the revision to me for fresh perspective. Strict reviewer-rejection lockout doesn't formally apply (CI is automated, not a reviewer verdict), but the routing reflects the same intent. My local validation (Xcode 26.5 / Swift 6.3.2) is the source of truth for the destination strings; CI runner-image manifest is the source of truth for what runtimes ship pre-installed.
---

---

## Public-Repo Readiness Audit — Richards (2026-05-15T09:49:00-04:00)

**Status:** Recommendation — pending Joe approval  
**Full audit:** docs/dev/public-repo-readiness.md

### Verdict

🟡 **Go public after a small, well-scoped cleanup pass.** Estimated 30–60 min of work + one PR cycle.

### Top 3 must-dos before flipping visibility

1. **Redact  username** (``) — single occurrence in `.squad/orchestration-log/2026-05-14T20-48-00Z-amber.md:46`.
2. **Add LICENSE (Apache 2.0)** + 2-line SPDX headers on ~20 committed `.swift` files.
3. **Add SECURITY.md, CONTRIBUTING.md, status banner in README.md** — light versions for personal-project scope.

### Hard rule to lock into the ledger

**AR-Runner shall not commit any asset, font, or layout template from ActiveLook/Activelook-Visual-Assets or ActiveLook/Config-Generator.** Both are CC BY-NC-ND 4.0, incompatible with permissive OSS. Original art only.

If AR-Runner remains permanently non-commercial, the licensing recommendation flips (source-available, non-commercial). Joe's call.

### Open questions for Joe (5)

1. **Apache 2.0 confirmed?** (vs. MIT — Apache better fit.)
2. **Copyright holder string** — `Joe Krilov`?
3. **ActiveLook visual-assets policy** — adopt the hard rule above?
4. **Outside-PR posture** — paused-until-v0.1 or open from day one?
5. **Squad-system tone in README** — explicit mention, light footnote, or no mention?

### Reviewer protocol note

When the prep PR lands, reviewer must not be Richards (authored both audit + plan). **Recommend Killian** — product perspective benefits the README/status framing.

---

## v0.1 Foundation Workstreams (2026-05-15T12:51:36-04:00)

# Decision drop: GlassesFrameTransport protocol surface (v0.1)

**Author:** Weiss
**Date:** 2026-05-15T12:51:36-04:00
**PR:** https://github.com/jkrilov/AR-Runner/pull/5
**Status:** Proposed (locks in once Joe merges PR #5)

## Decision

The `GlassesFrameTransport` protocol — the abstraction Amber's mock and Laughlin's `WorkoutSessionManager` consume — is now stabilised at the following surface:

```swift
public protocol GlassesFrameTransport: Sendable {
    var connectionState: GlassesConnectionState { get async }
    func connectionStates() async -> AsyncStream<GlassesConnectionState>
    func statusEvents() async -> AsyncStream<GlassesStatusEvent>
    func connect() async throws
    func disconnect() async throws
    func selectLayout(id: String) async throws
    func updateField(_ update: HUDFieldUpdate) async throws
    func updateFields(_ updates: [HUDFieldUpdate]) async throws  // default impl
}
```

Supporting Sendable value types (also in `ARRunnerCore`):
- `GlassesConnectionState` — `disconnected | scanning | connecting | connected | reconnecting | failed`
- `GlassesStatusEvent` — `batteryLevel | signalQuality | dropped(reason, at) | reconnected(gap, at) | reconnectAttemptFailed(attempt, nextDelay)`
- `GlassesDisconnectReason` — `userInitiated | linkLoss | peerPoweredOff | hostUnavailable | unknown(code)`
- `HUDFieldUpdate(layoutID: String, fieldIndex: UInt8, value: String)`
- `GlassesTransportError` — `notConnected | unknownLayout(id) | bluetoothUnavailable | writeFailed(reason) | scanTimeout`
- `ExponentialBackoff` — pure value, default 1s → 8s, multiplier 2.
- `CuratedLayoutCatalog` — string ID → on-device numeric slot map (placeholder values pending the layout BUILD step).

## Why

- **D8 (Swift 6 strict concurrency):** every method `async`, every type `Sendable`, no `@MainActor` leakage. Streams are `async`-getters so an `actor` conformance is trivial.
- **D4 (workout never blocks):** `connectionStates()` + `statusEvents()` give the watch UI and run-metadata side store enough signal to render "HUD offline" and log gaps without ever pausing the workout.
- **D6 (runtime = field-value updates):** `updateField(_:)` is the hot path; bulk `updateFields(_:)` lets adapters coalesce into one BLE write later if profiling demands it.
- **Vendor-agnostic:** no `CBUUID` / `Data` types in the protocol — Amber can mock and Laughlin can consume without importing CoreBluetooth.

## Reconnect strategy (locked)

Per D4, on unexpected disconnect:
1. Transition to `.reconnecting`.
2. Emit `.dropped(reason:, at:)` once.
3. Run an exponential-backoff loop (`ExponentialBackoff`, default 1s → 8s) calling `beginConnect()`.
4. Each failed attempt emits `.reconnectAttemptFailed(attempt:, nextDelay:)`.
5. On success, emit `.reconnected(gap:, at:)`, transition `.connected`, re-apply the active layout.
6. Loop ends when `disconnect()` is called by the host (sets `userDisconnectRequested`).

The workout MUST NOT pause during any of this; the watch UI shows "HUD offline" off the connection-state stream.

## Encoding / wire format (locked)

ActiveLook GATT frame: `0xFF | cmdID | format | length(1-2) | queryID? | data | 0xAA` — see `ActiveLookCommand` for the encoder. Tested exhaustively for 1- vs 2-byte length promotion and queryID encoding.

GATT UUID constants live in `ActiveLookGATT` as plain strings (not `CBUUID`) so `ARRunnerCore` stays Linux-buildable.

## What this does NOT decide

- Real curated layout binaries (the layout BUILD step) — still deferred per D6.
- Phone-side BLE — N/A per D1.
- Run-metadata side store integration with `JSONARMetadataStore` — Laughlin's PR.
- Any change to D1–D9.

## Files

- `ARRunnerCore/Sources/ARRunnerCore/Protocols/GlassesFrameTransport.swift`
- `ARRunnerCore/Sources/ARRunnerCore/Glasses/*` (new directory: 6 files)
- `ARRunnerCore/Tests/ARRunnerCoreTests/Glasses/*` (new test directory: 3 files)
- `ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift` (new)
- `ARRunnerWatch/Glasses/GlassesService.swift` (rewritten for new surface)
- `ARRunnerCore/Package.swift` (added `.macOS(.v13)` for local-dev `swift test`)

---

# Laughlin — WorkoutController surface + WorkoutHealthSubstrate seam (v0.1)

**By:** Laughlin
**Date:** 2026-05-15T12:51:36-04:00
**PR:** #7 (`feat/workout-controller`)

## Decision

Two team-relevant surfaces locked by the v0.1 WorkoutController implementation:

### 1. WorkoutController public surface (in ARRunnerCore)

```swift
public actor WorkoutController {
    public init(substrate: any WorkoutHealthSubstrate, sessionID: UUID = UUID(), clock: @escaping @Sendable () -> Date = { Date() })

    @discardableResult public func start(activityType: SportType = .running) async throws -> WorkoutState
    public func pause() async throws
    public func resume() async throws
    @discardableResult public func end() async throws -> WorkoutSummary

    public func reportGlassesSignal(_ signal: GlassesConnectivitySignal)   // D4: never pauses

    public nonisolated let states: AsyncStream<WorkoutState>
    public nonisolated let metrics: AsyncStream<WorkoutMetric>
}
```

- **Concurrency:** actor; no `@unchecked Sendable`.
- **State observation:** plain `AsyncStream` (not Combine, not a third-party reactive lib). Continuations are unbounded-buffered; consumers must drain or accept buffer growth during the workout.
- **Sport default:** `.running` per D3 — running-only feature surface for v0.1; cycling/walking compile but aren't surfaced.
- **Glasses input:** D4 enforcement is mechanical — `reportGlassesSignal(.disconnected(...))` does **not** call `substrate.pause()`. Only updates `glassesConnected` and increments `glassesDisconnectCount` for the summary.

### 2. HealthKit seam: `WorkoutHealthSubstrate` protocol (in ARRunnerCore)

```swift
public protocol WorkoutHealthSubstrate: Sendable {
    var stateEvents: AsyncStream<WorkoutSubstratePhase> { get }
    var metricEvents: AsyncStream<WorkoutMetric> { get }
    func begin(sport: SportType, startedAt: Date) async throws
    func pause(at date: Date) async throws
    func resume(at date: Date) async throws
    func end(at date: Date) async throws -> WorkoutHealthResult
}
```

Concrete implementations:
- `HealthKitWorkoutSubstrate` (in `ARRunnerWatch`) — real `HKWorkoutSession` + `HKLiveWorkoutBuilder` wrapper, watchOS-only via `#if os(watchOS)`.
- `InMemoryWorkoutHealthSubstrate` (public, in `ARRunnerCore`) — reusable mock for unit tests, SwiftUI previews, and Amber's parallel integration mocks. Records lifecycle calls; supports `emit(metric:)`, `queueNextError(_:)`, `queueResult(_:)`, `failSession(reason:)` for driver hooks.

`WorkoutHealthResult` carries `healthKitWorkoutID` (D9 side-store join key), `endedAt`, `activeDuration`, plus optional totals (`distance`, `energy`, `heartRate`, `elevation`).

### 3. AsyncStream over Combine

Standardize on `AsyncStream` (not Combine `Publisher`) for cross-module observation in this codebase. Reasons:
- Swift 6 strict concurrency support is first-class.
- Compiles on Linux SPM (Combine doesn't), keeping `ARRunnerCore` portable.
- Zero external dependencies.

Consumers needing back-pressure or transforms should use `swift-async-algorithms`, not migrate to Combine.

### 4. Package platform floor

Added `.macOS(.v14)` to `ARRunnerCore/Package.swift` so `AsyncStream` resolves on macOS hosts (CI matrix + local `swift test`). watchOS 11 / iOS 18 remain authoritative for app targets via `project.yml`.

## Implication for the team

- **Weiss (BLE):** the only input from your adapter is `GlassesConnectivitySignal` (a 2-case enum). If your adapter publishes a richer state, pipe just connect/disconnect into `controller.reportGlassesSignal(_:)`.
- **Amber (mocks):** extend `InMemoryWorkoutHealthSubstrate` or wrap it. Don't re-implement the protocol — your tests will diverge from mine.
- **Future cycling/walking surfaces:** add a new `HKWorkoutActivityType` mapping in `HealthKitWorkoutSubstrate.activityType(for:)` and surface a new picker; the controller is sport-agnostic.

## Operational note (for Squad conventions)

Multi-agent shared-FS hazard hit me hard at the start of this task — Amber's parallel branch silently shifted HEAD between my git calls. **Recommend:** all parallel agents use `git worktree add ../AR-Runner-{task}` from the first command. I'll draft this as a separate skill/convention proposal.

## Out-of-scope (deferred)

- D9 side-store *implementation* (only the join key is emitted).
- Phone WCSession sync.
- Glasses HUD rendering (D6 deferred).
- Action Button / App Intent wiring (D7 deferred — foreground via app icon).

---

# Amber — HealthKitSubstrate seam (v0.1 integration mocks)

**By:** Amber  
**Date:** 2026-05-15T12:51:36-04:00  
**PR:** `feat/integration-mocks`

## Decision

Introducing a small platform-neutral protocol in `ARRunnerCore` so the orchestrator can drive HealthKit-backed workouts without importing `HealthKit.framework` (Linux SPM CI requirement):

```swift
public protocol HealthKitSubstrate: Sendable {
    var workoutID: UUID { get async }                      // D9 side-store key
    var currentPhase: HealthKitWorkoutPhase { get async }
    func start(sport: SportType, at date: Date) async throws
    func pause(at date: Date) async throws
    func resume(at date: Date) async throws
    func end(at date: Date) async throws
    func metrics() async -> AsyncStream<WorkoutMetric>
    func phases() async -> AsyncStream<HealthKitWorkoutPhase>
}
```

And a sibling `GlassesConnectionObserver` protocol (separate from `GlassesFrameTransport` so Weiss's richer transport surface can subsume it without my PR fighting):

```swift
public protocol GlassesConnectionObserver: Sendable {
    var currentConnectionState: GlassesConnectionState { get async }
    func connectionStates() async -> AsyncStream<GlassesConnectionState>
}
```

`GlassesConnectionState` covers `disconnected / connecting / connected / reconnecting / failed(reason:)` — enough to exercise D4 disconnect/reconnect semantics.

## Why

- Brief required mocks runnable on `swift test` Linux CI; HealthKit has no Linux story.
- Wanted a stable, additive seam Laughlin can adopt for her `WorkoutController` on watchOS, with `HKLiveWorkoutBuilder` behind a thin adapter.
- Kept the surface deliberately minimal: just the calls a v0.1 orchestrator needs. No live-builder events, no statistics queries — Laughlin can extend.

## Reconciliation expected at merge

If Laughlin's `feat/workout-controller` introduces a richer substrate (e.g., the `WorkoutHealthSubstrate` shape with `WorkoutHealthResult` aggregates I saw in stashed WIP), the merge should:
- Keep her richer types as canonical.
- Either delete `HealthKitSubstrate` here or have it conform to her protocol (it's the simpler subset).
- Update `WorkoutController` and `FakeHealthKitSubstrate` accordingly.

Same pattern for Weiss: if her merged `GlassesFrameTransport` already surfaces a `connectionStates()` async stream, the standalone `GlassesConnectionObserver` protocol can be folded in or deprecated.

Both are additive seams introduced behind a `feat/` branch — `.gitattributes` `merge=union` doesn't help with `.swift` files, but the conflict surface is small and well-documented.

## Mock decisions

- **`MockGlassesFrame.MockGlassesFailureConfig`** — failures are one-shot per call (`failNextConnect` etc) so tests can sequence "fail then succeed" without rebuilding the mock. Simpler than priority queues.
- **`HealthKitScenario.explicit([WorkoutMetric])`** — escape hatch for snapshot-style tests. Carrying the full metric (with timestamp + unit) keeps determinism end-to-end.
- **`InMemoryARMetadataStore`** — D9 substrate that lives in the test target so prod `ARMetadataStore` stays filesystem-only.

## Open questions for Joe / team

- Should `WorkoutController` move to a richer state machine (`WorkoutPhase` like the stashed `WorkoutState.swift` model) for v0.1, or is the bool-based `isRunning` enough until Laughlin's controller lands?
- Should the controller persist the side-store row even when the workout ends with zero metrics (e.g., immediate user cancel)?  Currently it does — feels right but worth confirming.

---

# Decision Drop — CI / Security Workflow Architecture

**Author:** Richards (Lead / Architect)
**Date:** 2026-05-14T16:51:53-04:00
**Branch:** `chore/ci-workflows` (off `chore/macos-build-validation`)
**Status:** Proposed — pending merge of PR
**Related:** D1–D9, "No Direct Main" directive (2026-05-14T15:44:37-04:00), Amber's macOS build validation (2026-05-14T16:28:08-04:00), XcodeGen tooling decision (2026-05-14T16:09:31-04:00)

## What

Add three CI workflows to `.github/workflows/`, sitting alongside the Squad orchestration workflows but reserved under their own naming prefix (`ci-*.yml` for build/test, `codeql.yml` for security; `squad-*.yml` remains orchestration-only):

1. **`ci-core-tests.yml`** — Linux runner, `swift:6.0-jammy` container, `swift test` on `ARRunnerCore`.
2. **`ci-build.yml`** — macOS-15 runner, 4-way matrix, `xcodegen generate` + `xcodebuild` for `ARRunnerWatch`, `ARRunnerPhone`, `ARRunnerWidgetsPhone`, `ARRunnerWidgetsWatch`.
3. **`codeql.yml`** — macOS-15 runner, GitHub CodeQL Swift analysis with `security-extended` queries on PR + weekly schedule.

Full operational documentation is in `docs/dev/ci-workflows.md`.

## Why

Two real-code branches are about to land (Weiss's BLE wrapper, Laughlin's `WorkoutController`). Without CI, those PRs go in on the strength of one local macOS build per author. Amber's validation pass found three real scaffold bugs that would have shipped silently — every subsequent PR has the same exposure. CI is the cheapest insurance we'll ever buy on this project.

## The decisions, with trade-offs

### ADR — Runner mix: Linux for Core, macOS for shells

**Decision:** Split `swift test` (Linux) from `xcodebuild` (macOS).

**Spike result:** `ARRunnerCore` imports only `Foundation` (sources) and `XCTest` + `Foundation` (tests). No HealthKit, CoreBluetooth, WatchKit, WatchConnectivity, UIKit, AppKit. `SwiftPM`'s `platforms:` block is a minimum-Apple-version declaration — it doesn't gate Linux compilation. The pure-Swift Core compiles and tests cleanly on Linux Swift 6.

**Alternatives considered:**
- **All-macOS.** Simpler — one runner type, one mental model. Costs ~10x per minute. With macOS billed at 10x Linux and core tests being the most-frequently-failing job (every PR exercises model serialization), the rational answer is to keep the fast-iterating job on the cheap runner.
- **All-Linux.** Impossible — app shells need Apple SDKs (WatchKit, HealthKit, WidgetKit, UIKit).

**Cost of the chosen split:** ARRunnerCore *must* stay platform-agnostic. The moment someone imports HealthKit into Core, this job fails on Linux. **That cost is actually a feature** — it enforces ADR-001 (SPM-shared Core) and ADR-007 (`GlassesFrameProtocol` behind a protocol boundary) mechanically. Trade named, accepted.

### ADR — Trigger strategy: PR + push-to-main only

**Decision:** Workflows run on `pull_request` (any base) and `push` to `main`. Never on branch pushes outside of a PR.

**Alternative:** Run on every branch push. Faster feedback for devs working locally, but Apple-Watch devs already have a Mac on their desk (D-2026-05-14T16:09:31-04:00 dev workflow split) — they get faster feedback running `xcodebuild` directly. Branch-push CI would burn macOS minutes for marginal value.

**Cost:** A dev who pushes a branch without opening a PR gets no signal until they file the PR. Acceptable — opening a PR is one click.

### ADR — Concurrency cancellation on PRs, not on main

**Decision:** All three workflows use `concurrency: { group: ..., cancel-in-progress: ${{ github.event_name == 'pull_request' }} }`. Rapid pushes to a PR branch cancel in-flight runs; pushes to `main` are never cancelled.

**Why:** macOS minutes are the budget. A dev rebasing or force-pushing a PR five times shouldn't cost five full matrix builds. But on `main`, we want a clean, linear, never-cancelled history of green/red. Different audiences, different policies.

### ADR — Caching strategy

**Decision:**
- Linux: cache `ARRunnerCore/.build` + `~/.cache/org.swift.swiftpm`, keyed on `Package.swift` + `Package.resolved`.
- macOS: cache `~/Library/Caches/org.swift.swiftpm`, `DerivedData/**/SourcePackages`, and `DerivedData` itself, keyed on `project.yml` + `Package.swift`.

**Trade-off named:** DerivedData caches are large (hundreds of MB) and frequently invalidated by Xcode version drift. They will sometimes miss; that's fine — they're an optimization, not correctness. If cache restore costs ever exceed cache-hit savings, drop the DerivedData cache and keep only the SPM caches.

### ADR — CodeQL builds only ARRunnerWatch

**Decision:** CodeQL drives off a single `xcodebuild` of `ARRunnerWatch` (the largest single dependency closure — pulls Core + watch shell + widget extension). Not the full matrix.

**Alternative:** Build all four schemes under CodeQL. Marginal coverage gain (CodeQL re-analyses the same Swift sources), large minute cost (CodeQL Swift is the slowest of the three workflows).

**Cost:** If a phone-only or widget-only file is somehow never visited by the watch build's compile, CodeQL won't analyze it. In practice, Core is the only shared compile unit and it's visited. Acceptable.

### ADR — `security-extended` queries

**Decision:** Use the `security-extended` CodeQL query suite, not just the default.

**Trade-off:** ~30% more analysis time, broader rule coverage. For a security-sensitive surface (BLE pairing, HealthKit data handling, App Group sharing), the extra signal is worth the minutes.

## Punt list — what we are deferring and why

| Concern | Status | Rationale |
| --- | --- | --- |
| Lint (swiftlint vs swift-format) | **Deferred** | Joe + Richards to pick a tool with intent, not under deadline. No code has been written yet that exercises the difference. TODO captured in `docs/dev/ci-workflows.md`. |
| Code coverage | **Deferred** | Coverage on a scaffold-only test suite (6 Codable round-trips) is theatre. Re-evaluate after Weeks 1–3 of Weiss + Laughlin land real logic. |
| Release / TestFlight | **Out of scope** | Requires signing identity + secrets management. Separate workflow, separate decision. |
| Dependabot | **Deferred** | Zero external SPM deps today. Enable when ActiveLook SDK or any other vendor SPM dep lands. |
| Branch protection / required checks | **Manual** | Joe needs to toggle "Require status checks to pass before merging" on `main` after first green run. Workflows are designed to be the contract. |
| Linux build of app shells | **Not viable** | App shells depend on WatchKit / UIKit / HealthKit / WidgetKit — Apple-only. |

## What Weiss and Laughlin need to know

1. **Don't import Apple-framework code into `ARRunnerCore`.** It will fail the Linux core-tests job and block your PR. Concrete Apple-framework code lives in the app/extension targets. Use protocol boundaries in Core (ADR-007).
2. **Your PR must pass three required check sets**: `ci-core-tests`, all 4 `ci-build` matrix jobs, and `codeql`. Plan for ~15 min of CI time per PR after cache warm-up.
3. **Local validation matches CI 1:1.** See the repro block in `docs/dev/ci-workflows.md`. If it builds locally, it builds in CI — and vice versa.
4. **`@preconcurrency import` of the ActiveLook SDK stays in the watch/phone targets**, not Core. This was already the D8 plan; it's now mechanically enforced by the Linux core-tests job.

## Verification

This branch (`chore/ci-workflows`) sits on top of `chore/macos-build-validation` (Amber's three scaffold fixes), so the workflows are validated against the post-fix scaffold. When `chore/macos-build-validation` merges to `main`, this branch rebases cleanly.

## Files

- `.github/workflows/ci-core-tests.yml`
- `.github/workflows/ci-build.yml`
- `.github/workflows/codeql.yml`
- `docs/dev/ci-workflows.md`
- `.squad/skills/swift-linux-macos-runner-split/SKILL.md` (reusable pattern)

## 2026-05-15T14:01:55-04:00: Amber — Keep `FakeHealthKitSubstrate` and `MockGlassesFrame` alongside canonical stubs

**Author:** Amber  
**Context:** PR #6 reconciliation after #5 (`StubGlassesTransport`) and #7 (`InMemoryWorkoutHealthSubstrate`) merged into main.

### Decision

The test target keeps two QA mocks alongside the canonical happy-path stubs that landed in `ARRunnerCore` from PRs #5 and #7:

| Concern | Canonical stub (in `ARRunnerCore`) | QA mock (in test target) |
|---|---|---|
| `GlassesFrameTransport` | `StubGlassesTransport` (Weiss, #5) | `MockGlassesFrame` (Amber) |
| `WorkoutHealthSubstrate` | `InMemoryWorkoutHealthSubstrate` (Laughlin, #7) | `FakeHealthKitSubstrate` (Amber) |

### Rationale

The canonical stubs are deliberately simple — they're the "give me a working transport / substrate so my unit test compiles" surface, suitable for SwiftUI previews, basic lifecycle coverage, and ad-hoc happy-path checks. They don't carry the scenario-replay or failure-injection knobs QA needs.

The QA mocks add explicitly:

- **`MockGlassesFrame`** — `simulateDisconnect(reason:)` / `simulateReconnect(after:)` with paired `GlassesStatusEvent.dropped/.reconnected` emissions; one-shot failure injection on `connect` / `selectLayout` / `updateField`; `simulateBattery(_:)` for D9 metadata fixtures; recorded `selectedLayouts` and `receivedUpdates` for after-the-fact assertions.
- **`FakeHealthKitSubstrate`** — pre-canned `HealthKitScenario` replays (`steadyRun` / `intervals` / `explicit` / `ended`) that fire automatically after `begin(...)`, so integration tests stay declarative rather than imperative metric-pushing; stable `workoutID` chosen at init for deterministic D9 side-store round-trips; `isScenarioComplete` poll for tests that need to await replay.

### Boundaries

- The canonical stubs stay the public-surface "default" doubles; downstream code that just needs *a* transport/substrate should reach for those.
- The QA mocks are test-target-only (`@testable import ARRunnerCore`) and exist to exercise corner cases that the canonical stubs deliberately don't cover.
- Both sets coexist; there is no plan to merge them. If any QA mock affordance becomes generally useful, lift just that affordance into the canonical stub via a follow-up PR rather than absorbing the whole mock.

### Out-of-scope

- Did NOT modify `GlassesFrameTransport`, `WorkoutHealthSubstrate`, `WorkoutController`, `StubGlassesTransport`, or `InMemoryWorkoutHealthSubstrate` — those types are now canonical on `main`.
- Did NOT add new behaviours beyond reconciliation (the integration-test scope is unchanged: D4 happy path).

## 2026-05-15T18:29:17Z: User directive — Opus 4.7 1M Context for code-writing agents

**By:** Joe Krilov (via Copilot)
**What:** Sub-agents whose primary job is writing code (Weiss, Laughlin, Amber) should use `claude-opus-4.7-1m-internal` (Claude Opus 4.7, 1M context, Internal only).
**Why:** User request — captured for team memory. Saved as persistent agent overrides in `.squad/config.json` so the override survives across sessions.

**Scope:**
- ✅ Weiss (AR Integration — writes BLE / ActiveLook Swift code)
- ✅ Laughlin (watchOS Dev — writes WorkoutController / HealthKit code)
- ✅ Amber (QA & Fitness Domain — writes integration tests, mocks)
- ✅ Richards (Lead — code review and architectural code work)
- ❌ Killian (Product Strategist — no code, stays on haiku)
- ❌ Scribe (mechanical ops — never bumped, stays on haiku per squad rule)

**Note:** Layer 0 of the model selection hierarchy. Coordinator reads `.squad/config.json` on session start; per-agent overrides win over auto-selection.

---

## 2026-05-15T18:26:26Z: Killian — v0.2 Scope Proposal

**Author:** Killian (Product Strategist)  
**Date:** 2026-05-15T14:26:26-04:00  
**Status:** Proposed  
**Requested by:** Joe Krilov  

### v0.2 Theme

**"First runnable end-to-end workout: watch launch → live HUD frame → post-run HealthKit save."**

v0.2 closes the loop from v0.1's foundation. We go from "protocols + mocks" to "Joe runs, glances at glasses, finishes, HealthKit sees it."

### v0.2 User Stories

**Story 1: Watch App Launch Surface** — App icon tap → watch foreground workout screen within 1s. Owner: Laughlin. Est. 3–4 days.

**Story 2: Bare Workout Flow on Watch** — "Start" → watch records HKWorkoutSession, HR + distance + pace; glasses show live metrics; "Finish" → summary. Owner: Laughlin + Weiss. Est. 5–6 days.

**Story 3: Post-Run Save to HealthKit** — "Save" → HKWorkout + HKWorkoutRoute written; Apple Fitness shows run. Owner: Laughlin. Est. 3–4 days.

**Story 4: HUD Frame Builder** — Metrics → ActiveLook frame stream at ~1Hz. Owner: Weiss + Amber. Est. 4–5 days.

**Story 5: iPhone Companion Mirror** — iPhone shows real-time pace/HR/distance/time via WCSession. Owner: Laughlin + Amber. Est. 3–4 days.

### Out of Scope for v0.2

1. **HUD Customization Editor** (→ v1) — D6 locks baked presets for v0.1. v0.2 doesn't change that.
2. **iPhone Settings / Layout Config UI** (→ v0.2.5 or v1) — Phone app in v0.2 is read-only mirror only.
3. **GPS Route Map on Phone** (→ v1) — Core metric spine (pace/HR/distance/time) only; route is nice-to-have.
4. **Multi-Workout Types** (→ v1) — D3 locks running-only for v0.1; v0.2 stays running-only.
5. **Action Button + Smart Stack Full Integration** (→ v0.2.5) — Story 1 covers foreground launch (foundation); refinement deferred.

### Open Product Questions for Joe

1. **Watch-Only Run Assumption:** Should v0.2 assume runner always has watch but *may* leave phone at home? Affects phone mirror prioritization.
2. **Glasses Disconnect Handling:** When glasses drop mid-run, pause watch session (A), show haptic + keep recording (B, per D4), or silently keep recording (C)?
3. **HealthKit Active Energy:** Estimate from HR + age/weight, or let Health app calc from raw HR/distance?
4. **Post-Run Summary UI:** Static summary card (A), auto-save + disappear (B), or card + options menu (C)?
5. **Offline Metrics:** Should v0.2 support running completely offline (no phone, no iCloud)? Current assumption: yes (D5 + D9 locked this).

### v0.2 Size & Timeline

**Estimate:** 3–4 weeks.

| Team | Workstream | Size | Owner |
|------|-----------|------|-------|
| Watch | Stories 1–3 | 2.5 weeks | Laughlin |
| Glasses | Story 4 | 1.5 weeks | Weiss |
| Phone | Story 5 | 1 week | Laughlin + Amber |
| QA | Integration tests | 1 week | Amber |

**Success Criteria:**
1. ✅ Joe can launch 10-min test run from watch, see metrics on glasses HUD, finish, data in Apple Health (all within 1 min).
2. ✅ HUD frame delivery is steady (~1Hz, no stutter, no lag > 500ms).
3. ✅ Glasses disconnect doesn't crash app or lose watch-side metrics.
4. ✅ iPhone mirror dashboard is readable at a glance (large pace/HR).
5. ✅ Post-run HealthKit write is reliable and idempotent.

### Recommendations

1. **Lock the disconnect-handling UX (Q2 above) before Laughlin starts Story 2.**
2. **Weiss + Laughlin should pair briefly on the BLE push integration.**
3. **After v0.2 merges, gather Joe's real-run feedback ASAP.**

**Decision Gate:** Killian proposes v0.2 scope locked. Awaiting Joe's answers to the 5 open questions (especially Q2 and Q4).

---

## 2026-05-15T18:26:26Z: Richards — v0.2 Technical Slice Proposal

**Author:** Richards (Lead / Architect)  
**Date:** 2026-05-15T14:26:26-04:00  
**Status:** Proposed — awaiting Joe review and team input

### Executive Summary

v0.1 foundation is live: `ARRunnerCore` SPM, `GlassesFrameTransport` protocol, `WorkoutController` actor, `WorkoutHealthSubstrate` integration seams, and test scaffolding. All CI green (Linux + macOS + CodeQL).

v0.2 scope: Extend v0.1 seams into a **credible implementation slice**. Three parallel workstreams ship the core user-visible workout loop (watch starts, glasses display live metrics, phone mirrors, glasses reconnect on drop). Smaller footprint than v0.1, focused on delivery value with low architectural risk.

### v0.2 Candidate Workstreams

**1. Glasses Hardware Integration (Weiss) — CRITICAL PATH**
- Implement `ActiveLookAdapter: GlassesFrameTransport` conformance on watchOS.
- Handle GATT write for HUD frame updates (~1 Hz).
- Error handling: GATT write timeout, connection loss, invalid frame.
- Acceptance: Real Watch + glasses hardware sends live frame at workout tick rate.
- Deliverable: Merged to main; Weiss owns beta test on personal hardware.
- Risk: Medium (ActiveLook watchOS SDK gaps). Mitigation: Pivot to phone relay as fallback (~2–3 day impl, 1 Hz latency acceptable).
- Dependency: None — builds on v0.1 stubs, works in parallel.

**2. Watch SwiftUI View Stack (Laughlin) — CRITICAL PATH**
- Surface `WorkoutController` state in functional watch app UI.
- Workout start view, live metrics view, pause/resume/end controls, lock-screen complication.
- Acceptance: User can start workout from Smart Stack widget, see live metrics, end workout; complication visible.
- Deliverable: Functional watch app UI; merged to main.
- Risk: Low. Mitigation: Integration test on hardware.
- Dependency: None — builds on v0.1 `WorkoutController` actor, works in parallel with Workstream 1.

**3. iPhone Companion Mirror (Laughlin)**
- Phone app receives live metrics via `WCSession`, displays in SwiftUI.
- Implement `WCSessionDelegate` for `WorkoutTickMessage` from watch.
- Live metric tiles (HR, pace, distance, elapsed time) + post-run summary.
- Acceptance: iPhone companion shows live metrics during watch workout; summary persists post-run.
- Deliverable: Phone app with live mirror + summary.
- Risk: Low — uses existing WCSession patterns from v0.1 architecture doc.
- Dependency: Workstream 2 (watch must send ticks); Workstream 1 (optional).

**4. Glasses Disconnect Resilience (Weiss + Laughlin) — CRITICAL PATH**
- Implement D4 contract — workout continues if glasses drop; subtle UX.
- Auto-reconnect loop in `BLEManager` (exponential backoff, max retry window).
- Haptic alert when BLE connection lost; "HUD offline" indicator on watch view.
- Log drop event in run metadata.
- Acceptance: Disconnect glasses mid-run; watch continues ticking; reconnect auto-succeeds within 5s; user sees haptic + offline indicator.
- Deliverable: Merged to main; integrated into Workstreams 1 + 2.
- Risk: Low — standard BLE reconnect pattern.
- Dependency: Workstreams 1 + 2.

**5. HUD Layout Preset System (Laughlin)**
- Bake 2–3 ActiveLook Config-Generator layouts at build time.
- Phone app picker: user selects layout before workout.
- Watch reads preset on `WorkoutLifecycle.started`, pushes to glasses via `GlassesFrameTransport`.
- Acceptance: User can pick layout from phone; watch applies at start; glasses display chosen layout.
- Deliverable: Preset factory + phone picker UI; merged to main.
- Risk: Low — uses ActiveLook Config-Generator outputs (Weiss owns inputs).
- Dependency: Workstreams 1–3.

### Risk & Dependency Matrix

| Workstream | Risk | Blocked By | Blocks |
|-----------|------|-----------|--------|
| **1. Glasses Hardware** | Medium (SDK unknowns) | Nothing | 4 (reconnect logic), 5 (config push) |
| **2. Watch UI** | Low | Nothing | 3 (WCSession sender), 4 (disconnect UX) |
| **3. Phone Mirror** | Low | 2 (watch must send ticks) | Nothing |
| **4. Disconnect Resilience** | Low | 1 + 2 (uses both) | Nothing |
| **5. HUD Presets** | Low | 1 (SDK outputs) | Nothing |

**Critical path:** 1 → 4; 2 (parallel).

### Recommended v0.2 Slice

**Ship in v0.2 (3 workstreams):**
1. **Glasses Hardware Integration** (Weiss) — Without this, no glasses output; core promise unmet.
2. **Watch UI + Workout Loop** (Laughlin) — User-visible running app; turns v0.1 foundation into a workout.
3. **Glasses Disconnect Resilience** (Weiss + Laughlin) — Fulfills D4; production-critical.

**Why this slice?** Delivers a **credible end-to-end workout loop**: user starts on watch, sees live metrics on glasses (and in complication), glasses reconnect gracefully if signal drops.

**Defer to v0.2.1 or v0.3:**
- **Workstream 3 (Phone Mirror):** Nice-to-have. If phone is absent, watch + glasses works fine (per D5).
- **Workstream 5 (HUD Presets):** Cosmetics. v0.2 can ship with single hard-coded layout; preset picker is polish.

**Rationale:**
- **Architectural clarity:** Core loop (watch → glasses, resilience) is the hard part; phone mirror is downstream convenience.
- **Time risk:** Presets require ActiveLook Config-Generator outputs (Weiss input); deferring removes dependency fork.
- **User value:** Core 3 workstreams unlock "I can run with my AR glasses" (D5 fulfilled).
- **Unblock downstream:** Laughlin can start design on Workstream 3 (phone UI) in parallel; doesn't block v0.2 ship.

### Process Item: Git Worktree Convention

**Issue:** During v0.1 parallel work on shared macOS dev machine, branch shifts moved `HEAD` between Laughlin's git calls, causing coordination hazard.

**Proposal for `.squad/routing.md` or new `.squad/skills/parallel-agent-worktrees/SKILL.md`:**

> **Parallel Agent Working Directory Isolation**
> 
> When multiple agents work in parallel on the shared macOS dev machine, each agent must isolate its working directory using `git worktree add ../AR-Runner-{agent}-{task}` to avoid HEAD collisions. This prevents branch switches in one agent from interfering with git operations in another agent's session. Example: Amber uses `../AR-Runner-amber-integration`, Weiss uses `../AR-Runner-weiss-ble`, Laughlin uses `../AR-Runner-laughlin-workout`. All worktrees remain siblings of the main checkout; Scribe reconciles merges to main. This pattern is mandatory for all parallel multi-agent sessions going forward.

### Success Criteria (v0.2 Soft Launch)

- ✅ Real ActiveLook glasses display live workout metrics at 1 Hz (Workstream 1)
- ✅ Watch app UI lets user start/pause/end workouts and view live complication (Workstream 2)
- ✅ Glasses auto-reconnect on signal drop; watch shows offline indicator + haptic alert (Workstream 4)
- ✅ (Optional) iPhone companion shows live metrics during watch workout (Workstream 3)
- ✅ (Optional) User can pick HUD layout preset from phone (Workstream 5)
- ✅ All PRs merged, CI green (Linux + macOS + CodeQL), zero regressions vs. v0.1
- ✅ Weiss tests on personal Watch + glasses hardware; Laughlin + Amber verify simulator + integration tests

## 2026-05-15T18:55:00Z: Amber — v0.2 D4 resilience contract gaps

**From:** Amber (QA & Fitness Domain)  
**Source:** PR #8 — `feat/v02-disconnect-resilience-tests`  
**Audience:** Weiss (BLE / glasses transport), Laughlin (workout controller / watch UI)

While writing the anticipatory test suite for v0.2 #4 (D4 disconnect/reconnect resilience), the following contract gaps surfaced in the canonical surface. Each is tied to a test in `DisconnectResilienceTests.swift` so the implementation has a target.

### G1 — `GlassesFrameTransport` has no auto-reconnect surface (Weiss)

The protocol exposes `connect()` and `disconnect()` but no way to enable a transport-managed auto-reconnect loop. Weiss's `ReconnectPolicy` and `ExponentialBackoff` already exist as types but aren't reachable through the protocol. Decision #2 says "auto-reconnect in background" — implementation needs an entry point.

**Suggested shape:** either an `enableAutoReconnect(policy: ReconnectPolicy) async` method on the protocol, or a constructor option on the canonical `ActiveLookGlassesAdapter` that defaults to a sensible policy. **Pinned by:** `test_AutoReconnectAfterTransportDrop_ExpectedFailing`.

### G2 — No layout re-application contract after reconnect (Weiss)

After a reconnect the previously-active layout is lost. Today every test must manually re-`selectLayout` post-reconnect, which means production code would have to track `currentLayoutID` and replay it itself. The transport (or a thin wrapper) is the natural owner.

**Suggested shape:** transport tracks `currentLayoutID` set on the last successful `selectLayout` call and auto-replays it on the connection state's `.connected` re-entry. **Pinned by:** `test_Reconnect_AutoReappliesPreviousLayout_ExpectedFailing`.

### G3 — `WorkoutController.glassesDisconnectCount` is global, not session-scoped

`reportGlassesSignal(_:)` does not gate on workout phase, so pre-`start` connect/disconnect traffic accumulates on the same counter that the `WorkoutSummary` reads. Today's behavior is documented in `test_DisconnectBoundary_PreBegin_DoesNotPerturbPhase`, but the surface should be tightened — either reset the counter on `start(activityType:)`, or only count disconnects while `phase ∈ {.running, .paused}`.

**Owner:** Laughlin. **Tradeoff:** scoping is the conservative choice but means the WC mirror can't surface "you've had 3 drops this session" until after `start`.

### G4 — No dedicated alerts surface for haptic triggers (Laughlin)

The watch UI's only "fire a haptic on disconnect" signal today is observing `WorkoutState.glassesConnected` flipping to `false` on `controller.states`. That works but couples haptic logic to state-snapshot diffing. A dedicated `AsyncStream<WorkoutAlertEvent>` (with cases like `.glassesDropped`, `.glassesReconnected`, future room for `.heartRateZoneEntered`) would isolate the contract and make the haptic trigger point unambiguous.

**Pinned by:** `test_HapticAlertHook_OnDisconnect_ExpectedFailing` (skipped today; body sketch is in the test comment).

### G5 — `reportGlassesSignal` mutates `glassesConnected` in any phase

Including `.idle`, `.ended`, and `.failed`. This is fine for `.idle` (G3 covers it) but emitting a state snapshot with `.ended` phase and a flipped `glassesConnected` after the workout is over is probably noise. **Suggested fix:** short-circuit `reportGlassesSignal` when `phase == .ended` (skip both the count bump and the state emission).

**Owner:** Laughlin. Low priority — observable only by lingering subscribers to `controller.states`.

## 2026-05-15T18:55:00Z: v0.2 Product Decisions Locked

**By:** Joe Krilov (via Copilot interactive walkthrough)  
**Why:** Locks the v0.2 slice so Weiss / Laughlin / Amber can kick off in parallel.

**Locked decisions for v0.2:**

| # | Decision | Verdict |
|---|---|---|
| 1 | iPhone live mirror | **IN** — read-only watch→phone mirror via WCSession; no phone-side config UI |
| 2 | Glasses disconnect UX | **Keep recording + haptic alert** (D4 confirmed); auto-reconnect in background |
| 3 | Phone-presence assumption | **Watch-first** — must work with watch alone; phone mirror opportunistic |
| 4 | HealthKit active energy | **Hybrid** — local estimate (HR/age/weight) for live display; write HR-only to HealthKit, let it compute official kcal |
| 5 | Post-run save flow | **Menu** (Save / Cancel / Resume); workout pauses on Finish; immediate-save toggle deferred to v0.3 with iPhone settings UI |
| 6 | Offline guarantee | **Offline-capable** — must work with no phone/network; may opportunistically use phone/network when present |

**v0.2 workstreams approved (Killian + Richards reconciled):**

- **#1 Glasses Hardware Integration** (Weiss) — wire real ActiveLook BLE on watchOS to canonical `GlassesFrameTransport`. Spike-grade acceptable; if SDK watchOS support is blocked, document the gap and pivot to phone-relay.
- **#2 Watch SwiftUI workout app** (Laughlin) — start / pause / finish, live HR + pace + distance, lock-screen complication, Finish→menu (Save / Cancel / Resume) per decision #5.
- **#3 iPhone live mirror** (Laughlin) — read-only WCSession dashboard, ~1Hz tick stream, post-run summary card. No settings UI.
- **#4 Glasses Disconnect Resilience** (Weiss + Laughlin) — auto-reconnect loop, subtle haptic when HUD drops, "HUD offline" indicator. Anchored to D4.
- **#5 HUD layout presets** — **DEFERRED to v0.3** per Richards's recommended slice.

**Process items locked:**

- Worktree convention being landed as `.squad/skills/parallel-agent-worktrees/SKILL.md` by Richards this session. Adopt for future parallel batches.
- Per-agent model overrides: Weiss / Laughlin / Amber / Richards pinned to `claude-opus-4.7-1m-internal` for code work (`.squad/config.json`, Layer 0).

**Out of scope (carried forward from Killian):**

- HUD editor (D6 → v1)
- iPhone settings UI (v0.3, will host the Save flow toggle)
- Route map (v1)
- Multi-sport (D3 → v1)
- Action Button polish (v0.2.5)

## 2026-05-15T18:55:00Z: Richards — Parallel-agent worktree convention landed as SKILL

**By:** Richards (Lead / Architect)  
**Status:** SKILL `.squad/skills/parallel-agent-worktrees/SKILL.md` formalized

The parallel-agent worktree convention proposed in my `v02-technical-slice` decision is now formalized as a canonical skill at `.squad/skills/parallel-agent-worktrees/SKILL.md`.

### Rule (binding from v0.2 onward)

Whenever **two or more coding agents** are spawned in parallel on the shared dev machine, each agent runs in its own git worktree:

```bash
git worktree add ../AR-Runner-{agent}-{task} -b feat/{area}-{task} main
```

- Worktree dir: `../AR-Runner-{agent}-{task}` (sibling of main checkout).
- Branch: `feat/{area}-{task}`.
- Spawn prompts pass `WORKTREE_PATH` + `WORKTREE_MODE: true` (squad.agent.md spawn template).
- Cleanup: `git worktree remove` after PR merge; `git worktree prune` for orphans.
- `.squad/` state stays worktree-local; `merge=union` reconciles append-only files on merge (see squad.agent.md → Worktree Awareness).

### Scope

- **Applies to:** v0.3 batches and any v0.2 follow-up batch that spawns parallel coding agents (e.g., another foundation-style multi-stream push).
- **Does NOT apply to:** solo agent runs, doc-only / `.squad/`-only single-writer work, read-only explore agents.

### Provenance

Born from the v0.1 foundation batch shared-filesystem collision documented in `.squad/log/2026-05-15T16-51-36Z-v01-foundation-batch.md` (Amber's branch shift moved `HEAD` between Laughlin's git calls). Confidence remains **medium** until a parallel batch completes cleanly under this rule, at which point it graduates to **high**.

### Trade-off (named)

Each worktree costs a duplicate working directory on disk (full file checkout per agent) and one extra `git worktree remove` step at PR-merge time. In exchange we get hard isolation of `HEAD`/index/working dir per agent — eliminating an entire class of mid-flight collision bugs that are otherwise non-deterministic and painful to diagnose. Worth it.

## 2026-05-16T20:32:00Z: TestFlight CI Architecture (Richards)

**Status:** Proposed (will be locked when Joe merges PR #21).  
**PR:** #21 — feat(ci): TestFlight release pipeline via GitHub Actions  
**Charter ref:** Richards (Lead / Architect)

### Context

v0.2 is functionally complete in the simulator. Joe needs builds on his real Apple Watch but his iPhone is not in developer mode — so the path is TestFlight, not direct Xcode device install. He also wants CI-driven releases, secrets in GitHub (not local), and a tag-based release flow.

### Decisions

#### D-RICHARDS-TF-1: Native `xcodebuild` + ASC API key over fastlane `match`

We use `xcodebuild -allowProvisioningUpdates` with an App Store Connect API key for provisioning, not `fastlane match`. **Trade-off:** match would give us a private repo of pinned, audited profiles (better for big teams) at the cost of a second repo, Ruby tooling, and an extra encryption key to manage. For a one-developer Apple team this is overkill — Apple's first-party provisioning automation is good enough. Revisit if/when the Apple team grows past one human or we need profile-audit trails for compliance.

#### D-RICHARDS-TF-2: Tag pattern `v*.*.*-*` triggers TestFlight; `v*.*.*` is reserved for a future App Store workflow

Pre-release tags like `v0.2.0-rc1`, `v0.2.0-beta3` push to TestFlight via the new `release-testflight.yml`. A pure tag `v0.2.0` does **not** trigger this workflow — that path will be `release-appstore.yml` when we're ready to ship to the App Store. Keeping the two flows separate avoids one workflow needing two modes (review-submission vs. testing) and makes each one auditable on its own terms.

#### D-RICHARDS-TF-3: Version from tag, build number from `$GITHUB_RUN_NUMBER`

`MARKETING_VERSION = ${TAG#v}` (so `v0.2.0-rc1` → `0.2.0-rc1`). `CURRENT_PROJECT_VERSION = $GITHUB_RUN_NUMBER`. App Store Connect requires monotonically-increasing build numbers; the run number satisfies that without us tracking state. Both values are passed as `xcodebuild` build settings; the defaults in `project.yml` (`MARKETING_VERSION: 0.1.0`, `CURRENT_PROJECT_VERSION: 1`) are placeholders for local builds only.

#### D-RICHARDS-TF-4: `DEVELOPMENT_TEAM` lives in `Config/Signing.xcconfig` (gitignored), bootstrapped by `scripts/bootstrap-signing.sh`

`project.yml` references the xcconfig via `configFiles:`. The xcconfig is gitignored (Config/ already is, since xcodegen writes plists+entitlements there). `scripts/bootstrap-signing.sh` is idempotent: with no env, it creates the file with an empty `DEVELOPMENT_TEAM =` for Joe to fill in; with `APPLE_TEAM_ID=<id>` in env, it writes the team in (used by CI). This means: local Joe path (run script once, edit one line, `xcodegen generate`, open Xcode — Team auto-populates); CI path (workflow runs script with `APPLE_TEAM_ID` secret before every `xcodegen generate`); the team ID is never committed.

#### D-RICHARDS-TF-5: Seven-secret layout in GitHub

The minimum secrets required by the workflow:
1. `APPLE_TEAM_ID`
2. `APP_STORE_CONNECT_API_KEY_ID`
3. `APP_STORE_CONNECT_API_ISSUER_ID`
4. `APP_STORE_CONNECT_API_KEY_P8`
5. `BUILD_CERTIFICATE_P12_BASE64`
6. `BUILD_CERTIFICATE_P12_PASSWORD`
7. `KEYCHAIN_PASSWORD`

Documented exhaustively in `docs/dev/testflight-setup.md` Part B with copy/paste CLI for the encoded values. The API key role is **App Manager** (not Admin — least privilege for "create profiles + upload builds").

#### D-RICHARDS-TF-6: Workflow runs serially via `concurrency: { group: release-testflight, cancel-in-progress: false }`

App Store Connect doesn't tolerate concurrent uploads racing for the same build number, and cancelling a mid-upload is worse than queueing the next one. The PR-cancellation pattern from `ci-build.yml` is **explicitly not** copied here.

#### D-RICHARDS-TF-7: Pin Xcode 16.4 on `macos-15` (same rationale as `ci-build.yml`)

Reproducibility of signing/SDK behavior. Inherits the simulator-runtime trade-off documented in `docs/dev/ci-workflows.md`. Archiving doesn't need simulator runtimes, but pinning keeps the Release config behaviorally identical to the Debug-build matrix on the same OS image.

### Joe's manual prerequisites (one-time)

These are NOT in the PR; Joe must do them in the Apple portals before the first workflow run can succeed. Fully scripted in `docs/dev/testflight-setup.md` Parts A and B. Summary:

- Register the 4 bundle IDs at developer.apple.com (HealthKit + App Groups on the hosts; App Groups on the widget extensions).
- Create the App Store Connect app record for `com.arrunner.phone`.
- Create + export an **Apple Distribution** cert from Keychain Access.
- Create an App Store Connect API key (role: App Manager), download the `.p8`.
- Add the 7 secrets to the repo.

### Out of scope

- App Store submission flow (`release-appstore.yml`) — separate PR when v1 is ready.
- Notarization (Mac-only; not applicable to iOS/watchOS).
- fastlane / match adoption.
- Beta-tester management automation (still done manually in App Store Connect).

### Approval

Joe approves this design by merging PR #21. Once merged, this decision is locked.

---

## 2026-05-17T00:19:11Z: User directive — Opus 4.7 (1M context) for any code-touching agent

**By:** Joe Krilov (via Copilot)  
**What:** Going forward, any agent that touches code must run on `claude-opus-4.7-1m-internal` (Opus 4.7, 1M context). Re-affirms an existing preference already persisted in `.squad/config.json`.  
**Why:** User directive — captured for team memory. Code quality / context-window upgrade.

**Scope:**
- Applies to: Richards (Lead — code review/architecture), Laughlin (watchOS dev), Weiss (AR/BLE dev), Amber (QA — writes test code), and any new code-writing agent added later.
- Does NOT apply to: Scribe (mechanical file ops), Ralph (monitoring), Killian (product strategy).

**Implementation:** `.squad/config.json` `agentModelOverrides` block — Layer 0 persistent override. Coordinator MUST read this file on every session start.

**Coordinator lesson:** Squad failed to read `.squad/config.json` at the start of this session and spawned three audits on `claude-sonnet-4.6` in violation of the existing override. Re-spawned correctly after Joe re-flagged the directive. Going forward: read `.squad/config.json` as part of the standard parallel-read block on session start (alongside team.md / routing.md / registry.json).

**Fallback:** If `claude-opus-4.7-1m-internal` is unavailable, chain through `claude-opus-4.6-1m` → `claude-opus-4.6` → `claude-opus-4.5` → omit param. Never fall back DOWN to Sonnet or Haiku for a code task.

---

## 2026-05-16: HealthKit deprecated aggregate properties → statistics(for:)

**Date:** 2026-05-16  
**Agent:** Laughlin  
**Context:** watchOS code-health audit

### Issue

`HealthKitWorkoutSubstrate.swift:193–194` uses `HKWorkout.totalDistance` and `HKWorkout.totalEnergyBurned`, both deprecated since iOS 17 / watchOS 10. These are nil-returning stubs in current SDKs and will be removed in a future HealthKit version.

### Decision

Migrate to `HKWorkout.statistics(for:)` for both distance and energy on workout end. The builder collects per-type statistics which are available on the finished `HKWorkout` object.

```swift
// Replace:
workout?.totalDistance?.doubleValue(for: .meter())
workout?.totalEnergyBurned?.doubleValue(for: .kilocalorie())

// With:
workout?.statistics(for: HKQuantityType(.distanceWalkingRunning))?
    .sumQuantity()?.doubleValue(for: .meter())
workout?.statistics(for: HKQuantityType(.activeEnergyBurned))?
    .sumQuantity()?.doubleValue(for: .kilocalorie())
```

### Also needed

Add `case energy` to `MetricKind` in `ARRunnerCore/Sources/ARRunnerCore/Models/WorkoutMetric.swift` and update `HealthKitWorkoutSubstrate.swift:272` to emit `kind: .energy` for `activeEnergyBurned` samples.

### Effort

S — two-line change in `HealthKitWorkoutSubstrate.swift` for the deprecated API; two-line change for the MetricKind bug.

---

## 2026-05-16: Layout Bake Step is Blocking Hardware Use

**Agent:** Weiss  
**Date:** 2026-05-16T20:13:46-04:00  
**Related:** D6 (curated layout presets baked at build time)

### Issue

`CuratedLayoutCatalog` in `ARRunnerCore/Sources/ARRunnerCore/Glasses/ReconnectPolicy.swift:39–43`
maps string layout IDs to on-device numeric slots using **placeholder values**:

```swift
public static let mapping: [String: UInt8] = [
    "minimal-run":   0x01,
    "balanced-run":  0x02,
    "telemetry-run": 0x03
]
```

The in-code comment says: *"PLACEHOLDERS for v0.1: the real numbers come out of the layout BUILD step (deferred per task scope)."*

The adapter sends `ActiveLookCommand.displayLayout(id: deviceID)` using these slot numbers every time it connects or reconnects. If the glasses don't actually have layouts at slots 0x01–0x03, the `0x62 displayLayout` command will either do nothing or activate a different layout.

### Impact

- **Blocking for any real-hardware end-to-end test.** The glasses will not show the intended HUD.
- Affects `ActiveLookGlassesAdapter` (connect + reconnect), `RunningHUDPreset.layoutDescriptor()`, and the hardware test scaffold in `ActiveLookGlassesAdapterHardwareTests.swift`.

### Recommended Decision

**Before any hardware integration test:** run the ActiveLook Config-Generator against the three curated `HUDLayout` definitions (`minimalRun`, `balancedRun`, `telemetryRun`), flash the resulting binary to the glasses, and update `CuratedLayoutCatalog.mapping` with the real slot numbers the generator assigns. Record the generator inputs/outputs somewhere in `docs/` so they can be reproduced when glasses are re-flashed.

The Config-Generator outputs and any generated binary configs must **not** be committed to the repo (see permanent decision: ActiveLook visual-assets hard rule covers Config-Generator outputs, CC BY-NC-ND 4.0). Only the numeric slot constants belong in Swift source.

**Owner:** Weiss (integration) + Joe (hardware, Config-Generator access).

---

## P1 Audit Fixes — May 16 Turn (v0.2 release-candidate bugfixes)

### 2026-05-17T00:48:29Z: D-AMBER — Add `MetricKind.energy` for active kcal

**Author:** Amber (QA & Fitness Domain)  
**Branch / commit:** `fix/v02-p1-audit-bugs` @ `9571e23`  
**Audit ref:** `.squad/audits/2026-05-16-laughlin-watchos.md` (P1.3)

#### Context

`HealthKitWorkoutSubstrate.metric(for:)` mapped `HKQuantityType.activeEnergyBurned` to `WorkoutMetric(kind: .duration, …)` because Core's `MetricKind` enum had no kcal case. Both `WorkoutController.ingest` and the HUD formatters dropped the value silently. The saved `HKWorkout` still carried it, but live on-watch/on-glasses "flame" readings only ever reflected the local `EnergyAccumulator` estimate.

#### Decision

Added `case energy` to `MetricKind` in `ARRunnerCore/Sources/ARRunnerCore/Models/WorkoutMetric.swift`.

- **Unit:** kcal (matches HealthKit's `HKUnit.kilocalorie()`, no conversion at boundary).
- **rawValue:** `"energy"` (string-stable for WC payloads and persisted JSON).
- **Conformances unchanged:** `String, Sendable, Codable, CaseIterable, Equatable`.
- **Controller behaviour:** `WorkoutController.ingest(metric:)` folds `.energy` into the existing no-op `.pace, .duration` arm. The controller does not own kcal accumulation — that's substrate / `EnergyAccumulator` territory.

#### Required follow-up (Laughlin, Phase B)

- Update `HealthKitWorkoutSubstrate.metric(for:)` to return `MetricKind.energy` (unit `"kcal"`) when the sample's quantity type is `activeEnergyBurned`, instead of `.duration`.
- HUD / phone consumers that want the live flame value can now subscribe to `metric.kind == .energy` rather than reading the post-session `HKWorkout`.

Until that lands, the new case is dormant.

#### Test status

`ARRunnerCore/Tests/ARRunnerCoreTests/WorkoutMetricTests.swift`: **80 executed, 1 skipped, 0 failures**.

- `testEnergyKindExistsAndRoundTrips` — `.energy` ∈ `allCases`, Codable round-trip with kcal unit.
- `testMetricKindRawValueStable` — `.energy.rawValue == "energy"` (locks cross-process key).

#### Scope discipline

- Did NOT touch `HealthKitWorkoutSubstrate.swift` (Laughlin / watchOS-owned, Phase B).
- Did NOT touch the watch or phone apps. Core-only change.
- Touched two integration test helpers (`formatMetricImpl`, `formatMetricForResilience`) to handle the new case.

---

### 2026-05-17T00:48:29Z: D-WEISS — HUD per-tick wire + placeholder-ID hardware guard

**Author:** Weiss (AR/BLE Integration)  
**Branch / commits:** `fix/v02-p1-audit-bugs` @ `7dd784e` (P1.2 wire), `4f2947b` (P1.4 ID guard)  
**Audit ref:** `.squad/audits/2026-05-16-weiss-ar-ble.md` (P1.2, P1.4)

#### Context

The 2026-05-16 AR/BLE audit identified two P1 hardware-blocking gaps:

1. **P1.2** — `GlassesService.update(...)` was implemented but never instantiated. `WorkoutViewModel` constructed the transport and called `.connect()` only; the metric stream was never fanned out. Real glasses received the initial layout activation on connect and then nothing for the rest of the workout.
2. **P1.4** — `CuratedLayoutCatalog.mapping` returns placeholder slot bytes (`0x01–0x03`). Real values await the Config-Generator bake step. Hardware tests would silently activate the wrong on-device layout.

Both block TestFlight + bench bring-up.

#### Decision — P1.2: wire the per-tick HUD path

- `WorkoutViewModel.start(...)` now constructs a `GlassesService` alongside the transport and retains it.
- `attachGlasses(transport:service:)` selects the default curated preset (`RunningHUDPreset.default`, i.e. `balanced-run`) on every `.connected` edge, and calls `resetThrottle()` on `.disconnected` / `.reconnecting` / `.failed` edges so the first post-reconnect tick lands immediately per fieldIndex.
- `apply(metric:)` in the view model schedules `Task { await glasses.apply(metric:) }` on every metric tick. Fire-and-forget — BLE state never back-pressures the workout pipeline.
- `GlassesService.apply(metric:)` (new) maps `MetricKind → fieldIndex` via the active `HUDLayout.slots` ordering, guards on `transport.connectionState == .connected`, and consults a 1Hz-per-fieldIndex `HUDFieldThrottle` (new value type in Core). Unknown metric kinds (e.g. `.energy`, not yet addressed by curated presets) are dropped silently.
- `HUDFieldThrottle` uses strict `<` at the boundary, denies-without-advancing, and is per-`fieldIndex` independent.

#### Decision — P1.4: debug-assert on placeholder slot writes

- Kept `CuratedLayoutCatalog.deviceID(for:)` assert-free (pure lookup, exercised by Linux Core tests with placeholders).
- New `CuratedLayoutCatalog.placeholderDeviceIDs: Set<UInt8> = [0x01, 0x02, 0x03]` and `assertNotPlaceholder(_:layoutID:)` helper.
- `ActiveLookGlassesAdapter` calls the assert at three wire-write sites: `selectLayout`, `updateField`, and the reconnect re-apply. Debug builds trap; release builds log `.fault` for side-store visibility.
- Catalog `mapping` entries annotated with `TODO(P1.4 from .squad/audits/2026-05-16-weiss-ar-ble.md)`.

#### Rationale

- Metric fan-out **inside** `GlassesService` (vs. expanding `WorkoutViewModel.apply`) keeps `WorkoutViewModel` layout-agnostic and backs any future Mirror code path.
- Pure-Swift `HUDFieldThrottle` value type lives in Core so Linux CI exercises the contract; the actor-owned mutation lives in `GlassesService`.
- Debug-trap-on-placeholder + release-fault-log mirrors the existing `assertionFailure` / `os_log` pattern and avoids release-build crashes.
- Two separate commits — easy to revert P1.4's assert independently if Config-Generator bake lands a non-trivial slot range.

#### Test status

- **Core SPM:** 93/93 pass (1 skipped, pre-existing). New: `HUDFieldThrottleTests` (6), `WorkoutMetricFanoutTests` (3), `CuratedLayoutCatalogPlaceholderTests` (3).
- **watchOS build:** `xcodebuild ARRunnerWatch` succeeds (Swift 6 / Xcode 16, no warnings).
- **iOS build:** `xcodebuild ARRunnerPhone` succeeds.

#### Out of scope

- Hoisting `CBCentralManager` out of per-`beginConnect()` construction (audit debt #3).
- Scan-timeout `Task` retention + cancel-on-state-exit (audit debt #5).
- Real Config-Generator bake → replace `mapping` placeholders.
- Watch XCTest target.

---

### 2026-05-17T00:48:29Z: D-LAUGHLIN — P1.1 + P1.3 bugfixes — Smart Stack handoff + HK energy mapping

**Author:** Laughlin (watchOS Dev)  
**Branch / commits:** `fix/v02-p1-audit-bugs` @ `2a31b84` (P1.1), `2ca0d22` (P1.3)  
**Audit refs:** `.squad/audits/2026-05-16-laughlin-watchos.md` (P1.1, P1.3)  
**Related:** Amber's D-AMBER (commit 9571e23), Weiss's `7dd784e` (added `hasLiveHKEnergy` latch in `WorkoutViewModel`).

#### Context — P1.1: Smart Stack Start was a TODO

`ARRunnerWidgets/StartWorkoutIntent.swift:11-14` returned `.result()` and did nothing. `openAppWhenRun = true` foregrounded the host app, but the user landed on idle `WorkoutView` and still had to tap Start. v0.2 Story 1 acceptance ("user can start workout from Smart Stack widget") was failing.

#### Context — P1.3: HealthKit active energy mis-routed

`HealthKitWorkoutSubstrate.metric(for:)` mapped `HKQuantityType(.activeEnergyBurned)` to `WorkoutMetric(kind: .duration, …)` because Core's `MetricKind` had no kcal case. Both `WorkoutController.ingest` and `WorkoutViewModel.apply(metric:)` dropped every sample silently. The saved `HKWorkout.totalEnergyBurned` worked (read directly in `end()`), so the post-session summary was correct — but the on-watch and on-HUD live "flame" reading only ever reflected the local `EnergyAccumulator` HR-based estimate, never HK truth.

#### Decision — P1.1: App Group `UserDefaults` flag as the AppIntent → host handoff

Added a Core protocol `PendingWorkoutStartStore` + concrete `AppGroupPendingWorkoutStartStore` in `ARRunnerCore/Sources/ARRunnerCore/Workout/PendingWorkoutStart.swift`. Two methods: `markPending(at: Date)` (intent side) and `consumePending(now: Date, freshness: TimeInterval) -> Bool` (host side, atomic clear-on-read). Backed by `UserDefaults(suiteName: "group.com.arrunner.shared")` — the same App Group already declared on every relevant target's entitlements.

`StartWorkoutIntent.perform()` calls `pendingStartStore.markPending(at: now())`. `WorkoutView` reads `scenePhase` via `@Environment` and, on `.active` (plus a first-launch `.task`), calls `pendingStartStore.consumePending(now: Date(), freshness: 60)`. If `true` and `viewModel.launchState` is `idle/ended/cancelled/failed`, it calls `viewModel.start()`.

**Why a flag instead of URL / NotificationCenter?**
- Intent runs in widget-extension process; no equivalent of `UIApplication.openURL` round-trip on watchOS.
- `NotificationCenter` doesn't cross processes.
- App Group `UserDefaults` is documented, atomic, and already provisioned.
- Freshness window (60s) makes a stale tap safe.

#### Decision — P1.3: Pure mapping helper in Core, called by the watch substrate

Added `ARRunnerCore/Sources/ARRunnerCore/Workout/HealthKitMetricMapping.swift` with `static func activeEnergy(kilocalories:timestamp:) -> WorkoutMetric` returning `WorkoutMetric(kind: .energy, value: kcal, unit: "kcal", …)`. Substrate's switch case now calls through. Why a helper instead of inlining? The project has no watchOS test target — only `ARRunnerCoreTests`. The Core helper is the contract surface we can lock without needing HKHealthStore on the test runner.

Downstream display: Weiss's `7dd784e` already extended `WorkoutViewModel.apply(metric:)` with a `case .energy` arm + `hasLiveHKEnergy` latch (prevents subsequent heart-rate ticks from overwriting HK truth with the local estimate). Laughlin's was a no-op duplicate — confirmed her impl matches the intent.

#### Required follow-up

- v0.2 Story 4 (lock-screen complication) is planned separate work.
- Phone-side widget intent (same `StartWorkoutIntent`, runs in `ARRunnerWidgetsPhone`) will also drop the flag — but the phone app currently has no equivalent of `WorkoutView` and won't auto-start. Expected behaviour for v0.2 (watch is workout-authoritative per D1); the phone widget's value is launching the companion app for the live mirror.
- The latent bug noted in the audit (HealthKit identifier optional-pattern match in `metric(for:)` switch) was NOT addressed in this fix — out of scope per Joe's task framing. File as P2 for the next sweep.

#### Test status

- `ARRunnerCore/Tests/ARRunnerCoreTests/HealthKitMetricMappingTests.swift` — `testActiveEnergyMapsToEnergyKindWithKilocalorieUnit` locks the substrate's kcal contract; `testActiveEnergyPreservesValueAcrossRange` exercises the realistic sample range.
- `ARRunnerCore/Tests/ARRunnerCoreTests/PendingWorkoutStartStoreTests.swift` — covers empty/marked/consumed/stale/clock-skew/cross-instance flows. `StartWorkoutIntentContractTests` mirrors the intent's `perform()` flow.
- Watch target build: `xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED**.

**Test count:** `swift test` from `ARRunnerCore/`: **101 executed, 1 skipped (pre-existing v0.2 #5 anticipatory), 0 failures**.

#### Scope discipline

- Did NOT touch `WorkoutViewModel` — Weiss's `7dd784e` had already landed the `.energy` arm + `hasLiveHKEnergy` latch by the time Laughlin staged.
- Did NOT touch `GlassesService` — Weiss-owned, P1.2.
- Did NOT touch curated device IDs — Weiss-owned, P1.4.
- Did NOT touch `MetricKind` enum — Amber-owned, shipped 9571e23.
- Did NOT fix the latent optional-pattern-match in the substrate switch — out of scope per Joe.

# D-RICHARDS-TF-9 — Remove all signing build settings from xcodebuild CLI; xcconfig is single source of truth

**Date:** 2026-05-17
**Author:** Richards
**Status:** Proposed
**Supersedes / refines:** D-RICHARDS-TF-8 remains valid (probe-build is orthogonal). This decision completes the signing-pathway fix that D-RICHARDS-TF-1 through TF-7 established and rc1/rc2/rc3 exposed gaps in.

## Context

Three consecutive rc failures (rc1, rc2, rc3) all trace to the same root: signing-related build settings placed on the `xcodebuild archive` command line instead of in the project-level xcconfig.

| RC | CLI setting | Failure |
|---|---|---|
| rc1 | (none — inherited default `Apple Development`) | "no devices" — automatic signing tried Development profile path |
| rc2 | `CODE_SIGN_IDENTITY="Apple Distribution"` + `"CODE_SIGN_IDENTITY[sdk=iphoneos*]=..."` | xcodebuild mis-parsed `[sdk=...]` conditional; bare identity flagged as "manually specified" |
| rc3 | `CODE_SIGN_STYLE=Automatic` (with identity moved to xcconfig) | CLI override elevated style to highest precedence, making xcconfig identity appear as conflicting manual override on widget targets; main target fell back to Development path |

## Decision

**All signing-related build settings (`CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`) live exclusively in `Config/Signing.xcconfig`.** They are never passed on the `xcodebuild` command line.

The only signing-adjacent setting allowed on the CLI is `DEVELOPMENT_TEAM` (a runtime secret, not a mode selector).

The release workflow appends Distribution identity pins to the xcconfig after `bootstrap-signing.sh`:
```
CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution
CODE_SIGN_IDENTITY[sdk=watchos*] = Apple Distribution
```

**Additional fix:** xcodegen injects `CODE_SIGN_IDENTITY = "iPhone Developer"` at the target level for iOS application targets. This overrides the project-level xcconfig (target settings > project xcconfig in Xcode's precedence). Fixed by setting `CODE_SIGN_IDENTITY: $(inherited)` in `project.yml` for ARRunnerPhone, which defers to the xcconfig.

## Options considered

| Option | Verdict | Trade-off |
|---|---|---|
| **A: Manual signing for archive** (`CODE_SIGN_STYLE=Manual` on CLI + per-target profile specifiers) | Rejected | Defeats `-allowProvisioningUpdates` profile creation; requires portal pre-provisioning for every bundle ID; adds maintenance when adding new targets/extensions. Overkill given that xcconfig-only automatic signing should work. |
| **B: xcconfig-only automatic signing** (remove `CODE_SIGN_STYLE` from CLI, keep xcconfig pins) | **Chosen** | Both CODE_SIGN_STYLE and CODE_SIGN_IDENTITY at project-config level — consistent precedence, no conflict. `-allowProvisioningUpdates` creates Distribution profiles via ASC API. Trade-off: first archive after adding a new bundle ID may take 1-2 extra minutes while Xcode creates the profile. |
| **C: Keep automatic signing, override everything on CLI** | Rejected | xcodebuild's CLI parser doesn't support `[sdk=...]` conditionals, and any CLI identity conflicts with CLI `CODE_SIGN_STYLE=Automatic`. Three rc failures prove this approach is fundamentally broken. |

## Consequences

1. `release-testflight.yml` archive step passes `DEVELOPMENT_TEAM`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and `OTHER_CODE_SIGN_FLAGS` on CLI — nothing else signing-related.
2. Distribution profiles for all 4 bundle IDs must exist in the portal OR be mintable by the ASC API key (App Manager role).
3. Local dev is unaffected — `bootstrap-signing.sh` writes `CODE_SIGN_STYLE = Automatic` with no identity pin; Xcode.app uses the developer's personal Apple Development cert.

## Owner if accepted

Richards (Lead / Architect)

### D-RICHARDS-TF-11: rc5 archive fails on portal-side App ID capabilities — fix is portal action, not code (2026-05-17)

**Context.** v0.2.0-rc5 (run [26004285341](https://github.com/jkrilov/AR-Runner/actions/runs/26004285341)) confirmed the rc4 manual-signing fix worked: no more "automatically signed for development" conflict. Archive now fails one layer deeper, with two errors specific to provisioning-profile capability content:

> `"ARRunnerWidgetsPhone" requires a provisioning profile with the App Groups feature. Select a provisioning profile in the Signing & Capabilities editor.`
>
> `"ARRunnerPhone" requires a provisioning profile with the App Groups and HealthKit features. Select a provisioning profile in the Signing & Capabilities editor.`

The entitlements in the repo are correct and unambiguous:

| Target | Bundle ID | Entitlements declared |
|---|---|---|
| `ARRunnerPhone` | `com.arrunner.phone` | App Groups (`group.com.arrunner.shared`) + HealthKit |
| `ARRunnerWidgetsPhone` | `com.arrunner.phone.widgets` | App Groups (`group.com.arrunner.shared`) |

`Config/ARRunnerPhone.entitlements` declares both keys; `Config/ARRunnerWidgetsPhone.entitlements` declares App Groups. `project.yml` `ARRunnerPhone-Info.plist` has both `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`. Nothing on the repo side is missing.

**Root cause (portal-side).** `-allowProvisioningUpdates` + the ASC API key can mint an Apple Distribution provisioning profile on demand, **but only for capabilities already enabled on the App ID itself in the Apple Developer portal.** The error message is Xcode's way of saying "the profile I just minted doesn't satisfy your entitlements file because the App ID doesn't declare those capabilities." This is not something the CI can fix — App ID capability registration is a one-time portal action by an Account Holder / Admin.

**Decision: Path (a) — Joe enables capabilities on the App IDs in the developer portal. No code change. Retag rc6 after confirmation.**

Considered and rejected:

- **Path (b)** — pass `PROVISIONING_PROFILE_SPECIFIER` per target with hand-created profiles. Rejected: requires Joe to do portal work *and* a code change, couples the workflow to profile names, and breaks the ergonomic of `-allowProvisioningUpdates` minting profiles on demand. Reconsider only if path (a) reveals a portal-side blocker (e.g., HealthKit requires extra approval on this team).
- **Path (c)** — adopt fastlane `match`. Rejected per scope discipline: it's a larger architectural commitment (new dependency, private profiles repo, new secret rotation story) that would only be justified if (a) and (b) both failed. They haven't.

**Trade-off named.** Path (a) puts the source of truth for capability registration *outside* the repo — in the developer portal — which is invisible to code review and CI assertions. The mitigation is the runbook entry below (and SKILL.md update) that names this as a class of failure and tells future-us exactly which portal pages to check first.

**Required portal actions (for Joe — Account Holder).**

Go to <https://developer.apple.com/account/resources/identifiers/list> on the AR-Runner team and:

1. **App Group** — Identifiers → "App Groups" filter → confirm `group.com.arrunner.shared` exists. If not, create it (name: `AR-Runner Shared`, identifier: `group.com.arrunner.shared`).
2. **`com.arrunner.phone`** — open the App ID → enable **App Groups** capability → "Edit" → check `group.com.arrunner.shared` → Continue. Then enable **HealthKit** capability → Continue. Save.
3. **`com.arrunner.phone.widgets`** — open the App ID → enable **App Groups** capability → "Edit" → check `group.com.arrunner.shared` → Continue. Save.
4. *(Optional sanity, not required for this iteration)* — repeat the App Groups enable for the watchOS App IDs `com.arrunner.phone.watchkitapp` (App Groups + HealthKit) and `com.arrunner.phone.watchkitapp.widgets` (App Groups). The rc5 archive only signs the iOS scheme so they're not blocking, but they will be when the watch scheme starts shipping.

No need to manually create or download provisioning profiles. Once the App IDs declare the capabilities, `-allowProvisioningUpdates` + the ASC API key will mint matching Apple Distribution profiles on the next archive run.

**Validation plan.** After Joe confirms portal state, retag `v0.2.0-rc6` from `main`. Expected outcome: archive succeeds, IPA exports, altool upload reaches App Store Connect. If it still fails, capture the exact error and revisit — likely either a HealthKit approval requirement on the team or a stale cached profile, both of which have known fixes that do not require code changes.

**Supersedes:** none. **Extends:** D-RICHARDS-TF-10 (rc4 manual-signing fix); without that fix this error class would have been invisible behind the earlier identity conflict.

**Re-amplifies:** D-RICHARDS-TF-8 (PR-time Release-config probe). A `-showBuildSettings` probe wouldn't have caught this one — portal capability state is genuinely external — but a documented "before-rc-tag" runbook step ("confirm App ID capabilities match entitlements files") would have. Adding that to the TestFlight runbook.

— Richards, 2026-05-17T21:54Z
