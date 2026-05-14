# Decision Drop — CI / Security Workflow Architecture

**Author:** Richards (Lead / Architect)
**Date:** 2026-05-14T16:51:53-04:00
**Branch:** `chore/ci-workflows` (off `chore/macos-build-validation`)
**Status:** Proposed — pending merge of PR
**Related:** D1–D9, "No Direct Main" directive (2026-05-14T15:44:37-04:00), Amber's macOS build validation (2026-05-14T16:28:08-04:00), XcodeGen tooling decision (2026-05-14T16:09:31-04:00)

## What

Add three CI workflows to `.github/workflows/`, sitting alongside the Squad orchestration workflows but reserved under their own naming prefix (`ci-*.yml` for build/test, `codeql.yml` for security; `squad-*.yml` remains orchestration-only):

1. **`ci-core-tests.yml`** — Linux runner, `swift:6.0-jammy` container, `swift test` on `ARRunnerCore`.
2. **`ci-build.yml`** — macOS-15 runner, 4-way matrix, `xcodegen generate` + `xcodebuild` for `ARRunnerWatch`, `ARRunnerPhone`, `ARRunnerWidgetsPhone`, `ARRunnerWidgetsWatch`.
3. **`codeql.yml`** — macOS-15 runner, GitHub CodeQL Swift analysis with `security-extended` queries on PR + weekly schedule.

Full operational documentation is in `docs/dev/ci-workflows.md`.

## Why

Two real-code branches are about to land (Weiss's BLE wrapper, Laughlin's `WorkoutController`). Without CI, those PRs go in on the strength of one local macOS build per author. Amber's validation pass found three real scaffold bugs that would have shipped silently — every subsequent PR has the same exposure. CI is the cheapest insurance we'll ever buy on this project.

## The decisions, with trade-offs

### ADR — Runner mix: Linux for Core, macOS for shells

**Decision:** Split `swift test` (Linux) from `xcodebuild` (macOS).

**Spike result:** `ARRunnerCore` imports only `Foundation` (sources) and `XCTest` + `Foundation` (tests). No HealthKit, CoreBluetooth, WatchKit, WatchConnectivity, UIKit, AppKit. `SwiftPM`'s `platforms:` block is a minimum-Apple-version declaration — it doesn't gate Linux compilation. The pure-Swift Core compiles and tests cleanly on Linux Swift 6.

**Alternatives considered:**
- **All-macOS.** Simpler — one runner type, one mental model. Costs ~10x per minute. With macOS billed at 10x Linux and core tests being the most-frequently-failing job (every PR exercises model serialization), the rational answer is to keep the fast-iterating job on the cheap runner.
- **All-Linux.** Impossible — app shells need Apple SDKs (WatchKit, HealthKit, WidgetKit, UIKit).

**Cost of the chosen split:** ARRunnerCore *must* stay platform-agnostic. The moment someone imports HealthKit into Core, this job fails on Linux. **That cost is actually a feature** — it enforces ADR-001 (SPM-shared Core) and ADR-007 (`GlassesFrameProtocol` behind a protocol boundary) mechanically. Trade named, accepted.

### ADR — Trigger strategy: PR + push-to-main only

**Decision:** Workflows run on `pull_request` (any base) and `push` to `main`. Never on branch pushes outside of a PR.

**Alternative:** Run on every branch push. Faster feedback for devs working locally, but Apple-Watch devs already have a Mac on their desk (D-2026-05-14T16:09:31-04:00 dev workflow split) — they get faster feedback running `xcodebuild` directly. Branch-push CI would burn macOS minutes for marginal value.

**Cost:** A dev who pushes a branch without opening a PR gets no signal until they file the PR. Acceptable — opening a PR is one click.

### ADR — Concurrency cancellation on PRs, not on main

**Decision:** All three workflows use `concurrency: { group: ..., cancel-in-progress: ${{ github.event_name == 'pull_request' }} }`. Rapid pushes to a PR branch cancel in-flight runs; pushes to `main` are never cancelled.

**Why:** macOS minutes are the budget. A dev rebasing or force-pushing a PR five times shouldn't cost five full matrix builds. But on `main`, we want a clean, linear, never-cancelled history of green/red. Different audiences, different policies.

