# D-RICHARDS-TF-9 — Remove all signing build settings from xcodebuild CLI; xcconfig is single source of truth

**Date:** 2026-05-17
**Author:** Richards
**Status:** Proposed
**Supersedes / refines:** D-RICHARDS-TF-8 remains valid (probe-build is orthogonal). This decision completes the signing-pathway fix that D-RICHARDS-TF-1 through TF-7 established and rc1/rc2/rc3 exposed gaps in.

## Context

Three consecutive rc failures (rc1, rc2, rc3) all trace to the same root: signing-related build settings placed on the `xcodebuild archive` command line instead of in the project-level xcconfig.

| RC | CLI setting | Failure |
|---|---|---|
| rc1 | (none — inherited default `Apple Development`) | "no devices" — automatic signing tried Development profile path |
| rc2 | `CODE_SIGN_IDENTITY="Apple Distribution"` + `"CODE_SIGN_IDENTITY[sdk=iphoneos*]=..."` | xcodebuild mis-parsed `[sdk=...]` conditional; bare identity flagged as "manually specified" |
| rc3 | `CODE_SIGN_STYLE=Automatic` (with identity moved to xcconfig) | CLI override elevated style to highest precedence, making xcconfig identity appear as conflicting manual override on widget targets; main target fell back to Development path |

## Decision

**All signing-related build settings (`CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`) live exclusively in `Config/Signing.xcconfig`.** They are never passed on the `xcodebuild` command line.

The only signing-adjacent setting allowed on the CLI is `DEVELOPMENT_TEAM` (a runtime secret, not a mode selector).

The release workflow appends Distribution identity pins to the xcconfig after `bootstrap-signing.sh`:
```
CODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution
CODE_SIGN_IDENTITY[sdk=watchos*] = Apple Distribution
```

**Additional fix:** xcodegen injects `CODE_SIGN_IDENTITY = "iPhone Developer"` at the target level for iOS application targets. This overrides the project-level xcconfig (target settings > project xcconfig in Xcode's precedence). Fixed by setting `CODE_SIGN_IDENTITY: $(inherited)` in `project.yml` for ARRunnerPhone, which defers to the xcconfig.

## Options considered

| Option | Verdict | Trade-off |
|---|---|---|
| **A: Manual signing for archive** (`CODE_SIGN_STYLE=Manual` on CLI + per-target profile specifiers) | Rejected | Defeats `-allowProvisioningUpdates` profile creation; requires portal pre-provisioning for every bundle ID; adds maintenance when adding new targets/extensions. Overkill given that xcconfig-only automatic signing should work. |
| **B: xcconfig-only automatic signing** (remove `CODE_SIGN_STYLE` from CLI, keep xcconfig pins) | **Chosen** | Both CODE_SIGN_STYLE and CODE_SIGN_IDENTITY at project-config level — consistent precedence, no conflict. `-allowProvisioningUpdates` creates Distribution profiles via ASC API. Trade-off: first archive after adding a new bundle ID may take 1-2 extra minutes while Xcode creates the profile. |
| **C: Keep automatic signing, override everything on CLI** | Rejected | xcodebuild's CLI parser doesn't support `[sdk=...]` conditionals, and any CLI identity conflicts with CLI `CODE_SIGN_STYLE=Automatic`. Three rc failures prove this approach is fundamentally broken. |

## Consequences

1. `release-testflight.yml` archive step passes `DEVELOPMENT_TEAM`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and `OTHER_CODE_SIGN_FLAGS` on CLI — nothing else signing-related.
2. Distribution profiles for all 4 bundle IDs must exist in the portal OR be mintable by the ASC API key (App Manager role).
3. Local dev is unaffected — `bootstrap-signing.sh` writes `CODE_SIGN_STYLE = Automatic` with no identity pin; Xcode.app uses the developer's personal Apple Development cert.

## Owner if accepted

Richards (Lead / Architect)
