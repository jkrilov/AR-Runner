# Richards — History (Summarized)

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead
- **Joined:** 2026-05-14T18:30:31.650Z

## Active Learnings (Current)

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
