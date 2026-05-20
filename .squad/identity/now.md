---
updated_at: 2026-05-19T22:25:00Z
focus_area: rc17/v0.4.0-rc1 on TestFlight; awaiting Joe's bench confirmation. Killian starting docs cleanup pass on non-rc17 files. ADR-1 (BLE-link lifecycle) now canonical contract.
active_issues:
  - rc17 release: v0.4.0-rc1 merged, TestFlight upload queued, 186/186 tests passing
  - Joe bench validation: real hardware testing in progress (TestFlight notification sent)
  - Amber QA: 28 acceptance scenarios (§A–E) ready for formal validation
  - Killian docs: README + comment cleanup pass on non-rc17 files (needs v0.4.0 context from history.md)
---

# What We're Focused On

**Immediate (2026-05-19T22:25Z):** rc17/v0.4.0-rc1 shipped to TestFlight. Joe's bench validation now running in parallel with Apple's TestFlight processing. Team monitoring for early crash reports. Killian beginning docs cleanup pass (non-rc17 files).

**rc17 Delivered:**
- **ADR-1 (canonical contract):** BLE link is user-managed, not workout-scoped. Workout-stop does NOT disconnect glasses. Phone-optional invariants formalized.
- **Lifecycle fix:** `confirmSave`/`confirmCancel` keep link up, finish frame persists, user reads finish screen at own pace.
- **Finish-screen precision:** Y anchors recomputed under rc16 lens-flip formula (y_fb = 255 − wearer_top). Symmetric layout, fully on-panel, pinned by tests.
- **Battery → phone:** Glasses battery (0x180F/0x2A19) subscribed per-link, routed to iPhone via WatchConnectivity (queued, phone-optional).
- **Auto-reconnect + filter:** Unbounded reconnect attempts at 1/2/4/8/16/32/60 s schedule. `BatteryLevelFilter` drops >100 bytes, suppresses dupes, resets on disconnect.
- **Release mechanics:** MARKETING_VERSION 0.3.0→0.4.0, tag v0.4.0-rc1, TestFlight upload automatic (Joe's directive 2026-05-19T18:23).

**Test Status:** 186/186 Core pass (baseline 176 at rc16; +10 for filter/backoff/schema, +2 for finish-screen Y pins). Build: ARRunnerWatch SUCCEEDED.

**Next (parallel tracks):**
1. **Joe:** Bench-validates on real hardware. TestFlight link is the start signal. Hotfix rc-bumps (rc18, rc19) if needed.
2. **Amber:** Runs full QA suite (28 scenarios §A–E) as rc17 merges. Battery, reconnect, phone-optional contracts validated.
3. **Killian:** Docs cleanup pass. History append with v0.4.0 context provided (2026-05-19T22:25 Scribe update).
4. **Team:** Monitor GitHub for bench feedback. Coordinate hotfixes if early crashes detected.

**Decisions Merged (2026-05-19T22:25Z):**
- `richards-adr-ble-link-lifecycle` (ADR-1, canonical BLE-link contract)
- `weiss-rc17-ble-lifecycle-and-battery` (adapter impl + tests)
- `laughlin-rc17-lifecycle-finish-battery` (watchOS impl + release bump)
- `amber-rc17-qa-scenarios` (28 acceptance criteria + failure diagnostics)
- `copilot-directive-2026-05-19T18-20-phone-optional` (reaffirmed constraint)
- `copilot-directive-2026-05-19T18-23-auto-release` (working as intended)

**New Skills:**
- `paired-hardware-lifecycle-contract` (generalizes BLE-lifecycle pattern)
- `phone-optional-companion-qa` (QA framework for phone-optional features)

**Updated Skills:**
- `activelook-ble-adapter-pitfalls` (per-link subscription, filter-reset patterns)
- `release-mechanics-bundle-bump` (MARKETING_VERSION rollover + auto-release-notes)

**Updated:** 2026-05-19T22:25:00Z by Scribe (rc17 orchestration session)
