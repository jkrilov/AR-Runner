# Weiss — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** AR Integration
- **Joined:** 2026-05-14T18:30:31.656Z

## Learnings


## Summary
Pre-RC5 development and audits (2026-05-14 through 2026-05-17) archived in history-archive.md.

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

---

### 2026-05-20T12:42:23-04:00 — rc3: BLE-link UI-freeze on discard (observer-scope fix)

**Context:** Joe's rc2 bench finding #4 — discarding a run leaves the
watch chip on "Glasses: Connected" while the BLE link is dead, and the
Disconnect button is inert. Only killing the app recovers. Laughlin
owns the discard-returns-to-start-screen workout state machine in
parallel; my half was the BLE/observer-lifecycle audit.

**Root cause (single line, but architectural):** `WorkoutViewModel
.stopRuntimeTasks()` — called by both `confirmSave()` and
`confirmCancel()` — cancelled `glassesStateTask` and
`glassesStatusTask` alongside the workout-scoped tasks. These two are
the **only** consumers of `transport.connectionStates()` /
`statusEvents()`. The `start()` path reuses an existing transport
without re-calling `attachGlasses`, so once cancelled they were gone
for the VM's lifetime. ADR-1 held at the transport layer (no
`disconnect()` calls from workout-end paths) but was being violated at
the observer layer.

**Symptoms it produced (every one of Joe's findings #4 bullets):**
- UI shows stale `.connected` because nothing forwards
  transport-state changes into `glassesLinkState` anymore.
- `disconnectGlasses()` actually disconnects the link (adapter
  `cancelPeripheralConnection` runs and transitions to `.disconnected`)
  but the VM never sees the new state → "Disconnect button does nothing"
  is purely UI not reflecting the underlying tear-down.
- `connectGlasses()` early-returns on the stale `.connected` read.
- App restart rebuilds the VM and re-attaches the observers, so a
  clean relaunch is the only recovery — exactly what Joe reported.

**Whether the BLE link physically drops on discard is a separate
question** (it almost certainly does — watchOS suspends CoreBluetooth
once `HKWorkoutSession` ends and the app loses extended runtime), but
that doesn't matter once the observer survives: the UI will simply
follow the link to `.disconnected`, the Disconnect button becomes a
no-op-but-visible, and Reconnect actually works because the
short-circuit on `.connected` no longer fires.

**Fix:** Remove `glassesStateTask?.cancel()` and
`glassesStatusTask?.cancel()` from `stopRuntimeTasks()`. The
`attachGlasses` cancel-then-replace pattern at the top of that method
remains the ONLY sanctioned cancellation site for these tasks. Heavy
rationale comment block on `stopRuntimeTasks()` carries the contract
forward (no watchOS unit-test target yet).

**Coordination with Laughlin:** Touched only `stopRuntimeTasks()` in
`WorkoutViewModel.swift` — no edits to `confirmSave` / `confirmCancel`
state machine code, no edits to `launchState` cases, no changes to the
discard navigation/state behaviour. Laughlin's parallel work on
discard-returns-to-start is uncoupled from this fix.

**Scope guards held:** No edits to adapter internals, `write()`
serialization, flow-control gate, queryID stamping, cfgSet, HUD
encoders, rotation, lens-flip coords, the rc1/rc2 finish-screen path,
or v0.4 metric routing. No package version bump in this PR (bundled
into the rc3 fix train Laughlin is assembling).

**Tests:** 195/195 ARRunnerCore tests still pass. No watchOS unit-test
target so the regression guard is the rationale comment + decision
record. If/when a watch test target lands, the regression case is
`start → confirmCancel → toggle link state on adapter under test →
assert `glassesLinkState` updates`.

**Two things future-Weiss should remember:**

- **Two lifetimes coexist on the workout view-model.** Workout-scoped
  observation tasks (state/metric/elapsed/tick) end at every
  save/discard. Transport-scoped observation tasks
  (connectionStates/statusEvents) live as long as the transport does.
  Any cleanup helper that touches both is a bug waiting to happen.
- **"Disconnect button does nothing" is a UI-observer symptom, not an
  adapter symptom.** The adapter's `disconnect()` transitions state
  synchronously and tears down the CB connection. If you can't see the
  effect, look at the consumer of `transport.connectionStates()`
  before suspecting CoreBluetooth or the adapter.

**Decision filed:** `.squad/decisions/inbox/weiss-rc3-ble-observer-transport-scoped.md`.
**Skill updated:** `activelook-ble-adapter-pitfalls` — new "View-model:
observer tasks are TRANSPORT-scoped, not workout-scoped (rc3)" section.

---
