# CI Workflows

**Last updated:** 2026-05-14T16:51:53-04:00
**Owner:** Richards (Lead / Architect)
**Related decision drop:** `.squad/decisions/inbox/richards-ci-architecture.md`

This document is the operational reference for AR-Runner's continuous-integration workflows. The Squad-orchestration workflows (`squad-*.yml`, `sync-squad-labels.yml`) are documented separately under the Squad system; this file covers only the build/test/security workflows.

## Workflows at a glance

| File | Purpose | Runner | Trigger | Expected duration | Cost class |
| --- | --- | --- | --- | --- | --- |
| `ci-core-tests.yml` | `swift test` on `ARRunnerCore` (SPM, Linux Swift 6) | `ubuntu-latest` + `swift:6.0-jammy` container | PR + push to `main` | 1–3 min | Linux (free tier) |
| `ci-build.yml` | `xcodegen generate` + `xcodebuild` for the 4 app/widget schemes | `macos-15` (matrix x4) | PR + push to `main` | 5–12 min wall-clock per scheme | macOS (~10x Linux) |
| `codeql.yml` | GitHub CodeQL Swift analysis (security-extended queries) | `macos-15` | PR + push to `main` + weekly Sunday 07:00 UTC | 8–15 min | macOS |

All three honor `concurrency:` groups keyed on `${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: true` on pull requests. Pushes to `main` are never cancelled — we want a clean main-line history.

## ci-core-tests.yml — Linux SPM tests

**What it does:** runs `swift build --build-tests` followed by `swift test --skip-build` inside the official `swift:6.0-jammy` container.

**Why Linux:** `ARRunnerCore/Sources/**` and `ARRunnerCore/Tests/**` import only `Foundation` and `XCTest`. No HealthKit, CoreBluetooth, WatchKit, WatchConnectivity, UIKit, or AppKit. SwiftPM's `platforms:` declaration is a *minimum-version* constraint for Apple platforms; it does not exclude Linux. The trade-off is named in the decision drop.

**Caches:** `ARRunnerCore/.build` and `~/.cache/org.swift.swiftpm`, keyed on `Package.swift` + `Package.resolved`.

**Failure modes to watch:**
- If Laughlin/Weiss ever import an Apple-only framework into `ARRunnerCore` (HealthKit, CoreBluetooth, WatchKit, WatchConnectivity, UIKit, AppKit), this job will fail on Linux. The fix is *not* to move the job to macOS — it is to keep platform-conditional code out of Core (per ADR-001 / ADR-007). Use protocol boundaries and put concrete Apple-framework code in the app shells.
- `@preconcurrency import` of vendor SDKs (ActiveLook) must stay in the watch/phone targets, never in Core.

## ci-build.yml — macOS app & widget builds

**What it does:** pins Xcode 16.4 via `maxim-lobanov/setup-xcode@v1`, installs `xcodegen` via Homebrew, runs `xcodegen generate`, then runs `xcodebuild build` for each scheme in a matrix.

**Why pin Xcode 16.4:** The `macos-15` runner image ships multiple Xcode versions. We pin 16.4 because it is the runner image's *default* Xcode and ships with the **iOS 18.5 and watchOS 11.5 simulator runtimes pre-installed** — both satisfy our D2 minimums (iOS 18 / watchOS 11). The older `Xcode_16.app` (16.0) nominally bundles the 18.0 / 11.0 runtimes per the runner image manifest, but in practice the watchOS 11.0 simulator runtime is missing on the live image and `xcodebuild -downloadPlatform watchOS` cannot run unattended on CI (exits 70 — Apple ID auth required). Pinning a Xcode whose simulator runtimes are pre-baked into the image is the portable, unattended fix.

| Scheme | Destination |
| --- | --- |
| `ARRunnerWatch` | `generic/platform=watchOS Simulator` |
| `ARRunnerPhone` | `generic/platform=iOS Simulator` |
| `ARRunnerWidgetsPhone` | `generic/platform=iOS Simulator` |
| `ARRunnerWidgetsWatch` | `generic/platform=watchOS Simulator` |

`CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, `CODE_SIGN_IDENTITY=""`. CI has no signing identity and intentionally never will — signing happens in the release pipeline (out of scope for this PR).

**Matrix `fail-fast: false`** so a watch breakage doesn't mask a phone breakage; we want the full picture per PR.

**Caches:**
- `~/Library/Caches/org.swift.swiftpm` + `~/Library/Developer/Xcode/DerivedData/**/SourcePackages` — SPM artifacts as resolved by Xcode.
- `~/Library/Developer/Xcode/DerivedData` — compiled module/object cache.

Cache hits are best-effort. Cold-cache cost on macOS is the dominant cost driver; if cold builds drift past ~12 min/scheme, revisit cache keys.

## codeql.yml — Swift security analysis

**What it does:** initializes CodeQL with `languages: swift` and `queries: security-extended`, then runs an `xcodebuild build` of `ARRunnerWatch` as the build driver so CodeQL can observe a full Swift compile of `ARRunnerCore` + watch shell + widget extension.

We deliberately build only one scheme (the largest single dependency closure) rather than the full matrix. CodeQL needs *a* build, not every build, and Swift CodeQL is the slowest of the three workflows; running it 4x for marginal coverage gain is not worth the runner minutes.

**Schedule:** weekly Sunday 07:00 UTC. New CodeQL Swift queries land on a roughly monthly cadence; weekly re-runs surface advisories on code that hasn't changed.

## Running the same checks locally

Match the canonical commands from `docs/dev/macos-build-validation.md`:

```bash
# from repo root
brew install xcodegen
xcodegen generate

