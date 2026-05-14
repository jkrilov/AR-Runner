# Skill: Swift 6 Strict Concurrency is On By Default

**Confidence:** low (first observation, 2026-05-14)
**Owner:** Richards
**Applies to:** AR-Runner (all Swift targets), any Swift 6 codebase

## The pattern

Swift 6 language mode enables `StrictConcurrency` (the upcoming-feature flag) and
`-strict-concurrency=complete` (the build setting) **by default**. Re-declaring
either is at best redundant and at worst a hard compile error.

Specifically:

| Toolchain | `.enableUpcomingFeature("StrictConcurrency")` under Swift 6 mode |
|-----------|-------------------------------------------------------------------|
| Swift 6.0 (Xcode 16 GA, CI runners) | **Hard error** — `upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6` |
| Swift 6.1 – 6.2 | Warning |
| Swift 6.3+ (latest dev toolchains) | Silently tolerated |

Result: scaffolds written on bleeding-edge toolchains pass local builds but break
on stable-Xcode CI.

## Don't do

```swift
// Package.swift, swift-tools-version: 6.0
let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("StrictConcurrency")  // redundant — Swift 6.0 = hard error
]
```

```yaml
# project.yml or .xcconfig
settings:
  base:
    SWIFT_VERSION: '6.0'
    SWIFT_STRICT_CONCURRENCY: complete  # redundant under Swift 6 language mode
```

## Do

Set the language mode and let it imply the rest:

```swift
// Package.swift
// swift-tools-version: 6.0

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let package = Package(
    // ...
    targets: [
        .target(name: "Foo", swiftSettings: strictSettings)
    ],
    swiftLanguageModes: [.v6]
)
```

```yaml
# project.yml
settings:
  base:
    SWIFT_VERSION: '6.0'
    # Strict concurrency is implicit under Swift 6 language mode.
```

## Sibling redundant upcoming-feature flags to also strip under Swift 6

If you spot any of these explicitly enabled in a Swift 6 codebase, remove them —
they're all already on by default and risk the same hard-error / warning behavior
depending on the toolchain:

- `BareSlashRegexLiterals`
- `ConciseMagicFile`
- `ImportObjcForwardDeclarations`
- `DisableOutwardActorInference`
- `IsolatedDefaultValues`
- `ForwardTrailingClosures`
- `ExistentialAny` (still optional in 6.0 — check before stripping)
- `InternalImportsByDefault` (still optional — check)

When in doubt, consult [Swift Evolution proposals](https://github.com/swiftlang/swift-evolution/blob/main/proposals/) for the specific upcoming-feature's "Implemented in" version. If the implemented version ≤ current Swift mode, the flag is redundant.

## Diagnostic signature

If CI logs show this exact error and local builds pass:

```
error: upcoming feature 'StrictConcurrency' is already enabled as of Swift version 6
```

…the diagnosis is almost certainly local-vs-CI toolchain skew on a Swift 6 project.
Grep the repo:

```bash
grep -rn "enableUpcomingFeature\|SWIFT_UPCOMING_FEATURE\|SWIFT_STRICT_CONCURRENCY" \
  --include="*.swift" --include="*.yml" --include="*.xcconfig" .
```

Strip the offending lines, regenerate any xcodeproj (`xcodegen generate`), and verify
with `swift build` + a representative `xcodebuild` invocation before re-pushing.

## Verification command

```bash
# Local pre-push check that matches CI behavior:
swift build --package-path ARRunnerCore && \
xcodebuild -project AR-Runner.xcodeproj \
  -scheme ARRunnerWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

## Evidence trail

- PR #3 / commit `350eae0` (fix)
- Decision drop: `.squad/decisions/inbox/richards-strict-concurrency-cleanup.md`
- First observed: 2026-05-14, AR-Runner project, Joe Krilov on Swift 6.3.2 local vs Swift 6.0 CI
