# Architecture & Best-Practices Audit — 2026-05-16

**Author:** Richards (Lead / Architect) · **Scope:** read-only · **Branch:** main · **Peers:** Laughlin (Swift/HealthKit), Weiss (BLE/ActiveLook)

## Summary

- **Layering is clean.** ARRunnerCore is genuinely platform-pure (Foundation-only; verified across 22 source files). The Linux CI job enforces it for free. D1/D2/D8 still match the code.
- **Tooling pins are ~12 months stale for a 2026 audit.** Xcode 16.4 / Swift 6.0 / macos-15 were locked in May 2025; Xcode 17 + Swift 6.2 are GA as of late 2025 and macos-26 runners are available. No active reason to stay back; bumping is mostly mechanical but needs a probe PR.
- **One real source-tree hygiene break:** `ARRunnerWatch/Glasses/ActiveLookGlassesAdapterHardwareTests.swift` ships inside the production app target behind `#if AR_RUNNER_HARDWARE_TESTS`. Compile-guarded, so safe — but XCTest lives in the app source tree, which is a smell and will eventually trip a static analyzer or App Store review.
- **CodeQL only analyses ARRunnerWatch** — Phone target's WCSession + UI are never scanned. Asymmetric coverage.
- **Two doc-drift cliffs:** (a) `.github/copilot-instructions.md:5` still claims "greenfield, no application source code exists yet" while ~30 production files and 16 test files are committed; (b) no Dependabot, no SHA-pinned actions in the secret-handling release workflow.

---

## Layering & Module Boundaries

**Verdict: ✅ healthy.**

Module map (project.yml + on-disk):

| Module | Type | Platform(s) | Public deps |
|---|---|---|---|
| `ARRunnerCore` (SPM) | library | iOS 18 / watchOS 11 / macOS 14 (test-only) | Foundation |
| `ARRunnerWatch` | app | watchOS 11 | ARRunnerCore, SwiftUI, HealthKit, WatchConnectivity, CoreBluetooth, WatchKit, os |
| `ARRunnerPhone` | app | iOS 18 | ARRunnerCore, SwiftUI, WatchConnectivity, os |
| `ARRunnerWidgetsPhone` | app-extension | iOS 18 | ARRunnerCore, WidgetKit, AppIntents, SwiftUI |
| `ARRunnerWidgetsWatch` | app-extension | watchOS 11 | ARRunnerCore, WidgetKit, AppIntents, SwiftUI |

Verified by grep of all `^import` lines (`ARRunnerCore/Sources/**`): only `Foundation` appears. No back-channel imports of HealthKit / CoreBluetooth / WatchConnectivity / SwiftUI / WatchKit / AppIntents inside Core. ADR-001 ("Core is platform-pure") and ADR-007 hold.

**Minor:**
- `ARRunnerPhone/Sync/WatchConnectivityService.swift` and `ARRunnerWatch/Sync/WatchConnectivityService.swift` are two separate 116/124-line files with deliberately different role surfaces (sender vs receiver). The naming collision is intentional but invites confusion in code review. Consider `WatchConnectivityReceiver.swift` / `WatchConnectivitySender.swift`. Shared envelope encoding already lives in Core (`Messaging/WCMessage.swift`) — good.
- `ARRunnerWidgets/` is shared by both widget extensions (per `project.yml:106-141`). Per skill `xcodegen-shared-widget-per-platform` this is the right pattern; flag here only because any future extension-specific code (e.g. `WKExtension` use) needs an `#if os(watchOS)` guard.

---

## Cross-Cutting Concerns

