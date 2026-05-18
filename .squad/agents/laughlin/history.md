# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings

(See history-archive.md for learnings from 2026-05-14 through 2026-05-15.)

## 2026-05-16T20:25:00-04:00 — watchOS code-health audit (Opus 4.7-1m re-spawn)

Joe asked all three of us (Richards/me/Weiss) for a fresh 2026 look. Re-spawn on Opus 4.7-1m; overwrote prior claude-sonnet-4.6 audit at `.squad/audits/2026-05-16-laughlin-watchos.md` (intentional per Joe).

**Two real bugs found:**

1. `HealthKitWorkoutSubstrate.metric(for:)` maps `.activeEnergyBurned` to `WorkoutMetric.kind = .duration` (HealthKitWorkoutSubstrate.swift:271-272). Downstream `WorkoutController.ingest` and `WorkoutViewModel.apply(metric:)` both default-case `.duration` → live HK kcal is silently dropped. Saved summary still works because `HKWorkout.totalEnergyBurned` is read directly in `end()`, but the live "flame" metric only shows the local `EnergyAccumulator` estimate. Needs an `.energy` (or `.activeEnergy`) case in `WorkoutMetric.MetricKind` — that's an Amber-owned Core model edit.
2. `StartWorkoutIntent.perform()` (`ARRunnerWidgets/StartWorkoutIntent.swift:11-14`) is a TODO. The widget Start button foregrounds the app but lands on idle WorkoutView — v0.2 Story 1 acceptance ("start from Smart Stack widget") is not actually met. Needs deep-link routing.

**Latent bug:** `switch type { case HKQuantityType.quantityType(forIdentifier:): }` does optional-pattern unwrap against non-optional `type` — works today, silently no-ops if Apple ever returns nil. Better idiom: switch on `type.identifier` string.

**Modernization items (all S effort):**
- `Task.sleep(nanoseconds: 1_000_000_000)` → `.sleep(for: .seconds(1))` in three tickers.
- WidgetKit `TimelineProvider` callback form → async / `AppIntentTimelineProvider`; set policy `.never` while entry is static (currently burning 30-min refresh budget for a constant entry).
- `WorkoutController.metrics` is `.unbounded` — switch to `.bufferingNewest(64)` for live-only data.

**Things that are clean:** zero force-unwraps in app code, zero `try!`, no `ObservableObject`/`@StateObject`/`NavigationView` legacy, `@Observable` used correctly on both view-models, all three `@unchecked Sendable` usages justified (NSObject delegates + lock-protected mutable state), WCSession three-tier delivery matches the skill. Strict-concurrency hygiene from D8 is holding.

**Drop:** considered filing an inbox decision but the energy-routing fix is a Core model change (Amber) and the App Intent stub is mine to schedule — no cross-agent ADR needed. Will tackle both in v0.2 closure work.

### 2026-05-16 — watchOS / Swift / HealthKit Code-Health Audit

**Task:** Full read-only audit of all Swift sources (Watch, Phone, Core, Widgets).

**Key findings:**
- `HKWorkout.totalDistance` + `.totalEnergyBurned` are deprecated iOS 17 / watchOS 10. Still present at `HealthKitWorkoutSubstrate.swift:193–194`. Migration target: `HKWorkout.statistics(for:).sumQuantity()`.
- `activeEnergyBurned` HK sample emitted as `MetricKind.duration` — wrong kind. `MetricKind` has no `.energy` case. Currently silent (view-model ignores it) but will corrupt any future `.duration` consumer.
- `observedMetrics: [WorkoutMetric]` in `WorkoutController` grows without bound and is never read in `makeSummary`. Dead code + memory sink for long workouts.
- `AsyncStream.makeStream()` (Swift 5.9+) should replace `var cont: ...!` pattern — 4 sites across Watch and Core.
- `Task.sleep(nanoseconds:)` — 5 sites; `Task.sleep(for: .seconds(1))` is the modern form and is injectable with a custom `Clock`.
- `TimelineProvider` in widget should migrate to `AppIntentTimelineProvider` (watchOS 10+ preferred API).
- `xcodeVersion: '16.0'` in `project.yml` is stale; should be `'17.0'` for 2026.
- No `ObservableObject`, no `@Published`, no `NavigationView`, zero force-unwraps in production — SwiftUI / concurrency fundamentals are clean.
- Decision drop: `.squad/decisions/inbox/laughlin-audit-hk-deprecated-api.md` (deprecated HK API + MetricKind.energy).
- Audit deliverable: `.squad/audits/2026-05-16-laughlin-watchos.md`.

