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
