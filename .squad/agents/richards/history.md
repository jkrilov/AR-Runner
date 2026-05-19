# Richards — History (Current Session Summarized)

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead / Architect
- **Joined:** 2026-05-14T18:30:31.650Z

## Session 2026-05-18: Release v0.3.0-rc6 (BLE Fix + Post-Release Cleanup)

### 2026-05-18T23:00:00Z — BLE Write Serialization Root Cause + PR #55

**Diagnosis:** rc5 shipped with blank HUD on real hardware (Weiss's PR #53 also failed). After two consecutive failures on the same artifact, reviewer lockout activated and Richards took over.

**Root cause:** ActiveLook BLE protocol requires two serialization layers that our adapter violated:
1. **Write serialization** — Official SDK (`Glasses.swift:sendBytes()`) waits for `didWriteValueFor` callback before sending next command. Our adapter blasted 4 frames back-to-back; glasses firmware drops commands arriving before prior response is processed.
2. **Flow-control subscription gate** — SDK's `GlassesInitializer.isReady()` polls until `flowControlCharacteristic.isNotifying == true`. Our adapter transitioned to `.connected` before confirming this gate, then fired writes into unprepared peripheral.

**Why Weiss's hypotheses failed:** Both addressed command *content* (layout ID, power state) but not *delivery*. Commands were correct; they never reached the glasses' processor.

**Durable lesson:** When driving a BLE peripheral via custom GATT profile, read vendor SDK's write-path implementation BEFORE building your own. The ATT layer's `.withResponse` guarantee is necessary but not sufficient — peripherals have application-layer flow control gates above ATT. "Write returned" ≠ "peripheral processed command."

**Fix (PR #55):**
- Gate `.connected` on `didUpdateNotificationStateFor` confirming flow-control subscription (2s timeout fallback)
- Replace fire-and-forget with `CheckedContinuation`-based `write()` awaiting `didWriteValueFor`
- Add delegate methods to Coordinator
- Add os_log instrumentation (subsystem `com.arrunner.watch`, category `ActiveLookGlasses`)

**Result:** 145 tests passing on CI; PR #55 merged into rc6.

**Canonical reference:** `ActiveLook/ios-sdk` GitHub — `Glasses.swift:sendBytes()` serial gating, `GlassesInitializer.swift:isReady()` flow-control gate.

---

## Earlier Sessions (Archived Summary)

### TestFlight Campaign (rc1–rc15, 2026-05-18 earlier)

- **rc1–rc3:** Sign identity + CLI parsing issues. Solved with Manual signing + xcconfig.
- **rc4:** xcodegen baked `CODE_SIGN_STYLE=Automatic` into project; conflicted with xcconfig Manual pin. Fixed PR #26.
- **rc5:** App ID capabilities missing in developer portal. Fixed with portal action (no code change).
- **rc6–rc7:** API key role insufficient (likely Developer); cached profile diagnosis disconfirmed. Corrected to App Manager key requirement.
- **rc8:** Profiles not installed on runner. Fixed with `fastlane sigh download_all`.
- **rc9:** sigh downloaded zero profiles (platform filter trap). Pivoted to `PROVISIONING_PROFILE_SPECIFIER` in xcconfig.
- **rc10:** Export signing independent from archive signing. Fixed ExportOptions.plist with per-target profiles dict.
- **rc12–rc15:** macOS-26 runner upgrade (macos-15 had outdated iOS SDK). All validation gates cleared. Upload succeeded.

**Key learnings:**
1. Archive and export use separate signing resolution paths.
2. `-allowProvisioningUpdates` is create-if-missing, not create-or-refresh.
3. Clean exit code ≠ produced artifact (assert on artifacts, not return codes).
4. Absence of error ≠ success (demand positive evidence before claiming asymmetric pipeline behavior).
5. Ambiguous error strings require probing both axes, not hypothesis selection.

**Artifacts:** Comprehensive SKILL.md at `.squad/skills/ios-testflight-ci-via-actions/SKILL.md`; decisions D-RICHARDS-TF-8 through TF-17 in decisions.md.

---

## For Future Sessions

1. **Before tagging rc:** Run `-showBuildSettings` probe on Release config; verify App ID capabilities in portal match current entitlements.
2. **When adding entitlements:** Update portal App ID capabilities immediately (don't defer to rc burn-down).
3. **On "requires a provisioning profile with X" errors:** Probe, don't guess. Check: (a) App ID capability state, (b) profile's byte-level `DeveloperCertificates` via `security cms -D -i`.
4. **After every fetch-from-API step:** Assert on artifact count (not just exit code).
5. **On first-time-success in pipeline:** Check what's the next step downstream and verify its preconditions.
