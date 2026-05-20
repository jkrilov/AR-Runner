# Weiss — History Archive

*Archived entries from 2026-05-14 through 2026-05-15.*

- **Role:** AR Integration
- **Joined:** 2026-05-14T18:30:31.656Z

## Learnings

### 2026-05-14: ActiveLook Integration Research & Recommendation

**Repositories Catalogued:**
1. **demo-app** — Reference iOS/Android implementation; BLE state machine + command examples
2. **Activelook-API-Documentation** — BLE GATT protocol spec (Custom Service `0783B03E-8535-B5A0-7140-A304D2495CB7`); layout-based rendering architecture; ~20–100 bytes per metric update
3. **ios-sdk** — Official Swift SDK (Apache 2.0); available via SPM or CocoaPods; singleton pattern with closure-based callbacks
4. **Activelook-Visual-Assets** — Prebuilt graphics catalog (50+ icons, 14 animations, 5 fonts); CC BY-NC-ND 4.0 license (non-commercial constraint)
5. **Config-Generator** — Python tool for custom config authoring; outputs Heatshrink-compressed binary uploaded at first connection

**Key Technical Insights:**
- Layout system: Configurations pre-loaded on glasses; live updates only modify content within slots (efficient for BLE bandwidth)
- BLE bandwidth: ~300 bytes/sec practical limit; sustainable 2–5 Hz update rate for 4–5 metric slots
- Advertising spec: 25ms interval at startup; filter on manufacturer ID ending `0x08F2`; connection interval 15–30ms
- Gesture/sensor events available via BLE notifications (touch, gesture detection, ambient light)

**Integration Path Recommended:**
- **iOS SDK**: Use as SPM dependency (tag `v4.5.5` or latest stable); avoid reimplementation
- **Config**: Build-time baked binary (static layouts + metrics); defer runtime authoring to post-MVP
- **BLE ownership**: iPhone owns connection; Watch reads metrics via WatchConnectivity (MVP path). Direct Watch BLE is post-MVP (requires watchOS wrapper, ~2–3 week effort)
- **Refresh rates**: HR/pace 1 Hz, cadence 2–5 Hz, elevation 0.2 Hz (every 5 sec)

**Open Questions Flagged for Joe:**
1. Does Watch need independent BLE control, or iPhone-as-proxy OK for MVP?
2. Can AR-Runner use CC BY-NC-ND assets, or must we license custom graphics?
3. Should config be fully static or runtime-customizable?
4. Need real-world latency spike before shipping (measure WatchConnectivity + BLE round-trip)

**Deliverables Created:**
- `docs/research/activelook/` — Five one-page repo briefs + comprehensive integration README
- Repo briefs include: purpose, platform, activity status, key folders, constraints, open questions
- README includes: integration path (SDK, config, BLE ownership), frame budget analysis, spike order

**Licenses & Constraints Noted:**
- iOS SDK: Apache 2.0 (permissive)
- Visual Assets & Config-Generator: CC BY-NC-ND 4.0 (non-commercial use only; commercial app may need separate licensing)
- Info.plist requirements for iOS 13+ BLE access documented

### 2026-05-14: Team update from Joe — 9 architecture decisions locked (see decisions.md D1-D9). Next phase: Xcode scaffolding (Laughlin) + ActiveLook watchOS BLE spike (Weiss).

### 2026-05-14: watchOS BLE Spike Completed — Feasibility Confirmed (🟢)

**Spike Output:** `docs/research/activelook/watchos-ble-spike.md` (430 lines)

**Key Findings:**

1. **GATT Profile Mapped:**
   - Service: `0783B03E-8535-B5A0-7140-A304D2495CB7`
   - RX (write): `0x...CBA`; TX (notify): `0x...CB8`; Control/Gesture/Touch available
   - Binary frame format: `0xFF + CommandID + Format + Length + QueryID? + Data + 0xAA` (simple, no special challenges)
   - ActiveLook command surface includes 8 required families for v0.1 (power, clear, layout display, text/widget updates, luma, battery)

