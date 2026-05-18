# Weiss — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** AR Integration
- **Joined:** 2026-05-14T18:30:31.656Z

## Learnings

(See history-archive.md for learnings from 2026-05-14 through 2026-05-15.)

### 2026-05-16: AR/BLE read-only audit (merged with parallel sonnet-4.6 spawn)

Joe asked for fresh AR/BLE/ActiveLook audit. Earlier sonnet-4.6 spawn
had already landed `.squad/audits/2026-05-16-weiss-ar-ble.md`; per
last-writer-wins directive I rewrote it as a **merged** version keeping
their findings I'd missed (CBCentralManager re-instantiation per
reconnect; RSSI dropped at discovery; CBError raw-code drift) and adding
findings they missed (per-tick HUD silent: `GlassesService` never
instantiated and `updateField` never called from the workout pipeline;
scan-timeout `Task` not retained → stale timers race fresh scans;
`_ = try? sendRaw(...)` on layout re-apply silently swallows write
errors). Top-5 debt now: (1) wire per-tick HUD updates, (2) replace
placeholder `CuratedLayoutCatalog` device IDs, (3) hoist
`CBCentralManager` out of per-attempt construction, (4) throttle/coalesce
`updateField`, (5) cluster the small fixes (scan-timeout task,
controlChar parsing, re-apply error surfacing, RSSI emission).

**Process note for next merge-with-parallel-spawn:** always read the
prior file before writing — `create` refuses to overwrite, and a true
merge is far more valuable than blind last-writer-wins. Cost was one
extra read pass plus one `rm`+`create`.

**Skill candidates:** none — the audit-merge pattern is too situational
to reuse, and the BLE-specific findings are already covered in
`activelook-ble-adapter-pitfalls/SKILL.md`. Will not propose a skill
this pass.

**Decision-worthy?** Items 1 and 2 are arguably product decisions
(when to wire HUD updates; whether to ship placeholder layout IDs to
TestFlight) but they're already implied by D6 / v0.2 scope — no inbox
file. If Joe asks for a v0.3 plan I'll re-evaluate.

### 2026-05-16: AR/BLE Code-Health Audit

**Deliverable:** `.squad/audits/2026-05-16-weiss-ar-ble.md`

**Key findings:**

1. **`CuratedLayoutCatalog` device IDs are placeholders** (`0x01–0x03`). Layout bake step never ran. Any real-hardware test will activate the wrong on-device slot. Must be resolved before shipping to Joe's watch.

2. **`CBCentralManager` re-created on every `beginConnect()`** — including each of up to 30 reconnect attempts. Correct pattern: create CM once in `init`, hold across reconnects, reset only peripheral/characteristic references on drop. This avoids stale CB-queue callbacks and memory churn.

3. **Control characteristic flow-control notifications subscribed but never parsed.** `setNotifyValue(true, for: controlChar)` runs at line 256 of `ActiveLookGlassesAdapter.swift` but `didUpdateValueFor` ignores it (only routes battery). Low risk at 1 Hz; blocking for any higher-rate write path.

4. **RSSI discarded at discovery.** `GlassesStatusEvent.signalQuality` is defined but never emitted. Run-metadata (D9) and a future "weak signal" UX both need this wired up.

5. **`updateFields` not overridden for coalescing.** Default serial impl in Core is fine for current load; document it as a scaling knob before adding bulk write paths.

6. **`write` is `async throws` but calls synchronous `sendRaw` internally.** The `async` provides actor serialization only — no backpressure. Fine today; note before adding any high-rate path.

7. **Privacy / permissions surface is clean.** `NSBluetoothAlwaysUsageDescription` present with specific wording, both BLE background modes declared, no phone-side BT permission (D1-correct), App Group consistent across all 4 targets.

8. **Concurrency is clean.** `@preconcurrency import CoreBluetooth`, Swift 6 language mode, no `StrictConcurrency` upcoming-feature flag, `Coordinator: @unchecked Sendable` with `weak var adapter` — all correct.

9. **Disconnect reason code mapping** (`case 6, 7: .linkLoss; case 10: .peerPoweredOff`) uses raw integers. Should verify against `CBError` cases in Xcode 26 SDK rather than raw codes to guard against OS-version shifts.

### 2026-05-16: P1.2 + P1.4 audit follow-up (HUD wire + ID guard)

Joe spawned me to fix the two AR P1 audit findings on `fix/v02-p1-audit-bugs`. Both landed in two separate commits (`7dd784e` wire, `4f2947b` ID guard) on top of Amber's `9571e23` energy MetricKind commit. All 93 Core tests pass; ARRunnerWatch + ARRunnerPhone builds clean under Xcode 16 / Swift 6.

