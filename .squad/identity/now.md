---
updated_at: 2026-05-14T21:00:00Z
focus_area: v0.1 implementation — BLE wrapper (Weiss) + WorkoutController (Laughlin) starting after PR #2 (macos-build-validation) and PR #3 (ci-workflows) merge. CI now enforces ARRunnerCore Linux-compat as architectural guard.
active_issues:
  - chore/macos-build-validation (PR #2, waiting for Joe's manual filing)
  - chore/ci-workflows (PR #3, waiting for Joe's manual filing; blocks feature branch validation)
  - BLE wrapper implementation (Weiss, ready to start post-PR #3)
  - WorkoutController implementation (Laughlin, ready to start post-PR #3)
---

# What We're Focused On

**Immediate:** BLE wrapper implementation (Weiss) and WorkoutController scaffolding (Laughlin) begin post-PR #3 (ci-workflows) merge. All three feature branches (PRs #2, #3, and upcoming BLE/WorkoutController) queued for Joe's manual filing. CI now validates:

- **Linux core-tests:** ARRunnerCore platform-agnosticism (no Apple frameworks in Core)
- **macOS xcodebuild:** 4-target matrix (Watch, Phone, WidgetsPhone, WidgetsWatch)
- **CodeQL security:** Swift analysis with security-extended queries

Weiss and Laughlin: Write tests that pass on Linux. Don't import Apple frameworks into ARRunnerCore. Use `@preconcurrency import` for vendor SDKs in app/watch targets.

**Updated:** 2026-05-14T21:00:00Z by Scribe (session orchestration)