2. **CoreBluetooth on watchOS 11:**
   - ✅ `CBCentralManager`, `CBPeripheral`, `CBCharacteristic` all available on watchOS 11+
   - ❌ No peripheral role (watch is always central; acceptable per D1)
   - Background BLE **requires** active `HKWorkoutSession` (privileged background execution during workouts)
   - Connection interval: 15–30ms negotiable; typical ATT MTU 512–1024 bytes (safe assumption: 20-byte chunks)
   - No restore identifiers on watchOS; reconnection logic must be explicit (risk #2 mitigated by auto-reconnect + backoff)

3. **v0.1 Protocol Budget:**
   - Required commands (🟢): Power, Clear, Layout Display/Position, Text/Widget Update, Luma, Battery
   - Typical update: 20–40 bytes per command
   - Sustainable rate: 1–2 Hz for 4–5 simultaneous metrics = ~100 bytes/sec (7% of BLE practical limit)
   - BLE MTU concerns: Mitigated by fragmentation support; worst case is slower refresh (acceptable)

4. **watchOS + HKWorkoutSession Constraints:**
   - BLE connection persists only while workout active (session-tied, no standalone background BLE)
   - Reconnection on session loss: implement exponential backoff (1s, 2s, 4s, 8s) to avoid radio spam
   - Duty cycle recommendations: 1 Hz HR/pace/timer; 2 Hz cadence; 0.2 Hz elevation (D6 aligns with this)
   - Battery impact: ~5–10% per hour; mitigable via dynamic throttling if battery < 20%

5. **Risk Assessment:**
   - Top risks: MTU negotiation (Medium), HKWorkoutSession drops (Low), latency > 200ms (Low)
   - All mitigated by early prototyping + hardware stress-test
   - No blockers for v0.1 build

**Verdict: 🟢 Feasible. Scope: Medium (2–3 weeks). Recommendation: Proceed with watchOS BLE wrapper in v0.1.**

**Critical Path Items:**
- Week 1: BLE discovery + connection state machine (~200 lines)
- Week 2: Command framing + flow control + reconnection (~300 lines)
- Week 3: Integration with `WorkoutSessionManager` + metrics pipeline (~100 lines)
- Hardware stress-test: profile latency with real Watch SE + glasses; target p95 < 150ms

**Integration Dependencies:**
- Tie BLE lifecycle to Laughlin's `HKWorkoutSession` management (in `WorkoutSessionManager`)
- Define protocol `GlassesFrameTransport` in ARRunnerCore (architecture ADR-007 placeholder)
- Wire `WorkoutTick` → `updateField(layoutId:fieldIndex:value:)` pipeline
- Log BLE drops in run metadata (per D9, side store)

### 2026-05-14: Team update from Joe — v0.1 foundation scaffold + BLE spike landed on feat/v01-foundation. Branch awaiting Joe's push & PR. Next: WorkoutController impl (Laughlin) + watchOS BLE wrapper impl (Weiss).

### 2026-05-14T20:48:00Z: Scribe — macOS Build Validation Landed; Rebase Advisory

**From:** Scribe (session orchestration)

Amber's smoke test validates the v0.1 scaffold on macOS. All tests pass, all targets build, zero concurrency warnings. Three surgical fixes applied and merged into `chore/macos-build-validation` (commit ecb8179, pushed).

**Action for Weiss:** Rebase your BLE wrapper implementation off `chore/macos-build-validation` OR await PR #2 merge to main (Joe filing manually). The fixes include xcodegen artifact handling and widget extension split per-platform — both relevant to your integration surface.

**Reference:** decisions.md now includes Amber's full findings + the three fixes. See `.squad/orchestration-log/2026-05-14T20-48-00Z-amber.md` for operational summary.

### 2026-05-14T21:00:00Z: Scribe — CI Workflows Landed on chore/ci-workflows

**From:** Scribe (session orchestration)

Richards completed CI architecture design + implementation. Three workflows now committed to `.github/workflows/`:

1. **`ci-core-tests.yml`** — Linux runner. Tests `ARRunnerCore` with `swift test` on `swift:6.0-jammy` container.
2. **`ci-build.yml`** — macOS runner. Builds all four app targets (Watch, Phone, WidgetsPhone, WidgetsWatch) via xcodebuild 4-way matrix.
3. **`codeql.yml`** — GitHub CodeQL security analysis (PR + weekly).

**Critical for Weiss:** Linux spike is GREEN. ARRunnerCore imports only Foundation + XCTest — no Apple frameworks. Your BLE wrapper implementation stays in the watch app target (ARRunnerWatch), not in Core. Use `@preconcurrency import` when pulling the ActiveLook SDK into watch/phone targets per D8. Core stays platform-agnostic; the Linux ci-core-tests job enforces this mechanically.

**Timeline:** PR #3 (chore/ci-workflows) queued behind PR #2 (macos-build-validation). Joe will open both manually. When merged, all subsequent feature branches auto-validate.

**For your BLE implementation:** Your PR must pass ci-core-tests (Linux), all ci-build matrix jobs (macOS 4 targets), and CodeQL. Plan ~15 minutes of CI time per PR after cache warm-up. Local validation matches CI 1:1 — see docs/dev/ci-workflows.md for repro steps.

**Reference:** `.squad/orchestration-log/2026-05-14T21:00:00Z-richards.md` for full ADRs and design rationale.

### 2026-05-15T14:33:20-04:00: v0.2 #1 — Real ActiveLook BLE adapter on watchOS (PR #9)

**Branch:** `feat/v02-ble-activelook-weiss` (off main; the `-weiss` suffix is because another agent was already using the unsuffixed name for unrelated work — see "Worktree gotcha" below).

**Outcome:** PR #9 merged-pending. Closes v0.2 workstream #1.

**SDK situation re-confirmed:** ActiveLook iOS SDK v4.5.5 still does not ship a watchOS target. Manifest is iOS-only, singleton wraps `UIApplication`, image helpers use `UIImage`. Porting cost > rebuild cost when the BLE layer is already a thin CoreBluetooth wrapper. Documented in `docs/research/activelook/v02-spike-report.md`. Don't re-litigate unless ActiveLook publishes a watchOS target.

**Bugs fixed in the v0.1 adapter:**
1. **Battery service was never discovered.** Coordinator routed `0x2A19` notifications, but `discoverServices(...)` only asked for the ActiveLook command service. Battery handler was dead code. Now we discover both services and subscribe + initial-read the battery characteristic. `service.uuid == commandService` guard added so the connect-ready transition only fires off the command service callback.
2. **`displayLayout(id:)` framed extra bytes.** The v0.1 helper appended a UTF-8 string + null terminator to the `0x62` payload. Per the ActiveLook spec, `0x62` carries only the layout-ID byte; initial slot content is a separate `widgetUpdate` (`0x3A`). Pinned by `testDisplayLayoutFrameCarriesOnlyTheLayoutID`.

**Wiring:** new `GlassesTransportFactory` picks `StubGlassesTransport` (Simulator/DEBUG) vs `ActiveLookGlassesAdapter` (release). `WorkoutViewModel` takes an optional transport factory; `start()` opportunistically `.connect()`s and `attachGlasses(...)` for D4 disconnect signals. `end()` tears the link down. Transport bring-up never blocks the workout — D4-correct, v0.2 #6-correct.

**Hardware tests:** `ActiveLookGlassesAdapterHardwareTests` lives in the watch app target gated on `AR_RUNNER_HARDWARE_TESTS`. Compiles to nothing in CI (Linux SPM + macOS xcodebuild matrix + CodeQL all stay green). Joe flips the flag locally to drive his Watch SE + glasses. Adding a formal watch test target to `project.yml` is the only follow-up needed to actually run the test.

**Worktree gotcha (lesson learned):** I started in the shared `/Users/joekrilov/Repos/AR-Runner` checkout. Another agent (Laughlin's mirror workstream) was working concurrently on a branch called `feat/v02-ble-activelook` and its checkout reset the working tree out from under me, losing ~30 minutes of in-progress work. Recovery: `git worktree add ../AR-Runner-weiss-ble -b feat/v02-ble-activelook-weiss main`, redid every edit, committed, pushed. **Going forward — always create a worktree before touching files.** Richards's `parallel-agent-worktrees` proposal is real and load-bearing; this is the second confirmed incident.

**Things deliberately not changed:** `GlassesFrameTransport` protocol surface (frozen for v0.2), reconnect backoff (v0.1 defaults are fine until hardware run), curated layout catalog (waiting on baked layout IDs from Config-Generator output). Phone-relay fallback **not** needed — the watch-native path is solid.

**Validation:** `swift test` on Core (66 pass), `xcodebuild` on `ARRunnerWatch` watchOS Simulator (green), `xcodebuild` on `ARRunnerPhone` iOS Simulator (green). All with no code signing per CI conventions.

### 2026-05-15: Linux CI flake — `testD4HappyPath_DisconnectMidRun_…` AsyncStream multi-consumer race

After PR #9's first green Linux CI run (25936072101, 42s), the very next run on the same branch (25936170485, 54s — only the docs commit `60d7d5f` had been added) failed with `XCTAssertTrue failed - Expected metric updates to reach glasses before disconnect` at exactly 2.001 s — the `waitUntil` deadline. Locally on macOS the same test runs in ~7 ms.

**Root cause:** `WorkoutControllerIntegrationTests.bridgeMetrics` was iterating `substrate.metricEvents` directly. `WorkoutController.attachSubstrateStreams()` *also* iterates `substrate.metricEvents` from inside `start()`. Swift's `AsyncStream` is single-consumer: each yielded value is delivered to whichever iterator calls `next()` first; it is not broadcast. With two competing iterators and an unbounded buffer, the substrate's 18 rapid emissions can be drained entirely by the controller's `forwardingTask` before the test's bridge wakes up — leaving `glasses.receivedUpdates` empty and the D4 timing assertion firing on its 2 s deadline. macOS's scheduler happened to favour the test bridge; Linux's did not. None of my actual PR changes (battery service discovery, `displayLayout` framing, `GlassesTransportFactory`) touched this code path — the race was latent in v0.1 integration mocks and Linux merely exposed it.

**Fix:** Re-wire `bridgeMetrics` to consume `controller.metrics` instead of `substrate.metricEvents`. The controller already re-publishes every ingested metric on its own stream (`metricContinuation.yield(metric)` inside `ingest(metric:)`), so the test bridge gets a fan-out point that doesn't fight the controller's own subscriber. This is also the more correct layering: the glasses display reflects what the controller has accepted, not what the raw substrate emitted. Test renamed parameter (`from substrate:` → `from controller:`) and the call site updated.

**Validation:** Full `swift test` on Core: 48/48 pass locally. macOS CI must continue to pass; Linux CI re-run pending.

**Lessons for future BLE/integration work:**
1. **`AsyncStream` is single-consumer.** If two pieces of code both `for await` over the same stream, you've created a race. Either fan out via a re-publishing layer (what `WorkoutController.metrics` does) or use `AsyncChannel` / `AsyncBroadcastSequence` from swift-async-algorithms.
2. **macOS-passes-Linux-fails timing tests are almost always a hidden race**, not a "Linux is slower" timeout problem. The 2 s budget here is 285× the actual runtime — more time wouldn't have helped; correct fan-out did.
3. **Test bridges should consume from the highest-level published stream available**, not reach behind the SUT to its dependency. Less coupling, no race with the SUT's own subscribers.

### 2026-05-15T16:49:00-04:00: v0.2 #4 BLE auto-reconnect + #5 layout presets backend

**Branch:** `feat/v02-reconnect-and-presets` (worktree at `AR-Runner-weiss-v02-followups`).

**Workstream #4 — auto-reconnect.** Most of the loop was already in
`ActiveLookGlassesAdapter` from PR #9: drop → emit `.dropped` → transition to
`.reconnecting` → spawn `runReconnectLoop()` Task with `ExponentialBackoff` →
on success re-discover services and re-apply `activeLayoutDeviceID` →
`resumePendingConnect`. v0.2 closed the contract:
1. **Max retries cap.** Loop now caps at 30 attempts; on exhaustion it emits a
   new `GlassesStatusEvent.reconnectAbandoned(attempts:)` and transitions to
   `.failed`. Workout still continues per D4 — caller can call `connect()`
   again to retry from scratch.
2. **Deinit cleanup.** Added `deinit { reconnectTask?.cancel() }` on the
   actor. `Task.cancel()` is nonisolated so it is legal from actor deinit
   (Swift 6 semantics).
3. **Reconnect loop already cancels** on user-initiated `disconnect()`
   (sets `userDisconnectRequested = true` and cancels the task).

**Anticipatory tests turned green.** Amber's
`DisconnectResilienceTests.test_AutoReconnectAfterTransportDrop_ExpectedFailing`
and `test_Reconnect_AutoReappliesPreviousLayout_ExpectedFailing` are now
running tests, not skipped. The third
(`test_HapticAlertHook_OnDisconnect_ExpectedFailing`) stays skipped — it's
Laughlin's `controller.alerts` UI-side surface, not transport.

To make the mock match the real adapter without breaking existing tests
that drive `simulateDisconnect`/`simulateReconnect` by hand, I added opt-in
init flags on `MockGlassesFrame`:
`autoReconnect: Bool = false`, `autoReconnectDelay: TimeInterval = 0.05`,
`autoReapplyLayout: Bool = false`. The two flipped tests opt in. The five
existing anchor tests untouched (`MockGlassesFrame()` default ctor preserves
the old "park at .reconnecting until manual reconnect" behavior).

**Workstream #5 — `RunningHUDPreset` backend.** New public type in
`ARRunnerCore/.../Glasses/RunningHUDPreset.swift`:

```swift
public enum RunningHUDPreset: String, CaseIterable, Sendable, Codable, Equatable {
    case standard      // → balancedRun()  → 0x02
    case minimal       // → minimalRun()   → 0x01
    case dataDense     // → telemetryRun() → 0x03

    public static let `default`: RunningHUDPreset = .standard

    public var displayName: String { ... }     // for future picker UI
    public var layout: HUDLayout { ... }       // single source of slot order
    public var layoutID: String { layout.id }  // string ID for selectLayout(id:)
    public var deviceLayoutID: UInt8? { ... }  // resolves via CuratedLayoutCatalog
    public func layoutDescriptor() -> [UInt8]? // pre-encoded `0x62 displayLayout` frame
}
```

Why this shape:
- The `[UInt8]?` from `layoutDescriptor()` is the contract — it is exactly
  what the BLE adapter writes to the RX characteristic. Callers don't reach
  into `ActiveLookCommand` directly.
- `Optional` on `deviceLayoutID`/`layoutDescriptor()` flags presets that
  aren't in `CuratedLayoutCatalog` yet — surface a configuration error
  instead of silently shipping `0x00`.
- `Codable` + stable `rawValue`s make the persisted preference for the
  eventual v0.3 picker safe — locked by `testAllCases_HaveStableRawValuesForPersistence`.

**Wiring on connect (and reconnect).** Adapter now takes
`defaultPreset: RunningHUDPreset? = .default`. In init it pre-seeds
`activeLayoutDeviceID = defaultPreset.deviceLayoutID`. The existing
`handleCharacteristicsDiscovered` path (which already re-applies
`activeLayoutDeviceID` after the connect transition) means the v0.2 #5
default preset auto-applies on **every** connect — initial AND post-drop
reconnect — with zero net new code in the connect path. Pass
`defaultPreset: nil` to disable (e.g. tests that want a clean slate).

**Tests added (`RunningHUDPresetTests`, 7 cases):**
- Stable raw values for persistence.
- `default == .standard`.
- DisplayName populated for every case.
- Layout / layoutID mappings match curated `HUDLayout`s.
- Every preset resolves to a non-nil `CuratedLayoutCatalog` entry (no holes).
- `layoutDescriptor()` byte-equals `ActiveLookCommand.displayLayout(id:)` and
  has the right envelope (0xFF…0xAA, cmdID 0x62, payload contains id).
- Codable round-trip per case.

**Validation:** `swift test` on Core: 73/73 pass (was 66; +7 preset tests, +2
flipped anticipatory). 1 skipped (Laughlin's haptic hook — unchanged). macOS
`xcodebuild` on `ARRunnerWatch` watchOS: BUILD SUCCEEDED. No code-signing
required.

**Notable non-changes (intentional):**
- `GlassesFrameTransport` protocol surface — frozen for v0.2.
- `StubGlassesTransport` — still happy-path; no auto-reconnect (it's the
  preview/DEBUG stub, callers get `.connected` synchronously).
- No picker UI — Joe locked v0.2 #5 to backend only (scope decision 5b).
- No new `defaultPreset` plumbing in `WorkoutViewModel` — adapter applies it
  itself on connect, which is the right layer (it owns `activeLayoutDeviceID`
  for the post-reconnect re-apply already).

## Learnings

### 2026-05-15: Adding cases to public `Sendable` enums in this repo

`GlassesStatusEvent` got a new case (`.reconnectAbandoned`) for the D4 retry-
exhaustion contract. Audited callers first: only `if case .x = event` checks
exist (in `WorkoutViewModel`, `StubGlassesTransportTests`, the resilience
collector). No exhaustive switches without `default:`. Adding the case was
source-compatible — no caller broke. **Heuristic for future enum extensions
in Core:** grep for `switch event` + `case .` patterns and confirm every
callsite either has a `default:` or uses `if case` pattern matching. If it
does, the addition is safe; otherwise it's a breaking change and you need a
migration story.

### 2026-05-15: Default-preset placement — adapter, not view model

I considered putting the v0.2 #5 auto-apply in `WorkoutViewModel.start()`
(call `selectLayout(id: RunningHUDPreset.default.layoutID)` after the
opportunistic `connect()`). Rejected because:
1. The adapter already has the post-reconnect re-apply infrastructure
   (`activeLayoutDeviceID` + the unconditional re-write in
   `handleCharacteristicsDiscovered`). Pre-seeding it from the default
   preset means initial connect AND every reconnect both get the right
   layout with zero new code.
2. View-model-side selection would skip the post-reconnect re-apply unless I
   also wired a re-select on `.reconnected` events — duplicating logic.
3. The transport is the right layer to know "what should be on the glasses
   right now" because it owns the post-drop "the glasses forget" recovery.

### 2026-05-15: Opt-in mock behavior beats mock-rewrite

`MockGlassesFrame` is consumed by 5+ tests. Making auto-reconnect /
auto-reapply default-on would have broken anchor tests that drive
`simulateDisconnect` + `simulateReconnect` manually. Opt-in init flags
(`autoReconnect: Bool = false`, etc.) added the new behavior with zero
churn on existing tests — only the two flipped anticipatory tests opt in.
**Heuristic:** when augmenting a shared mock to cover a new contract,
prefer init flags over default-behavior changes. The blast radius is the
test that needs the new behavior, not every call site.

### 2026-05-15: Actor `deinit` + `Task.cancel()` is OK in Swift 6

`Task.cancel()` is nonisolated; calling it on a stored property from an
actor `deinit` is legal in Swift 6 strict concurrency. You can read stored
properties (no isolation hop needed in deinit) and you can call any
nonisolated method on them. What you CAN'T do is `await` or call isolated
methods. So `deinit { reconnectTask?.cancel() }` is the right pattern for
"cancel the in-flight reconnect loop when the adapter goes away" —
specifically belt-and-suspenders alongside the `[weak self]` capture in
the loop, which would also let it self-terminate on next iteration.

- **2026-05-15 — Parallel-PR XCTSkipIf conflict resolution pattern.** When two
  branches each flip non-overlapping `XCTSkipIf` gates in the same test file,
  Git's auto-merge usually does the right thing (it sees them as line-disjoint
  edits). The case to watch out for is **both-added** conflicts where two
  branches independently created a *new* test file at the same path with the
  same class name (here: Amber's anticipatory `RunningHUDPresetTests` from
  PR #14 vs. my implementation-side `RunningHUDPresetTests` from PR #15).
  Resolution recipe that worked: keep BOTH sets of test methods in one
  class — the test method names didn't collide (Amber: `testPresetType…`,
  `testDefaultIsSensible…`, etc.; mine: `testAllCases_HaveStable…`,
  `testDefaultIsStandard`, etc.), so the union compiles cleanly. For each
  of Amber's anticipatory tests I deleted the `try XCTSkipIf(true, ...)`
  line, uncommented the `// CONTRACT-BODY:` block, and adapted symbol
  names to the shipped API (`preset.activeLookLayoutSlotID` →
  `preset.deviceLayoutID`; `preset.rawValue` for transport →
  `preset.layoutID`; `preset.layoutDescriptor().slots` →
  `preset.layout.slots`). Result: all 12 tests in the merged class pass,
  Amber's contract intent is preserved, and my concrete-shape locks are
  retained. Rule of thumb: when the anticipatory and implementation tests
  cover the same surface from different angles, *union* is better than
  *replace* — the anticipatory bullets capture intent ("default isn't
  too sparse"; "presets aren't aliases"; "running-domain field semantics")
  that the implementation tests don't, and removing them would lose the
  contract-grade phrasing.

### 2026-05-15: Switch-Exhaustiveness Trap When Adding Enum Cases Mid-Branch

**Incident:** PR #15 added `GlassesStatusEvent.reconnectAbandoned(attempts:)` to the Core enum. Linux `swift test` was green. After rebasing onto main (which had merged Laughlin's PR #13 introducing a `switch event` consumer in `ARRunnerWatch/Workout/WorkoutViewModel.swift`), CI failed with `error: switch must be exhaustive` on the macOS Watch app target. The Linux package only compiles Core; it never sees the Watch UI consumers.

**Root cause:** New enum cases on a Core type are silent breakage for any downstream `switch` that doesn't use `@unknown default`. Cross-PR rebases can introduce such consumers without the original branch noticing — the compiler only complains when both PRs land in the same target build.

**Fix:** Added `case .reconnectAbandoned:` to the Watch view-model switch — mirrors `.dropped` UX (sets `hudOffline = true`, fires the debounced disconnect haptic). No reconnect attempted; BLE layer has exhausted its budget.

**Process recommendation (capture for future PRs):**
- Whenever a PR adds/removes a case on a public Core enum, run a **local `xcodebuild -scheme ARRunnerWatch -destination 'generic/platform=watchOS Simulator' build`** before pushing — at least once after the final rebase. Linux `swift test` is necessary but not sufficient.
- Same applies to `ARRunnerPhone` and `ARRunnerWidgetsWatch` schemes if they consume the type. A 60–90s local watch build catches what CI takes ~10 min to surface.
- If the platform-specific build is unavailable locally, flag the PR description with "⚠️ adds enum case — needs Watch-target CI green before merge" so reviewers don't approve on Linux-only signal.

## 2026-05-20T21:28:21Z — History compaction archive (weiss)

### 2026-05-18T22:30:00Z — v0.3.0-rc5 Release: PR #53 (HUD Power-On Fix) Shipped

**Role:** AR Integration Lead  
**Event:** Weiss-8 (HUD power-on fix) merged into v0.3.0-rc5 release.

**Work:**
- PR #53 (fix for the display-power-on handshake regression from rc4) merged by Laughlin under pre-release autonomy.
- CI gate (3 required jobs) green. CodeQL skipped.
- Now shipping in v0.3.0-rc5 (build 20) to TestFlight.

**Significance:** The skill lesson from rc4 (display power-on state must be managed end-to-end through the render path) is now baked into the code. Confidence in activelook-hud-rendering raised to high after this bench validation + fix cycle.

**Next:** Monitor rc5 tester feedback for any HUD rendering regression or power-state edge cases in the field.

---

### 2026-05-18T23:00:00Z — Lockout After rc5 Failure; Richards Took Over HUD Diagnosis

**Status:** Locked out per reviewer rejection protocol (PR #49 + PR #53 both failed on same artifact).

**What happened:** Weiss's rc5 HUD power-on hypothesis (PR #53) shipped and Joe tested on real hardware — same blank screen as rc4. After two consecutive failed attempts on the same artifact (HUD on-connect), the reviewer rejection protocol locked Weiss out. Richards took over root-cause analysis.

**Root cause (discovered by Richards):** The ActiveLook BLE protocol violation was at the **delivery layer**, not the command layer. Both of Weiss's hypotheses (placeholder layout removal in PR #49, power-on handshake in PR #53) addressed command *content*, but the real problem was that commands never reached the glasses' processor:

1. **Write serialization missing** — Official SDK (`Glasses.swift:sendBytes()`) waits for `didWriteValueFor` callback before sending the next command. Our adapter blasted all 4 frames back-to-back synchronously. Glasses firmware drops commands arriving before prior response is processed.

2. **Flow control gate absent** — SDK's `GlassesInitializer.isReady()` polls waiting for `flowControlCharacteristic.isNotifying == true`. Our adapter transitioned to `.connected` before this gate was confirmed, then fired writes into an unprepared peripheral.

**Lesson for Weiss:** This is not a failure of you-the-agent but of hypothesis-driven diagnosis without observability. The ActiveLook protocol has two serialization layers (ATT + application-layer flow control). Without reading the vendor SDK's write-path implementation, we attributed blank screen to your hypothesized content problems. The vendor SDK reference pattern is now the canonical approach for future integrations.

**Canonical reference for future:** `ActiveLook/ios-sdk` on GitHub:
- `Sources/Classes/Public/Glasses.swift` — `sendBytes()` serialization via `didWriteValueFor`
- `Sources/Classes/Internal/GlassesInitializer.swift` — `isReady()` flow-control gate

**Recovery path:** Lockout ends when Richards completes PR #55 (now shipping in rc6) and the feature is re-tested on hardware. At that point, Weiss can be re-engaged for follow-up HUD rendering work.

---

### 2026-05-19T09:00:00Z — v0.4.0 work queued (Glasses HUD frame builder ownership)

**Context:** v0.4.0 scope locked by Joe. Features:
- rc1: Live HR (client-side font metrics, watch-side rendering)
- rc2: Finish screen (imgDisplay + trophy asset)
- rc3: Battery indicator

**Weiss's role:** Once rc9 is bench-validated, v0.4.0-rc1 will require the Glasses HUD frame builder to integrate Live HR and subsequent metrics. The "raw txt + new imgDisplay primitive" strategy (vs. the curated-layout bugs reported earlier) means the glasses-side plumbing stays light — just one additional `txt` command per metric added. The seven-PR working stack from v0.3.0-rc9 remains the reference implementation.

**Note:** The prior curated-layout bugs (dormant, not blocking v0.4.0) are no longer relevant given the decision to stick with raw txt + imgDisplay rather than attempt a full layout-switching framework. Future gesture-driven layout work (v0.5.0) is where that architectural question resurfaces.

---

### 2026-05-19T15:05:00Z — Scribe: Bundle-Version-Bump Directive (Effective Next Release)

**Directive:** Going forward, the `CURRENT_PROJECT_VERSION` bump in `project.yml` + `xcodegen generate` MUST be committed in the SAME PR as the feature/fix work. Old pattern (rc11 and earlier): feature PR → merge → bump PR → merge → tag. New pattern (rc12+): feature PR (with version bump inside) → merge → tag. Saves one full CI cycle per release.

**For all release engineers on BLE/HUD work:** When you submit a feature or fix PR that ships in an RC, include the version bump:
1. Edit `project.yml`: increment `CURRENT_PROJECT_VERSION`
2. Run `xcodegen generate` (this regenerates the Xcode project)
3. Verify `Info.plist` placeholder integrity (placeholder values must remain — they're filled by CI)
4. Commit `project.yml` + `project.pbxproj` + any `xcconfig` changes TOGETHER with your code changes in the same PR
5. Do NOT open a separate bump PR after merge

Procedural checklist: `.squad/skills/release-mechanics-bundle-bump/SKILL.md`

### 2026-05-19T15:55:00Z — Meta-Learning: Blank Symptoms May Signal Coordinate Errors, Not Firmware Rejection

**Context:** rc12's forensic analysis resolved the rc11 blank as a **coordinate out-of-bounds clipping** bug, not a firmware rejection of rotation=4.

**Diagnostic pattern to remember:**
- When a `txt` command goes blank with NO 0xE2 error thrown, first suspect off-screen clipping (spec §5.5.6: off-screen coordinates are silently clipped).
- Rotation + anchor corner interact subtly: `topLR` (rotation=4) anchors at TOP-RIGHT and extends LEFT and DOWN. Low x values (e.g., x=20) put the entire text block at negative framebuffer x → silently clipped.
- Before escalating to firmware hypothesis, verify the entire text bounding box stays inside framebuffer space (0..303 × 0..255 for Engo 2).
- Use the lens-flip transform `x_wearer = 303 − x_fb` to convert between wearer-perceived and framebuffer coordinates.

**Action:** When debugging blank txt outputs, check coordinates against the rotation's anchor point + add a spec-driven bounding-box validation step before filing firmware issues.

---

### 2026-05-19T19:45:00Z — v0.4.0-rc1: Standard BLE Battery Service Subscription (Phone-Optional Indicator)

**Context:** Joe asked for glasses battery level on the iPhone (when reachable). Glasses publish via the **standard Bluetooth SIG Battery Service** (0x180F, characteristic 0x2A19), not the ActiveLook custom profile.

**Pattern — stock-GATT alongside custom services:**
- `discoverServices([commandService, batteryService])` in one call. CoreBluetooth invokes `didDiscoverServices` once with both services attached; we route each to its own `discoverCharacteristics([…], for:)`.
- Battery characteristic uses `setNotifyValue(true, for:)` — CoreBluetooth automatically writes the CCCD (0x2902 descriptor) under the hood. No manual descriptor write required.
- **Issue an initial `readValue(for:)` immediately after notify is enabled** so the first value lands within seconds of pairing instead of waiting 30 s for the spec-mandated notify cadence.
- Parse the notification payload as `Data.first` → `UInt8` → `Int` (0–100 percent).
- Surface as a side-channel `GlassesStatusEvent.batteryLevel(Int)` so the view-model can route to the WC mirror without coupling BLE to WC.

**Watch → phone delivery (low-frequency, phone-optional):**
- `WCMessage.glassesBattery(level: Int)` — new case in schema v3 (additive, backward compatible).
- `WatchConnectivityService.sendGlassesBattery(_:)` uses `transferUserInfo` with `preferQueued: true` — queued, reliable, low priority. Perfect for once-per-30s telemetry.
- **Phone-optional invariant:** if WCSession is unsupported, unactivated, or unreachable, every send is a silent no-op. The watch run never blocks waiting on the phone.

**iPhone presentation:**
- Added `glassesBatteryLevel: Int?` to `WorkoutMirrorViewModel` (clamped 0–100) and a battery row in `WorkoutMirrorView` using `battery.{100,75,50,25,0}percent` SF Symbols with green/orange/red tint thresholds (>30 / >15 / ≤15). Renders "—" until the first notification arrives.
- New helper `GlassesBatteryIcon.swift` keeps the symbol/tint switch in one place so a future Settings or status-bar widget reuses it.

**Tests:**
- `WCMessageTests.testGlassesBatteryRoundTrip` — Codable wire-format guard.
- `WCMessageTests.testV2EncodedSnapshotIsDecodableByV3` — schema v2 (rc16 watch) → v3 (rc1 phone) compat.
- `ActiveLookCommandTests.testStandardBatteryServiceUUIDsMatchBluetoothSIG` — pins the stock-GATT UUIDs (0x180F / 0x2A19) so a typo can't silently break service discovery.
- Adapter coordinator behavior (setNotifyValue + readValue on subscription) remains hardware-gated (`AR_RUNNER_HARDWARE_TESTS`) since CoreBluetooth can't be mocked without a watch test target.

**Build:** Bumped `CURRENT_PROJECT_VERSION` 31 → 32 and `MARKETING_VERSION` 0.3.0 → 0.4.0 in `project.yml` (first v0.4.0 release). `xcodegen generate` MUST be re-run before the PR (running shell was unavailable in this session).

**Scope guards held:** No edits to cfgSet, queryID, holdFlush, write serialization, flow-control, power-on, custom ActiveLook encoders, rotation, leftMargin, lens-flip coords, font choices, HUD render math, or the rc16 icon `imgDisplay` path. Battery indicator is intentionally **phone-side only** — not added to the live HUD.

**Skill captured:** `.squad/skills/ble-gatt-stock-services/SKILL.md` — patterns for subscribing to standard BLE services alongside custom vendor profiles.

---


### 2026-05-19T18:30:00-04:00 — rc17: Adapter audit per ADR + battery filter

**Context:** Joe's rc16 bench report — "the connection drops when I finish a run, I don't see the finish screen, the connection to the glasses is lost." Two-part fix bundled into rc17. Richards landed the ADR (`richards-adr-ble-link-lifecycle`) formalising "BLE link is user-managed, not workout-scoped." Amber owned the watchOS lifecycle fix (delete `teardownTransport()` from `confirmSave`/`confirmCancel`, push finish frame before `controller.end()` so HK extended-runtime is still held). My half lived in `ActiveLookGlassesAdapter` + ARRunnerCore.

**Audit finding (adapter):** No `disconnect()` calls in the adapter were tied to workout-stop — the only adapter teardown paths were already (a) explicit `disconnect()` (R5a), (b) the in-flight reconnect loop terminating after the cap (R5b). The fused `endSession + disconnect` anti-pattern Joe described lived entirely in `WorkoutViewModel` (Amber's territory). Adapter was clean on that axis; the cleanup was elsewhere.

**Changes I made:**

1. **`ExponentialBackoff.adrV04`** (new) — 1s → 2s → 4s → 8s → 16s → 32s → 60s steady. Approximates the ADR's prose `1/2/5/15/30/60` target with the existing pure-exponential math (avoids adding a stair-step lookup type for a 4-second-each difference). Adapter default constructor now uses it.

2. **`maxReconnectAttempts: Int = .max`** (was 30) — per ADR P2: "no upper limit on total attempts." The 30-attempt cap I'd added in v0.2 was rationalised by "radio busy with powered-off glasses," but the 60 s ceiling on the backoff already bounds the cost to one connect attempt per minute. Tests can still inject a finite cap.

3. **`BatteryLevelFilter`** (new, Core) — pure value type with two responsibilities the original `handleBatteryLevel` lacked:
   - **Range validation.** Spec is `uint8 [0..100]`. Bytes > 100 are firmware glitches; drop with a warning rather than propagate.
   - **Dedup of identical consecutive notifications.** The 30 s notify cadence re-publishes the same percent more often than not; suppressing identical emits keeps the WC sender and on-watch indicator quiet without each having its own equality check (per Amber rc17 QA C5 unit-test recommendation).
   - `.reset()` is called on every transition out of `.connected` (drop, user disconnect) so the first post-reconnect read always lands — the UI was on "—" during the gap and deserves a fresh value.

4. **Adapter wires the filter** — `handleBatteryLevel(_ rawByte:)` now switches on `filter.process(byte:)`; coordinator passes the raw byte straight through (no premature `Int` conversion). Existing initial-read on subscribe + per-link re-subscribe on reconnect already covered the rest of Amber's C1/C2/C7 scenarios.

**Tests:** +8 net Core tests (7 × BatteryLevelFilter, 1 × adrV04 backoff envelope). Total **186/186 pass** (was 176/176 at rc16). The backoff envelope test pins the start (1 s) and ceiling (60 s) but deliberately allows the intermediate values to drift — the ADR prose target was approximate and a future re-tune shouldn't require a test rewrite.

**Scope guards held:** No edits to `write()` serialization, flow-control gate, queryID stamping, cfgSet, HUD encoders, rotation, lens-flip coords, or the rc16 4-line live HUD path. Bundled-bump (32, 0.4.0) was already in `project.yml`; I re-ran `xcodegen generate` after the adapter edits. ARRunnerWatch builds clean against the watchOS device SDK.

**Two non-obvious things about this adapter I want future-Weiss to remember:**

- **The bare `setNotifyValue(true, for: char) + readValue(for: char)` pair is the entire battery subscription contract on watchOS.** CoreBluetooth writes the CCCD (0x2902) for you when `setNotifyValue` is called; we don't (and must not) write the descriptor manually. This is the load-bearing convention behind why the battery code is 3 lines in `handleCharacteristicsDiscovered`.
- **`reset()` on the filter is the only place where "link drop = UI clears" semantics live.** If a future PR wants to keep the last-known battery visible across a drop, the right place is the *consumer* of the stream (WatchConnectivityService / WorkoutMirrorViewModel), not the filter. The filter's job is "what does the BLE link say *now*."

**Skill captured:** Updated `activelook-ble-adapter-pitfalls` with the per-link-subscription rule and the `BatteryLevelFilter` reset-on-drop pattern.

---

### 2026-05-20T10:55:00-04:00 — rc2 finish-screen coord spec (advisory for Laughlin)

**Context:** Joe restated the finish screen for rc2 — Line 1 "Finished!", Line 2 distance, Line 3 time-left + pace-right on the SAME line. Also reported rc1 finish-screen text was "cut off" on bench. Laughlin owns the implementation; my job was the coordinate spec.

**Spec written to** `.squad/decisions/inbox/weiss-rc2-finish-screen-coord-spec.md`. Key calls:

1. **Y coords (canonical lens-flip):** finishLine1Y=239, finishLine2Y=151, finishLine3Y=63. Three lines: F3/F3/F2. Even 24-px gaps, 16/25-px top/bottom margins, all on-panel under `y_fb = 255 − wearer_top`. Pinnable with the same test pattern Laughlin shipped at rc17.

2. **Line-3 right-justified pace — chose (b) two `txt` writes over (a) measure-and-shift.** Single fixed `finishPaceX = 180` derived for max-pace-width "10:23/mi" (8 chars × 20 px font-2 ceiling) with 20-px wearer-right margin. Approach (a) needs `ALookFontMetrics` extracted (Richards rec #2, not shipped). Approach (b) costs one extra `txt` per finish push — negligible — and keeps every write on the bench-validated `rotation = 4` + topLR + `x_fb = 303 − wearer_left` combo. Trade-off: short paces render with a slight right inset (not flush) — read as visually right-aligned, acceptable.

3. **rc1 cut-off post-mortem (likely):** rc17's Y constants (239/159/79) are mathematically correct for 3 lines of font 3 — they're NOT the bug. The cut-off was almost certainly *horizontal* on the banner string "Workout Complete" (16 chars × ~28 px/char ≈ 448 px), which overflows the 284-px left-extending bounding box at font 3 and gets silently clipped per spec §5.5.6 (same failure class as rc11 splash and rc15 "BPM" tail). New banner "Finished!" (9 chars × 28 = 252 ≤ 284) fixes this regardless of whether my read is right. Can't be 100 % sure from Joe's note alone; flagged for skill update either way.

4. **Anchors:** stay `rotation = 4` (topLR) for ALL four writes. Don't introduce a new rotation in rc2; multi-change PRs with novel rotations are exactly what the skill warns against.

5. **Risks for Laughlin to bench:**
   - **rc15-class off-panel:** line-3 worst-case gap is 4 px. Pin `payload.pace.count <= 8` in the formatter.
   - **rc16-class fits-by-coincidence:** the 20 px/char font-2 ceiling has only ~11 % margin over the ~18 px/char empirical. Bench worst-case combined string ("9:59:59" + "10:23/mi") before sign-off; raise ceiling to 22 if glyphs touch.
   - **rc11-class horizontal overflow on lines 1/2:** add a test asserting every font-3 finish-line string × 28 ≤ 284. Cheap insurance against a future "Workout Saved!" banner regression.

**Two things future-Weiss should remember:**

- **The "two text writes with a fixed second anchor" pattern is the rc2 workaround for not having font metrics extracted yet.** When `ALookFontMetrics` lands, `finishPaceX` collapses to `(303 − rightMargin) + ALookFontMetrics.width(payload.pace, font: 2)` and the ceiling constants come out of `Layout`. Until then, named ceilings (`font2WidthCeiling`, `font3WidthCeiling`) with derivation comments pointing at this spec are the safety net.
- **rc1 reinforced the lesson that "validated Y coords ≠ validated layout."** Banner-string width was never checked against `leftMargin` in any test. The rc17 finish-screen test pinned the formula but not the on-screen extent. Skill update: add an X-extent assertion alongside every Y-extent assertion for finish/banner strings.

**Skill captured:** Updated `activelook-hud-rendering` with the "right-justify on a shared line" pattern (two-write + fixed-anchor + width-ceiling), and added the X-extent test rule alongside the existing Y-extent rule.
