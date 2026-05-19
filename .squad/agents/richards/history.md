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

---

### 2026-05-19T15:05:00Z — Scribe: Bundle-Version-Bump Directive (Effective Next Release)

**Directive:** Going forward, the `CURRENT_PROJECT_VERSION` bump in `project.yml` + `xcodegen generate` MUST be committed in the SAME PR as the feature/fix work. Old pattern (rc11 and earlier): feature PR → merge → bump PR → merge → tag. New pattern (rc12+): feature PR (with version bump inside) → merge → tag. Saves one full CI cycle per release.

**For all release engineers on architecture/BLE work:** When you submit a feature or fix PR that ships in an RC, include the version bump:
1. Edit `project.yml`: increment `CURRENT_PROJECT_VERSION`
2. Run `xcodegen generate` (this regenerates the Xcode project)
3. Verify `Info.plist` placeholder integrity (placeholder values must remain — they're filled by CI)
4. Commit `project.yml` + `project.pbxproj` + any `xcconfig` changes TOGETHER with your code changes in the same PR
5. Do NOT open a separate bump PR after merge

Procedural checklist: `.squad/skills/release-mechanics-bundle-bump/SKILL.md`

### 2026-05-19T15:55:00Z — Meta-Learning: Blank Text May Indicate Off-Screen Clipping, Not Firmware Rejection

**Context:** rc12 forensic research (textrotation agent) resolved the rc11 blank at rotation=4 as an off-screen coordinate clipping bug per spec §5.5.6, NOT a firmware rejection.

**Pattern to integrate into future debugging:**
- Silent blank with no 0xE2 error → suspect off-screen clipping before firmware hypothesis.
- Rotation value interacts with text anchor corner: `topLR` (rotation=4) anchors at TOP-RIGHT, extends LEFT and DOWN. Placing anchor at small x (e.g., x=20) pushes the entire text block off-screen (negative x).
- Spec §5.5.6 guarantees silent clipping for out-of-bounds coordinates — no error thrown, just silently discarded.
- Before opening firmware escalation, verify the text bounding box stays within framebuffer bounds (0..303 × 0..255 for Engo 2). Use lens-flip formula `x_wearer = 303 − x_fb` for coordinate transforms.

**Recommendation:** Add a pre-flight coordinate validation step to any txt debug flow: check all glyphs fit on-screen before assuming protocol/firmware issue.

---

## Learnings — 2026-05-19 — rc13→rc16 HUD layout+icons architectural review

**Scope reviewed:** PRs #72/#74/#75/#76 (tags v0.3.0-rc13..rc16). Tests: 176/176 (1 skipped) on `swift test` against `ARRunnerCore`.

**What's solid (promote / canonicalize):**
1. **Lens-flip transform is now empirically pinned, not derived.** rc16 corrected the rc12-era `y_fb = 255 − T − font_height` to the correct `y_fb = 255 − T` after Joe's "1 pixel at bottom" bench evidence proved the prior derivation was coincidence. Worth canonicalizing as the single source of truth: anchor=top-right (topLR), `y_fb = 255 − wearer_top`, `x_fb = 303 − wearer_right` for text; for images (no rotation flag) it's `x_fb = 303 − wearer_left − w`, `y_fb = 255 − wearer_top − h`. The arithmetic shows up inline as comments next to every constant — that's readable today but a `LayoutGeometry` helper (or even a `WearerRect → FramebufferAnchor` mapper) would prevent the next coordinate-system regression.
2. **Per-tick HUD pushes await the BLE actor (rc13 Bug B fix).** The "MainActor caller must `await`, not `Task { … }`" rule for any actor that's reentrant between `await`s inside a multi-frame `holdFlush` burst is now load-bearing. Already extracted into the `activelook-ble-adapter-pitfalls` skill; worth re-reading on any new burst-emitting code path.
3. **Preloaded ALooK flash IDs sidestep the cfgWrite/imgSave iceberg.** rc15's research correctly flagged custom-image upload as multi-rc work, but rc16 found that the 4 runner icons we needed (chrono/heart/distance/pace) ship preloaded — `imgDisplay(id, x, y)` is one BLE write, no chunk-split, no `cfgWrite`. Decisive simplification. **Architectural rule going forward:** any new icon proposal MUST first check whether an ALooK preloaded asset covers the semantic before invoking the upload pipeline.
4. **Live HUD = 4 fields / finish HUD = 2 fields.** Settled in rc14; the dedicated `summaryFrames(for:)` discards HR + pace at the encoder, callers pass full Payload for symmetry. Two surfaces, distinct evolution paths. Canonicalize.
5. **Bundled-bump release pattern.** Five releases in a row (rc12→rc16) under one PR per RC (feature + `CURRENT_PROJECT_VERSION` + xcodegen regen + tag + TestFlight). Now an established team default — `release-mechanics-bundle-bump` skill captures it.

**Tech debt accruing (not yet a fire, but watch):**
- **`Layout` enum is becoming a god-bag.** `RunningHUDFrame.Layout` now holds 25+ constants spanning splash, live HUD (3 lines × ≈3 attrs each + font), finish screen, 4 icon IDs, 8 icon coords, lens/rotation/color globals. It's still navigable because each cluster has a `MARK:` divider, but a third HUD screen (cue / split / pre-run) will push past the manageable threshold. **When v0.4.x adds another screen, factor into `SplashLayout` / `LiveHUDLayout` / `FinishLayout` / `IconCatalog` siblings.** Not now — the cost of restructuring without a third concrete consumer is speculative; current shape is still legible.
- **Font-width estimates are hardcoded in prose comments**, not code. "Font 2 ≈ 18 px/char", "Font 3 ≈ 28 px/char" appear in derivations but nothing in the build asserts text-block widths against the 304-px framebuffer. The rc15→rc16 cycle's root cause was a height under-estimate; the next cycle's risk is a width under-estimate (a long pace string like "12:34/mi" + a wider HR like "180" colliding on line 1). **Recommend:** lift the font height + advance-width table into a `ALookFontMetrics` value type with assertions, sourced from the Visual-Assets repo README. Single source of truth, and we get compile-time-ish guards on layout math.
- **rc13 push-policy reset is defensive but undocumented at the API surface.** `hudPushPolicy.reset()` + `needsHUDPowerOn = true` at every `start()` papers over potential bugs (stale payload, splash clearing power-on flag). It's the right belt-and-braces but it means we no longer trust the connect-state task's invariants. Eventually worth a state-machine review of `WorkoutViewModel` ↔ `RunningHUDPushPolicy` ↔ adapter connect-state, but only when a fourth caller appears.
- **Icon-rotation hypothesis is unverified-in-test.** The rc16 doc block (line 137-149 of RunningHUDFrame.swift) says "preloaded ALooK icons ship pre-rotated 180°… if build 31 shows icons upside-down, rc17 will pre-rotate at upload time." Joe's confirmation that "we got the layout working, even have icons showing" implicitly validates this — but nothing in the test suite would catch a regression where someone swaps in a non-pre-rotated icon. Acceptable for now (we only use 4 preloaded IDs), but document the convention in the SKILL when we promote it.

**Risks specific to the rapid rc13→rc16 cadence (5 releases in ~6 days):**
- **Coordinate constants now have two contradictory historical derivations.** The file documents BOTH the rc12 `y_fb = 206 − T` (still used for `timeY/distanceY/paceY` of the finish screen at lines 60-62) AND the corrected rc16 `y_fb = 255 − T` (used for live HUD lines 150-153). They produce the same screen-on-bench result only because the finish-screen Ys were chosen to fit by trial; nobody has gone back to validate that the finish-screen coordinates are *correct* under the rc16 formula — they may also be off by a font-height that we haven't noticed because the finish frame is short and the slop happens to fit. **Worth a deliberate pass** to recompute timeY/distanceY/paceY using the rc16 formula before v0.4 ships, even if the bench shows it's fine today.
- **`summaryFrames(for:)` reuses `paceY` as the *distance* line's y-anchor** (line 498). That's a tripwire — the constant name no longer matches its usage. Either rename to `summaryLine3Y` or assert via test name what each anchor is wired to.
- **rc17 (in-flight, per Amber's inbox) deletes `teardownTransport`**, leaving BLE up indefinitely past workout end. Architecturally sound (the wearer wants to read stats; user has explicit disconnect affordance) but it shifts BLE lifecycle ownership entirely onto the user. Worth an ADR before v0.4 GA to declare "the BLE link is user-managed, not workout-scoped" as the canonical contract — Battery indicator (Weiss's v0.4 work) will live or die on this assumption.

**Decisions worth canonicalizing in `.squad/decisions.md` (Scribe to merge):**
- The lens-flip formulas (text + image variants) as the project's authoritative coordinate-system contract.
- Live HUD = 4 fields, finish HUD = 2 fields as a stable surface contract.
- Preloaded ALooK icons preferred over custom upload pipeline (rule: check Visual-Assets repo first).
- BLE link lifecycle is user-managed post-rc17, not workout-scoped.


### 2026-05-19T18:35:00-04:00 — ADR drafted: BLE link is user-managed, not workout-scoped

**Trigger:** Joe reported the rc16 (and prior) behavior where workout-finish dropped the BLE link, finish screen never landed, manual reconnect required. Confirmed NOT a regression — that was always the implicit contract. rc17's `WorkoutViewModel.confirmSave`/`confirmCancel` already comply (no `teardownTransport()`), but the contract was undocumented and would not survive the next refactor.

**What I wrote:** `.squad/decisions/inbox/richards-adr-ble-link-lifecycle.md` — full ADR with 4 invariants (I1–I4), 5 tear-down rules (R1–R5), 5 reconnect-policy clauses (P1–P5), 4 subscription rules (S1–S4), 3 phone-optional clauses (PO1–PO3). Five rejected alternatives (A–E), each named with the reason it lost.

**Architectural insight worth keeping:** The right mental model for paired peripheral hardware is "**peripheral session ⊥ application session**" — they observe each other but neither owns the other's lifecycle. Once you let an application-domain event (workout-finish) drive peripheral lifecycle, you've created an implicit coupling that will break every adjacent feature (finish HUD, battery telemetry, post-workout review). The fix is not to find the bug — it's to declare the orthogonality as a contract.

**Heuristic for next time I see this anti-pattern:** If a tear-down lives in the application-domain shutdown path, ask "who else needs this resource after the application event?" — if anyone (UI, telemetry, user attention), the resource is mis-scoped. Promote it to user-managed.

**Promoted to skill:** `.squad/skills/paired-hardware-lifecycle-contract/SKILL.md` — generalizes the pattern (it applies to any paired BLE peripheral, USB device, HID controller, etc., not just AR glasses).

**Implications dispatched:**
- Weiss: audit adapter for stray `disconnect()` call sites; implement P1–P5 backoff; make subscriptions idempotent per `.connected`; wire battery 0x2A19 into on-connect setup.
- Laughlin: no new work, but add regression test asserting `disconnect()` is NOT called in `confirmSave`/`confirmCancel`.
- Amber: battery-on-phone is a `WatchConnectivityService` mirror, never on the critical path.

**Recommendation count update:** #5 from rc13→rc16 review is now canonical. #1 (lens-flip geometry helper) and #2 (`ALookFontMetrics` width table) still open as the "two other blocking" items Joe referenced.
