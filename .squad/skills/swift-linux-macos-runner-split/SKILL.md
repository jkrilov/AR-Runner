# Skill: Swift CI — Linux + macOS Runner Split

**Captured by:** Richards
**Date:** 2026-05-14T16:51:53-04:00 (initial); updated 2026-05-14T17:21:00-04:00
**Context where it emerged:** AR-Runner CI workflow design (`chore/ci-workflows`)
**Confidence:** medium (pattern applied + watchOS-runtime gotcha confirmed in CI)

## When to use this pattern

You're building CI for a Swift project that has:
- A **pure-Swift shared core** as an SPM package (imports `Foundation` + `XCTest` only; no `UIKit`, `AppKit`, `WatchKit`, `HealthKit`, `CoreBluetooth`, `WatchConnectivity`).
- **One or more Apple-platform app/extension targets** that build via `xcodebuild` (watchOS, iOS, macOS, etc.) and naturally depend on Apple frameworks.

macOS GitHub runners are billed at roughly 10x Linux. If you run every job on macOS, you're paying that premium for tests that don't need Apple frameworks.

## The pattern

Run the SPM test job on the **open-source Swift toolchain on Linux**, and reserve macOS runners for `xcodebuild` of the app/extension targets.

### Linux core-tests job (sketch)

```yaml
jobs:
  swift-test:
    runs-on: ubuntu-latest
    container:
      image: swift:6.0-jammy   # match your swift-tools-version
    defaults:
      run:
        working-directory: SharedCore
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: |
            SharedCore/.build
            ~/.cache/org.swift.swiftpm
          key: spm-linux-${{ hashFiles('SharedCore/Package.swift', 'SharedCore/Package.resolved') }}
      - run: swift build --build-tests
      - run: swift test --skip-build
```

### macOS app-build job (sketch)

```yaml
jobs:
  xcodebuild:
    runs-on: macos-15
    strategy:
      fail-fast: false
      matrix:
        scheme: [AppA, AppB, ExtensionA, ExtensionB]
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s /Applications/Xcode_16.app/Contents/Developer
      - uses: actions/cache@v4
        with:
          path: |
            ~/Library/Caches/org.swift.swiftpm
            ~/Library/Developer/Xcode/DerivedData
          key: deriveddata-${{ matrix.scheme }}-${{ hashFiles('project.yml', 'SharedCore/Package.swift') }}
      - run: |
          xcodebuild -project YourApp.xcodeproj -scheme ${{ matrix.scheme }} \
            -destination 'generic/platform=...Simulator' \
            -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Trade-offs (name them explicitly)

1. **The Core *must* stay platform-agnostic.** If anyone imports `HealthKit`, `WatchKit`, `UIKit`, `AppKit`, `WatchConnectivity`, or `CoreBluetooth` into the Core, the Linux job fails. **This is a feature, not a bug** — it mechanically enforces the architectural rule "shared Core has no Apple-framework dependencies." The CI failure is the architecture review.

2. **Two toolchain images to keep in sync.** The Linux `swift:X-jammy` container version must match the `swift-tools-version` declared in `Package.swift`. Drift causes confusing failures. Pin both.

3. **SwiftPM `platforms:` declaration is NOT a Linux exclusion.** Many people mis-read `platforms: [.iOS(.v18), .watchOS(.v11)]` as "this package only builds on iOS and watchOS." It's actually a minimum-version constraint for those Apple platforms; Linux is unrestricted. Trust the imports, not the manifest.

4. **`@preconcurrency import` of vendor SDKs must stay in app shells, not in Core.** If the Core needs to *reference* a vendor SDK, define a protocol in Core, conform to it in the app target. Linux core-tests then keep working even when the vendor SDK is Apple-only.

5. **Caching is per-runner-OS.** Linux SwiftPM caches live at `~/.cache/org.swift.swiftpm` + `<pkg>/.build`; macOS Xcode-resolved SPM lives at `~/Library/Caches/org.swift.swiftpm` + `DerivedData/**/SourcePackages`. Don't try to share keys across OSes.

## watchOS gotcha: SDK ≠ simulator runtime on `macos-15`

The GitHub `macos-15` image ships Xcode 16 with the watchOS 11 **SDK** but **not**
the watchOS 11 **simulator runtime**. Symptoms are asymmetric and confusing:

- **App scheme** (`type: application`, `platform: watchOS`) targeting
  `-destination 'generic/platform=watchOS Simulator'` fails destination
  resolution: `xcodebuild: error: ... watchOS 11.0 is not installed`. The
  scheme's destination matcher rejects the generic simulator spec because no
  installed simulator runtime backs it.
- **Widget extension scheme** (`type: app-extension`, `platform: watchOS`) on
  the **same destination spec** **succeeds** — and even builds the watchOS app
  as a transitive dependency. The extension scheme's destination resolver is
  more lenient (SDK-only build is enough; no runtime probe).

The destination string is correct in both cases. The fix is to install the
runtime on watchOS matrix cells:

```yaml
- name: Install watchOS simulator runtime
  if: contains(matrix.destination, 'watchOS')
  run: sudo xcodebuild -downloadPlatform watchOS
```

Adds ~3–5 min per watchOS cell. Cheaper alternatives — pinning `Xcode_16.x.app`
that bundles the runtime, or `maxim-lobanov/setup-xcode@v1` — are runner-image
dependent and brittle. The `-downloadPlatform` step is portable and survives
runner image churn.

**Same pattern applies to** any platform where Apple ships the SDK separately
from the simulator runtime (visionOS commonly, tvOS occasionally on minor
Xcode bumps). Gate the install step on the destination string.

**Do not "fix" this by changing the destination to `platform=watchOS` (real
device)** — that builds for arm64 device but loses simulator coverage and
breaks any future `xcodebuild test` use. Keep the destination as
`generic/platform=watchOS Simulator`; install the runtime instead.

## Concurrency / cost notes

- Use `concurrency: { group: ..., cancel-in-progress: ${{ github.event_name == 'pull_request' }} }`. Cancel rapid-fire PR pushes; never cancel `main`.
- `fail-fast: false` on the macOS matrix so one platform's breakage doesn't mask another's.
- CodeQL only needs **one** scheme to build — pick the largest dependency closure and skip the rest. Re-running Swift CodeQL across a full matrix is expensive and rarely changes the result.

## Anti-pattern to avoid

Running `swift test` on macOS "just to be safe" while you also run `xcodebuild`. The macOS `swift test` adds no signal beyond what `xcodebuild test` would already give you (when you wire that up), and it burns macOS minutes for tests that Linux would run for free.

## Reference implementation

`.github/workflows/ci-core-tests.yml`, `.github/workflows/ci-build.yml`, `.github/workflows/codeql.yml` in the AR-Runner repo. Decision rationale in `.squad/decisions/inbox/richards-ci-architecture.md` (or the merged entry in `.squad/decisions.md` after Scribe runs).
