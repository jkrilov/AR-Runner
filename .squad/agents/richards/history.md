# Richards — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead
- **Joined:** 2026-05-14T18:30:31.650Z

## Active Learnings

### 2026-05-16: Architecture & Best-Practices Audit (read-only)

Delivered `.squad/audits/2026-05-16-richards-architecture.md`. Parallel-run with Laughlin and Weiss on their domains.

**Top 3 findings:**
1. **`.github/copilot-instructions.md:5` is grossly stale** — declares repo "greenfield, no source code yet" while ~30 production files + 16 test files exist. Every new agent's first-read mental model is wrong. Highest-leverage, lowest-effort fix.
2. **Toolchain pins ~12 months stale** — Xcode 16.4 / Swift 6.0 / macos-15. Xcode 17 + Swift 6.2 are GA. No CVE pressure yet but every month makes catch-up costlier. Recommend probe-PR bump in next 30 days.
3. **`ActiveLookGlassesAdapterHardwareTests.swift` lives inside the production app target** behind `#if AR_RUNNER_HARDWARE_TESTS`. Compile-guarded so safe, but XCTest shipping in app source is a smell — will trip App Store static analysis eventually. Move to dedicated test target in `project.yml`.

**ADR drift caught:**
- **D8** technically only sanctions `@preconcurrency import` for the ActiveLook *vendor SDK*; we're using it for *CoreBluetooth* (system framework) at `ActiveLookGlassesAdapter.swift:5`. Justified (CB delegates aren't `Sendable`) but D8 wording should be amended. Filed as decision-inbox candidate? — minor enough to fold into a later D8 revision rather than a standalone inbox drop.

**Layering verdict:** ✅ ARRunnerCore is genuinely platform-pure (Foundation-only across 22 source files); Linux CI enforces it for free; ADR-001/D1/D2/D4 all hold.

**CodeQL coverage gap:** only `ARRunnerWatch` is built for analysis; Phone target's WCSession + UI unscanned. Cheap to fix.

**No code changes made** (read-only audit per task scope).

### 2026-05-16: Gitignored xcconfig + configFiles reference requires bootstrap in ALL xcodegen workflows

**Pattern:** When `project.yml` references a gitignored xcconfig via `configFiles` (e.g., `Config/Signing.xcconfig`), `xcodegen generate` exits 1 with "Invalid config file" if that file is absent — regardless of whether the consuming build uses `CODE_SIGNING_ALLOWED=NO`. xcodegen validates file existence at parse time, before any xcodebuild flags are considered.

**Rule (durable):** Every workflow that calls `xcodegen generate` must call `scripts/bootstrap-signing.sh` first — not just the release workflow. The script is idempotent: called with no `APPLE_TEAM_ID`, it creates a placeholder xcconfig with `DEVELOPMENT_TEAM =` (empty). For no-signing CI builds, the empty team ID is harmless.

**PR #21 incident:** `release-testflight.yml` bootstrapped correctly (needed real team ID from secrets). `ci-build.yml` and `codeql.yml` did not. All 4 macOS matrix builds + CodeQL went red. Linux `swift test` was unaffected (never calls xcodegen). Fixed in commit d8339d0 — added `Bootstrap signing xcconfig` step before `xcodegen generate` in both workflows.

**Checklist:** When adding a new workflow that calls `xcodegen generate`:
- Does `project.yml` have any `configFiles` references pointing to gitignored files?
- If yes → add `Bootstrap signing xcconfig` step before `xcodegen generate`

**References:** Decision inbox: `richards-pr21-ci-fix.md`; Skill: `.squad/skills/ios-testflight-ci-via-actions/SKILL.md`

### 2026-05-15: pbxproj target-membership "bug" was actually stale-generated-project (XcodeGen)

**Reported symptom:** `Cannot find 'GlassesTransportFactory' in scope` at `ARRunnerWatch/Views/WorkoutView.swift:11`. Coordinator diagnosed it as PR #9 having missed `GlassesTransportFactory.swift` and `ActiveLookGlassesAdapterHardwareTests.swift` from `AR-Runner.xcodeproj/project.pbxproj` target membership.