**P1.2 — dead-code-after-connect pattern.** Classic shape: `GlassesService.update(...)` was implemented and unit-test-exercised in StubGlassesTransportTests but `WorkoutViewModel` only constructed the transport and called `.connect()` — the service itself was never instantiated, so no callsite wired `controller.metrics → updateField`. Wire was a 4-line change in `apply(metric:)` once `GlassesService` was held on the view model. The non-obvious bits: (a) `selectLayout(preset:)` has to happen at the `.connected` state edge in the connection-state task (not in `start()`, because the transport may still be `.scanning`); (b) throttle must be `reset()` on both layout-change AND every (re)connect so the first post-reconnect tick lands immediately for each fieldIndex.

**Rate-limit cadence.** Landed at **1Hz per fieldIndex** (`HUDFieldThrottle.defaultMinimumInterval = 1.0`) — matches the controller's emission rate so no metric is ever dropped under steady-state operation, but a misbehaving emitter or a future ≥5Hz source can't saturate the BLE link. Strict `<` comparison at the boundary (test pins this). Per-field independence means a 4-slot balanced-run burst within the same millisecond all passes on the first tick.

**P1.4 — debug-assert on placeholder IDs.** Tried the "assert inside `CuratedLayoutCatalog.deviceID(for:)`" approach first; backed out because Linux Core tests legitimately exercise the accessor with the placeholder IDs (`ExponentialBackoffTests:24-27`, `RunningHUDPresetTests:82,96,203`). Correct layering: keep the catalog accessor assert-free (pure lookup), expose `placeholderDeviceIDs` + `assertNotPlaceholder()` helpers, and call the assert at the actual wire-write sites in `ActiveLookGlassesAdapter` (`selectLayout`, `updateField`, and the reconnect re-apply at line 291). Release-build fault log via `logger.fault(...)` so a leaked build is at least visible in the side store, never silent UX.

**Test placement note.** Task said "place in the existing watch test target" — there is no watch test target in `project.yml` (only the four app/extension targets). Wrote three Core-side tests instead: throttle behavior (`HUDFieldThrottleTests`), placeholder catalog surface (`CuratedLayoutCatalogPlaceholderTests`), and metric → slot mapping against StubGlassesTransport (`WorkoutMetricFanoutTests`). The fan-out test deliberately reproduces `GlassesService.apply(metric:)`'s mapping rule so a future divergence fails CI loudly with a clear hint to update both.

**Learnings.**
- "Dead code after connect" smells like missing instantiation, not missing implementation — grep for `Service.update`/`adapter.updateField` callsites in the connecting layer before assuming the helper itself is broken.
- 1Hz default + per-key throttle gate that "denies-without-advancing" is the safe shape: a flapping emitter can't push the next-allowed-send point forward past the gate.
- Debug-trap on known-bad lookup *values* belongs at the wire boundary, not in the lookup function — same lookup is exercised by Linux tests with known-bad-on-hardware values that are fine in Core.
- **Cross-agent P1 coordination: Amber → Weiss → Laughlin.** Amber's MetricKind.energy case enabled Weiss to wire the HUD updater and add the `hasLiveHKEnergy` latch in `WorkoutViewModel.apply(metric:)` — a defensive pattern to prevent HK kcal truth from being overwritten by subsequent HR-estimate ticks (HK updates tick asynchronously). Laughlin's HealthKit mapping simply flipped the switch to emit `.energy`. The latch proved a valuable cross-agent coordination point: both Weiss and Laughlin touched `WorkoutViewModel` late-game, but the rebase-before-push discipline ensured no conflicts.

**Skill candidate:** yes — wrote `.squad/skills/dead-code-after-connect/SKILL.md` capturing the "instantiated but unwired" pattern + how to backstop it with a per-key throttle and connected-state guard. Generalises beyond BLE: WCSession, network sockets, any async transport with a `connect()` → `send()` shape.

## 2026-05-17T21:56:30Z — Cross-agent note from Scribe (D-RICHARDS-TF-11 trap)

**From Richards' rc5 diagnostics:** When using `-allowProvisioningUpdates` + manual signing (Xcode CLI), the provisioning profiles minted by the ASC API can only declare capabilities that are already enabled on the App ID itself in developer.apple.com. If your code entitlements declare App Groups but the App ID doesn't have App Groups enabled in the portal, the minted profile won't satisfy Xcode's entitlement checker, and the archive will fail with a "missing capability" error.

**Canonical rule:** "App ID capabilities must mirror entitlements when using -allowProvisioningUpdates + manual signing."

This is portal-side state, not code-fixable, and is a new trap class in SKILL.md. Relevant during any future release campaign / signing fix work.