### ADR — Caching strategy

**Decision:**
- Linux: cache `ARRunnerCore/.build` + `~/.cache/org.swift.swiftpm`, keyed on `Package.swift` + `Package.resolved`.
- macOS: cache `~/Library/Caches/org.swift.swiftpm`, `DerivedData/**/SourcePackages`, and `DerivedData` itself, keyed on `project.yml` + `Package.swift`.

**Trade-off named:** DerivedData caches are large (hundreds of MB) and frequently invalidated by Xcode version drift. They will sometimes miss; that's fine — they're an optimization, not correctness. If cache restore costs ever exceed cache-hit savings, drop the DerivedData cache and keep only the SPM caches.

### ADR — CodeQL builds only ARRunnerWatch

**Decision:** CodeQL drives off a single `xcodebuild` of `ARRunnerWatch` (the largest single dependency closure — pulls Core + watch shell + widget extension). Not the full matrix.

**Alternative:** Build all four schemes under CodeQL. Marginal coverage gain (CodeQL re-analyses the same Swift sources), large minute cost (CodeQL Swift is the slowest of the three workflows).

**Cost:** If a phone-only or widget-only file is somehow never visited by the watch build's compile, CodeQL won't analyze it. In practice, Core is the only shared compile unit and it's visited. Acceptable.

### ADR — `security-extended` queries

**Decision:** Use the `security-extended` CodeQL query suite, not just the default.

**Trade-off:** ~30% more analysis time, broader rule coverage. For a security-sensitive surface (BLE pairing, HealthKit data handling, App Group sharing), the extra signal is worth the minutes.

## Punt list — what we are deferring and why

| Concern | Status | Rationale |
| --- | --- | --- |
| Lint (swiftlint vs swift-format) | **Deferred** | Joe + Richards to pick a tool with intent, not under deadline. No code has been written yet that exercises the difference. TODO captured in `docs/dev/ci-workflows.md`. |
| Code coverage | **Deferred** | Coverage on a scaffold-only test suite (6 Codable round-trips) is theatre. Re-evaluate after Weeks 1–3 of Weiss + Laughlin land real logic. |
| Release / TestFlight | **Out of scope** | Requires signing identity + secrets management. Separate workflow, separate decision. |
| Dependabot | **Deferred** | Zero external SPM deps today. Enable when ActiveLook SDK or any other vendor SPM dep lands. |
| Branch protection / required checks | **Manual** | Joe needs to toggle "Require status checks to pass before merging" on `main` after first green run. Workflows are designed to be the contract. |
| Linux build of app shells | **Not viable** | App shells depend on WatchKit / UIKit / HealthKit / WidgetKit — Apple-only. |

## What Weiss and Laughlin need to know

1. **Don't import Apple-framework code into `ARRunnerCore`.** It will fail the Linux core-tests job and block your PR. Concrete Apple-framework code lives in the app/extension targets. Use protocol boundaries in Core (ADR-007).
2. **Your PR must pass three required check sets**: `ci-core-tests`, all 4 `ci-build` matrix jobs, and `codeql`. Plan for ~15 min of CI time per PR after cache warm-up.
3. **Local validation matches CI 1:1.** See the repro block in `docs/dev/ci-workflows.md`. If it builds locally, it builds in CI — and vice versa.
4. **`@preconcurrency import` of the ActiveLook SDK stays in the watch/phone targets**, not Core. This was already the D8 plan; it's now mechanically enforced by the Linux core-tests job.

## Verification

This branch (`chore/ci-workflows`) sits on top of `chore/macos-build-validation` (Amber's three scaffold fixes), so the workflows are validated against the post-fix scaffold. When `chore/macos-build-validation` merges to `main`, this branch rebases cleanly.

## Files

- `.github/workflows/ci-core-tests.yml`
- `.github/workflows/ci-build.yml`
- `.github/workflows/codeql.yml`
- `docs/dev/ci-workflows.md`
- `.squad/skills/swift-linux-macos-runner-split/SKILL.md` (reusable pattern)
