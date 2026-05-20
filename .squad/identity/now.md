---
updated_at: 2026-05-20T13:22:00Z
focus_area: v0.4.0-rc1 live on TestFlight. Docs cleanup landed (PR #78). Team idle — awaiting Joe's bench feedback or next direction. ADR-1 (BLE-link lifecycle) and Killian's swift-comment-hygiene-checklist now canonical.
active_issues:
  - v0.4.0-rc1 live: Shipped to TestFlight (commit c58d575), docs cleanup merged (PR #78, commit ffa3af8)
  - Joe bench validation: real hardware testing in progress with rc1 build
  - Team idle: Awaiting Joe's feedback on bench run. Hotfix rc-bumps (rc18+) only if early crashes detected.
---

# What We're Focused On

**Immediate (2026-05-20T13:22Z):** v0.4.0-rc1 live on TestFlight. Docs cleanup landed (PR #78, all CI green). Joe bench-validating on real hardware. Team monitoring GitHub for feedback. Idle until Joe confirms rc1 fitness or requests next direction.

**rc1 Delivered (2026-05-19T22:25Z, now live 2026-05-20T13:22Z):**
- **ADR-1 (canonical contract):** BLE link is user-managed, not workout-scoped. Workout-stop does NOT disconnect glasses. Phone-optional invariants formalized.
- **Lifecycle fix:** `confirmSave`/`confirmCancel` keep link up, finish frame persists, user reads finish screen at own pace.
- **Finish-screen precision:** Y anchors recomputed under rc16 lens-flip formula (y_fb = 255 − wearer_top). Symmetric layout, fully on-panel, pinned by tests.
- **Battery → phone:** Glasses battery (0x180F/0x2A19) subscribed per-link, routed to iPhone via WatchConnectivity (queued, phone-optional).
- **Auto-reconnect + filter:** Unbounded reconnect attempts at 1/2/4/8/16/32/60 s schedule. `BatteryLevelFilter` drops >100 bytes, suppresses dupes, resets on disconnect.
- **Release mechanics:** MARKETING_VERSION 0.3.0→0.4.0, tag v0.4.0-rc1, TestFlight active (commit c58d575).
- **Docs cleanup:** PR #78 merged (Killian swift-comment-hygiene pass, all CI green, no functional change).

**Test Status:** 186/186 Core pass (validated on rc1 + docs-only merge).

**Current Activity (2026-05-20T13:22Z):**
1. **Joe:** Bench-validating rc1 on real hardware (start signal = TestFlight notification sent). In-progress.
2. **Team:** Idle, monitoring for bench feedback. Hotfix rc-bumps (rc18, rc19) only if early crashes detected.

**Canonical Artifacts:**
- ADR-1 (BLE-link lifecycle contract)
- Killian's `swift-comment-hygiene-checklist` (docs standards)

**Skills Locked:**
- `paired-hardware-lifecycle-contract` (generalizes BLE-lifecycle pattern)
- `phone-optional-companion-qa` (QA framework for phone-optional features)

**Updated:** 2026-05-20T13:22:00Z by Scribe (post-PR#78-merge session)
