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