**Actual root cause:** This repo uses **XcodeGen**. `AR-Runner.xcodeproj/` is gitignored (see `.gitignore`: `*.xcodeproj/`), regenerated from `project.yml`. The Watch target's `sources: [path: ARRunnerWatch]` is **recursive** — every `.swift` under that tree is auto-included. Both "missing" files exist on disk and appear immediately after `xcodegen generate`. Joe's local pbxproj was simply stale (generated before PR #9 landed those files).

**Unblock for Joe:** `xcodegen generate` from repo root; re-open Xcode.

**Recurring failure-mode pattern (durable learning):**
- Symptom: "Cannot find X in scope" for a Swift type whose file demonstrably exists.
- Diagnosis trap: looks identical to a missed Xcode-target-membership bug (the classic Apple-developer footgun in hand-managed `.xcodeproj` files). In a hand-edited project, it would be — and the suggested fix (add to PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase) is correct.
- In **this** repo, it's never that. pbxproj is generated. The fix is always `xcodegen generate`.
- The generated-project/hand-edited-project distinction needs to be the **first** question whenever an Xcode target-membership bug is suspected. `git check-ignore AR-Runner.xcodeproj/project.pbxproj` answers it in one shot.

**Artifacts produced:**
- New skill: `.squad/skills/xcodegen-stale-generated-project/SKILL.md` — failure mode + 30-second triage.
- Decision inbox: `.squad/decisions/inbox/richards-pbxproj-target-membership-checklist.md` — proposes triage-first rule for any "missing symbol / target membership" report.

**No code/pbxproj edits made.** pbxproj is gitignored — committing it would create a stale snapshot that fights XcodeGen on every regen.

### 2026-05-17 — First real TestFlight run: archive failed on automatic signing identity

Joe tagged `v0.2.0-rc1` (commit `da7f129`); the release-testflight workflow I authored in PR #21 ran for the first time against real secrets and failed at the `Archive (xcodebuild)` step.

**Symptom (run 25989849479):**
```
error: Communication with Apple failed: Your team has no devices from which to
       generate a provisioning profile. (in target 'ARRunnerPhone')
error: No profiles for 'com.arrunner.phone' were found: Xcode couldn't find any
       iOS App Development provisioning profiles matching 'com.arrunner.phone'.
```

The keychain step had already logged `1 valid identities found — Apple Distribution: JOSEPH LOUIS KRILOV (***)` — so the cert was correct. The `-configuration Release` flag was being honored. Yet Xcode was asking for an **iOS App Development** profile.

**Root cause:** Xcode 16 quirk. With `CODE_SIGN_STYLE=Automatic` invoked from CLI via `xcodebuild ... archive` (not Xcode.app's GUI Product → Archive), automatic signing honors the build setting `CODE_SIGN_IDENTITY` literally. xcodegen-generated projects don't set this, so it defaults to Xcode's project template default of `"Apple Development"`. `-allowProvisioningUpdates` then dutifully tries to mint a *development* profile — which requires the team to have registered devices. CI runners don't, so it fails with the misleading "no devices" message.

This is a known foot-gun documented in many Stack Overflow threads but I missed it when authoring PR #21. My TestFlight setup doc anticipated several portal/secret failure modes but not this build-setting one.

**Fix (PR `fix/v02-rc1-archive-failure`):** explicit override on the archive command:
```bash
xcodebuild ... archive \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  "CODE_SIGN_IDENTITY[sdk=iphoneos*]=Apple Distribution" \
  ...
```
Both forms are needed — the bare `CODE_SIGN_IDENTITY` covers the generic case; the sdk-scoped one wins on iOS device builds when both are present in build settings.

**Decision implication (deferred to inbox):** should PR CI probe-build the Release configuration with signing disabled to catch Release-only build errors before they manifest as broken TestFlight runs? (Current ci-build.yml only builds Debug for simulator. Release config is *almost* the same code but optimizations differ, and warnings-as-errors flips behavior under `-O`.) See `decisions/inbox/richards-first-tf-run-postmortem.md`.

**Doc fix:** `docs/dev/testflight-setup.md` troubleshooting table previously misdiagnosed `No profiles ... were found` as "first-run timing, just re-run". That row is now split: the "no devices" variant points at the CODE_SIGN_IDENTITY override; the bare variant keeps the re-run advice.

**Skill update:** `.squad/skills/ios-testflight-ci-via-actions/SKILL.md` — added the failure pattern + fix to the trap list. Confidence stays Medium until rc2 actually uploads green; that's the empirical proof, not my reasoning about it.

## Archive

See `history-archive.md` for learnings from 2026-05-14 and early 2026-05-15 (GitHub remote setup, CI/simulator architecture, Swift 6 toolchain, system architecture ADRs, parallel workstream coordination, XcodeGen stale-project incident).