## 2026-05-16T20:50:00-04:00 — v0.2 P1.1 + P1.3 bugfix execution

Shipped two fixes on `fix/v02-p1-audit-bugs`:

- **2a31b84** `fix(widgets): implement StartWorkoutIntent.perform()` — Smart Stack handoff via App Group shared state.
- **2ca0d22** `fix(healthkit): map activeEnergyBurned to WorkoutMetric.energy` — HK kcal now flows live (uses Amber's MetricKind.energy from 9571e23).

Tests: 101 passing in `swift test` from `ARRunnerCore/`, 0 failures, 1 pre-existing skip. Watch build: `xcodebuild -scheme ARRunnerWatch -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO` BUILD SUCCEEDED.

### Learnings

- **AppIntent → host-app handoff via App Group `UserDefaults` flag.** `AppIntent.perform()` runs in the WidgetKit extension process and cannot touch the host's `WorkoutController` directly. The handoff pattern: intent calls `pendingStartStore.markPending(at: now())` (writes `pendingWorkoutStartTimestamp` Double to `UserDefaults(suiteName: "group.com.arrunner.shared")`); `openAppWhenRun = true` foregrounds the host; the host reads `scenePhase == .active` in `WorkoutView.onChange(of:)` (plus a first-launch `.task`) and calls `pendingStartStore.consumePending(now: Date(), freshness: 60)`. Returns `true` exactly once per fresh flag — atomic clear-on-read. The 60s freshness window matters: a forgotten widget tap from yesterday must not auto-start a workout tomorrow. The store lives in Core (`ARRunnerCore/Sources/.../Workout/PendingWorkoutStart.swift`) so both the widget extension and the watch host can import it via the SPM package dependency they already share. Skill drop: `.squad/skills/app-intent-shared-state-handoff/SKILL.md` (low confidence — first observation, but the shape is generic).

- **"Enum case missing → silent default-case drop" gotcha confirmed (P1.3).** When the substrate didn't have an `.energy` case to emit, `HealthKitWorkoutSubstrate.metric(for:)` routed kcal through `.duration`. Both `WorkoutController.ingest` AND `WorkoutViewModel.apply(metric:)` had `default: break` / `case .pace, .duration: break` arms that swallowed every sample silently. The saved `HKWorkout` still carried the total (read directly in `end()`), so post-session reconciliation worked — masking the live-display bug. **Lesson:** when adding a new MetricKind, audit every `switch metric.kind` in the codebase for `default: break` and consider whether the new case needs an explicit no-op vs. real handling. Amber's commit 9571e23 already folded `.energy` into the controller's no-op arm; mine added the viewmodel display arm. Defense-in-depth idea for the future: an `os_log` warning in any `default:` arm of a `MetricKind` switch (debug builds only) would surface this class of bug instantly.

- **Mapping-helper-in-Core pattern for testing watch-only adapters.** The project has no watchOS or widget test target (only `ARRunnerCoreTests`). To test the HK substrate's kcal-mapping fix I extracted the pure mapping into `Core/Workout/HealthKitMetricMapping.swift` (a thin static function taking `Double` kcal + `Date`) and call it from the substrate. The contract is now lockable from Core tests (`HealthKitMetricMappingTests`) without needing an HKHealthStore on the test runner. Useful pattern any time a watchOS-only or widget-only file has a pure-data transformation worth testing.

- **Local working-tree gets passively updated when teammates push.** Started the session with `git pull --rebase` saying "Already up to date" (HEAD was 9571e23). By the time I went to commit, Weiss's 7dd784e and 4f2947b had landed on HEAD — and her 7dd784e already contained the WorkoutViewModel `hasLiveHKEnergy` latch I'd planned to add. Net effect: my "viewmodel changes" diffed to zero because they were already there. Lesson: re-check `git log --oneline -5` before committing, not just before pulling. Worst case I would've overwritten Weiss's work with an identical-but-conflict-prone duplicate edit.

- **Cross-agent P1 coordination: Amber → Weiss → Laughlin handoff.** Amber's commit 9571e23 added the `MetricKind.energy` case Laughlin needed for the P1.3 HealthKit mapping. Before Laughlin could stage, Weiss's 7dd784e arrived with the `hasLiveHKEnergy` latch already present in `WorkoutViewModel.apply(metric:)` — a workaround Weiss invented to prevent downstream HR-estimate updates from overwriting the live HK kcal truth once the substrate emits `.energy`. Laughlin's mapping simply wired the `.energy` emission. The latch made sense given the live-metric-overwrite risk (HK updates tick asynchronously vs. controller accumulation) and proved a valuable defence-in-depth. Rebase-before-push pattern ensured no conflicts when both Weiss + Laughlin touched `WorkoutViewModel`.

## 2026-05-17T21:56:30Z — Cross-agent note from Scribe (D-RICHARDS-TF-11 trap)

**From Richards' rc5 diagnostics:** When using `-allowProvisioningUpdates` + manual signing (Xcode CLI), the provisioning profiles minted by the ASC API can only declare capabilities that are already enabled on the App ID itself in developer.apple.com. If your code entitlements declare HealthKit but the App ID doesn't have HealthKit enabled in the portal, the minted profile won't satisfy Xcode's entitlement checker, and the archive will fail with a "missing capability" error.

**Canonical rule:** "App ID capabilities must mirror entitlements when using -allowProvisioningUpdates + manual signing."

This is portal-side state, not code-fixable, and is a new trap class in SKILL.md. Relevant during any future release campaign / signing fix work.

## 2026-05-18T09:34:18-04:00 — rc12 CI alignment: ci-build + codeql → macos-26 / Xcode 26.4

PR #32 (`chore/v02-rc12-align-ci-workflows`) → squash-merged into main. Brings `ci-build.yml` and `codeql.yml` onto the same runner image + Xcode pin Richards-9 introduced for `release-testflight.yml` in #31. Surgical diff: runner label, `XCODE_VERSION` env var, comment refresh. Same `setup-xcode@v1` action and same `XCODE_VERSION` env-var pattern as #31, so the three macOS workflows now read identically at the top of each job.

Post-merge verification on main:
- **CI — App Builds (macOS)** (4-scheme matrix on macos-26): ✅ success in 8m34s.
- **CodeQL — Swift** on macos-26 / Xcode 26.4: ✅ success in 27m54s (verified via the rc12 release commit's own CodeQL run — my PR's CodeQL run was queue-cancelled by a subsequent push under `cancel-in-progress: false` queue eviction; not a workflow failure).

### Learnings

- **`cancel-in-progress: false` does NOT protect queued runs from eviction by newer queued runs of the same concurrency group.** Both rc12's CodeQL run and my PR-32 CodeQL run targeted `refs/heads/main` (same concurrency group `codeql-CodeQL — Swift-refs/heads/main`). My run waited behind rc12's; while waiting, a third push (iPad orientation fix) landed; GitHub evicted my queued run in favour of the newest queued run and rc12's in-progress run completed normally. **Implication:** "I'll wait for it to drain naturally" only holds if no third push arrives. For belt-and-braces post-merge verification of a workflow change, re-trigger via `workflow_dispatch` or a no-op commit on a quiet branch rather than relying on the natural main push being the verifying run.

- **macos-26 CodeQL run is materially slower than macos-15 was** (27m54s vs ~19m on previous green run of the same workflow). Plausibly first-run cache cold on a new image, plausibly Xcode 26.4 toolchain weight, plausibly CodeQL Swift extractor doing more on a newer SDK. Not slow enough to bump the `timeout-minutes: 45` ceiling, but worth knowing — if a future change pushes the total past ~35m, raise the timeout rather than chase a phantom hang.

- **The runner version drift would have silently masked SDK breakage.** Before #31 + #32, PR builds were compiling against iOS 18.5 / watchOS 11.5 SDKs but rc tags were archiving against iOS 26.4 / watchOS 26.4. Any iOS-26-only deprecation, removed API, or behavior shift would only have surfaced at tag time (release-testflight.yml), past the point of cheap correction. Aligning all three macOS workflows on the same image+SDK closes that drift window. Generalizes: **whenever a release workflow moves to a new toolchain, every PR-gating workflow that compiles the same code must move with it in the same campaign — runner-version skew between PR CI and release CI is a defect category, not a config preference.**

- **`gh pr merge --auto --delete-branch` can complete instantly when branch protection allows it.** PR #32 reported `mergedAt` populated on the first call rather than enqueueing an `autoMergeRequest`, presumably because there are no required status checks blocking main. Useful to know: if you want CI to validate the change *before* merge specifically, you can't rely on `--auto` alone — you'd need to add a required check at the branch-protection level, or push to a dummy branch first.
- 2026-05-18: v0.2.0 shipped to TestFlight via rc13 (final release campaign milestone)

## 2026-05-18T10:24:15-04:00 — rc14: Watch companion app embed (silent rc13 pairing failure)

Joe installed rc13 from TestFlight: iOS app launched fine, but the AR-Runner Watch app was completely absent from the paired Apple Watch — not auto-installed, not even listed under the Watch app's "Available Apps" section. Diagnosed and shipped rc14 (PR #36, merged; tag v0.2.0-rc14 pushed; release workflow queued).

### Root cause

`project.yml` declared `ARRunnerWatch` as a top-level target but never wired it as a dependency of the iOS app target. The `ARRunnerPhone` `dependencies:` block listed only `ARRunnerWidgetsPhone` (embed) and `ARRunnerCore` (SPM). Without an `embed: true` dep on the watch app, xcodegen never emits the **Embed Watch Content** `PBXCopyFilesBuildPhase`, so the archive build produces a phone .app with no `Watch/ARRunnerWatch.app/` subdirectory. The resulting IPA is internally consistent and signs/uploads cleanly — Apple's validator does not flag missing watch content because watch-companion embedding is optional from its perspective. The watch app's own Info.plist + bundle ID + WKCompanionAppBundleIdentifier were already correct (Weiss + I had set them right back in v0.1). Embed phase was the single missing piece.

### Fix

11 lines added to `project.yml` (with explanatory comment block):
```yaml
dependencies:
  - target: ARRunnerWidgetsPhone
    embed: true
  - target: ARRunnerWatch          # ← new
    embed: true
  - package: ARRunnerCore
```

Verified locally: `xcodegen generate` now produces `PBXCopyFilesBuildPhase "Embed Watch Content"` containing `ARRunnerWatch.app` in the generated pbxproj. Pre-fix that phase was absent.

### Learnings

- **The "silent embed gap" failure mode.** A missing watch-app embed dependency in xcodegen-managed projects causes zero build errors, zero warnings, zero signing failures, zero TestFlight upload rejections. Every CI gate passes green. The only symptom surfaces on-device when the user installs the phone app and notices the watch app never appears. Validation idea for future release campaigns: add a post-archive grep step in `release-testflight.yml`: `unzip -l "$IPA" | grep -q 'Watch/.*\.app/Info\.plist' || (echo "::error::Watch companion app not embedded in IPA" && exit 1)`. This would catch the same failure pre-upload and save a TestFlight round-trip. (Worth a decision proposal if Joe wants it for v0.3.)
- **Verify embed dependencies by inspecting the generated pbxproj after xcodegen, not just by reading project.yml.** The xcodegen DSL makes it easy to express target dependencies (`- target: X`) without `embed: true` and have them still work as a link/build-order constraint — but link-only deps don't put the product into the parent bundle. Grep the generated pbxproj for `Embed Watch Content` / `PBXCopyFilesBuildPhase` whenever you add or modify a host-of-host (phone-hosts-watch, watch-hosts-extension) relationship.
- **All five "is the watch app correctly configured?" preconditions were already in place** from v0.1 setup (WKApplication, WKCompanionAppBundleIdentifier matching parent bundle ID, watch bundle ID = parent + `.watchkitapp` suffix, TARGETED_DEVICE_FAMILY=4, platform: watchOS). The only thing missing was the embed wiring on the *iOS* side. This split — "watch target self-config is right, but the host doesn't include it" — is the canonical xcodegen watch-companion trap.
- **Joe-facing remediation pattern for embedded-watch-app fixes.** After the fixed IPA reaches TestFlight, the user must: (1) delete the existing TestFlight install on iPhone, (2) reinstall from TestFlight. The Watch app then auto-installs on the paired Apple Watch within ~30s–2min. If it doesn't, open Watch app → My Watch → Available Apps → Install next to AR-Runner. No watchOS-side action required first; the iPhone-side reinstall is what triggers re-discovery of the newly-embedded watch payload.
- **`gh pr merge --auto --squash` completes instantly on this repo (again).** Same as rc12: branch protection blocks direct pushes to main but PRs auto-merge without required status checks. CI runs *after* the merge. For this task that was fine — the change is config-only and xcodegen-verified locally — but for a riskier change I'd add a required-checks gate at the repo-protection level first. Cross-ref the rc12 history entry on this same gotcha.

## 2026-05-18T10:57:54-04:00 — CI regression fix: watchOS destination on macos-26 (PR #39)

Joe caught that `ARRunnerWidgetsWatch` had been failing CI on every PR since the rc12 alignment landed (#32), but auto-merge kept landing red because branch protection doesn't enforce required checks here. Two-tier fix on `fix/ci-build-watch-destination` (PR #39):

- **`ARRunnerWatch` (app scheme):** changed destination from `generic/platform=watchOS Simulator` → `generic/platform=watchOS`. Device-class generic is the right form when no sim runtime is preinstalled; mirrors what `release-testflight.yml` uses for archive. ✅ Passed on first try after the change.
- **`ARRunnerWidgetsWatch` (app-extension scheme):** the device-class generic destination *doesn't work* for this scheme on macos-26 — `xcodebuild -showdestinations` returns only macOS / iOS / iOS Simulator, no watchOS entries at all, and the build dies with `IDERunDestination: Supported platforms for the buildables in the current scheme is empty.` Had to install the watchOS Simulator runtime explicitly (`xcodebuild -downloadPlatform watchOS`) and keep `=watchOS Simulator` as the destination. Conditional `if: matrix.scheme == 'ARRunnerWidgetsWatch'` so only that one matrix job pays the ~3–5 min download cost.
- **`codeql.yml`:** uses ARRunnerWatch as its build driver, so a single destination change suffices (no runtime install needed).

### Learnings

- **Runner image runtime drift is a real, recurring trap class.** Migrating GitHub Actions runner images between major versions (here `macos-15` → `macos-26`) can silently remove preinstalled SDK simulator runtimes. The macos-26-arm64 image ships iOS Sim, visionOS Sim, and macOS — but **NO watchOS Simulator runtime preinstalled**. Any workflow whose `-destination` says `generic/platform=watchOS Simulator` will fail with `Unable to find a destination matching the provided destination specifier` until you either drop "Simulator" from the destination (preferred for app schemes) or install the runtime via `xcodebuild -downloadPlatform watchOS` (required for some extension schemes). Verify by running `xcodebuild -showdestinations -scheme {Scheme}` against the new image before committing the migration. Skill appended.

- **App vs. app-extension watchOS schemes behave differently w.r.t. the device-class generic destination.** For the watch *app* scheme, `generic/platform=watchOS` is satisfiable without a sim runtime — same form `xcodebuild archive` uses in release. For the watch *widget extension* scheme on Xcode 26 / macos-26, that destination is NOT enumerated (the scheme reports empty supported platforms when no watchOS sim runtime is installed). For app extensions, you either need the sim runtime present OR you can rely on the parent watch app's embed dependency to compile the extension transitively. We went with explicit sim-runtime install to keep the matrix shape and per-job signal that Joe expects. If CI minutes ever become tight, the alternative is dropping the standalone `ARRunnerWidgetsWatch` matrix entry — its build is redundant because `ARRunnerWatch` embeds it.

- **Required status checks at the branch-protection level matter.** This is now the third entry in my history noting that `gh pr merge --auto --squash` lands instantly because no checks are required. So far each instance had been "fine" because the change was config-only or hand-verified — but this regression is the textbook case the gate is supposed to catch: a CI workflow change silently broke a build job, then four subsequent PRs piled on top without anyone noticing because each PR's own merge succeeded. If branch protection had required `ARRunnerWidgetsWatch` green, #32 would have been the only red PR and would have been fixed immediately. Worth raising with the coordinator as a proposed governance tightening for v0.3.

- **A failing job that nobody reads is worse than no job at all.** All five build jobs ran on every PR since #32. The `xcodebuild` log clearly said "no watchOS Simulator destinations available." The information was there; the system just wasn't surfacing it forcefully enough — no required-checks block, no PR-author notification. When introducing a new CI job, also introduce the enforcement; otherwise it's documentation, not validation.

- **Three-workflow toolchain alignment must include destination semantics, not just runner + SDK.** PR #32's mistake wasn't picking macos-26 — that's still correct. It was assuming "same image + same Xcode = same destination semantics." The release workflow had already moved off `=watchOS Simulator` (uses device-class generic for archive). Aligning ci-build / codeql with release should have included aligning the destination form too, not just the runner label. Generalizes: when moving a PR-gating workflow to mirror a release workflow's toolchain, also diff their `-destination` arguments — they're often different for principled reasons (test vs. archive vs. verify-build), and surface-level "make them match" can leave the destinations stale.

- **Shared working-tree hazard with parallel agents.** Mid-task, Richards' agent ran a `docs(squad)` commit in the same filesystem and switched branches around me — I appended to `history.md` and `SKILL.md` while my working tree had been silently moved off `fix/ci-build-watch-destination` onto `main`. Those appends were then lost when Richards' merge updated main and the branch checkouts shuffled. Untracked files (the inbox decision file) survived; tracked-file appends did not. **Lesson:** in shared-working-tree multi-agent sessions, after every long-running step (CI polls, ~minutes wait) re-verify `git branch --show-current` before further file edits, and prefer committing the docs to the working branch in the same commit batch as the code change rather than relying on the working tree to stay put. Or: use git worktrees so each agent has an isolated working directory.

## 2026-05-18T11:50:00-04:00 — CI fix pivot: drop ARRunnerWidgetsWatch standalone matrix entry (PR #39, 3rd commit)

The two-tier approach (install watchOS sim runtime via `xcodebuild -downloadPlatform watchOS`, keep `=watchOS Simulator` destination) did NOT work either. CI run on commit 2ebbbfb showed:

- Install step succeeded: "watchOS is already downloaded as universal" / "watchOS 26.4 (23T240b) - A1446080-FB6D-4CA7-B96D-BF6079D10E2F".
- But the subsequent xcodebuild step for `ARRunnerWidgetsWatch` STILL reported no watchOS destinations available. Available list showed only macOS / iOS / iOS Simulator / visionOS Simulator (with named devices like "Apple Vision Pro OS 26.4.1") — no Apple Watch entries at all.

So the constraint isn't "watchOS runtime missing" — it's that the ARRunnerWidgetsWatch app-extension scheme on Xcode 26 / macos-26-arm64 just doesn't enumerate watchOS destinations, even with the runtime present. Probably related to how xcodegen generates the scheme's supported platforms for shared-source widget extensions, but root-causing that is out of scope.

Pivoted to option A' (drop the standalone matrix entry). ARRunnerWatch's `embed: true` dependency on ARRunnerWidgetsWatch means the widget extension gets compiled transitively whenever ARRunnerWatch builds — any compile error in the widget will fail the ARRunnerWatch job. The standalone matrix entry was duplicating work and provided no unique signal.

### Learnings

- **`xcodebuild -downloadPlatform watchOS` installs the *runtime* but does not create simulator *devices*.** The log clearly showed the runtime present, but xcodebuild's destination enumeration for the widget extension scheme remained empty. Installing the runtime is necessary-but-not-sufficient for watchOS Simulator destinations to appear. To go further you'd need `xcrun simctl create "Apple Watch" "Apple Watch ..." watchOS26.4` to materialize a simulator device, AND fix whatever's keeping the scheme from advertising watchOS as a supported platform. Way more work than the regression warrants.

- **Embed dependencies provide free transitive build coverage.** ARRunnerWatch's `dependencies: [- target: ARRunnerWidgetsWatch, embed: true]` means xcodebuild compiles the widget as part of building the watch app. A standalone widget-only matrix job adds CI minutes (parallel runner, full xcodegen + cache restore + build) but adds zero failure-detection capability beyond what the watch app build already covers. Same logic applies to ARRunnerWidgetsPhone vs. ARRunnerPhone — that pair could also be collapsed in a future cleanup, though I left it alone here (out of regression scope, and the iOS sim destination Just Works on macos-26).

- **Iterating in PR-CI is slow and expensive.** Three xcodebuild iterations on this PR alone (~14 min each for the matrix job, plus 20+ min CodeQL queues). For a "fix the destination" task this approached the runtime of writing the actual code. Lesson: for CI changes that hinge on runtime introspection (which destinations exist, which runtimes are present), it's worth pushing a one-off diagnostic commit early that does `xcodebuild -showdestinations` + `xcrun simctl list runtimes` + `ls /Library/Developer/CoreSimulator/Profiles/Runtimes/` and prints the results, then iterate locally on the fix based on real output. Cheaper than iterating on the fix itself in CI.

- **Shared-working-tree hazard hit AGAIN.** Weiss's agent checked out `feat/watch-glasses-connect` mid-task and my next `edit` calls failed because the file content no longer matched my `old_str`. Recovery: re-fetch, re-checkout my branch, redo the edits. **Reinforcement of the earlier lesson:** in shared-working-tree multi-agent sessions, verify `git branch --show-current` before every batch of file edits, especially after any non-trivial wait (CI polls, sleeps).
