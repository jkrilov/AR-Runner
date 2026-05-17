# Richards — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead
- **Joined:** 2026-05-14T18:30:31.650Z

## Active Learnings

### 2026-05-17 — rc4 archive trap: CLI archive + Automatic style → Apple Development identity → xcconfig Distribution pin is treated as conflicting manual override; project.yml `CODE_SIGN_STYLE: Automatic` also shadows xcconfig style at project-base precedence

**Context:** PR #25 (rc3 fix) successfully removed `CODE_SIGN_STYLE` from the xcodebuild CLI. v0.2.0-rc4 was tagged from main. Run [26003539754](https://github.com/jkrilov/AR-Runner/actions/runs/26003539754) failed the Archive step with TWO errors, one per iOS target:

> `ARRunnerPhone has conflicting provisioning settings. ARRunnerPhone is automatically signed for development, but a conflicting code signing identity Apple Distribution has been manually specified.`
>
> `ARRunnerWidgetsPhone has conflicting provisioning settings. ARRunnerWidgetsPhone is automatically signed for development, but a conflicting code signing identity Apple Distribution has been manually specified.`

CLI was clean (rc3 fix held). Both targets carried the conflict — not just the widget. The pre-work hypothesis ("xcconfig identity + automatic style is fundamentally OK at project-config level") was wrong. Two compounding precedence bugs surfaced:

**Bug A — CLI `xcodebuild archive` + `CODE_SIGN_STYLE=Automatic` always resolves to `Apple Development` identity.** Xcode.app's GUI archive action auto-promotes automatic signing to Distribution because it knows the action's intent. The CLI does not. With Automatic style on the CLI, Xcode resolves identity = `Apple Development` and treats the xcconfig's `Apple Distribution` pin as a conflicting manual override. No amount of xcconfig-level pinning fixes this — it's a CLI archive limitation.

**Bug B — xcodegen bakes `CODE_SIGN_STYLE = Automatic` into the project-level pbxproj** when `project.yml settings.base.CODE_SIGN_STYLE: Automatic` is set. Project-level pbxproj has **higher precedence than xcconfig** in Xcode's settings hierarchy. So even appending `CODE_SIGN_STYLE = Manual` to xcconfig is silently ignored until the project-base pin is removed. Verified empirically: `xcodebuild -showBuildSettings` returned `CODE_SIGN_STYLE = Automatic` even with `Manual` written into xcconfig — until I removed the project-base pin, after which Manual resolved correctly.

**Per-target widget gotcha confirmed but re-explained:** rc4 hitting both targets isn't because the widget needs its own `$(inherited)` injection — the widget doesn't get xcodegen's iPhone-Developer target-level inject (that's an iOS application-target-only behavior, per rc3 learning). The widget fails for the same root reason as the main app: project-wide xcconfig identity + project-base Automatic style → conflict on every signed target. The fix at the project-base + xcconfig layer covers both targets in one shot.

