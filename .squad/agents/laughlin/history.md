# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings


## Summary

Pre-RC5 development and audits (2026-05-14 through 2026-05-17) archived in history-archive.md.

### RC5–RC8 Campaign (2026-05-18 → 2026-05-19T12:00:00Z): Five-RC Blank-Screen Saga + Root Cause Discovery

**Summary of RCs 5–8:**

- **rc5–rc6** (PRs #53–#55): Weiss and Richards iteratively fixed hypothesis-driven command issues (power-on, serialization). Both CI passed; both shipped to TestFlight; both produced blank screen on Joe's bench. Pre-release autonomy model (coordinator-merge → Laughlin-release) validated operationally, but three coders now locked out.
- **rc7** (PR #57): Under cross-research protocols, discovered two missed bugs: (1) missing 1-byte queryID (firmware silently misparses frames, shifts txt 5000px off-panel), (2) missing didUpdateValueFor wiring for control + TX chars (flow-control and 0xE2 errors silently dropped). All 147 tests updated; uploaded to TestFlight.
- **rc8** (PR #60): After rc7 still blank on bench, Joe authorized override + forensic researcher found third bug: cfgSet("ALooK") required on every connect (fonts 1–5 are config-resident in "ALooK" flash partition, not firmware-baked). Without cfgSet, txt commands referencing fonts 1–5 are silently dropped or emit 0xE2 errors. Also fixed rotation mislabel (4 → 0 = bottomRL natural direction). 150 tests, uploaded to TestFlight.

**Key learnings archived:**
1. **queryID implicit requirement:** Spec marks optional; firmware + SDK always include. Rule: always attach 1-byte queryID except for DFU ops.
2. **All notify chars must be wired:** Control + TX chars carry flow-control + error signals; routing only battery char hides rejections.
3. **Asset repos hold operational rules:** The answer was in `ActiveLook/Activelook-Visual-Assets`, not spec + SDK source. Always sweep vendor GitHub org for `*-Visual-Assets` / `*-Configurations` repos.
4. **Override criterion:** spec-backed diagnosis + mechanical fix = safe to override strict-lockout once per artifact.
5. **Config-resident fonts:** Engo 2 fonts live in flash, not firmware. Pre-connect cfgSet("ALooK") is non-negotiable.
6. **CI polling hygiene:** Avoid `sleep N && gh pr view ... | python3` (leaves zombie shells). Use `gh pr checks <pr> --watch` or explicit loop with `sleep 45` + `gh run view <id> --json`.

---

### 2026-05-19T12:55:00Z — v0.3.0-rc9 Polish: rotation calibration + holdFlush anti-flicker

**Role:** watchOS Dev (rc8 lockout cleared by Joe — text renders ✅)
**Event:** Joe's bench test of rc8 confirmed the cfgSet("ALooK") fix worked — both the connect banner ("AR-Runner Start a run") AND the live workout HUD (time / distance / pace) render on the Engo 2. Five-RC saga concluded. Two polish bugs remained: text rendered upside-down, and the HUD flashed every second on tick update. PR #63 fixed both.

**Work:**
- PR #63: `Layout.rotation: 0 → 2` (180° rotation accounting for Engo 2 lens flip); added `ID.holdFlush = 0x39` to the encoder enum with `holdFlush(hold:)` builder; wrapped per-tick `frames(for:)` in `holdFlush(hold:true)` … `holdFlush(hold:false)` for atomic display commits. Did NOT wrap `connectFrames()` or `summaryFrames()` — those are one-shot draws where the user only sees the final state.
- 154 ARRunnerCore tests pass (150 prior + 4 new: holdFlush encoder, frames-wraps-in-holdFlush, connect/summary do-not-wrap negative tests; plus updated 6-frame layout assertions).
- Merged PR #63, bumped build 23→24 (PR #64), tagged v0.3.0-rc9, watched release-testflight.yml to `UPLOAD SUCCEEDED with no errors` (MARKETING_VERSION=0.3.0 CURRENT_PROJECT_VERSION=24).

## Learnings

1. **AR glasses' rotation parameter is calibrated against perceived orientation, not framebuffer orientation.** The Engo 2's optical projection path flips/mirrors the framebuffer relative to what the wearer sees through the waveguide. `rotation = 0` (bottomRL per SDK enum) looked logically "natural" on paper, but rendered upside-down in real life. `rotation = 2` (topRL, 180° from 0) is what the wearer perceives as right-side-up. **Rule: rotation is empirically calibrated per device — trial-and-error against the wearer's POV is unavoidable.** The spec describes glyph orientation in framebuffer space; the lens flip is undocumented and must be discovered on hardware.

2. **Per-tick frame sequences with `clear` + multiple `txt` writes MUST be wrapped in holdFlush(0x39).** Without the wrap, each BLE write commits to the framebuffer independently — the wearer sees a brief blank between `clear` and the first `txt` plus tearing between txt writes ("flashes every second"). Per ActiveLook spec §4.6: `holdFlush(action:0)` defers commits, `holdFlush(action:1)` flushes them atomically. The stock ActiveLook iOS app uses this pattern; our v0.3 raw-txt HUD did not, hence the flicker. **Rule: any multi-write update sequence that should appear atomic to the user wraps in holdFlush. One-shot draws (banner, summary) don't need it because the user only sees the final state.**

3. **The five-RC saga concluded with all prior fixes load-bearing.** The confirmed-working stack is the cumulative product of seven PRs across three coders: scan fix (PR #45, Weiss) + version pipeline (PR #48) + HUD MVP (PR #49, Weiss) + power-on (PR #53, Richards) + write serialization (PR #55, Weiss) + queryID/flow-control/observability (PR #57, Laughlin) + cfgSet ALooK (PR #60, Laughlin). Removing any single one breaks the chain. **Lesson: in a multi-bug pipeline where each fix is real but masked by a downstream bug, you don't get to know which fixes were "actually" needed until the whole stack lights up. Resist the urge to revert anything during the dark period.**

4. **Polish bugs in greenfield protocol code are not equivalent to functional bugs and should ship as fast-cycle RCs.** rc9 changed three lines of value-type logic, added one encoder method, and shipped within hours of rc8 confirmation. No need to re-litigate the working stack, no need for cross-research, no need for new forensic. The bench-test cadence is what matters now — Joe iterates rotation/timing against real hardware, we ship calibration RCs. **Rule for v0.3.x: polish cycles are tight; reserve forensic ceremony for "doesn't work at all" regressions.**

---

### 2026-05-19T09:00:00Z — Scribe merge session (orchestration + history context sharing)

**Recognition:** The seven-PR working stack from rc7 through rc9 is now documented in the `activelook-hud-rendering` skill under "🟢 CONFIRMED WORKING STACK". This is a strong reference artifact for future HUD debugging — tells newcomers "here's what we know works end-to-end" rather than forcing them to re-derive from git history. The iterative polish cadence (rc8 bench → rc9 rotation/flicker fixes) proved effective; v0.4.0 will follow the same pattern.

---

### 2026-05-19T13:45:00Z — v0.3.0-rc10 Release (bisect of rc9 regression)

**Role:** watchOS Release Lead (under Joe's second one-time lockout override)
**Event:** rc9 went blank on Joe's bench. rc9 had bundled TWO polish changes (`Layout.rotation: 0→2` + `holdFlush(true/false)` wrap on `frames(for:)`). rc10 surgically reverts rotation only, keeps holdFlush, to bisect which change caused the blank.

**Work:**
- PR #66 — single-line revert: `Layout.rotation: 2 → 0`. holdFlush untouched. All 154 ARRunnerCore tests pass (tests reference `Layout.rotation` symbolically, so no test value update needed).
- PR #67 — build bump 24 → 25, xcodegen regenerated, plist placeholders verified intact.
- Tag `v0.3.0-rc10` pushed; release-testflight.yml succeeded with `MARKETING_VERSION=0.3.0 CURRENT_PROJECT_VERSION=25` and `UPLOAD SUCCEEDED with no errors`.

**Diagnosis still pending (Joe's bench test of rc10 decides):**
- Text renders upside-down without flicker → rotation=2 was the bug; holdFlush is good. rc11 iterates rotation values (1, 3, 6, 7) ONE-AT-A-TIME in their own PRs.
- Still blank → holdFlush is the culprit; rc11 reverts holdFlush too and goes back to rc8 baseline.

**Lessons (hard ones):**

1. **Engo 2 firmware likely silently rejects undocumented rotation enum values.** The ActiveLook SDK only documents 0 (bottomRL) and 4 (topLR). 2 is plausible (topRL) but undocumented. rotation=2 produced a completely blank screen — not a tilted-but-wrong image — which is the textbook signature of a silently-dropped draw command (the firmware sees an invalid enum byte and skips the entire `txt` op). **If you need a different orientation, test ONE rotation value at a time in its OWN PR, and treat anything other than 0 and 4 as "unknown — verify on hardware before trusting."**

2. **NEVER ship two unrelated polish changes in one PR if either could plausibly break the screen.** rc9 bundled rotation + holdFlush. Both touched the HUD render path, both were "polish" not "bug fix", and when the screen went blank we had no way to tell which one broke it without a bisect cycle — costing a full release cycle (rc10) just to isolate. **Rule:** one polish dimension per PR when the failure mode is binary (works / blank). Acceptable to bundle changes only when each is independently observable (e.g., a layout tweak + an unrelated formatter fix).

3. **Bisect-on-multi-change-PR pattern works mechanically:** revert one change, keep the other, ship, bench-test, observe. The strict-lockout rule is suspended only because Joe explicitly authorized — under normal rules, the rc9 author would be locked out and a different agent would do this revert.

**Skill update:** `activelook-hud-rendering` confidence held at HIGH (the seven-PR working stack from rc7/rc8 is unchanged; this is a polish calibration miscalibration, not a working-stack regression). Added CRITICAL note documenting valid TextRotation enum values + the one-rotation-per-PR rule.

## 2026-05-19 — rc11: rotation=4 (topLR) attempted

After rc10 bisect confirmed holdFlush is good and rotation=0 (bottomRL) reads
upside-down through the Engo 2 lens, calibrated to the other documented SDK
`TextRotation` value: **4 (topLR)**. One-line change in
`RunningHUDFrame.swift` (Layout.rotation: 0 → 4). All 154 ARRunnerCore tests
pass; holdFlush/queryID/cfgSet/flow-control untouched.

Shipped end-to-end: PR #69 (code) merged → PR #70 (build 25→26) merged →
tag `v0.3.0-rc11` pushed → release-testflight.yml uploaded
`MARKETING_VERSION=0.3.0 CURRENT_PROJECT_VERSION=26` to TestFlight ("UPLOAD
SUCCEEDED with no errors").

Outcome pending Joe's bench test:
- If rc11 renders right-side-up → rotation calibration done; lock in 4.
- If rc11 is blank → 4 is also rejected by Engo 2 firmware; we're out of
  documented enum values and need to ask Weiss for guidance (maybe rotation
  byte isn't TextRotation at all on this firmware rev).
- If rc11 is still upside-down → rotation byte has no observable effect at
  the protocol level; investigate whether the lens itself is the inversion
  source (mirror in firmware coords vs. user-eye coords).

---

### 2026-05-19T15:05:00Z — Scribe: Recognition for rc11 one-line ship + bundle-version-bump directive

**Recognition:** rc11 demonstrated clean calibration under pressure: one surgical
line change (rotation 0→4), full CI gate pass, TestFlight upload succeeded, no
regressions introduced to the working seven-PR stack. This was the LAST release
using the 2-PR pattern (feature PR + separate bump PR). The bundle-version-bump
directive (below) is now in effect for all future release PRs.

**Directive (All Release Engineers):** Going forward, the `CURRENT_PROJECT_VERSION`
bump in `project.yml` + `xcodegen generate` MUST be committed in the SAME PR as
the feature/fix work. Old pattern (rc11 and earlier): feature PR → merge → bump
PR → merge → tag. New pattern (rc12+): feature PR (with version bump inside) →
merge → tag. Saves one full CI cycle per release. When editing `project.yml`,
always run `xcodegen generate` and verify `Info.plist` placeholder integrity
in the same commit — ship them together. See `.squad/skills/release-mechanics-bundle-bump/SKILL.md`
for procedural checklist.

## 2026-05-19 — rc12: a "blank" doesn't always mean firmware rejection (off-screen clipping pattern)

rc11 shipped `rotation = 4` (topLR) with `leftMargin = 20` and the screen
went blank. The instinct was "rotation byte rejected by firmware" — same
reasoning we used for rc9's blank at `rotation = 2`. **That was wrong.**

The textrotation forensic (`.squad/files/hud-rotation-research.md`)
proved it: topLR anchors at the TOP-RIGHT of the text block and the
block extends LEFT + DOWN. At `x_fb = 20`, the full ~200 px string
landed at negative x. Per spec §5.5.6, off-screen coords are SILENTLY
CLIPPED — no 0xE2 error, no log, nothing on the wire. Same visible
symptom as firmware rejection. Identical wearer experience.

**The lesson:** when you see a blank Engo 2 screen with the rc8 working
stack intact (cfgSet, power-on, queryID, flow-control, holdFlush) and
NO 0xE2 errors in the BLE log, off-screen clipping is more likely than
rotation-byte rejection. Verify the anchor coords keep the text on-
screen for that rotation's bounding box BEFORE concluding the rotation
byte is bad. The two failure modes are visually indistinguishable; do
the math first.

Engo 2 lens flip (point-symmetric 180°): `x_wearer = 303 − x_fb`,
`y_wearer = 255 − y_fb`. For wearer-readable text at wearer-coord
(x_w, y_w) with topLR and a font of height H:
- `x_fb = 303 − x_w` (right anchor lands at wearer's left edge)
- `y_fb = 255 − y_w − H` (top of glyph block lands at wearer's top)

rc12 ships rotation=4 + (284, 166/86/6) per the formula above. If it's
still blank, the diagnostic ladder in the research doc (single test
`txt` at center 152,128 from a dev path; then try rotation=5 variants)
takes over.

## 2026-05-19 — bundled version-bump pattern validated on rc12

First release shipped under Joe's `copilot-directive-bundle-version-bump`
directive: feature PR contained `CURRENT_PROJECT_VERSION: 26 → 27` plus
the regenerated `pbxproj` alongside the code change. No separate bump
PR, no second CI round-trip. PR merged → tagged from main → TestFlight
upload succeeded with `MARKETING_VERSION=0.3.0 CURRENT_PROJECT_VERSION=27`.
Pattern is keep-it. Procedural checklist lives in
`.squad/skills/release-mechanics-bundle-bump/SKILL.md`.
