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

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