## 2026-05-18 — rc11 app icon + Info.plist fix

Designed Engo 2-style app icon (sport-wrap sunglasses with cyan AR HUD lens
over a white runner silhouette on navy→blue gradient) as a 1024×1024 SVG at
`Assets/AppIcon/AppIcon-1024.svg`. Rendered to PNG via `qlmanage -t -s 1024`,
then flattened alpha by round-tripping through JPEG with `sips` (App Store
rejects alpha in icons).

Wired into `ARRunnerPhone/Assets.xcassets/AppIcon.appiconset/` using the iOS
14+ single-size universal icon format (1 PNG + Contents.json; Xcode
synthesizes 120×120 / 152×152 / etc. at build time). Added `CFBundleIconName`
and `UISupportedInterfaceOrientations` to `ARRunnerPhone`'s `info.properties`
in `project.yml` — the plist is xcodegen-generated, NOT a hand-edited file at
`ARRunnerPhone/Info.plist`. Confirmed plist output and pbxproj wiring after
`xcodegen generate`.

Closed Apple validation errors 1–4 for rc11. Error 5 (iOS 26 SDK requirement)
is out of scope — blocked on Xcode 26 availability on GitHub-hosted runners.

Pattern worth remembering: on a runner without librsvg/rsvg-convert, the
`qlmanage -t -s N -o DIR FILE.svg` → `sips` flatten pipeline is a zero-deps
SVG→opaque-PNG path on macOS.

## 2026-05-18 — pre-run glasses connect screen (PR #42)

Joe v0.2.0 device-test feedback: app launches but no way to pair Engo 2
before tapping Start Run. Added a watch-side "Connect Glasses" flow on
`feat/watch-glasses-connect`.

**SDK reality check:** ActiveLook still ships no watchOS SDK. The
project's `ActiveLookGlassesAdapter` is a hand-rolled CoreBluetooth
actor, and that's what this PR builds on — no new dependency, no
Info.plist change (`NSBluetoothAlwaysUsageDescription` was already
present from the 2026-05-16 audit pass).

**UX pattern landed:** pre-run status chip + sheet, with the chip
visible ONLY in idle / terminal `launchState`s so it doesn't compete
with live metrics during a run. Sheet has five button states keyed off
`GlassesConnectionState`: Scan & Connect (disconnected) → Cancel
(scanning/connecting/reconnecting w/ ProgressView) → Disconnect
(connected) → Retry (failed, with surfaced typed-error message).

**`WorkoutViewModel` wiring:** added `prepareGlassesIfNeeded()` (lazy
build + attach streams, no scan), `connectGlasses()` (errors caught
into a new `glassesPairingError` observable), `disconnectGlasses()`,
`autoReconnectGlassesOnLaunch()` (only fires if `GlassesPairingPreferences.hasPaired`
to avoid wasting battery on a fresh install). The key change in
`start()` is reusing an existing transport instance instead of always
rebuilding — otherwise a user-pre-paired link would be torn down and
re-scanned the moment they tapped Start.

**Protocol extension trick worth keeping:** added
`var connectedDeviceName: String? { get async }` to
`GlassesFrameTransport` with a default-nil impl in the protocol
extension. Linux stubs and the existing `StubGlassesTransport` callsites
needed no source changes; only the new test exercises the override.
This mirrors how `updateFields` is already done in the same file.

**Process trap encountered:** the working directory is shared with
other parallel Squad agents. Another agent switched branches
mid-session and wiped my uncommitted edits to tracked files (untracked
new files survived). Recovery: re-applied all edits, then committed +
pushed to origin IMMEDIATELY before another switch could happen. Going
forward I'll commit aggressively after every coherent batch of changes
in this kind of shared-cwd setup.

**Scope guards held:** zero touches to in-run display (Laughlin's
`feat/watch-in-run-display-improvements` will rebase cleanly), CI,
HealthKit, or signing. AR HUD rendering itself remains a follow-up.

**Skill candidate:** yes — wrote
`.squad/skills/activelook-bluetooth-pairing/SKILL.md` capturing the
pre-run-vs-in-run state separation, the lazy-transport reuse pattern,
the "auto-reconnect only if user previously paired" UserDefaults gate,
and the `connectedDeviceName` protocol-extension default. The shared-
cwd commit-immediately discipline goes into a separate trap note
because it generalises far beyond BLE.

## 2026-05-18T13:40:57-04:00 — v0.3.0-rc1 glasses "Scanning…" hang: watchOS CB Central restriction (PR #42 fallout)

Joe's on-device test of the pairing screen I shipped in PR #42 hangs
indefinitely on "Scanning…" against a confirmed-on, in-pairing-mode Engo 2.
Diagnosis at `.squad/files/glasses-pairing-diagnosis.md`. Decision proposed
at `.squad/decisions/inbox/weiss-glasses-pairing-architecture-pivot.md`.