# Linux-equivalent core tests (also works on macOS — same toolchain)
cd ARRunnerCore && swift test && cd ..

# App and widget builds (mirrors ci-build.yml)
for SCHEME in ARRunnerWatch ARRunnerPhone ARRunnerWidgetsPhone ARRunnerWidgetsWatch; do
  case $SCHEME in
    *Watch*) DEST='generic/platform=watchOS Simulator' ;;
    *)       DEST='generic/platform=iOS Simulator' ;;
  esac
  xcodebuild -project AR-Runner.xcodeproj -scheme "$SCHEME" \
    -destination "$DEST" -configuration Debug \
    CODE_SIGNING_ALLOWED=NO build
done
```

CodeQL has no realistic local equivalent — it runs only in CI.

## What is NOT in CI yet (and why)

| Concern | Status | Why deferred |
| --- | --- | --- |
| **Linting** (swiftlint vs swift-format) | Deferred | Joe + Richards to pick a tool and a ruleset together. Picking under deadline pressure produces a bad ruleset. TODO: open a follow-up issue once we have ≥1 PR of real code to lint against. |
| **Code coverage** (xccov / llvm-cov) | Deferred | Coverage on a 6-test scaffold is theatre. Wire up when Laughlin's `WorkoutController` and Weiss's BLE wrapper land real logic. |
| **Release / TestFlight / App Store** | Out of scope | No signing identity in CI; needs Joe's developer team and a separate workflow with restricted secrets. |
| **Dependabot** | Deferred | We have zero external SPM dependencies. Re-enable when the ActiveLook SDK lands. |
| **Branch protection / required checks** | Manual step | Toggling required status checks on `main` is a GitHub repo-settings change that Joe must make after the first green run. The workflows are designed to be the contract. |
| **Linux build of app shells** | Not viable | App shells depend on WatchKit/UIKit/HealthKit/WidgetKit — Apple-only. Stay on macOS for builds. |

## Cost shape

- **Linux** (free for public repos; 2x billing weight on private): `ci-core-tests` is essentially free.
- **macOS** (10x billing weight on private; metered on public above limits): `ci-build` × 4 schemes per PR + `codeql` per PR is the dominant spend. The concurrency cancellation policy is the primary mitigation — a rapid-fire push sequence cancels all but the last run.
- If macOS minutes become a real cost concern, the next lever is to drop `codeql` from per-PR to push-to-main + weekly schedule only. That's a one-line change.

## Triggering matrix

| Event | `ci-core-tests` | `ci-build` | `codeql` |
| --- | :-: | :-: | :-: |
| PR (any base) | ✅ | ✅ | ✅ |
| Push to `main` | ✅ | ✅ | ✅ |
| Schedule (weekly) | — | — | ✅ |
| Branch push (non-PR) | — | — | — |

Branch-only pushes are intentionally excluded — devs push frequently, and PRs are the gate. This pattern saves significant runner minutes.

## Failure triage

When a workflow goes red:

1. **`ci-core-tests` (Linux):** Almost always a real test failure or an accidental Apple-framework import in Core. Run `cd ARRunnerCore && swift test` locally — reproduces 1:1.
2. **`ci-build` (matrix):** Look at which scheme failed. The most common scaffold-class breakages live in `project.yml`, not Swift code. Run `xcodegen generate && xcodebuild -scheme <failed-scheme> ...` locally.
3. **`codeql`:** Findings show up under the repo's Security tab. CodeQL build failure usually means `xcodebuild` failed — fix `ci-build` first; `codeql` will follow.

## Future work (issues to file when CI is green)

- [ ] Pick lint tool (swiftlint vs swift-format) and add `ci-lint.yml`.
- [ ] Add `xcodebuild test` for app-target test bundles once Laughlin/Weiss add UI/integration tests.
- [ ] Add code coverage upload (xccov-parse → SARIF or Codecov) after real test surface exists.
- [ ] Release workflow with code signing, archives, and TestFlight upload.
- [ ] Dependabot config once external SPM deps are introduced.
- [ ] Enable required status checks on `main` for `ci-core-tests`, all 4 `ci-build` matrix jobs, and `codeql`.
