# 2026-05-14T21:12:05Z — CI Strict Concurrency Fix

## Event

PR #3 (chore/ci-workflows) first real CI run caught hard error on Swift 6.0 CI:
> error: upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6

## Root Cause

Scaffold included redundant strict-concurrency opt-ins:
- `ARRunnerCore/Package.swift`: `.enableUpcomingFeature("StrictConcurrency")`
- `project.yml`: `SWIFT_STRICT_CONCURRENCY: complete`

Swift 6 language mode enables strict concurrency by default. Flags are redundant and hard-fail on Swift 6.0 CI. Local Swift 6.3.2 silently accepted them.

## Resolution

Richards removed both flags (350eae0). Local verification: `swift build` + `xcodebuild ARRunnerWatch` both succeeded. Committed 39bfa07 (decision + history + skill).

## Team Lesson

**Toolchain-version gap:** Local development may run ahead of CI. Deprecated flags, newly-deprecated syntax, or removed features can silently work locally but hard-fail CI. **Treat CI as the authoritative compiler.** When importing examples, strip redundant feature flags — especially `.enableUpcomingFeature("StrictConcurrency")`.

## Next

PR #3 CI re-running. Watch for green after fix lands.
