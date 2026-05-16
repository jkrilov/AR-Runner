# Skill: WKCompanionAppBundleIdentifier Prefix Rule

**Slug:** `wkcompanion-bundle-id-prefix-rule`
**Owner:** Laughlin (watchOS)
**Captured:** 2026-05-15T18:15:00-04:00
**Origin:** AR-Runner PR #18 (rename `com.arrunner.watch[.*]` → `com.arrunner.phone.watchkitapp[.*]`)

## Problem

When you ship a watchOS app paired with an iPhone host app, Apple enforces a **strict dotted-prefix descendancy rule** between bundle identifiers:

> The watch app's `CFBundleIdentifier` must be a strict dotted-prefix descendant of the iPhone app's `CFBundleIdentifier` (the value declared in the watch app's `WKCompanionAppBundleIdentifier` Info.plist key).

The same rule cascades to any `.appex` (widget, intent extension, etc.) embedded in either app: an extension's bundle ID must be a strict dotted-prefix descendant of its *host* app's bundle ID — *not* its sibling's host.

"Strict dotted-prefix descendant" means: split both IDs on `.`, the parent's components must be an exact prefix of the child's components, and the child must have strictly more components.

- ✅ `com.acme.phone` → `com.acme.phone.watchkitapp` (descendant; OK)
- ❌ `com.acme.phone` → `com.acme.watch` (sibling; **not** a descendant — violates the rule)
- ❌ `com.acme.phone` → `com.acme.phoneextra` (string-prefix but not *dotted*-prefix — violates the rule)

## When the failure surfaces

**Not at build time.** `xcodebuild` will happily produce non-compliant `.app` bundles. Failure modes:

1. `xcrun simctl install <watch-sim-UDID> <ARRunnerWatch.app>` exits non-zero with a message like:
   > This app's bundle identifier does not start with its parent app's bundle identifier
   > WKCompanionAppBundleIdentifier=com.acme.phone
   > watch app bundle id=com.acme.watch
2. SwiftUI Previews for the watch target fail silently / time out (Preview uses a sim install under the hood).
3. On-device install via Xcode "Run" silently fails or installs only the iPhone half of the pair.

## Canonical Apple layout

Follow Apple's own watchOS app template:

| Target                    | Bundle ID                                          |
| ------------------------- | -------------------------------------------------- |
| iPhone app (root)         | `com.acme.phone`                                   |
| Watch app                 | `com.acme.phone.watchkitapp`                       |
| Watch widget / appex      | `com.acme.phone.watchkitapp.<extension-name>`      |
| Phone widget / appex      | `com.acme.phone.<extension-name>`                  |

> Note: `.watchkitapp` is a convention, not a magic suffix — any descendant works. But matching Apple's template makes the relationship obvious to other engineers and to Apple's review tooling.

## XcodeGen recipe

In `project.yml`, set `PRODUCT_BUNDLE_IDENTIFIER` per target. Don't rely on `options.bundleIdPrefix` for anything beyond defaulting test targets — set the production IDs explicitly:

```yaml
targets:
  ARRunnerPhone:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.arrunner.phone

  ARRunnerWatch:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.arrunner.phone.watchkitapp
    info:
      properties:
        WKApplication: true
        WKCompanionAppBundleIdentifier: com.arrunner.phone  # MUST match phone target's ID exactly

  ARRunnerWidgetsWatch:        # embedded in ARRunnerWatch
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.arrunner.phone.watchkitapp.widgets

  ARRunnerWidgetsPhone:        # embedded in ARRunnerPhone
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.arrunner.phone.widgets
```

App group IDs (`group.com.arrunner.shared`) are a **separate identifier namespace** and are not subject to the prefix rule — they can be whatever you want and are shared across phone+watch via the entitlements file.

## Audit checklist when renaming bundle IDs

Run this search and triage every hit:

```bash
grep -rn "com\.<old-prefix>" --include="*.swift" --include="*.plist" \
                             --include="*.entitlements" --include="*.yml" .
```

| Location                                | Action                                                                                         |
| --------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `project.yml` / `*.xcconfig`            | **Update** — these are the canonical bundle IDs.                                               |
| `Info.plist` `WKCompanionAppBundleIdentifier` | **Update if you renamed the phone app**; verify it still points at the phone root.       |
| `Info.plist` `NSExtension` dicts        | Usually no bundle-ID values; verify.                                                           |
| `*.entitlements` app groups (`group.*`) | **Do not touch** unless intentionally renaming the group.                                      |
| `Bundle.main.bundleIdentifier` checks   | **Update** any literal comparisons.                                                            |
| WCSession peer-ID checks                | **Update** if any (rare — WCSession identifies peers via session activation, not by bundle ID).|
| Keychain access groups                  | **Update** if access group strings include the bundle ID.                                      |
| UserDefaults suite names                | **Update** if suites are named after the bundle ID.                                            |
| Test assertions on bundle IDs           | **Update**.                                                                                    |
| `Logger(subsystem: "...")` labels       | **Leave alone** by default — subsystem strings are free-form and changing them invalidates saved Console.app filters and log queries. Update only as a deliberate, separately-scoped change. |
| `DispatchQueue(label: "...")`           | **Leave alone** — labels are free-form, not bundle IDs.                                        |
| `docs/**`                               | **Leave alone** in historical / postmortem text. Update only in live "how to deploy" docs.     |

## Verification recipe (always run all four steps)

```bash
xcodegen generate
xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build
xcodebuild -project AR-Runner.xcodeproj -scheme ARRunnerPhone \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# The decisive check — only this catches WKCompanion prefix violations:
SIM_UDID=<watch-sim-UDID>
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
xcrun simctl install "$SIM_UDID" \
  ~/Library/Developer/Xcode/DerivedData/AR-Runner-*/Build/Products/Debug-watchsimulator/ARRunnerWatch.app
echo "install exit=$?"   # MUST be 0; any non-zero exit = prefix rule violation

cd ARRunnerCore && swift test  # catches any hardcoded ID in test assertions
```

If `xcodebuild` succeeds but `simctl install` fails, the bundle ID layout is wrong. If all four steps succeed, the rename is complete.

## Related skills

- `widgetkit-extension-plist-constraints` — what *not* to put in a WidgetKit appex Info.plist.
- `xcodegen-shared-widget-per-platform` — why we have separate `ARRunnerWidgetsWatch` and `ARRunnerWidgetsPhone` targets sharing one source dir (also a consequence of this prefix rule).
- `xcodegen-stale-generated-project` — always re-run `xcodegen generate` after editing `project.yml`.