**Root cause — new trap class: `watchos-cbcentral-third-party-restriction`.**
`CBCentralManager.scanForPeripherals(withServices:options:)` from a
watchOS target silently no-ops against non-MFi third-party BLE peripherals
like ActiveLook-family glasses. The scan call is accepted without error,
no `didDiscover` ever fires, no diagnostic logging surfaces — the Watch
radio just doesn't surface those devices to third-party apps. Service-UUID
filtering (which the docs require and we already do) doesn't help; this is
a platform allow-list, not a code bug. Documented in Apple Developer Forums
thread/774914 (and sibling thread/746043) with no developer-side fix.

**Verifications that ruled out other causes.** Info.plist key present
(`NSBluetoothAlwaysUsageDescription`, project.yml:76). Background mode
declared (`bluetooth-central`, project.yml:78). No additional Bluetooth
entitlement is required for the Central role (the `com.apple.developer.bluetooth-*`
keys are MFi/L2CAP-only). Service UUID correct
(`0783B03E-8535-B5A0-7140-A304D2495CB7`, round-tripped against
`ActiveLookCommandTests`). Scan waits for `.poweredOn` via
`centralManagerDidUpdateState` — no race. Strong refs held on peripheral
and central — no premature dealloc. Code is textbook; platform is the
problem.

**Resolution path: Path A (phone-side BLE + WCSession state bridge).**
Move `ActiveLookGlassesAdapter` to the phone target (pure CoreBluetooth —
compiles unchanged), put the pairing UI on the phone, give the watch a
read-only status chip + "Pair on iPhone" explainer, extend `WCMessage` with
a `glassesState` case carried on `updateApplicationContext` (latest-wins
across unreachability). HUD frame writes also follow the BLE link onto the
phone as a v0.3 follow-up. Watch-first stance narrows: workouts stay
watch-first, glasses cannot be. Scoped at ~5 files + 1 WCMessage case + ~300
new LOC; no new dependencies; no signing/CI churn (rc14 embed wiring already
correct).

**Process traps re-encountered.**
- Apple's docs site is client-rendered JS (`web_fetch` returns the empty
  shell). Cross-checking via `web_search` against forums/SO is the
  practical fallback for any future "what does Apple say about X" question.
- The concurrent `chore/skip-encryption-compliance-prompt` PR touches
  `project.yml` — Path A's `project.yml` additions are in a different
  section (ARRunnerPhone.info.properties vs. encryption-compliance) so
  merge should be mechanical, but rebase carefully before implementation.

**Scope guard held.** This run was diagnose-only — no code changes, no
tag, no PR. Returned recommendation to Joe via Squad.

**Skill candidate:** yes — `watchos-cbcentral-third-party-restriction`
deserves its own SKILL.md (very different surface from
`activelook-ble-adapter-pitfalls/` and `activelook-bluetooth-pairing/`,
which both assume the central role works at all). Will draft on the way
through Path A implementation rather than as a standalone task.

## 2026-05-18T13:46:44-04:00 — Glasses pairing diagnosis CORRECTED (v2)

Joe pushed back on weiss-4: the official ActiveLook watch app ships and
pairs from watchOS, so "watchOS CBCentralManager can't see non-MFi
peripherals" cannot be the whole story. Joe also set a hard constraint
that the iPhone must NOT be a runtime BLE dependency — workouts happen
watch+glasses only, phone optional.

**Corrected root cause.** Read `ActiveLook/ios-sdk@a39839f`,
`Sources/Classes/Public/ActiveLookSDK.swift`. Line 192 carries a literal
`// Scanning with services list not working` comment, followed by
`scanForPeripherals(withServices: nil, options:
[CBCentralManagerScanOptionAllowDuplicatesKey: false])`. They filter
peripherals inside `didDiscover` (line 549) via
`peripheralIsActiveLookGlasses(...)` (line 383) which inspects
`kCBAdvDataManufacturerData` for the Microoled company-ID prefix
`0xFA 0xDA`. Our PR #42 scan filters with the ActiveLook command-service
UUID `0783B03E-…`, which the glasses don't include in advertising data
(it lives on the GATT table post-connect). Service-UUID filters match
the advertising packet, so `didDiscover` is never called. **Same code
would fail on iOS too**, not a platform restriction.

**Known-device fast path** also discovered in the SDK: line 368 uses
`retrievePeripherals(withIdentifiers:[gUUID])`, line 395 uses
`retrieveConnectedPeripherals(withServices:[GAS, DIS, Battery])`. Persist
the peripheral UUID on first pair, skip scanning entirely on subsequent
launches — `connect(peripheral)` directly. This is the right reconnect
path for both v0.3 and any future phone-assisted handoff (Pattern Y).

