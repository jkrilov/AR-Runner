# TestFlight Release Setup

**Last updated:** 2026-05-16T16:11:23-04:00
**Owner:** Richards (Lead / Architect)
**Workflow:** `.github/workflows/release-testflight.yml`

This is the one-time setup guide to wire AR-Runner up to TestFlight via GitHub
Actions, plus the recurring release flow. Read it once when you set up the
secrets; consult Part C every time you cut a build.

## Architecture summary

- **Trigger:** pushing a pre-release tag `v*.*.*-*` (e.g. `v0.2.0-rc1`,
  `v0.2.0-beta3`) — or manually via the Actions tab's "Run workflow" button.
  Pure-release tags (`v0.2.0`) intentionally don't trigger this workflow; the
  App Store submission path will live in a future `release-appstore.yml`.
- **Build:** `macos-15` runner, Xcode 16.4, `xcodegen generate` → `xcodebuild
  archive` → `xcodebuild -exportArchive` → `xcrun altool --upload-app`.
- **Signing:** automatic, with Xcode pulling provisioning profiles via the App
  Store Connect API key (`-allowProvisioningUpdates`). No fastlane, no `match`,
  no manual profile management.
- **Versioning:** `MARKETING_VERSION` comes from the tag (strip the `v`),
  `CURRENT_PROJECT_VERSION` comes from `github.run_number` — monotonically
  increasing per Actions run, which satisfies App Store Connect's "build number
  must increase" rule.

### Why this approach (and what we rejected)

| Option | Why we didn't pick it |
| --- | --- |
| **fastlane `match` + `pilot`** | Heavier setup, needs a separate private git repo to store encrypted profiles, adds Ruby + a gem manifest to the repo. Overkill for a one-app pipeline. We can adopt it later if our signing footprint grows. |
| **Local Xcode Organizer upload** | Manual. Breaks Joe's "secrets stay in GitHub" requirement and isn't reproducible. Useful as a fallback if CI is wedged. |
| **Manual provisioning profiles in a secret** | Needs to be re-uploaded every time Apple rotates them or we add capabilities. The ASC API key + `-allowProvisioningUpdates` lets Xcode do this for us. |

The trade-off named: `-allowProvisioningUpdates` lets a CI job create &
download profiles for any of the team's bundle IDs. That's more privilege than
strict-mode shops want. For a single-person developer team like AR-Runner it's
the right ergonomic choice; revisit if/when more humans join the Apple team.

---

## Part A — Apple Developer Portal (one-time, manual UI work)

### A.1 Register the four App IDs

Visit https://developer.apple.com/account/resources/identifiers and create
**App ID** entries (type: App) for each of these bundle IDs. Match the
descriptions exactly — App Store Connect cares about the bundle ID, not the
description.

| Bundle ID | Description | Capabilities to enable |
| --- | --- | --- |
| `com.arrunner.phone` | AR-Runner iPhone | **HealthKit**, **App Groups** (group `group.com.arrunner.shared`) |
| `com.arrunner.phone.watchkitapp` | AR-Runner Watch | **HealthKit**, **App Groups** (`group.com.arrunner.shared`) |
| `com.arrunner.phone.widgets` | AR-Runner Widgets (Phone) | **App Groups** (`group.com.arrunner.shared`) |
| `com.arrunner.phone.watchkitapp.widgets` | AR-Runner Widgets (Watch) | **App Groups** (`group.com.arrunner.shared`) |

> When you enable App Groups for the first time, the portal will ask you to
> create the group. Use the identifier `group.com.arrunner.shared` (matches
> `project.yml`).

The watch + watch-widgets IDs follow Apple's nested-bundle rule (extensions
must be prefixed by the host app's ID — see
`.squad/skills/wkcompanion-bundle-id-prefix-rule/SKILL.md`).

### A.2 Create the App Store Connect app record

