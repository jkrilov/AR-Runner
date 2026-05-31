---
updated_at: 2026-05-31T00:00:00Z
focus_area: v0.5.20 shipped to TestFlight (build 50). Release-monotonicity guard validated end-to-end on the tag-push path. Awaiting Joe's decision on second 0.5.x fix and on-device smoke for build 50.
active_issues:
  - v0.5.20 build 50 processing/processed on TestFlight (run 26511705252 green 2026-05-27). Awaiting Joe's on-device smoke confirmation.
  - "Second 0.5.x fix" hinted by Joe before workstation switch — name + scope still TBD when Joe resumes.
  - Issue #80 (App Attest) remains the only other open issue in the tracker.
---

# What We're Focused On

**Immediate (2026-05-31):** v0.5.20 is on TestFlight. Two ships completed in
quick succession this past week:

- **v0.5.19 (PR #116, `25ee63a`)** — Watch discard dialog text fix. Old v0.2-era
  copy at `ARRunnerWatch/Views/WorkoutView.swift:117` was telling users their
  run would be saved when discard already correctly dropped the HKWorkout
  (rc2 terminal-path fix had been correct since 2026-05-20). One-line dialog
  copy update; comment cleanup on `WorkoutViewModel.swift:41-44`.

- **v0.5.20 (PR #117, `13c8f7a`)** — Release-monotonicity guard fix. The
  `release-testflight.yml` guard had two bugs: (1) self-collision when the
  push that triggered the workflow was itself the new tag, and (2)
  semver-incorrect ordering via `sort -V` (pre-release vs release). Fix:
  inline `semver_gt()` bash function (SemVer 2.0 correct) + 11-assertion
  self-test step that runs BEFORE the real guard + trigger-tag exclusion on
  `push: tags` events. **First v0.5.x release in project history to traverse
  `git tag && git push` cleanly** (run 26511705252 green in 3m45s).

**Skill captured:** `.squad/skills/release-monotonicity/SKILL.md` — medium
confidence after a single real-world smoke. Promote to high after the next
pre-release reconfirms.

## Standing Directives (Layer 0)

- **All code-editing agents must run Opus 4.7 or better** (Joe, 2026-05-26).
  `.squad/config.json` pins laughlin / weiss / amber / richards to
  `claude-opus-4.7-1m-internal`. Every spawn of those agents MUST use that
  model. See `.squad/decisions.md` for the full directive entry.

## Open Threads for Next Session

1. **Second 0.5.x fix.** Joe said "I have a couple fixes in mind" at session
   start but only named the discard-dialog one before switching workstations.
   When Joe resumes, ask what the second item is.
2. **v0.5.20 build 50 on-device smoke.** TestFlight build was green ~4 days
   ago. Joe to confirm the watch-side discard flow + general regression
   sanity once he installs it.
3. **Issue #80 (App Attest).** Still the only other open tracker item.
   No active work assigned.

## Release Mechanics Reminder

- Branch protection blocks direct push to `main`. All commits go via PR.
- Token must carry `workflow` scope to push files under `.github/workflows/`.
  `gh auth refresh -h github.com -s workflow` fixes it for both `git push`
  and `gh`.
- `project.yml` `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` bump ships
  with the work, not in a separate PR.
- `VERSION` file mirrors marketing version; tooling reads it.

**Updated:** 2026-05-31 by Scribe-equivalent housekeeping pass (coordinator
direct mode) post-v0.5.20 ship, prior to Joe's workstation switch.