**Pivot recommendation withdrawn.** Pattern X (watch-direct, scan-nil +
manufacturer-data filter + retrievePeripherals on reconnect) satisfies
Joe's runtime-independence constraint, matches ActiveLook's own
implementation, and is a ~10-30 line fix to `ActiveLookGlassesAdapter`
plus a UserDefaults slot for the paired UUID. D-WEISS-WC-1 (watch-first)
is **reinforced**, not narrowed.

Rewrote `.squad/files/glasses-pairing-diagnosis.md` end to end (kept the
filename so backlinks work). Wrote v2 decision at
`.squad/decisions/inbox/weiss-glasses-pairing-architecture-pivot-v2.md`.
v1 is explicitly retracted. The `watchos-cbcentral-third-party-restriction`
skill draft mentioned in weiss-4 should NOT be authored — the restriction
as I framed it doesn't exist.

**Lessons (the real ones this time).**
- **Validate "platform limitation" against shipping counter-examples
  BEFORE recommending architectural pivots.** A vendor shipping a watch
  app is strong prima facie evidence the platform supports the use case.
  Apple Developer Forum threads describe failure modes; they don't bound
  the platform's capabilities. I cited thread/774914 as if it justified
  ignoring the existence of the ActiveLook watch app. It didn't.
- **Read the reference SDK source FIRST.** A 30-second `grep
  scanForPeripherals ActiveLook/ios-sdk` would have flipped the diagnosis
  immediately. I skipped that step and went straight to architecture
  pivot. Cost: one wasted diagnosis pass plus Joe having to push back.
- **`scanForPeripherals(withServices:)` matches the ADVERTISING packet,
  not the GATT table.** Vendor peripherals that hide their primary service
  behind connect-then-discover require manufacturer-data filtering
  (`kCBAdvDataManufacturerData`). This is general BLE knowledge I should
  have applied unprompted.
- **`retrievePeripherals(withIdentifiers:)` + `connect(peripheral)`
  bypasses scan entirely.** This is the runtime path for any
  previously-paired peripheral on any Apple platform — fewer moving
  parts, no scan-time filter risk, and works identically on iOS / iPadOS /
  watchOS / macOS.

**Skill update plan:** roll the manufacturer-data filter + known-peripheral
reconnect into `.squad/skills/activelook-bluetooth-pairing/SKILL.md`
during PR #43. Do NOT publish the
`watchos-cbcentral-third-party-restriction` draft. Add a separate trap
note under "Diagnosis hygiene: validate platform limits against shipping
counter-examples before recommending pivots" — generalises beyond BLE.

---

## 2026-05-18 — PR #45 landed the watch-direct glasses scan fix (Pattern X)

Joe approved Pattern X from the v2 decision. Implementation was as scoped
in the corrected diagnosis — ~140 LoC net change, watch-only.

### What I actually shipped

1. **Pure helper in Core**:
   `ARRunnerCore/Sources/ARRunnerCore/Glasses/GlassesAdvertisementFilter.swift`
   exposes `isActiveLookPeripheral(manufacturerData: Data?) -> Bool`.
   8 XCTest cases in `Tests/ARRunnerCoreTests/Glasses/`. Lives in Core
   specifically so Linux CI exercises it without `import CoreBluetooth`.

2. **Adapter scan call** (`ActiveLookGlassesAdapter.swift`):
   - `scanForPeripherals(withServices: nil,
     options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])`.
   - `handleDiscovered` now takes `manufacturerData: Data?` (not the raw
     `[String: Any]` dictionary) — the coordinator extracts
     `advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data`
     on the CB delegate queue so we only ship a Sendable `Data?` across
     the actor boundary. Avoids a Swift 6 strict-concurrency warning.
   - Rejected peripherals logged at INFO under category `Glasses`,
     subsystem `com.arrunner.watch`; accepted peripherals logged too.

3. **Known-peripheral persistence** (`GlassesPairingPreferences.swift`):
   - New `pairedPeripheralID: UUID?` slot, key
     `glasses.lastKnownPeripheralIdentifier`, stored as a UUID string.
   - `clear()` now removes both `pairedKey` and the peripheral ID.

4. **Fast-reconnect path** in `handleCentralStateUpdate`:
   - On `.poweredOn`, `tryRetrieveKnownPeripheral()` runs FIRST.
   - If `prefs.pairedPeripheralID` is set AND
     `central.retrievePeripherals(withIdentifiers: [saved])` returns
     non-empty, we wire up the peripheral and call `connect()` directly
     — no scan.
   - 8-second safety timeout (new `knownPeripheralConnectTimeout`
     parameter, defaulted) cancels the attempt and falls back to the
     manufacturer-data scan path if the system never produces a
     `didConnect`. WARN-level log on fallback.
   - On `didConnect`, the `fastReconnectAttempted` flag is cleared so
     the safety timeout becomes a no-op.

