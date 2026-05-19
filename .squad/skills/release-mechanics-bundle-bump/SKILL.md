# Skill: Release Mechanics — Bundle Version Bump Into Feature PR

**Confidence:** Low (first-iteration pattern, effective from rc12+)  
**Owner:** Laughlin (watchOS Release Lead), coordinated by Scribe  
**Date of origin:** 2026-05-19T15:05:00Z (Joe Krilov directive)

## Pattern

Effective **rc12 onwards**, the `CURRENT_PROJECT_VERSION` bump in `project.yml` + xcodegen regeneration MUST be included in the SAME PR as the feature/fix work.

### Old Pattern (rc11 and earlier) — DEPRECATED

```
feature PR → merge → bump PR → merge → tag
```

Cost: 2 PRs, 2 CI cycles, 1 extra merge round per release.

### New Pattern (rc12+) — ACTIVE

```
feature PR (with version bump committed inside) → merge → tag
```

Cost: 1 PR, 1 CI cycle, saves ~1–2 hours per release.

## Procedural Checklist

When shipping a feature or fix PR that will be released as an RC:

1. **Edit `project.yml`** (at repo root)
   - Increment `CURRENT_PROJECT_VERSION` (numeric, no quotes)
   - Example: from 26 to 27
   - Do NOT touch `MARKETING_VERSION`

2. **Run `xcodegen generate`**
   - Regenerates Xcode project from the YAML spec
   - Command: `xcodegen generate`
   - Must run this BEFORE committing (CI does it again, but you need to verify the delta)

3. **Verify `Info.plist` integrity**
   - After xcodegen, open `Info.plist` (or `grep` for placeholders)
   - Confirm that placeholder values like `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)` are PRESERVED (not expanded)
   - These placeholders are filled by CI at build time; expanding them breaks the release workflow
   - Example valid line: `<string>$(MARKETING_VERSION)</string>` (NOT `<string>0.3.0</string>`)

4. **Commit project changes**
   - Commit `project.yml` + `project.pbxproj` + any `xcconfig` changes TOGETHER with your code changes
   - Single commit message, e.g.: `feat: add HR display + bump build 26→27`
   - This commit is part of your feature PR, not a separate PR

5. **Verify PR CI gates pass**
   - Standard 3 required GitHub Actions jobs
   - CodeQL (or skip per Joe's standing directive)
   - No new friction vs. pre-bump workflow

6. **After merge, do NOT open a separate bump PR**
   - Old pattern required a follow-up PR to bump and merge before tagging; that's gone
   - Tag immediately after your feature PR merges
   - Release-testflight.yml will pick up the new CURRENT_PROJECT_VERSION from main

## Gotchas

- **xcodegen must be run locally before commit.** If you skip it or run it after commit, the `.pbxproj` won't match the `project.yml`, and CI may regenerate it with a different delta than you tested.
- **Info.plist placeholders MUST NOT be expanded.** Test: `grep '$(CURRENT_PROJECT_VERSION)' ARRunner/Info.plist` should return the literal string with `$()`, not a number.
- **CURRENT_PROJECT_VERSION is numeric, MARKETING_VERSION is semantic.** Bump CURRENT (build number), never touch MARKETING (semver stays 0.3.0 or 0.4.0 for the whole rc family).
- **All three files in one commit.** If you commit project.yml and then pbxproj in a separate commit within the same PR, the histories diverge and make it hard to bisect later.

## Example Workflow

```bash
# 1. Make your feature changes (e.g., add HR display)
# ... edit ActiveLookHUDFrame.swift, RunningHUDAdapter.swift, etc.

# 2. Edit project.yml
sed -i '' 's/CURRENT_PROJECT_VERSION = 26/CURRENT_PROJECT_VERSION = 27/' project.yml

# 3. Run xcodegen
xcodegen generate

# 4. Verify placeholders
grep '$(CURRENT_PROJECT_VERSION)' ARRunner/Info.plist
# Expected output: <string>$(CURRENT_PROJECT_VERSION)</string>

# 5. Stage and commit
git add project.yml ARRunner/Info.plist ARRunner.xcodeproj/project.pbxproj ActiveLookHUDFrame.swift RunningHUDAdapter.swift ...
git commit -m "feat: add HR display + bump build 26→27"

# 6. Push to PR branch
git push origin feat/add-hr-display

# 7. After PR merges, tag from main
git tag -a v0.3.0-rc12 -m "..."
git push origin v0.3.0-rc12
```

## Release Roadmap Impact

- **rc12** (first release using bundled pattern): HealthKit HR display (Feature A + Suggestion 1 battery)
- **rc13+** (if cadence continues): Finish screen, HR zones, gesture controls — each a separate PR with bundled version bump
- **rc17 / v0.4.0-rc1** (first MARKETING_VERSION rollover under bundled pattern): BLE keep-alive past workout-end + finish-screen Y revalidation + glasses battery → phone WC.
- Estimated time savings: ~2–3 hours per release (1 fewer CI cycle + 1 fewer merge round + less coordinator coordination overhead)

## Lessons Learned

- rc11 was the last release using the 2-PR pattern to demonstrate its inefficiency and document the new pattern.
- Joe explicitly measured the overhead and authorized the directive to save iteration cycles.
- If a feature PR fails CI or review, you DO NOT increment the version — revert and resubmit (no partial-bump commits).
- **rc17 (v0.4.0-rc1) MARKETING_VERSION rollover.** When the rc family rolls (0.3.x → 0.4.0), `MARKETING_VERSION` bumps in the SAME commit as `CURRENT_PROJECT_VERSION` (e.g., 31→32 AND 0.3.0→0.4.0 together). The next tag resets the rc counter — `v0.4.0-rc1`, not a continued `rc17`. xcodegen typically produces NO `.pbxproj` delta on either bump because the build settings are sourced from xcconfig placeholders; verify with `git status AR-Runner.xcodeproj/` after `xcodegen generate` to confirm — a non-empty delta there means a setting was hard-coded somewhere it shouldn't be (audit `project.yml` for stray `MARKETING_VERSION` literals).
- **Auto-release directive (2026-05-19).** Joe authorized tag + TestFlight upload to proceed automatically as soon as the merged-to-main PR's CI is green — no wait for bench-test verdict. Bench failures become hotfix rc bumps, not pre-release blockers. The merging agent reports "PR merged, CI green," coordinator proceeds straight to tag.
