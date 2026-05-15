# Weiss — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
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