5. **Persist on connect success**: in `handleCharacteristicsDiscovered`,
   once `rxCharacteristic` is in hand we write
   `prefs.pairedPeripheralID = peripheral.identifier` before resuming
   the pending connect continuation. INFO log of the persisted UUID.

### Patterns I want to remember

**Manufacturer-data filter — 0xFA 0xDA, little-endian.** Microoled's
Bluetooth SIG company identifier is `0xDAFA`; the wire/CoreBluetooth
representation is little-endian so it appears as bytes
`[0xFA, 0xDA, …]`. ActiveLook's iOS SDK
(`Sources/Classes/Public/ActiveLookSDK.swift:383-388`) is the canonical
reference. The byte-swapped variant `[0xDA, 0xFA]` is the easy mistake
— I added an explicit negative test for it.

**Index manufacturer data from `data.startIndex`, not literal 0.** A
`Data` slice (e.g. `backing.suffix(from: 2)`) preserves the parent's
indices, so `manufacturerData[0]` would either crash or return wrong
bytes. The helper always uses
`manufacturerData[manufacturerData.startIndex + i]`. Test
`test_isActiveLookPeripheral_respectsNonZeroStartIndex` guards against
regressing this.

**Known-peripheral retrieve pattern.**
`retrievePeripherals(withIdentifiers:)` returns `[]` on cache eviction
(post-reboot, long idle) — treat that as "fall back to scan", NOT as
an error. Even when retrieve returns a peripheral, the subsequent
`connect()` may never produce a callback (glasses off / out of range);
always pair the call with a safety timeout (I picked 8 s). The 15 s
scan timeout safety net in the scan path is untouched.

**Hoist non-Sendable extraction onto the CB queue.** When the actor
needs only a small piece of the `advertisementData: [String: Any]`
dictionary, pull it out inside the `Coordinator` delegate method (which
runs on the CB queue) and ship only the Sendable extract into the
`Task { await actor… }`. Cleaner than `@preconcurrency`-ing the whole
dictionary across the boundary.

### Verification

- ARRunnerCore: `swift test` — 121 tests, 1 skipped, 0 failures (8 new
  filter cases all pass).
- ARRunnerWatch: `xcodebuild -scheme ARRunnerWatch
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build`
  — succeeds, zero warnings/errors traceable to this change.
- Real-device validation still pending Joe's bench session.

### Skill update

Appended a "CoreBluetooth scan filter — the trap that broke PR #42"
section and a "Fast reconnect — never scan twice for the same glasses"
section to `.squad/skills/activelook-bluetooth-pairing/SKILL.md`. The
`watchos-cbcentral-third-party-restriction` skill draft remains
un-authored — the restriction as v1 described it doesn't exist.

### Lessons (compounded with the v2 retraction)

1. **A 30-second `grep scanForPeripherals` on the vendor SDK** would
   have flipped my v1 diagnosis before it ever made it to a decision
   inbox. Read the reference implementation FIRST when diagnosing
   third-party-device integration bugs.
2. **`scanForPeripherals(withServices:)` filters the advertising
   packet, not the GATT table.** Vendor peripherals very often expose
   their command service on GATT but only broadcast a manufacturer-data
   payload. Don't assume "service is in the GATT table → can scan-
   filter by it."
3. **Persisting `peripheral.identifier` + `retrievePeripherals` is the
   standard fast-reconnect pattern on every Apple platform.** Whenever
   we add new BLE peripheral integrations, build this in from day one
   — it's cheap and removes the scan-time race entirely on subsequent
   launches.

### 2026-05-18: PR #49 — v0.3.0 AR HUD MVP (raw txt rendering)

Joe's rc2 bench test: pairing works (PR #45), but "Start a run" leaves
the glasses frozen on the "Connection Successful" splash. Diagnosed in
30 s by re-reading `ReconnectPolicy.swift` — the on-connect path called
`selectLayout(preset: .default)` which resolves to placeholder slot
0x02. No such layout is baked onto the Engo 2 yet
(Config-Generator still deferred), so every subsequent `updateField`
wrote into a layout that doesn't exist. `assertNotPlaceholder` did its
job in debug — but Joe was on a release build, which just logs a fault
and continues silently. The HUD was always going to look broken until
either the bake step ships OR we render without depending on it.