**Resolution (PR #26 forthcoming, branch `fix/v02-rc4-signing-pathway`):**

Two coordinated layer changes:

1. **`project.yml`** — `settings.base.CODE_SIGN_STYLE: Automatic` → `CODE_SIGN_STYLE: $(inherited)`. xcodegen now writes `CODE_SIGN_STYLE = "$(inherited)"` to project-level pbxproj, deferring to xcconfig. Local dev still resolves to Automatic because `bootstrap-signing.sh` writes `CODE_SIGN_STYLE = Automatic` to xcconfig.
2. **`release-testflight.yml`** — xcconfig append changed from identity-only to:
   ```
   CODE_SIGN_STYLE = Manual
   CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution
   CODE_SIGN_IDENTITY[sdk=watchos*] = Apple Distribution
   ```
   Manual signing makes the archive intent explicit; `-allowProvisioningUpdates` + ASC API key fetches/creates the App Store distribution profile for each bundle ID on demand.

**Strategy:** Option A (Manual signing for the archive). Rejected Option B (try harder with Automatic — three iterations of evidence say it can't work for CLI archive), Option C (hybrid `[config=Release]` conditional — doesn't address the identity-default root cause), Option D (Manual + explicit `PROVISIONING_PROFILE_SPECIFIER` per target — reserved as a fallback if rc5 fails; specifier coupling is fragile).

**Trade-off named:** Distribution profiles must be creatable for both bundle IDs via the ASC API key. Joe's key has Admin scope, so this is automatic on first archive. If the key is ever scoped down to read-only, we'd add explicit specifiers — at which point we revisit.

**Local dev verified intact:** `xcodebuild -showBuildSettings -configuration Debug` for all four targets resolves to `Automatic` + `Apple Development` after the project.yml change. Personal Team device debugging keeps working — the project.yml change is `$(inherited)`, not `Manual`, so local xcconfig (`Automatic`) wins for non-CI scenarios.

**Durable rules added to skill:**

- Never pin `CODE_SIGN_STYLE` at `project.yml settings.base` if you want xcconfig to drive style — xcodegen bakes it into project-level pbxproj at higher precedence than xcconfig. Use `$(inherited)` if you need an entry there at all.
- For CLI `xcodebuild archive` to App Store: **use Manual signing with Apple Distribution identity, both set in xcconfig.** Automatic signing for CLI archive is a four-iteration trap (rc1 → rc4); Manual is one line of xcconfig and works on the first try.
- Symptom "automatically signed for development, but a conflicting code signing identity Apple Distribution has been manually specified" on **every** signed target → check both layers: project.yml CODE_SIGN_STYLE pin (remove if present) AND xcconfig style (must be Manual, not Automatic).

**Artifacts:**
- PR (forthcoming): `fix/v02-rc4-signing-pathway`.
- Skill update: new rc4 CRITICAL TRAP section + incident log row + updated Open Question. Confidence bumped to **High** (four independent rc burns, all on the same signing-pathway pattern, all fixed by Manual-in-xcconfig).
- Doc update: `docs/dev/testflight-setup.md` Architecture summary now says "manual" not "automatic"; troubleshooting table replaces rc3 row with rc4-final row that names both layers.
- Decision inbox: `richards-tf-rc4-signing-pathway.md` (D-RICHARDS-TF-10) — supersedes D-RICHARDS-TF-9 in part. Re-amplifies D-RICHARDS-TF-8 (PR-time Release-config probe) for the fourth time.

**Meta-observation (fourth iteration):** Every rc fix to date has been reasoned correctly *for the failure mode visible at the time*, and validated only by tag-and-pray. The real validation surface is `xcodebuild -showBuildSettings -configuration Release -sdk iphoneos | grep CODE_SIGN`, which I now run locally before every signing-related PR. Adding this assertion to PR CI (D-RICHARDS-TF-8) would catch the precedence regression class at PR time instead of burning rc tags. Four signal points in two days is well past anecdote; this should ship.

### 2026-05-17: rc2 archive trap — xcodebuild CLI mis-parses `SETTING[sdk=...]=value`, and CLI-set `CODE_SIGN_IDENTITY` conflicts with `CODE_SIGN_STYLE=Automatic`

**Context:** PR #23 pinned `CODE_SIGN_IDENTITY="Apple Distribution"` plus `"CODE_SIGN_IDENTITY[sdk=iphoneos*]=Apple Distribution"` on the xcodebuild archive command line, fixing rc1's "no devices" error in principle. rc2 (run 25990326363) failed differently:

```
Build settings from command line:
    CODE_SIGN_IDENTITY = iphoneos*]=Apple Distribution
...
error: ARRunnerWidgetsPhone has conflicting provisioning settings.
ARRunnerWidgetsPhone is automatically signed, but code signing identity
iphoneos*]=Apple Distribution has been manually specified.
```

**Two compounding bugs:**

1. **xcodebuild's command-line setting parser does not support `SETTING[sdk=...]=value` conditional syntax.** That syntax is xcconfig-only (and Build Settings editor). On the CLI, xcodebuild silently mis-parses `CODE_SIGN_IDENTITY[sdk=iphoneos*]=Apple Distribution` into setting name = `CODE_SIGN_IDENTITY` (somehow stripping the `[sdk=` prefix) and value = literally `iphoneos*]=Apple Distribution`. The bare `CODE_SIGN_IDENTITY="Apple Distribution"` that preceded it gets overwritten. No warning. No diagnostic.
2. **CLI-set `CODE_SIGN_IDENTITY` + `CODE_SIGN_STYLE=Automatic` is treated as a "conflicting provisioning setting"** by Xcode 16, per target. Even if (1) hadn't garbled the value, the bare pin alone would have failed every signed target with the same error. The pin works fine when set in the project / xcconfig — but on the CLI it's always rejected as a manual override.

**Resolution (PR #24, branch `fix/v02-rc2-archive-failure`):**

Removed both `CODE_SIGN_IDENTITY` args from the `xcodebuild ... archive` invocation in `release-testflight.yml`. Instead, after `bootstrap-signing.sh` runs (which writes `Config/Signing.xcconfig` with `DEVELOPMENT_TEAM` + `CODE_SIGN_STYLE=Automatic`), the workflow appends:

```
CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution
CODE_SIGN_IDENTITY[sdk=watchos*] = Apple Distribution
```

xcconfig accepts the conditional syntax. Project-level xcconfig values are treated as project config, not manual overrides, so the "conflicting provisioning settings" check passes. Scoped by sdk so simulator builds and local Personal-Team device debugging (which uses `Apple Development`) are unaffected — the bootstrap script itself does NOT write these lines; only the release workflow appends them.

**Why this slipped past rc1's fix (meta-observation):**

rc1's PR (#23) was reasoned through correctly: project default of `Apple Development` → needs to be `Apple Distribution` for archive → pin it on the CLI. But the fix was *only validated by reasoning*, not by an actual archive build, because the release workflow only fires on tag push and tag push is "the test". There is no Release-config probe build in PR CI. We're now two-for-two on first-real-archive-run learnings (rc1: wrong identity inherited; rc2: right identity, wrong place to set it). Decision inbox entry `richards-rc2-postmortem.md` proposes a Release-config archive smoke step in PR CI — second data point for the same recommendation already filed at rc1.

**Durable rules added to skill:**

- Never set `CODE_SIGN_IDENTITY` on the xcodebuild command line with `CODE_SIGN_STYLE=Automatic` — always go through xcconfig.
- `SETTING[sdk=...]=value` conditional syntax is xcconfig-only. xcodebuild's CLI parser will silently mis-parse it.

**Artifacts:**
- PR #24 (branch `fix/v02-rc2-archive-failure`).
- Skill update: new "⚠️ CRITICAL TRAP: xcodebuild CLI doesn't parse `SETTING[sdk=...]=value`" section + new incident-log row. Confidence bumped Medium → Medium-High.
- Doc update: `docs/dev/testflight-setup.md` troubleshooting table — refined the "no devices" row to reference the xcconfig fix and added a new row for the "conflicting provisioning settings" symptom.
- Decision inbox: `richards-rc2-postmortem.md` re-amplifying the Release-config probe-build proposal.

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

### 2026-05-17: v0.2.0-rc3 signing fix — CLI CODE_SIGN_STYLE shadow effect

**Root cause (rc3, run 25991312727):** `CODE_SIGN_STYLE=Automatic` on the `xcodebuild archive` CLI has highest precedence. This made Xcode treat the xcconfig's `CODE_SIGN_IDENTITY=Apple Distribution` (project-config level) as a "conflicting manual override" on extension targets (ARRunnerWidgetsPhone), and the main target (ARRunnerPhone) fell through to the Development-profile pathway ("no devices" error).

**Fix:** Removed `CODE_SIGN_STYLE=Automatic` from the archive CLI entirely. Both CODE_SIGN_STYLE and CODE_SIGN_IDENTITY now live exclusively in Config/Signing.xcconfig at the same precedence level. Xcode treats them as consistent project configuration. Also discovered xcodegen injects `CODE_SIGN_IDENTITY = "iPhone Developer"` at the **target level** for iOS app targets, overriding the project-level xcconfig — fixed by setting `CODE_SIGN_IDENTITY: $(inherited)` in project.yml for ARRunnerPhone.

**Durable learning — three rc failures confirm one rule:** Never put `CODE_SIGN_STYLE` or `CODE_SIGN_IDENTITY` on the xcodebuild CLI for archive. xcconfig is the only safe location. The CLI's highest-precedence semantics create unavoidable conflicts with project-level signing configuration. Specifically:
- rc1: missing identity → Development default → "no devices"
- rc2: CLI `[sdk=...]` mis-parsed by xcodebuild CLI parser
- rc3: CLI CODE_SIGN_STYLE at override level → xcconfig identity treated as conflict

**Key file paths:** `.github/workflows/release-testflight.yml` (archive step), `scripts/bootstrap-signing.sh` (base xcconfig), `Config/Signing.xcconfig` (gitignored, written at CI time), `project.yml` (configFiles reference).

**Decision:** D-RICHARDS-TF-9 (proposed, `.squad/decisions/inbox/richards-tf-rc3-signing-fix.md`).
**Skill updated:** `.squad/skills/ios-testflight-ci-via-actions/SKILL.md` — new trap section, incident log, confidence bump.

## Archive

See `history-archive.md` for learnings from 2026-05-14 and early 2026-05-15 (GitHub remote setup, CI/simulator architecture, Swift 6 toolchain, system architecture ADRs, parallel workstream coordination, XcodeGen stale-project incident).

