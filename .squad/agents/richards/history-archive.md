# Richards — History Archive

**Archive created:** 2026-05-17T00:48:29Z

Summarized entries from 2026-05-14 and early 2026-05-15; see active `history.md` for recent sessions.

## 2026-05-14–2026-05-15: Foundation Architecture & CI Groundwork

**Accomplishments:**
- GitHub Remote Setup: SSH-configured, 126-file Squad scaffolding committed to `main` (fd2faad)
- CI/Simulator Runtime Matrix: Linux (ARRunnerCore purity, Swift 6.0-jammy enforcer) + macOS (Xcode 16.4 pin solved watchOS 11 runtime gap on macos-15 runner image)
- Swift 6 StrictConcurrency: Redundant `enableUpcomingFeature` flags stripped; language mode is SSOT
- System Architecture (ADR-001–007): `docs/planning/architecture.md` v0.1 delivered; D1–D9 locked by Joe
- Public-Repo Readiness: Verdict 🟡 (go after small cleanup); 5 open policy questions for Joe on LICENSE/copyright/visual-assets

**Key learnings:**
- Linux CI as architecture enforcement: Any Apple-framework leak into ARRunnerCore fails Linux build immediately
- Runner image manifest is SSOT for installed simulators/SDKs (asymmetric failures like ARRunnerPhone ✅ + ARRunnerWidgetsPhone ❌ traced to this)
- Xcode version pins ≠ simulator runtime catalog; test against CI toolchain version, not local
- `xcrun altool --upload-app` deprecated post-Xcode 15; migration planned before WWDC drop
- `@unchecked Sendable` audit pattern: all 3 production sites are NSObject + delegate bridges (canonical correct pattern)
- WCMessage `schemaVersion` guard is backward-compat but NOT forward-compat; negotiation step needed for multi-user distribution

**Non-blocking nits pending Joe's decision:**
- README hyperlink to ActiveLook website on first mention (UX for strangers)
- CONTRIBUTING.md one-liner pointing to Releases page
- Minimal CODE_OF_CONDUCT.md (GitHub community profile will flag absence)

**Reviewer rejection status:** Richards locked out of follow-up revisions on that branch per reviewer-rejection-protocol. Killian or Amber must implement nit fold-ins if Joe requests.

## Parallel Workstream Coordination (2026-05-15)

Three agents completed and opened PRs:
- **Weiss** (PR #5, `feat/ble-wrapper`): GlassesFrameTransport + ActiveLook watchOS adapter; 24 tests, CI green
- **Laughlin** (PR #7, `feat/workout-controller`): WorkoutController + HealthKit substrate; 14 tests, CI green
- **Amber** (PR #6, `feat/integration-mocks`): Integration mocks + D4 happy-path tests; 12 tests + CodeQL green

**XcodeGen stale-pbxproj incident (2026-05-15):** "Cannot find X in scope" reported for GlassesTransportFactory + ActiveLookGlassesAdapterHardwareTests; both files existed on disk. Root cause: `AR-Runner.xcodeproj/` is gitignored (generated from `project.yml`), Joe's local was simply stale. Fix: `xcodegen generate`. **Skill recorded:** `.squad/skills/xcodegen-stale-generated-project/SKILL.md`. **Lesson:** Always ask `git check-ignore AR-Runner.xcodeproj/` first before diagnosing Xcode target-membership bugs.

## Key Durable Patterns

- **Linux CI as boundary enforcement** — best architecture guard for Swift SPM projects
- **Xcode version pinning with cache** — unversioned `brew install xcodegen` breaks on format changes
- **Gitignored xcconfig + `configFiles` in xcodegen** — `bootstrap-signing.sh` required in ALL workflows, not just release
- **Runner image manifest** — SSOT for simulator catalog; match CI toolchain version locally before committing