1. Go to https://appstoreconnect.apple.com/apps and click **+** → **New App**.
2. Platforms: iOS (the watch app is bundled in the iPhone app's listing).
3. Bundle ID: `com.arrunner.phone`.
4. SKU: pick anything unique (e.g. `arrunner-ios`). It's internal.
5. User Access: Full Access (default).
6. Click **Create**. Don't fill in screenshots/metadata yet — that's only
   needed for App Store review, not TestFlight.

### A.3 Create the Apple Distribution certificate

1. Go to https://developer.apple.com/account/resources/certificates and
   click **+**.
2. Pick **Apple Distribution** (NOT "iOS Distribution" — Apple Distribution is
   the modern unified type that signs for both iOS and watchOS).
3. Follow the CSR flow:
   - On your Mac: Keychain Access → Certificate Assistant → Request a
     Certificate From a Certificate Authority. Save the CSR to disk.
   - Upload the CSR to the portal.
   - Download the resulting `.cer` file.
4. Double-click the `.cer` to install it into your login keychain.
5. In Keychain Access, find **Apple Distribution: Your Name (TEAMID)** under
   **My Certificates** (it must have the private key disclosure triangle).
   Right-click → **Export…** → save as `Distribution.p12`. Set a strong
   password — you'll paste this into `BUILD_CERTIFICATE_P12_PASSWORD` below.

### A.4 Create the App Store Connect API key

1. Visit https://appstoreconnect.apple.com/access/integrations/api.
2. Click **+** to generate a new key.
3. Name: `AR-Runner CI`. Access: **App Manager** (the minimum role that can
   create profiles + upload builds).
4. Click **Generate**.
5. **Immediately download the `.p8` file** — Apple only shows it once. If you
   lose it you have to revoke and reissue.
6. Note these three values from the page:
   - **Key ID** — 10-char alphanumeric (e.g. `ABCDE12345`)
   - **Issuer ID** — UUID (e.g. `12345678-1234-1234-1234-1234567890ab`)
   - **The `.p8` file contents** — the full text including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`.

---

## Part B — GitHub Secrets

Add these under **Settings → Secrets and variables → Actions → Repository
secrets** on github.com/jkrilov/AR-Runner. Names must match exactly.

| Secret name | What it is | How to produce the value |
| --- | --- | --- |
| `APPLE_TEAM_ID` | 10-char Apple Developer Team ID | Top right at https://developer.apple.com/account, or `security find-identity -v -p codesigning` then grab the parenthesized ID. |
| `APP_STORE_CONNECT_API_KEY_ID` | The 10-char Key ID from A.4 | Copy from the ASC integrations page. |
| `APP_STORE_CONNECT_API_ISSUER_ID` | The UUID Issuer ID from A.4 | Copy from the ASC integrations page (above the keys list). |
| `APP_STORE_CONNECT_API_KEY_P8` | Full contents of the `.p8` file | `cat ~/Downloads/AuthKey_ABCDE12345.p8 \| pbcopy` then paste. Include the `BEGIN`/`END` lines. |
| `BUILD_CERTIFICATE_P12_BASE64` | Base64-encoded `Distribution.p12` | `base64 -i Distribution.p12 \| pbcopy` on macOS. Paste raw — GitHub stores it as one secret string. |
| `BUILD_CERTIFICATE_P12_PASSWORD` | Password you set when exporting the `.p12` in A.3 | Whatever you typed in the Keychain Access export dialog. |
| `KEYCHAIN_PASSWORD` | Throwaway password for the CI's temp keychain | Anything — pick a random 20+ char string. Only used inside the runner. |

### Quick CLI for the encoded values

```bash
# From the Mac that has Distribution.p12 and AuthKey_*.p8
base64 -i Distribution.p12 | pbcopy            # → BUILD_CERTIFICATE_P12_BASE64
cat AuthKey_ABCDE12345.p8 | pbcopy             # → APP_STORE_CONNECT_API_KEY_P8
LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 | pbcopy
                                                # → KEYCHAIN_PASSWORD (any random string)
```

> ⚠️ Never commit any of these values. The `.p12`, `.p8`, and team ID should
> live in GitHub Secrets only. Delete the local `.p12` and `.p8` from your
> downloads folder once they're uploaded.

---

## Part C — Cutting a TestFlight build

Once Parts A and B are done, every release is three commands:

```bash
git tag v0.2.0-rc1                # any vX.Y.Z-anything pre-release tag
git push origin v0.2.0-rc1
gh run watch                      # follow along, or open the Actions tab
```

Expected timeline:

1. **0–1 min** — workflow boots, runner provisioned.
2. **1–4 min** — Xcode selection, xcodegen, archive (first run: + 1–2 min
   while Xcode auto-creates provisioning profiles for the 4 bundle IDs).
3. **4–7 min** — export `.ipa`, upload to App Store Connect.
4. **7–20 min** — App Store Connect "processes" the build. You'll see it in
   https://appstoreconnect.apple.com/apps → AR-Runner → TestFlight → iOS Builds
   first as "Processing", then ready for testing.
5. **+ instant** — add yourself to **Internal Testing** group (do this once;
   it sticks for future builds). Open the **TestFlight** app on your iPhone,
   sign in with the same Apple ID, and the AR-Runner build appears.
6. **+ ~1 min** — install on iPhone. The paired Apple Watch picks up the
   companion watch app automatically (provided the Watch's "Automatic App
   Install" toggle is on in the iPhone's Watch app).

### Versioning rules

The workflow derives versions from the tag:

| Tag pushed | `MARKETING_VERSION` | `CURRENT_PROJECT_VERSION` |
| --- | --- | --- |
| `v0.2.0-rc1` | `0.2.0-rc1` | GitHub Actions run number (e.g. `47`) |
| `v0.2.0-beta3` | `0.2.0-beta3` | `48` (the next run) |
| `v0.2.0` | (workflow does not trigger — pure releases go through `release-appstore.yml`, not built yet) | — |

Build numbers must always increase per App Store Connect. Using
`$GITHUB_RUN_NUMBER` guarantees that even across retries on the same tag.
If you ever need to re-upload an existing tag, delete + re-push the tag
(GitHub increments `run_number` per workflow execution regardless).

### App Store releases (future, not in this PR)

When we're ready to ship a real release to the App Store, we'll add
`release-appstore.yml` that triggers on `v*.*.*` (no pre-release suffix),
mirrors the archive/export flow above, and replaces the `xcrun altool
--upload-app` step with one that also calls the App Store Connect API to
**submit the build for review**. The setup work in Parts A and B carries over
unchanged.

---

## Part D — Local development (Joe on his Mac)

Nothing in this pipeline replaces the dev loop. Your local flow:

```bash
./scripts/bootstrap-signing.sh       # one time — creates Config/Signing.xcconfig
                                     # edit it: set DEVELOPMENT_TEAM = ABCD1234EF
xcodegen generate                    # regenerate AR-Runner.xcodeproj
open AR-Runner.xcodeproj
```

In Xcode:

1. Select the `ARRunnerPhone` (or `ARRunnerWatch`) target → **Signing &
   Capabilities**.
2. **Automatically manage signing** is already on (the xcconfig sets it).
3. **Team** should auto-populate from the xcconfig. If it shows "None", drop
   down and pick your team — Xcode will write it back, but the canonical
   source is `Config/Signing.xcconfig`.
4. Build & Run as before. Xcode uses your personal Apple Developer cert (or
   Personal Team for the "Sign to Run Locally" simulator case) — no CI secrets
   needed locally.

> If you ever rerun `xcodegen generate` and Xcode complains about a missing
> `Config/Signing.xcconfig`, just run `./scripts/bootstrap-signing.sh` again.
> It's idempotent and only rewrites the file if you've passed `APPLE_TEAM_ID`
> as an env var; otherwise it leaves your existing file alone.

---

## Part E — Verification & failure-mode triage

### First-run verification (after adding the 7 secrets)

```bash
git tag v0.0.0-rc-test
git push origin v0.0.0-rc-test
gh run watch
```

A green run means the entire pipeline works. A red run usually means one of
these — fix the secret and retry by deleting + re-pushing the tag:

| Symptom | Most likely cause | Fix |
| --- | --- | --- |
| `errSecInternalComponent` during `security import` | `.p12` base64 was truncated or wrapped with line breaks GitHub stripped | Re-run `base64 -i Distribution.p12 \| pbcopy`, replace `BUILD_CERTIFICATE_P12_BASE64`. |
| `MAC verification failed during PKCS12 import` | Wrong `BUILD_CERTIFICATE_P12_PASSWORD` | Re-export the `.p12` from Keychain (A.3), set a fresh password, update the secret. |
| `Authentication credentials are missing or invalid` (during archive or upload) | Wrong API Key ID, wrong Issuer ID, or `.p8` body missing `BEGIN`/`END` lines | Re-check all three ASC secrets against the integrations page. |
| `No profiles for 'com.arrunner.phone' were found` | First archive can take 60–120s while Xcode talks to ASC to create profiles — sometimes it times out the first time | Re-run the workflow (Actions tab → re-run job). On the second run the profiles already exist and the archive completes quickly. |
| `The bundle identifier cannot be registered to your team` | App ID not yet created in the developer portal | Go back to A.1 and create the missing bundle ID. |
| `Build number X has already been used` | Re-uploading the same `run_number` (unlikely — would need a manual tag delete + workflow rerun *and* the previous attempt actually uploaded) | Push a new pre-release tag. Don't try to overwrite an accepted build. |

### Once verified

Delete the test build from App Store Connect (TestFlight → iOS Builds → trash
icon) and the throwaway tag (`git push --delete origin v0.0.0-rc-test`).

---

## File map

```
.github/workflows/release-testflight.yml   # the workflow
project.yml                                # references Config/Signing.xcconfig
scripts/bootstrap-signing.sh               # idempotent xcconfig generator
scripts/ExportOptions.plist                # template for xcodebuild -exportArchive
Config/Signing.xcconfig                    # gitignored; holds DEVELOPMENT_TEAM
docs/dev/testflight-setup.md               # this file
```
