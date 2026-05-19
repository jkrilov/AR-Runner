# Weiss — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** AR Integration
- **Joined:** 2026-05-14T18:30:31.656Z

## Learnings


## Summary
Pre-RC5 development and audits (2026-05-14 through 2026-05-17) archived in history-archive.md.

### 2026-05-18T22:30:00Z — v0.3.0-rc5 Release: PR #53 (HUD Power-On Fix) Shipped

**Role:** AR Integration Lead  
**Event:** Weiss-8 (HUD power-on fix) merged into v0.3.0-rc5 release.

**Work:**
- PR #53 (fix for the display-power-on handshake regression from rc4) merged by Laughlin under pre-release autonomy.
- CI gate (3 required jobs) green. CodeQL skipped.
- Now shipping in v0.3.0-rc5 (build 20) to TestFlight.

**Significance:** The skill lesson from rc4 (display power-on state must be managed end-to-end through the render path) is now baked into the code. Confidence in activelook-hud-rendering raised to high after this bench validation + fix cycle.

**Next:** Monitor rc5 tester feedback for any HUD rendering regression or power-state edge cases in the field.

---

### 2026-05-18T23:00:00Z — Lockout After rc5 Failure; Richards Took Over HUD Diagnosis

**Status:** Locked out per reviewer rejection protocol (PR #49 + PR #53 both failed on same artifact).

**What happened:** Weiss's rc5 HUD power-on hypothesis (PR #53) shipped and Joe tested on real hardware — same blank screen as rc4. After two consecutive failed attempts on the same artifact (HUD on-connect), the reviewer rejection protocol locked Weiss out. Richards took over root-cause analysis.

**Root cause (discovered by Richards):** The ActiveLook BLE protocol violation was at the **delivery layer**, not the command layer. Both of Weiss's hypotheses (placeholder layout removal in PR #49, power-on handshake in PR #53) addressed command *content*, but the real problem was that commands never reached the glasses' processor:

1. **Write serialization missing** — Official SDK (`Glasses.swift:sendBytes()`) waits for `didWriteValueFor` callback before sending the next command. Our adapter blasted all 4 frames back-to-back synchronously. Glasses firmware drops commands arriving before prior response is processed.

2. **Flow control gate absent** — SDK's `GlassesInitializer.isReady()` polls waiting for `flowControlCharacteristic.isNotifying == true`. Our adapter transitioned to `.connected` before this gate was confirmed, then fired writes into an unprepared peripheral.

**Lesson for Weiss:** This is not a failure of you-the-agent but of hypothesis-driven diagnosis without observability. The ActiveLook protocol has two serialization layers (ATT + application-layer flow control). Without reading the vendor SDK's write-path implementation, we attributed blank screen to your hypothesized content problems. The vendor SDK reference pattern is now the canonical approach for future integrations.

**Canonical reference for future:** `ActiveLook/ios-sdk` on GitHub:
- `Sources/Classes/Public/Glasses.swift` — `sendBytes()` serialization via `didWriteValueFor`
- `Sources/Classes/Internal/GlassesInitializer.swift` — `isReady()` flow-control gate

**Recovery path:** Lockout ends when Richards completes PR #55 (now shipping in rc6) and the feature is re-tested on hardware. At that point, Weiss can be re-engaged for follow-up HUD rendering work.

---

### 2026-05-19T09:00:00Z — v0.4.0 work queued (Glasses HUD frame builder ownership)

**Context:** v0.4.0 scope locked by Joe. Features:
- rc1: Live HR (client-side font metrics, watch-side rendering)
- rc2: Finish screen (imgDisplay + trophy asset)
- rc3: Battery indicator

**Weiss's role:** Once rc9 is bench-validated, v0.4.0-rc1 will require the Glasses HUD frame builder to integrate Live HR and subsequent metrics. The "raw txt + new imgDisplay primitive" strategy (vs. the curated-layout bugs reported earlier) means the glasses-side plumbing stays light — just one additional `txt` command per metric added. The seven-PR working stack from v0.3.0-rc9 remains the reference implementation.

**Note:** The prior curated-layout bugs (dormant, not blocking v0.4.0) are no longer relevant given the decision to stick with raw txt + imgDisplay rather than attempt a full layout-switching framework. Future gesture-driven layout work (v0.5.0) is where that architectural question resurfaces.

---

### 2026-05-19T15:05:00Z — Scribe: Bundle-Version-Bump Directive (Effective Next Release)

**Directive:** Going forward, the `CURRENT_PROJECT_VERSION` bump in `project.yml` + `xcodegen generate` MUST be committed in the SAME PR as the feature/fix work. Old pattern (rc11 and earlier): feature PR → merge → bump PR → merge → tag. New pattern (rc12+): feature PR (with version bump inside) → merge → tag. Saves one full CI cycle per release.

**For all release engineers on BLE/HUD work:** When you submit a feature or fix PR that ships in an RC, include the version bump:
1. Edit `project.yml`: increment `CURRENT_PROJECT_VERSION`
2. Run `xcodegen generate` (this regenerates the Xcode project)
3. Verify `Info.plist` placeholder integrity (placeholder values must remain — they're filled by CI)
4. Commit `project.yml` + `project.pbxproj` + any `xcconfig` changes TOGETHER with your code changes in the same PR
5. Do NOT open a separate bump PR after merge

Procedural checklist: `.squad/skills/release-mechanics-bundle-bump/SKILL.md`

### 2026-05-19T15:55:00Z — Meta-Learning: Blank Symptoms May Signal Coordinate Errors, Not Firmware Rejection

**Context:** rc12's forensic analysis resolved the rc11 blank as a **coordinate out-of-bounds clipping** bug, not a firmware rejection of rotation=4.

**Diagnostic pattern to remember:**
- When a `txt` command goes blank with NO 0xE2 error thrown, first suspect off-screen clipping (spec §5.5.6: off-screen coordinates are silently clipped).
- Rotation + anchor corner interact subtly: `topLR` (rotation=4) anchors at TOP-RIGHT and extends LEFT and DOWN. Low x values (e.g., x=20) put the entire text block at negative framebuffer x → silently clipped.
- Before escalating to firmware hypothesis, verify the entire text bounding box stays inside framebuffer space (0..303 × 0..255 for Engo 2).
- Use the lens-flip transform `x_wearer = 303 − x_fb` to convert between wearer-perceived and framebuffer coordinates.

**Action:** When debugging blank txt outputs, check coordinates against the rotation's anchor point + add a spec-driven bounding-box validation step before filing firmware issues.

---