Picked the latter for v1 per Joe's spec: render time/distance/pace via
ActiveLook's raw `txt` command (cmdID 0x37 — draw text at absolute
(x, y)). Works on any stock Engo 2 with zero on-device config.

**What shipped:**

1. `ActiveLookCommand.text(x:y:rotation:fontSize:color:string:)` —
   x/y are i16 big-endian, defaults match ActiveLook iOS sample
   (rotation=4 bottom-RL, font=3 largest stock, color=15 full white).
2. `RunningHUDFrame` pure builder — `[clear, txt(time), txt(distance),
   txt(pace)]` at y=40/120/200, x=20 on the 304×256 panel. Reuses
   Laughlin's `RunMetricFormatting` so the wrist and the HUD share one
   source of truth.
3. `RunningHUDPushPolicy` — 1Hz minimum + change-detection.
4. `GlassesFrameTransport.sendCommands([[UInt8]])` with default no-op;
   adapter writes each frame via `sendRaw`; stub records into
   `receivedHUDFrameBatches`.
5. `WorkoutViewModel`: per-tick push from the existing 1Hz
   `tickElapsed`, initial frame on start + on glasses (re)connect,
   "Workout Complete" splash on save. Killed the
   `selectLayout(preset: .default)` call on `.connected`.
6. `ActiveLookGlassesAdapter.init(defaultPreset:)` default changed to
   `nil` and the pre-seed gated on
   `!placeholderDeviceIDs.contains(id)` so re-connect doesn't trip
   `assertNotPlaceholder`.

The v0.2 curated-layout pipeline (`HUDLayout`, `HUDFieldUpdate`,
`GlassesService.apply(metric:)`, `HUDFieldThrottle`) is **dormant,
not deleted**. The moment Config-Generator output replaces the
placeholder slot IDs, callers pass `defaultPreset: .default` again
and the per-tick field-update path comes back online alongside the
raw HUD. Raw HUD = "works on any stock device"; curated HUD = "richer
post-bake experience".

