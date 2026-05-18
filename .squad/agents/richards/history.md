# Richards — History (Summarized)

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead
- **Joined:** 2026-05-14T18:30:31.650Z

## Active Learnings (Current)

### 2026-05-18T13:23Z — rc12→rc15: TestFlight campaign COMPLETE. macos-26 runner + Xcode 26.4 SDK + Watch validation fixes.

**What happened (rc12):** Joe identified the permanent fix for the SDK validation gate that blocked rc11. Apple now requires apps be built with the iOS 26 SDK. The `macos-15` runner only has Xcode 16.4 (iOS 18.5 SDK). Switched `release-testflight.yml` to `runs-on: macos-26` + `XCODE_VERSION: '26.4'` (pinned via `maxim-lobanov/setup-xcode@v1`). The `macos-26` runner is **GA** (actions/runner-images#13739), ships Xcode 26.0.1 through 26.5-beta, defaults to 26.2. We pin 26.4 (latest stable). PR #31 merged, CI green.

**rc12 upload failure (ITMS-90474):** Archive/export succeeded with iOS 26.4 SDK — first time past the SDK gate. Upload reached App Store Connect but server-side validation rejected the binary: missing `UIInterfaceOrientationPortraitUpsideDown` for iPad multitasking. Phone target defaults to `TARGETED_DEVICE_FAMILY=1,2` (iPhone+iPad), so Apple requires all four orientations. Fixed in PR #34 (rc13 tag).

**rc14 upload failure (3 Watch errors):** PR #36 (Laughlin) embedded the Watch app companion into the iOS bundle. Three new server-side validation errors appeared:
- **ITMS-90391:** Missing Icons — Watch app had no asset catalog.
- **ITMS-90713:** Missing `CFBundleIconName` in Watch bundle.
- **ITMS-90362:** Invalid `UIBackgroundModes` value `workout-processing` — **Apple removed this in watchOS 11.** Apps must migrate to the Background Tasks API (`CKWorkoutBackgroundTask`).

Fixed all three in PR #38 (rc15 tag): added `ARRunnerWatch/Assets.xcassets/AppIcon.appiconset` with 1024px icon, added `CFBundleIconName: AppIcon` to Watch Info.plist, removed `workout-processing` from `UIBackgroundModes`.

**rc15 result: ✅ UPLOAD SUCCEEDED.** Full pipeline green — archive, export, upload to App Store Connect, artifact upload. Build is now processing for TestFlight. Campaign complete after 15 RCs.

**Key findings on macos-26 runner:**
- GA, not preview (despite expectations). Apple Silicon arm64.
- Ships Xcode 26.0.1, 26.1.1, 26.2 (default), 26.3, 26.4.1, 26.5 (beta).
- `maxim-lobanov/setup-xcode@v1` needed to pin from default 26.2 → 26.4.
- Manual signing chain (temp keychain, cert import, ASC API key, PROVISIONING_PROFILE_SPECIFIER) is fully arch-agnostic — zero changes needed.
- Known flaky: `ARRunnerWidgetsWatch` CI job intermittently can't find `generic/platform=watchOS Simulator` destination. Passes on retry sometimes. Not a blocker for release workflow (which uses `generic/platform=iOS` for archive).

**Durable rule:** *When Apple changes SDK requirements, first check the runner-images repo for GA images — don't assume preview.*

### 2026-05-18T00:45Z — rc10: TF-17. Archive finally succeeded; export failed on a separate signing pass. ExportOptions.plist needs its own `provisioningProfiles` map.

**What happened:** TF-16 (rc10 tag) worked — the archive built cleanly for the first time in nine rcs. Per-target `PROVISIONING_PROFILE_SPECIFIER` + `-allowProvisioningUpdates` + the ASC API key fetched the four App Store distribution profiles from App Store Connect at archive time and signed every bundle. Then the very next step, `xcodebuild -exportArchive`, blew up with `Cloud signing permission error` and `No profiles for 'com.arrunner.phone' were found`. Same job, same keychain, same API key, same secrets — but a brand-new failure mode that the previous nine rcs had never reached because Archive had always died first.

**Root cause:** `xcodebuild -exportArchive` does not inherit signing configuration from the archive it's processing. It re-resolves signing from scratch using **only** the file passed to `-exportOptionsPlist`. `ExportOptions.plist` had `signingStyle = automatic` and no `provisioningProfiles` map, so xcodebuild fell through to Apple's "cloud signing" pathway (Xcode Cloud), which fails on a generic runner with no Xcode Cloud entitlement. The "Cloud signing permission error" string is xcodebuild's confusing way of saying *"automatic style, tried cloud, no entitlement, no local fallback map"*. The "No profiles for <bundle id>" line that follows is technically true (no usable profile at export time) but reads as if the archive itself had no profiles — which is the opposite of what actually happened.

**Fix:** Surgical. Updated only `scripts/ExportOptions.plist` to use `signingStyle = manual` plus a four-entry `provisioningProfiles` dict mapping each bundle ID to its App Store Connect profile name (matching `PROVISIONING_PROFILE_SPECIFIER` in `project.yml`). Added a 12-line documentation comment on the workflow's `Prepare ExportOptions.plist` step explaining the export-vs-archive signing split. Did NOT touch project.yml, the archive command, cert handling, or anything else. Profile names are now duplicated across project.yml and ExportOptions.plist; called out the constraint in both files; deferred centralization (low value, real risk, three sources is the soft cap before refactoring).

**🪦 The reasoning lesson:** *"the archive succeeded so signing is fine"* is a category error. Archive signing and export signing are **two independent resolution passes** that share some inputs (cert in keychain, ASC API key) but consult **different configuration sources** (build settings + xcconfig for archive; `-exportOptionsPlist` only for export). I had vaguely assumed export would inherit from the archive bundle's signed metadata — it does not. xcodebuild treats export as a fresh signing job that happens to take an already-built archive as input.

**Durable rule (going to my pre-commit checklist as item #5):** *"When I fix a build/CI step that has never previously succeeded, what's the NEXT step downstream and have I verified its preconditions?"* — TF-16's success unmasked an entirely latent defect in TF-17 territory. The signing onion has at least two layers (archive + export) and any "first time this step ran" is also "first time downstream steps are exercised." This is the inverse of the silence-as-success family from TF-12/TF-13/TF-16: those were *"the tool returned, did it do the thing?"*; this is *"the upstream tool finally worked, what's now the new critical path?"*

**Sub-lesson on error-string archaeology:** "Cloud signing permission error" had nothing to do with Apple account permissions or cloud accounts. It was xcodebuild's transliteration of "automatic signingStyle defaulted to cloud, cloud was unavailable, no manual fallback configured." Apple's CLI error strings often describe the **last thing that was tried** rather than the **misconfiguration that caused the cascade**. Treat them as crime-scene evidence (what happened last), not as forensic conclusions (why).

**Pivot timing reflection:** I did NOT do speculative work this round. Read the error, recognized the export-vs-archive split immediately (Apple docs are unambiguous on this), proposed the canonical fix, shipped. No new traps invented mid-flight, no layering of additional cleverness. After nine rcs of compounded onion-peeling, the discipline of *"is the fix described in the official manual? then ship that exact fix"* is paying off. Save the speculation budget for problems that aren't already solved.

**Decision:** D-RICHARDS-TF-17 (inbox) — names this trap; ships as PR for rc11.

**Artifacts:** branch `fix/v02-rc10-export-options-profiles`, PR (URL pending), decision inbox `richards-tf-rc10-export-options.md`, SKILL.md (new trap section: "exportArchive signing is resolved from ExportOptions.plist, NOT from the archive's build settings"), this history entry.

---

### 2026-05-18T00:35Z — rc9: TF-15 shipped but was vacuous. `fastlane sigh download_all --platform ios` silent-zero trap; pivoted to PROVISIONING_PROFILE_SPECIFIER.

**What happened:** My TF-15 fix (rc8 — `fastlane sigh download_all` to install the four manual App Store distribution profiles onto the runner) merged and tagged as rc9. The sigh step exited code 0, looked healthy in the run log. Archive then failed with the **byte-identical** "requires a provisioning profile with the <X> feature" error from rc5–rc7. The smoking gun was buried two lines below sigh's success message:

```
Installed provisioning profiles:
total 0
drwxr-xr-x  2 runner  staff  64 May 18 00:28 .
```

**sigh downloaded zero profiles.** The directory was empty. The TF-15 falsifier explicitly named this case ("if rc8 fails identically AND `ls -la` shows the profiles present, the 3-way-error model is incomplete — open TF-16"). It triggered on the OTHER half: `ls -la` showed empty. So the TF-14 diagnosis (cause #3: no profile on disk) was correct all along; my TF-15 implementation just didn't actually fix it.

**Root cause (likely, not exhaustively probed before pivot):** sigh 2.233.0's `--platform ios` filter excludes profiles whose `Platform` array is `[iOS, xrOS, visionOS]` — which is the default for modern App Store Connect profiles minted against iOS-family App IDs. sigh expected an exact-match primary platform. Other candidate causes (api_key_path JSON format edge cases, App Store profile scope quirks without `--app-identifier`) were not falsified; I pivoted instead of layering.

**Pivot (TF-16):** Drop the sigh step. Pin `PROVISIONING_PROFILE_SPECIFIER` per target in `project.yml` under `configs.Release` only (leaving Debug untouched so local Automatic-signing dev keeps working). Manual signing + `-allowProvisioningUpdates` + a valid App Manager ASC API key — all already in force from earlier rcs — gives xcodebuild everything it needs to fetch named profiles directly from App Store Connect at archive time. No local install step, no fastlane dependency, no platform-filter trap. Trade-off: profile names become coupled to App Store Connect display names; renaming a profile breaks the build until `project.yml` is updated. Documented in comments on both the workflow and project.yml.

**🪦 The big reasoning lesson:** *I treated a clean exit code as a non-vacuous outcome.* My TF-15 step did `ls -la "$PROFILES_DIR"` for debug visibility but didn't assert on the count. The "total 0" line was right there in the rc9 log, mocking me. The sigh step's `set -euo pipefail` was honored, sigh returned 0, the step passed — and the next step failed for a reason that looked like the same old error string. Exit codes describe a tool's internal happy path; they do **not** describe whether the tool produced the artifact the next step needs.

**Durable rule (going to my pre-commit checklist as item #4):** *"Am I treating a clean exit as a non-vacuous outcome?"* — After every "fetch N things from an API" step in CI, assert on the artifact count. `find … | wc -l` with an explicit `[[ "$count" -gt 0 ]] || exit 1` turns vacuous success into loud failure. This is the third member of the "silence ≠ success" family: TF-12 was "absence of error log ≠ success," TF-13 was "unfalsifiable diagnosis ≠ confirmed diagnosis," TF-16 is "clean exit ≠ produced artifact." All three are the same family — *the tool returned, but did it do the thing you needed?*

**Secondary lesson (pivot timing):** I didn't try to debug sigh further before pivoting. Could have dropped `--platform`, upgraded to fastlane 2.234.0, or written a curl-against-ASC-REST script. Decided not to: every one of those keeps a moving part the system didn't need in the first place. We've been chasing layers in the signing onion all night (rc1→rc9). The right reflex when a dependency fails opaquely AND a simpler native path exists is to remove the dependency, not debug it. Layered fixes compound brittleness; removing a layer reduces failure surface area.

**Decision:** D-RICHARDS-TF-16 (inbox) — supersedes TF-15 implementation, confirms TF-14 diagnosis.

**Artifacts:** Decision inbox file, SKILL.md new trap section ("`fastlane sigh download_all` exits 0 with zero profiles installed"), updated previous trap's "Fix" section (Option A failed, Option B is now chosen), this history entry.

---

### 2026-05-17T23:25Z — rc7: TF-13 also wrong. The error string is 3-way ambiguous; stop guessing causes, start probing axes.

**What happened:** Joe's ASC API key was already App Manager (TF-13 disconfirmed). He fell to Option B and manually pre-created all four App Store Distribution profiles in the portal. rc7 failed with the **byte-identical** error as rc5 and rc6: `"<Target>" requires a provisioning profile with the <Capability> feature`.

**The real meta-lesson:** that error string is **not a diagnosis, it is a symptom**. It is emitted whenever xcodebuild's candidate-profile set has no member satisfying (bundleID ∧ entitlements ∧ available cert). At least three distinct root causes collapse to the same string: (1) App ID lacks the capability so any profile minted/created lacks the entitlement; (2) profile has the entitlement but its `DeveloperCertificates` doesn't include the cert in the signing keychain; (3) no profile at all (mint failed silently). My TF-11, TF-12, TF-13 chain treated successive iterations of this error as evidence for successively new mechanisms when actually each iteration was **the same insufficiency** — I was picking causes without probing whether the previous fix actually changed the candidate-set state.

**Durable rule (high confidence):** When `requires a provisioning profile with the <X> feature` appears, do NOT propose a cause. **Probe.** Two axes, every time: (1) App ID capability ground truth in the portal; (2) `.mobileprovision` byte-level ground truth via `security cms -D -i <file>` (reveals both `Entitlements` and `DeveloperCertificates`). The error itself contains no signal that disambiguates them; the build log will not help. Don't pattern-match on the string — instrument the truth.

**Sub-rule on UI recall:** When a user reports "I just configured X in the portal," that is not ground truth, it is recall. Apple's portal has multiple App-Groups surfaces, silent Save no-ops on lost modals, and per-App-ID-vs-global checkbox confusion. Always trust the downloaded profile bytes over user recall, especially when their recall is freshly biased toward "I just did the thing."

**Reasoning hygiene I'm adding to my pre-commit-decision checklist:**

1. *"Am I treating silence as success?"* (from TF-12 retraction — still in force)
2. *"Is my diagnosis falsifiable in practice by one cheap probe?"* (from TF-13 retraction — still in force)
3. **NEW from TF-14:** *"Could the error string I'm reading actually be ambiguous between multiple causes? If so, what probe disambiguates, and have I asked for it BEFORE proposing a fix?"* — Three iterations of misdiagnosis is the signature of pattern-matching on a string that has more than one preimage.

**Decision:** D-RICHARDS-TF-14 (inbox) — refines TF-11; retracts TF-13. Proposes one-click portal probe with contingent profile-bytes fallback. Critically, the decision *itself* names what would falsify it (if both probes return clean and rc8 still fails identically, TF-14 is wrong and I escalate to TF-15 with a workflow instrumentation change rather than another speculative cause).

**Artifacts:** Decision inbox file, SKILL.md (new trap section: "requires a provisioning profile with the <X> feature is a 3-way error"), this history entry.

---

### 2026-05-17T23:16Z — rc6 corrected: API key role insufficient (TF-12 retracted; reasoning lesson logged)

**What happened:** My TF-12 diagnosis (cached stale Distribution profiles being reused by `-allowProvisioningUpdates`) was **wrong**. Joe checked the portal Profile list with the correct team selected — it is **empty**. There is nothing to reuse. The reuse-if-present semantic is real but is not the trap firing here.

**Corrected root cause (high confidence):** The App Store Connect API key in `APP_STORE_CONNECT_API_KEY_ID` likely has the **Developer** role. `-allowProvisioningUpdates` mints Distribution profiles via the App Store Connect REST API, and that endpoint is role-gated — Developer can read profiles but cannot create them. xcodebuild surfaces the underlying 403 as the generic "requires a provisioning profile with the <Capability> feature" error, indistinguishable at the build-log layer from the rc5 App-ID-capability bug. Fastlane docs and Apple's roles reference both explicitly require **App Manager** or **Admin** for profile creation.

**Joe's action:** Check role at <https://appstoreconnect.apple.com/access/integrations/api>. If Developer → generate new App Manager key, rotate three GH secrets (`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`), retag rc7. If already App Manager → fall back to manually pre-creating one App Store Distribution profile per bundle ID in the portal.

**Trade-off named:** App Manager key has wider blast radius than "manage profiles only" — Apple does not offer the fine-grained role. For a solo project, fine. In a multi-team org, isolate to a dedicated build-automation user.

**🪦 Reasoning lesson (the big one):** TF-12 failed because **I treated "no error logged for X" as "X succeeded."** Specifically, the rc6 log mentioned only iOS targets failing, and I built a whole "asymmetric Watch-pass / iOS-fail" diagnostic fingerprint on top of that — concluding the Watch path was minting profiles correctly. But `xcodebuild archive` has stop-at-first-error semantics: it aborts the moment any target fails. The Watch targets may have **never been reached**. I had zero positive evidence they succeeded. That entire line of reasoning was air.

**Durable rule for myself (not just signing):** When a tool fails fast / stops at first error, *absence of evidence is not evidence of absence*. Before claiming asymmetric behavior across pipeline stages, demand a log line that **affirmatively** confirms the supposedly-passing stage ran. If you can't point at it, you don't have evidence — you have a hypothesis dressed up as a fingerprint. This applies to xcodebuild, `swift build`, `ld`, `codesign`, test runners, CI pipelines, and most build systems. Add this to my pre-commit-decision checklist: "Am I treating silence as success?"

**Secondary lesson:** When a diagnosis is unfalsifiable in practice (TF-12 asked Joe to revoke profiles that didn't exist, which would have "worked" by silently doing nothing, and rc7 would have still failed identically — leaving us no closer to truth), it's a tell that the model is under-constrained. The corrected diagnosis is falsifiable: Joe checks the role; if App Manager, my hypothesis is wrong and we move on.

**Decision:** D-RICHARDS-TF-13 (inbox), supersedes TF-12, refines TF-11 (which is still correct and still in force).

**Artifacts:** Decision inbox file, SKILL.md (retraction of the rc6 "asymmetric fingerprint" + new corrected entry on API key role), this history entry. Citations: Apple roles reference + fastlane App Store Connect API permissions doc — both authoritative, both converge.

---

### 2026-05-17T23:09Z — [RETRACTED] rc6 archive trap: `-allowProvisioningUpdates` reuses cached profile (DISCONFIRMED)

**Root cause:** Apple's profile resolution for `-allowProvisioningUpdates` is **create-if-missing, reuse-if-present**. When an App Store distribution profile already exists for a bundle ID (cached server-side at Apple from earlier rc attempts), the flag reuses it as-is — it does NOT reconcile against the current `.entitlements`. So a capability added to the App ID *after* the profile was first minted is invisible to subsequent archives until the cached profile is revoked.

**Diagnostic fingerprint:** rc6 failed on the two iOS targets (`com.arrunner.phone`, `com.arrunner.phone.widgets`) but **succeeded** on the two Watch targets (same workflow, same API key, same flag, same capability fix). The asymmetry is the smoking gun: Watch targets had no pre-existing profile so the freshly-minted one inherited current capabilities; iOS targets had stale profiles from rc1–rc5 attempts that pre-dated D-RICHARDS-TF-11's capability fix.

**Durable rule (high confidence):** "When archive errors are identical to rc5 (`requires a provisioning profile with the <Capability> feature`) *despite* the App ID having the capability enabled, the trap is a cached pre-existing distribution profile that Apple keeps reusing. Fix: revoke the affected profile(s) in the portal so `-allowProvisioningUpdates` is forced into the create-if-missing path on the next archive."

**Trade-off named:** Manual portal revoke is one click per affected bundle ID; very easy this time but recurs on every future entitlement change. Alternatives (fastlane sigh --force in CI, fastlane match) trade automation for a fastlane dependency + extra moving parts. Acceptable for a solo project with quarterly-rate entitlement churn; revisit if it recurs more than once more.

**Decision:** D-RICHARDS-TF-12 (inbox). No code change. Joe revokes the two iOS distribution profiles for `com.arrunner.phone` and `com.arrunner.phone.widgets` in the portal; I retag rc7. Watch profiles stay (they're correct).

**Refinement to D-RICHARDS-TF-11:** TF-11 said "just enable capability, then re-archive." That's necessary but not sufficient when a stale profile exists. The full rule is "enable capability AND revoke any pre-existing distribution profile for that bundle ID."

**Artifacts:** Decision inbox file, SKILL.md (6th distinct trap class), this history entry. Web research cited: Stack Overflow + fastlane sigh `--force` semantics confirming reuse-by-default behavior.

---

### 2026-05-17T21:54Z — rc5 archive trap: provisioning profiles lack required capabilities when App IDs in developer portal don't declare them

**Root cause:** `-allowProvisioningUpdates` + ASC API key mints Apple Distribution profiles on demand, but **only for capabilities already enabled on the App ID itself** in developer.apple.com.

**Durable rule (high confidence):** "Manual-signed CLI archive errors of the form `<Target> requires a provisioning profile with the <Capability> feature` mean the App ID in the developer portal does not have that capability enabled. Fix in the portal; do not touch the workflow."

**Trade-off named:** App ID capability state lives outside the repo (invisible to code review). Mitigation: pre-flight runbook checklist: "before any rc tag, verify App ID capabilities match entitlements files."

**Decision:** D-RICHARDS-TF-11 (inbox). No code change — Joe enables capabilities in portal, then retags rc6.

**Artifacts:** Decision inbox, SKILL.md update (5th distinct trap class, all with high confidence).

---

### 2026-05-17 — rc4 archive trap: xcconfig identity + project-base `CODE_SIGN_STYLE=Automatic` creates conflict

**Root cause (dual bug):**
1. CLI `xcodebuild archive + CODE_SIGN_STYLE=Automatic` always resolves identity to `Apple Development`, treating xcconfig's Distribution pin as conflicting manual override.
2. xcodegen bakes `CODE_SIGN_STYLE = Automatic` into project-level pbxproj, **higher precedence than xcconfig**, so xcconfig Manual setting is silently ignored.

**Durable rule (high confidence):** Use Manual signing with Apple Distribution identity, both in xcconfig. Automatic signing for CLI archive is a four-iteration trap (rc1→rc4); Manual works on the first try.

**Fix:** PR #26 — remove `CODE_SIGN_STYLE` from project.yml (set to `$(inherited)`), append `CODE_SIGN_STYLE = Manual` + Distribution identity to release xcconfig.

**Artifacts:** PR #26 (merged), SKILL.md update (4th distinct trap class), testflight-setup.md doc update.

---

### Summary of prior rc failures (rc1–rc3)

| RC | Root Cause | Fix |
|----|-----------|-----|
| rc1 | CLI missing identity → Development default → "no devices" error | Add explicit identity on CLI |
| rc2 | xcodebuild CLI doesn't support `SETTING[sdk=...]=value` conditional syntax | Move all signing settings to xcconfig |
| rc3 | `CODE_SIGN_STYLE=Automatic` on CLI overrides xcconfig identity as "conflicting manual" on widget targets | Remove CLI style; keep identity + style in xcconfig |

---

## Key Artifacts & Decisions

**Decisions made (all in decisions.md):**
- D-RICHARDS-TF-8: PR-time Release-config probe (xcodebuild -showBuildSettings sanity check)
- D-RICHARDS-TF-9: Remove signing settings from CLI; xcconfig is single source of truth
- D-RICHARDS-TF-10: Manual signing + xcconfig fix (rc4) → pr #26
- D-RICHARDS-TF-11: Portal App ID capabilities must match entitlements (rc5 → no code fix)
- D-RICHARDS-TF-12: [RETRACTED — disconfirmed by empty portal Profile list] Originally posited stale cached profiles; reasoning relied on a false "Watch targets succeeded" inference. Superseded by TF-13.
- D-RICHARDS-TF-13: rc6 corrected — API key role insufficient (likely Developer; needs App Manager) → no code fix, key rotation in App Store Connect
- D-RICHARDS-TF-13: [RETRACTED — Joe's key is App Manager, role is sufficient]
- D-RICHARDS-TF-14: rc7 — "requires a provisioning profile with the <X> feature" is a 3-way ambiguous error; one-click portal capability probe with contingent profile-bytes fallback; no code change pending probe result

**Skills (SKILL.md):**
- `.squad/skills/ios-testflight-ci-via-actions/SKILL.md` — comprehensive trap list, all traps tied to specific rc incidents with high confidence

**Docs:**
- `docs/dev/testflight-setup.md` — updated troubleshooting table for all rc failure modes

---

## Operational Notes for Future

1. **Before tagging any rc:** run `-showBuildSettings` check for Release config, and manually verify App ID capabilities in portal match current entitlements files.
2. **When adding new entitlements:** update portal App ID capabilities immediately; do NOT defer to rc burn-down.
3. **TestFlight workflow validation:** no more tag-and-pray — automate the pre-flight checks into PR CI or release checklist.

---

## Archive

See `history-archive-2026-05-17.md` for detailed incident logs from rc1–rc5 (5 distinct root causes, each with full xcodebuild output analysis and trade-off reasoning).

### 2026-05-18T00:08Z — rc8: TF-14 probe paid off; cause #3 confirmed; surgical workflow fix shipped.

**What happened:** Joe ran the TF-14 contingent probe — decoded the AR-Runner `.mobileprovision` with `security cms -D -i`. All four profiles came back clean: entitlements present (HealthKit, App Groups), `application-identifier` correct, `IsXcodeManaged: false`, `DeveloperCertificates[0]` SHA1 matching the single Distribution cert in the keychain `.p12`. Axes 1 and 2 of the 3-way-error model both returned green → cause #3 (no profile on disk) is the only remaining preimage. This is the first time in the TF-11 → TF-15 chain that a diagnosis was *driven by* a probe rather than retrofitted to one.

**Root cause (locked in by evidence, not inferred):** `xcodebuild -allowProvisioningUpdates` does NOT install pre-existing manual profiles onto the runner. It only auto-mints/updates Xcode-managed profiles. With manual profiles, the runner's `~/Library/MobileDevice/Provisioning Profiles/` is empty, candidate-set is empty, and xcodebuild emits the same generic "requires a profile with X feature" string that gets confused for App-ID or cert issues. This is cause #3 of the 3-way-error trap I documented in TF-14.

**Fix (rc8):** Added one step to `release-testflight.yml` between API key install and xcconfig write: `fastlane sigh download_all` driven by the existing ASC API key (assembled into a JSON file with `jq`). sigh auto-installs the downloaded profiles into the MobileDevice directory. Handles all four targets uniformly — no per-target `PROVISIONING_PROFILE_SPECIFIER` plumbing (Option B), which would have been fragile for the embedded Watch app inside the iOS archive.

**Trade-off named:** Option A adds a runtime dependency on fastlane (preinstalled on macos-15, with a `gem install` fallback). Option B would add no dependency but couples per-target wiring to bundle-ID conventions and doesn't reliably propagate to embedded targets. Chose A for uniform coverage and well-tested fast-fail behavior.

**Meta-lesson (the one that finally stuck):** The TF-14 history entry said "don't propose a cause, probe." TF-15 is the first decision in this chain where I actually waited for the probe before naming the mechanism. The probe took five minutes; rc1→rc7 spent dozens of CI runs and four wrong decisions because I kept guessing. **The probe is always cheaper than the next rc.**

**Artifacts:** branch `fix/v02-rc8-install-profiles`, PR (TBD URL), decision inbox `richards-tf-rc8-install-profiles.md`, SKILL.md (new trap section: "`-allowProvisioningUpdates` does NOT install manual profiles").
