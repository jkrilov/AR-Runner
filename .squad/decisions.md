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

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