**Tests:** 19 new pure-function tests in `ARRunnerCoreTests/Glasses/
RunningHUDFrameTests.swift` (`swift test` → 140 passing, was 121).
Covers: encoder wire-format (incl. negative y two's-complement),
payload formatter wiring, distance < 0.01 mi → pace placeholder, the
4-frame `[clear, txt, txt, txt]` sequence, txt-payload geometry on
Engo 2, summary-frame banner, push-policy 1Hz gate + change detection
+ reset semantics. CI on PR #49: all three build/test jobs green;
squash-merged as `5849343`. Real-device validation queued.

**Patterns I want to remember:**

* **Default-no-op protocol extension for transport capabilities.** Same
  trick as `connectedDeviceName` in PR #42 — adding `sendCommands` to
  `GlassesFrameTransport` with a default no-op meant zero churn at
  every test stub / preview site; only the platform adapter and the
  one test stub that wanted to record needed to override. Strict
  Swift 6 stayed quiet.

* **Pure builder in Core + side-effect push at the watch boundary.** The
  raw HUD `[UInt8]` frames are generated in ARRunnerCore (Linux-CI-
  buildable, fully unit-tested) and only the BLE write lives in the
  watch target. Same separation as PR #42's
  `GlassesAdvertisementFilter` — pays for itself in test coverage every
  time.

* **Send-on-1Hz-elapsed-ticker, not on every metric change.** The
  workout pipeline emits metrics at variable cadence (HK statistics
  callbacks can fire faster than the wall clock). Hanging the HUD push
  off `tickElapsed` (already 1Hz) means the throttle is mostly a
  belt-and-braces guard; the elapsed ticker is the natural rate-
  limiter. Bonus: time / distance / pace all update together in a
  single frame, so the wearer never sees a stale time next to a fresh
  distance.

* **`Payload` struct, not three loose `String`s, for change detection.**
  Made the policy a single `==` and means future fields (HR, splits)
  can extend without re-shaping every call site.

**Lessons:**

1. **A debug `assert` is not a release safety net.** P1.4's
   `assertNotPlaceholder` was right to add, but it's silent in release
   — exactly when it matters most. For "this should never reach
   production hardware" cases, pair the assert with a behavioural
   guard (here: refuse to pre-seed a placeholder ID in the first
   place) so the bug can't manifest even if the assert is compiled out.

2. **Always have a path that doesn't depend on a deferred build step.**
   The curated-layout pipeline was correct architecture but
   blocked on Config-Generator. A "works on any stock device" fallback
   (raw `txt`) costs ~150 LOC and unblocks every bench session until
   the proper bake step lands. Build the fallback first, then layer
   the optimisation on top.

3. **Re-read the audit before you debug.** I literally wrote
   "placeholder layout IDs → silent on hardware" as P1.4 of the
   2026-05-16 audit. Reading my own audit before chasing Joe's
   symptom would have saved 10 minutes of confused
   `central?.scanForPeripherals` re-skimming.

### 2026-05-18: PR #53 — rc4 HUD regression (blank screen on connect, no draws during run)

Joe installed v0.3.0-rc4 (build 19, PR #49 HUD MVP) on real Engo 2
hardware. Three symptoms: connect works (PR #45 holding), but the
glasses go **blank** on connect (was "Connection Successful" pre-#49),
and the HUD never renders during a workout — stays blank end-to-end.

**Root cause:** Engo 2 firmware paints "Connection Successful" as part
of the BLE link-up handshake, but the **display itself is in a low-
power state** until the host sends `power(on:true)` (cmdID 0x00) at
least once. Subsequent `txt` draws are silently dropped. PR #49 began
clearing the splash via `clear()` on connect / workout start, but
never sent `power(on:true)` first — so `clear` worked (operates on
the display buffer regardless of power state) and the splash visibly
disappeared, but every `txt` after that was a no-op. Pre-#49 builds
*looked* fine only because they never cleared the splash, so the
firmware text remained visible by default; #49 unmasked the missing
power-on by removing the splash without replacing it.

**Fix shipped (PR #53):**
- `RunningHUDFrame.connectFrames(banner:)` — `[power on, clear,
  txt("AR-Runner Ready"), txt("Start a run")]`. Painted on every
  `.connected` edge so the wearer sees pairing succeeded.
- `RunningHUDFrame.framesWithPowerOn(for:)` /
  `summaryFramesWithPowerOn(for:)` — prepend `power(on:true)` to
  existing per-tick / end-of-workout frames.
- `WorkoutViewModel.needsHUDPowerOn: Bool` — per-BLE-connection flag.
  Set true on every `.disconnected/.reconnecting/.failed` edge.
  Cleared by either the connect-screen push or the first per-tick
  HUD frame after a (re)connect. Subsequent ticks use plain frames
  to keep BLE writes minimal.
- On `.connected` edge: push `connectFrames` first; if a workout is
  already running, follow up with the live HUD so we don't sit on
  the splash.

**Tests:** ARRunnerCore 140 → 145 passing. Five new tests pin the
power-on byte sequence, the banner string placement, the prepend
contract, and the throttle init (first send at t=0 must pass
immediately — guards a hypothetical `lastSentAt = now` regression
that would delay the first frame by 1s).

**Patterns I want to remember:**

* **For a peripheral with a "display power" concept, send `power(on:
  true)` once per BLE connection BEFORE the first draw.** Track it
  with a `needsPowerOn` flag that resets on every disconnect edge.
  Belt-and-braces: prepend it to the first per-tick frame too, so
  even if the on-connect path skipped it (race / failure), the
  workout still renders.
* **A firmware splash is not the same as a host-driven render.** If
  the user can see *something* before our first command lands, that
  thing is being painted by firmware bypassing the host display-
  power state. Don't infer "display is on" from "I can see text".
* **`clear` operates on the buffer; `txt` requires the display to be
  powered on.** This is the asymmetry that masked the bug — `clear`
  worked, `txt` didn't, so the screen went blank rather than
  staying-splash or rendering. Any time a peripheral has a clear-vs-
  draw asymmetry, the first symptom of a power/init bug is a clean
  blank screen, not a garbled one.

**Lessons:**

1. **"Works on any stock device today" must include the device's
   own power-on handshake.** PR #49's raw-`txt` path was supposed
   to bypass the curated-layout dependency — and it did — but it
   inherited a different deferred dependency: the assumption that
   the display was already on. The skill (`activelook-hud-rendering`)
   captured the layout-bake-step trap; it did NOT capture the
   display-power trap. Updated to medium confidence with that
   caveat now.
2. **A skill at "high" confidence after the first bench validation
   is premature.** PR #49's skill was high-confidence after CI but
   before real-hardware proof. The rc4 regression is exactly the
   class of bug a CI green can't catch. Demote new skills to medium
   until two consecutive bench sessions pass.
3. **When the symptom is "screen went from showing-X to blank", the
   cause is almost always a clear/erase command landing without a
   matching draw/render path.** Next time, my first hypothesis
   should be the matching-side missing render, not the rendering
   code itself.
4. **Add a watch-side test target for `WorkoutViewModel`.** The
   on-connect-produces-non-empty-write and first-frame-fires-
   immediately invariants are currently covered only indirectly via
   Core pure-function tests. Flagged as a follow-up — when it lands,
   we can assert the full byte sequence the VM hands to
   `transport.sendCommands(...)` end-to-end.
