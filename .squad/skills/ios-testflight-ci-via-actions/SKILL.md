# Skill: iOS / watchOS TestFlight CI via GitHub Actions (no fastlane)

**When to use:** You have an Xcode project (ideally driven by XcodeGen) for an
iOS app with optional watchOS companion + WidgetKit extensions, and you want
tag-triggered TestFlight uploads from GitHub Actions without standing up
fastlane / `match` / a separate private profile repo.

**Trade-offs named up front:**
- **Pros:** Single workflow file, no Ruby toolchain, no second repo for
  encrypted profiles. Apple's own `xcodebuild -allowProvisioningUpdates` does
  the profile work via an App Store Connect API key.
- **Cons:** The API key has team-wide profile-mutation rights. Fine for a
  one-developer shop, marginal for a 20-person team where you'd want
  fastlane `match`'s explicit profile audit trail.
- **Cons:** `xcrun altool --upload-app` is on Apple's slow-deprecation track.
  Still supported in Xcode 16; swap to App Store Connect REST API or a future
  `notarytool`-style uploader if/when Apple yanks it.

---

## The seven secrets

These are the irreducible minimum. Name them in GitHub identically — the
workflow reads them by name.

| Secret | Source | Notes |
| --- | --- | --- |
| `APPLE_TEAM_ID` | developer.apple.com/account (top right) | 10 chars, alphanumeric. Semi-public, but cleaner in secrets so the workflow file stays generic. |
| `APP_STORE_CONNECT_API_KEY_ID` | appstoreconnect.apple.com/access/integrations/api | 10 chars. |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Same page, top of the keys list | UUID format. |
| `APP_STORE_CONNECT_API_KEY_P8` | The `.p8` downloaded at key creation | Full file body, includes `BEGIN`/`END` lines. Apple shows the file ONCE — re-issue if lost. |
| `BUILD_CERTIFICATE_P12_BASE64` | `base64 -i Distribution.p12 \| pbcopy` | Apple Distribution cert (not "iOS Distribution"). Export from Keychain Access **with** the private key. |
| `BUILD_CERTIFICATE_P12_PASSWORD` | Whatever you typed at export time | Random ≥ 16 chars. |
| `KEYCHAIN_PASSWORD` | Anything | Throwaway. Only used inside the runner's temp keychain. |

API key role: **App Manager** is the minimum that can create profiles + upload
builds. Don't grant **Admin**; it can change team membership.

---

## Workflow shape

```yaml
on:
  push:
    tags: ['v*.*.*-*']   # pre-release tags only — pure releases go to a separate workflow later
  workflow_dispatch:
    inputs:
      version: { required: true }

concurrency:
  group: release-testflight
  cancel-in-progress: false   # never cancel mid-upload — ASC won't recover gracefully

jobs:
  testflight:
    runs-on: macos-15
    steps:
      - checkout
      - resolve version from tag (strip leading 'v') → MARKETING_VERSION
      - use $GITHUB_RUN_NUMBER → CURRENT_PROJECT_VERSION (always-increasing)
      - select Xcode (pin a version — same logic as your debug-build workflow)
      - install xcodegen, cache SwiftPM
      - create temp keychain, import .p12 cert, set partition list, prepend to search list
      - install .p8 to ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
      - write Config/Signing.xcconfig from APPLE_TEAM_ID
      - xcodegen generate
      - render ExportOptions.plist (substitute teamID)
      - xcodebuild archive -allowProvisioningUpdates \
          -authenticationKeyID/-IssuerID/-Path  (ASC API key flags)
          DEVELOPMENT_TEAM=$APPLE_TEAM_ID
          MARKETING_VERSION=... CURRENT_PROJECT_VERSION=...
      - xcodebuild -exportArchive (same -authenticationKey* flags, ExportOptions.plist)
      - xcrun altool --upload-app --apiKey $KEYID --apiIssuer $ISSUER --file path.ipa
      - upload .ipa as artifact (always); upload .xcarchive on failure
      - delete temp keychain & .p8 (always-run cleanup)
```

---

## The `DEVELOPMENT_TEAM` problem (and the xcconfig pattern that solves it)

