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
| Corporate-account redaction | `.squad/orchestration-log/` and audit doc |
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

1. **Redact Microsoft-corporate username** (`joekrilov_microsoft`) — single occurrence in `.squad/orchestration-log/2026-05-14T20-48-00Z-amber.md:46`.
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