| Concern | State | Notes |
|---|---|---|
| Logging | `os.Logger` in Watch/Phone (`ActiveLookGlassesAdapter.swift:7`, `HealthKitWorkoutSubstrate.swift:19`, both `WatchConnectivityService.swift`). Core: silent. | Sensible — Core can't depend on `os`. No subsystem/category convention documented. **Trade-off:** distributed logging vs. a thin `LogSink` protocol in Core. At current scale, status quo is fine. |
| Error model | Per-actor enums (e.g. `WorkoutController.Error` at `WorkoutController.swift:22`). No shared error taxonomy. | Acceptable for v0.1. Risk emerges if/when telemetry needs cross-module error fingerprinting. |
| Config / secrets | No secrets in Core. Release secrets confined to `release-testflight.yml` (per-job keychain pattern, `.p12` deleted after import — correct). `Config/Signing.xcconfig` generated at CI time by `scripts/bootstrap-signing.sh` from `APPLE_TEAM_ID`. | ✅ |
| Telemetry | None. | Acceptable pre-public-beta. Will need a decision before TestFlight invites beyond the team. |
| Concurrency | Swift 6 language mode everywhere (`Package.swift:8,39`, `project.yml:14`). `@preconcurrency` used at `ActiveLookGlassesAdapter.swift:5` for `CoreBluetooth` — D8 names the ActiveLook *SDK* boundary specifically; CoreBluetooth is a system framework, not the vendor SDK. The escape hatch is justified (CB delegates aren't `Sendable`) but constitutes minor ADR drift in spirit. |

---

## CI Hygiene

| Workflow | Trigger | Runner | Pin | Verdict |
|---|---|---|---|---|
| `ci-core-tests.yml` | PR + push main | `swift:6.0-jammy` container on `ubuntu-latest` | Swift 6.0 | ✅ healthy. Concurrency cancel-on-PR. 15-min cap. Cache key off `Package.swift` + `Package.resolved`. |
| `ci-build.yml` | PR + push main | `macos-15` × 4-scheme matrix | Xcode **16.4** | ✅ working. `fail-fast: false`, 30-min cap, cache for SwiftPM + DerivedData. Comments document the watchOS-11 runtime gap clearly. |
| `codeql.yml` | PR + push main + weekly cron | `macos-15` | Xcode 16.4 | ⚠️ analyses **only ARRunnerWatch** (`codeql.yml:70`). Phone, Widgets-Phone, Widgets-Watch never scanned. `security-extended` query suite is good. |
| `release-testflight.yml` (feat/testflight-ci) | tag `v*.*.*-*`, workflow_dispatch | `macos-15` | Xcode 16.4 | ✅ correct keychain pattern; ASC API key handling solid; concurrency `cancel-in-progress: false` is the right call for a release queue. Action versions pinned only by major (`@v4`, `@v1`) — see Dependency table. |

**Cross-cutting CI gaps:**
1. **No SHA-pinned actions.** `actions/checkout@v4`, `actions/cache@v4`, `github/codeql-action/*@v3`, `maxim-lobanov/setup-xcode@v1` are all floating major tags. The TestFlight workflow handles signing cert + ASC API key — that's the one where supply-chain SHA pinning matters most. Trade-off: SHA pins add maintenance burden; mitigated by Dependabot (which we don't yet have).
2. **No `.github/dependabot.yml`.** Actions versions and (eventually) SPM deps can drift silently. Cheap to add.
3. **No SwiftLint / SwiftFormat in CI.** Style is currently enforced by reviewer judgement only.
4. **`ci-build.yml` doesn't actually run tests** — it's a Debug build matrix. Test execution happens only on the Linux Core job. Acceptable while Apple-specific tests don't exist, but worth flagging: Watch/Phone code is currently **not unit-tested**.

---

## Dependency & SDK Currency (2026 lens)

| Component | Current | Latest (May 2026) | Gap | Recommendation |
|---|---|---|---|---|
| Swift toolchain (CI/Linux) | 6.0 (`ci-core-tests.yml:27`) | 6.2 GA, 6.3 in preview | 2 minors | Bump to `swift:6.2-jammy`; rerun Linux suite. Low risk. |
| Xcode (macOS CI) | 16.4 (3 workflows) | Xcode 17.x | 1 major | Re-evaluate `macos-15` + Xcode 16.4 pin. The watchOS-runtime rationale (history.md:54) may be obsolete on macos-26 runners. |
| GitHub runner image | `macos-15` | `macos-26` available | 1 major | Test `macos-26` in a probe PR; the pin should follow the Xcode bump. |
| `actions/checkout` | `@v4` | `@v4` (current) | none | SHA-pin for release workflow. |
| `actions/cache` | `@v4` | `@v4` (current) | none | SHA-pin for release workflow. |
| `github/codeql-action` | `@v3` | `@v3` (current) | none | OK; SHA-pin optional. |
| `maxim-lobanov/setup-xcode` | `@v1` | `@v1` (current) | none | SHA-pin for release workflow. |
| `xcodegen` | Homebrew latest | Homebrew latest | n/a | `project.yml:3` requires ≥2.44; no upper pin. Fine. |
| ActiveLook SDK | Not vendored; using our own `ActiveLookGlassesAdapter` direct-BLE wrapper (D1). | — | n/a | Out of scope (Weiss). |
| SPM deps (Core) | **Zero** | — | — | Core has no external SPM deps; nothing to age. |
| `iOS` deployment target | 18.0 | 19.0 GA | 1 major | Keep at 18 (D2); revisit when iOS 19 install base crosses ~80%. **No action.** |
| `watchOS` deployment target | 11.0 | 12.0 GA | 1 major | Keep at 11 (D2). **No action.** |

**Trade-off named:** Xcode/Swift currency vs. boring-pin reproducibility. The 12-month-stale toolchain hasn't bitten us, but every additional month increases the catch-up cost and the surface area of pre-existing CVE fixes we're missing. Recommendation: **schedule a toolchain bump sprint within the next 30 days**, gated on a probe PR.

**No known CVEs against current pins** (manual cross-check; not exhaustive).

---

## ADR Drift

Selected the 5 most consequential decisions and verified against code:

| ADR / Decision | Status | Evidence |
|---|---|---|
| **D1** — Watch owns BLE directly | ✅ Holds | `ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift:5` imports CoreBluetooth on the watch target. No phone-side BLE code. |
| **D2** — watchOS 11 / iOS 18 / Swift 6 | ✅ Holds | `project.yml:10-11,14`, `Package.swift:13-15,39`. |
| **D4** — Glasses disconnect does NOT pause workout | ✅ Holds | `WorkoutController.swift:11` docstring explicitly references D4. `glassesDisconnectCount` is recorded as metadata, not used to drive phase transitions. |
| **D8** — Swift 6 strict + `@preconcurrency` at SDK boundary | ⚠️ Slight drift | `@preconcurrency import CoreBluetooth` (`ActiveLookGlassesAdapter.swift:5`). D8 names the ActiveLook SDK as the escape-hatch site; CoreBluetooth is a system framework. Justified (CB delegates aren't `Sendable`) but D8 wording should be amended to: "non-Sendable boundaries (vendor SDKs **and** CoreBluetooth)". |
| **D9** — Three-tier storage (HealthKit + side-store + CloudKit) | ⚠️ Partial | `ARMetadataStore.swift` exists (Tier 2 side-store seam ✅). HealthKit via `WorkoutHealthSubstrate` ✅ (Tier 1). CloudKit (Tier 3) intentionally deferred to v1 — not drift, just unbuilt. |
| **ADR-001 (architecture.md)** — Core is platform-pure | ✅ Holds | Linux CI enforces; all 22 Core sources import only Foundation. |

**Doc drift (separate from code drift):**
- `.github/copilot-instructions.md:5` declares the repo "greenfield, no application source code exists yet." **Demonstrably false** as of 2026-05-16 (~30 source files committed across 4 targets, 16 test files in Core). Any new agent or external contributor reading this is misled. **One-paragraph rewrite — but high impact because it gates every AI agent's mental model on first contact.**

---

## Top 5 Debt Items (Prioritized)

| # | Item | Effort | Impact | Notes |
|---|---|---|---|---|
| 1 | **Refresh `.github/copilot-instructions.md`** — replace "greenfield, no source code yet" with the actual module map + current state. | S | High | Every new agent's first-read priming. Cheapest, highest-leverage fix in this audit. |
| 2 | **Bump CI toolchain to Xcode 17 / Swift 6.2 / macos-26**, gated on a probe PR. | M | Med-High | 12-month stale. Each month older = harder catch-up. Probe-and-promote keeps risk low. |
| 3 | **Move `ActiveLookGlassesAdapterHardwareTests.swift` out of `ARRunnerWatch/` source tree** into a dedicated `ARRunnerWatchHardwareTests` test target in `project.yml`. | M | Med | XCTest currently ships inside the app target (compile-guarded, so technically safe). Smell; will surface in App Store static analysis eventually. Also unblocks running it via `xcodebuild test` without ad-hoc `OTHER_SWIFT_FLAGS`. |
| 4 | **Extend CodeQL to all four targets** (or at minimum add `ARRunnerPhone` as a second build driver), and **add `.github/dependabot.yml`** for the `github-actions` ecosystem. | S+S | Med | Phone-side WCSession currently unscanned. Dependabot is ~10 lines of YAML. |
| 5 | **SHA-pin actions in `release-testflight.yml`** (the only workflow that handles signing cert + ASC API key). Major-tag pins elsewhere are fine. | S | Med | Defense-in-depth against supply-chain compromise of the four third-party actions. Pairs naturally with Dependabot, which auto-PRs SHA bumps. |

**Honorable mentions (not top 5):**
- Add SwiftLint or SwiftFormat — currently zero style enforcement.
- Rename the two `WatchConnectivityService.swift` files to disambiguate roles.
- Amend D8 wording to cover CoreBluetooth alongside vendor SDKs.
- Watch/Phone targets have **no unit tests** — Core is well-covered (16 test files) but the app shells aren't. Acceptable while shells are thin; will get worse as `WorkoutViewModel` and `GlassesService` accumulate logic.

---

## Out of Scope (handed to Laughlin / Weiss)

- **Laughlin:** `WorkoutController` actor design quality, HealthKit substrate idioms, SwiftUI view-model patterns in `WorkoutViewModel`/`WorkoutMirrorViewModel`, App Intent shape in `StartWorkoutIntent.swift`, WCSession three-tier delivery correctness.
- **Weiss:** ActiveLook adapter BLE state machine, GATT characteristic handling, reconnect/backoff policy implementation (`ReconnectPolicy.swift` + `ExponentialBackoffTests.swift`), CoreBluetooth delegate Sendable boundary, hardware-test ergonomics on real glasses.
- **Killian (if asked):** HUD layout/preset design tradeoffs (`RunningHUDPreset.swift`, `HUDLayout.swift`).
- **Amber:** Integration test scaffolding quality and mock realism.

---

_End of audit. No code changes made — read-only per task scope._
