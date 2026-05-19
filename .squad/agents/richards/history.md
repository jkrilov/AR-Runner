# Richards — History (Summarized 2026-05-19)

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead / Architect
- **Joined:** 2026-05-14T18:30:31.650Z

## Session 2026-05-18: Release v0.3.0-rc6 (BLE Fix)

**BLE Write Serialization Root Cause (PR #55):** rc5 failed with blank HUD. Root cause: ActiveLook protocol requires two serialization layers: (1) write-response gating per `didWriteValueFor`, (2) flow-control subscription gate (`GlassesInitializer.isReady()` confirms `flowControlCharacteristic.isNotifying == true`). Our adapter violated both, firing 4 frames back-to-back into an unprepared peripheral.

**Fix:** Gate `.connected` on flow-control notify confirmation (2s timeout), replace fire-and-forget with `CheckedContinuation`-based `write()` awaiting didWriteValueFor, add os_log.

**Key learning:** "Write returned" ≠ "peripheral processed command." Read vendor SDK's write-path BEFORE building your own. ATT `.withResponse` is necessary but not sufficient.

**Result:** 145 tests passing; PR #55 merged into rc6.

---

## Earlier Sessions — Archive Summary

**rc1–rc15:** TestFlight platform engineering (signing identity, App ID capabilities, provisioning profiles, export signing). Comprehensive SKILL at `.squad/skills/ios-testflight-ci-via-actions/SKILL.md`.

**rc12–rc16:** Bundled-bump release pattern validated (5 releases, feature + version + xcodegen in single PR, no follow-up bump).

**rc13–rc16 Architecture Review:**
- **Lens-flip formula canonicalized:** `y_fb = 255 − wearer_top` (empirically pinned by Joe's rc16 bench evidence)
- **Tech debt accruing:** Layout enum god-bag (25+ constants), font metrics hardcoded in prose (needs ALookFontMetrics helper)
- **Solid patterns:** Per-link BLE subscription gating, preloaded ALooK assets over custom upload, 4-field live HUD + 2-field finish HUD
- **Open recommendations:** #1 geometry helper, #2 font metrics table, #5 finish-screen Y recompute (→ rc17)

---

## 2026-05-19: ADR — BLE Link Lifecycle (User-Managed, Not Workout-Scoped)

**Trigger:** Joe's rc16 bench report: connection drops on workout-stop, finish screen never lands, manual re-pair required. Confirmed NOT a regression — that was always the contract. rc17's confirmSave/confirmCancel already comply (no teardownTransport), but contract was undocumented.

**What I wrote:** `.squad/decisions/inbox/richards-adr-ble-link-lifecycle.md` — full ADR with:
- **4 invariants (I1–I4):** Link persists, finish frame persists until user action, subscriptions per-link, phone never precondition
- **5 tear-down rules (R1–R5):** confirmSave/confirmCancel MUST NOT disconnect, only two legal paths
- **5 reconnect-policy clauses (P1–P5):** Unbounded attempts, 1/2/5/15/30/60 s backoff, adaptive throttle
- **4 subscription rules (S1–S4):** Per-link, survive workout boundaries, battery 0x2A19 on every .connected
- **3 phone-optional clauses (PO1–PO3):** Battery authoritative on watch, opportunistic mirror on phone, phone offline = no watch impact

**Architectural insight:** "peripheral session ⊥ application session" — they observe each other but neither owns the other's lifecycle. Once workout-finish drives peripheral teardown, you've created coupling that breaks finish-HUD, battery telemetry, post-workout review. The fix is declaring orthogonality as a contract.

**Heuristic:** If tear-down lives in application shutdown path, ask "who else needs this resource after this event?" If anyone, the resource is mis-scoped. Promote to user-managed.

**Promoted to skill:** `.squad/skills/paired-hardware-lifecycle-contract/SKILL.md` (generalizes for any paired BLE/USB/HID device).

**Implications:**
- Weiss: audit adapter disconnect() sites, implement P1–P5 backoff, subscriptions idempotent, battery 0x2A19 on-connect
- Laughlin: add regression test asserting disconnect() NOT called in confirmSave/confirmCancel
- Amber: battery-on-phone is WatchConnectivityService mirror, never critical path

**Status:** Scribe merged ADR to decisions.md 2026-05-19T22:25Z. rc17 implementation (Laughlin + Weiss + Amber) validated compliant. Canonical contract now in place for v0.4+.

---

## Key Learnings Retained

1. **Peripheral lifecycle is a first-class design concern.** Treat it as orthogonal to application lifecycle; never gate on transient events.
2. **Coordinate systems need canonical transforms, not derived recipes.** The lens-flip formula `y_fb = 255 − wearer_top` is now authoritative; any new screen must validate against it.
3. **Preloaded peripheral assets >> custom upload pipelines.** Check vendor asset catalog before invoking upload machinery.
4. **Bundled-bump pattern cuts release cycle in half.** Feature + version + xcodegen + tag + TestFlight in single PR; now team standard.
5. **BLE protocol layering matters.** ATT response gating is necessary but not sufficient; peripherals have application-layer flow control above it.
