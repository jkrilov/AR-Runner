---
updated_at: 2026-05-14T21:12:00Z
focus_area: PR #2 merged. PR #3 CI re-running after StrictConcurrency fix. Once green and merged, Weiss + Laughlin start v0.1 BLE wrapper + WorkoutController.
active_issues:
  - chore/ci-workflows (PR #3, CI re-running post StrictConcurrency fix)
  - BLE wrapper implementation (Weiss, ready post-PR #3 merge)
  - WorkoutController implementation (Laughlin, ready post-PR #3 merge)
---

# What We're Focused On

**Immediate:** PR #3 (chore/ci-workflows) CI re-running after Richards' StrictConcurrency redundant-flag fix (commit 350eae0). Once green and merged, Weiss and Laughlin begin v0.1 feature implementation.

**All three CI workflows now active:**

- **Linux core-tests:** ARRunnerCore platform-agnosticism (no Apple frameworks in Core)
- **macOS xcodebuild:** 4-target matrix (Watch, Phone, WidgetsPhone, WidgetsWatch)
- **CodeQL security:** Swift analysis with security-extended queries

**Key lesson from PR #3 CI run:** Local Swift 6.3.2 silently accepts `.enableUpcomingFeature("StrictConcurrency")` flags that CI Swift 6.0 rejects as hard errors. When importing Apple/vendor samples (especially ActiveLook), strip explicit strict-concurrency flags — treat CI as the authoritative compiler.

**Updated:** 2026-05-14T21:12:00Z by Scribe (session orchestration)