Apple's automatic signing requires every target to know its team. You don't
want to hardcode the team ID in `project.yml` (it's not secret, but committing
it makes the repo less portable + couples reviews to one team's lifecycle).

Pattern that works for both local and CI:

1. `project.yml` declares
   ```yaml
   configFiles:
     Debug: Config/Signing.xcconfig
     Release: Config/Signing.xcconfig
   ```
2. `Config/` is gitignored (often already is, because xcodegen writes plists +
   entitlements there).
3. A small `scripts/bootstrap-signing.sh` creates the xcconfig idempotently.
   If `APPLE_TEAM_ID` is in the env, it writes that team in; otherwise it
   creates the file with an empty `DEVELOPMENT_TEAM =` (which local Xcode lets
   you fill in via the Signing & Capabilities dropdown).
4. CI runs the script with the secret as env: `APPLE_TEAM_ID=$SECRET
   ./scripts/bootstrap-signing.sh` before `xcodegen generate`.
5. Local devs run `./scripts/bootstrap-signing.sh` once, then edit
   `Config/Signing.xcconfig` to add their team. The file is gitignored so it
   stays personal.

The xcconfig also sets `CODE_SIGN_STYLE = Automatic` so the same
`DEVELOPMENT_TEAM` line covers the whole project's automatic signing
configuration in one place.

---

## ExportOptions.plist template

Commit a template at `scripts/ExportOptions.plist` with a `__APPLE_TEAM_ID__`
placeholder; the workflow does a `sed` substitution into a build/-local copy.

Key entries:
```xml
<key>method</key>            <string>app-store-connect</string>
<key>signingStyle</key>      <string>automatic</string>
<key>teamID</key>            <string>__APPLE_TEAM_ID__</string>
<key>uploadSymbols</key>     <true/>
<key>stripSwiftSymbols</key> <true/>
```

> `app-store-connect` is the modern method name — `app-store` still works but
> is the legacy alias as of Xcode 15+.

---

## Bundle IDs to register up front

For an iPhone + watchOS + widgets app you'll need **four** App IDs registered
in the Apple Developer portal before the first archive succeeds. The watch
nested IDs are mandatory — Apple validates that an embedded extension's bundle
ID is a strict prefix of its host's. See
`.squad/skills/wkcompanion-bundle-id-prefix-rule/SKILL.md` for the longer
explanation.

Example for AR-Runner:
- `com.arrunner.phone`                       (iPhone host)
- `com.arrunner.phone.watchkitapp`           (Watch app)
- `com.arrunner.phone.widgets`               (Phone widget appex)
- `com.arrunner.phone.watchkitapp.widgets`   (Watch widget appex)

Enable capabilities at registration time — adding them later requires
regenerating profiles, which `-allowProvisioningUpdates` does, but it's faster
to do it once up front. For HealthKit apps: turn on **HealthKit** on both
host App IDs and **App Groups** on all four (so the shared group exists when
Xcode auto-creates profiles).

---

## Common first-run failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| `MAC verification failed during PKCS12 import` | Wrong `.p12` password in secret | Re-export `.p12`, set a known password, update secret. |
| `errSecInternalComponent` | `.p12` base64 corrupted | Re-encode with `base64 -i Distribution.p12`. |
| `Authentication credentials are missing or invalid` | `.p8` body missing `BEGIN`/`END` lines, or wrong Key ID/Issuer ID | Re-paste the entire .p8 file body verbatim. |
| `No profiles for 'com.x.y' were found` (first run) | Xcode is still creating the profile — sometimes times out the first time | Re-run the job. Second run finds the profile already in ASC. |
| `The bundle identifier cannot be registered to your team` | App ID not registered in the portal | Create it at developer.apple.com/account/resources/identifiers. |

---

## Versioning that "just works"

```bash
TAG="${GITHUB_REF#refs/tags/}"
MARKETING_VERSION="${TAG#v}"           # v0.2.0-rc1 → 0.2.0-rc1
CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER"  # always increasing, unique
```

Pass these as `xcodebuild` build settings; don't rely on what's in
`project.yml`. This way ASC's "build number must increase" rule is satisfied
automatically even across retries.

---

## What's intentionally NOT in this skill

- **App Store release (not TestFlight):** Add a sibling
  `release-appstore.yml` on `tags: ['v*.*.*']` (no pre-release suffix) that
  reuses the same archive/export steps and adds a final ASC REST API call to
  submit the build for review. Don't try to overload one workflow for both
  paths — TestFlight needs zero review, App Store needs review metadata.
- **Code-signing reproducibility audits:** If you need to prove which cert
  signed which build, switch to fastlane `match` or store the profile UUIDs
  per build in your release notes. `-allowProvisioningUpdates` trades
  auditability for ergonomics.
- **Notarization:** Not applicable to iOS / watchOS App Store apps. (It's a
  Mac-only flow.)
