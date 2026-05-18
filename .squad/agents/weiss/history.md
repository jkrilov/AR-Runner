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
