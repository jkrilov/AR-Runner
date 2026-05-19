# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings


## Summary
Pre-RC5 development and audits (2026-05-14 through 2026-05-17) archived in history-archive.md.

### 2026-05-18T22:30:00Z — v0.3.0-rc5 Release (Pre-Release Autonomy Model)

**Role:** watchOS Release Lead  
**Event:** End-to-end RC5 shipping — first release under pre-release autonomy delegation.

**Work:**
- Merged PR #53 (Weiss-8: HUD power-on fix) + PR #54 (build 19→20 version bump).
- Both CI gates (3 required jobs each) passed green; CodeQL skipped per Joe's standing directive.
- Tagged v0.3.0-rc5 from main.
- Watched release-testflight workflow to completion: TestFlight upload succeeded. ARRunner 0.3.0 (20) now in pipeline.

**Model:** Pre-release autonomy (coordinator-merge + Laughlin-release) validated — no step blockers, decision inbox had the pre-release directive ready-to-hand.

**Next:** Await release-testflight job completion + tester sanity gates. Ready for rc6 (if needed) or final v0.3.0 push.

---

### 2026-05-18T23:00:00Z — v0.3.0-rc6 Release: Pre-Release Autonomy + Post-Release Cleanup

**Role:** watchOS Release Lead  
**Event:** Second pre-release under autonomy model; coordinated with Richards's HUD fix.

**Work:**
- Merged PR #55 (Richards: BLE serialization + flow control gate fix) under autonomy.
- Bumped build 20 → 21 in `project.yml`.
- Tagged v0.3.0-rc6, pushed to remote.
- Release-testflight workflow executed: archive, code-signing, upload to TestFlight all passed. Upload succeeded; build 0.3.0 now in TestFlight pipeline.

**Operational debt recorded:**
- ⚠️ Used `sleep N && gh pr view ... | python3` polling pattern for CI checks.
- Result: **7 stuck shell processes** left running after the coordinator killed them manually.
- **Lesson:** Use `gh pr checks <number> --watch` or `gh run watch <id>` with explicit timeout instead.
- Captured in `.squad/skills/release-mechanics-ci-polling/SKILL.md` for future releases.

**Pre-release autonomy validated:** Both rc5 (Weiss's power-on fix) and rc6 (Richards's serialization fix) shipped autonomously without manual gates. Coordination model working.

**Post-release clean-up directive applied:** Joe's directive from inbox file — swept background agents, drained stale notifications, verified no orphan shells (after killing Laughlin's 7 poll processes).

---

### 2026-05-19T03:20:00Z — v0.3.0-rc7 Release: Sole-Coder HUD Fix After 3-PR Lockout

**Role:** watchOS Dev + Release Lead (under rejection-lockout protocol)
**Event:** Both Weiss (PRs #49, #53) and Richards (PR #55) locked out from the HUD render fix after three consecutive real-device blank-screen failures. Joe spawned two parallel forensic researchers (one against ActiveLook iOS SDK source, one against the protocol spec); reports converged on two missed bugs. I was the only eligible coder remaining.

**Work:**
- PR #57: encoder + adapter fix. Two changes:
  1. `ActiveLookCommand.encode` now defaults to `format = 0x01` + 1-byte queryID (was `format = 0x00` with no queryID). Engo 2 firmware silently misparses missing-queryID frames — reads the on-byte of `power(on:true)` as the queryID, shifts txt coordinates 5000+ px off the 304-px panel. Exactly explains the rc4→rc5→rc6 symptom progression.
  2. Wired `didUpdateValueFor` for control characteristic (0xCB9) and TX characteristic (0xCB8). Previously only battery was routed; flow-control OFF signals (0x02) and 0xE2 error notifications were silently dropped. Added `flowControlAllowsWrite` runtime gate + 0xE2 error parsing/logging.
- All 147 ARRunnerCore tests pass after updating byte-pinning expectations for the new envelope; added 3 new tests including a regression guard for the missing-queryID bug.
- Merged PR #57, bumped build 21→22 (PR #58), tagged v0.3.0-rc7, watched release-testflight.yml to "No errors uploading archive" with Delivery UUID 885f579c-589a-41e3-96de-743a693f46fe.

**Learnings:**

1. **queryID is implicitly required by Engo 2 firmware, even though spec marks it optional.** The protocol spec (§3.1) shows queryID as 0–15 bytes ("optional"), but the official ActiveLook iOS SDK ALWAYS attaches a 1-byte queryID for every application command. `withoutQueryId: true` is only passed for three DFU ops. Firmware parsing apparently assumes the queryID is always there. **Rule for any future ActiveLook command we add: always include the 1-byte queryID; only opt out for DFU.**

2. **Always wire `didUpdateValueFor` for ALL ActiveLook notify characteristics — not just battery.** The control char (0xCB9) and TX char (0xCB8) carry critical runtime signals: flow-control state, "corrupt command" errors, "protocol decoding error" responses. Routing only the battery char silently masks every command rejection. Without this observability, three PRs shipped without ever seeing the glasses' actual feedback.

3. **Cross-research methodology after N consecutive failures: spawn two parallel researchers on different evidence sources, look for convergence.** Joe spawned one researcher against the iOS SDK source (`ActiveLook/ios-sdk`) and another against the protocol API doc (`Activelook-API-Documentation`). Independent investigations converged on the same two bugs — that convergence is what made it safe to ship without another hardware iteration. When three PRs from two different agents all fail with similar symptoms, the bug is upstream of any of them; you need orthogonal evidence to find it.

4. **CI polling pattern that doesn't leave shell zombies (per `release-mechanics-ci-polling` skill):** `gh pr checks <pr> --watch --interval 30` is great when required-check labels exist on the branch; otherwise a short bash loop calling `gh pr checks <pr>` and `gh run view <id> --json status,conclusion` with `sleep 45` between iterations works fine. The trap is `sleep N && gh pr view ... | python3` constructs that left 7 orphan shells in rc6.

---

### 2026-05-19T11:55:00Z — v0.3.0-rc8 Release: cfgSet("ALooK") — the bug all prior PRs danced around

**Role:** watchOS Dev (sole-coder under Joe-authorized lockout-override)
**Event:** After PR #57 (rc7) shipped the verified-correct queryID + flow-control + 0xE2 observability fix, Joe's bench test still showed a blank screen. All three coders (Weiss, Richards, me) were now formally locked out per strict-lockout protocol. Joe explicitly authorized a one-time override for me to own rc8 after a demoapp forensic researcher analyzed the `ActiveLook/Activelook-Visual-Assets` repo and found the deeper bug.

**Work:**
- PR #60: prepended `cfgSet("ALooK")` (cmdID 0xD2, NUL-terminated config name) to `connectFrames()` and `framesWithPowerOn(for:)`. Added `ID.cfgSet = 0xD2` to the encoder enum. Fixed the rotation mislabel (`Layout.rotation: 4 → 0`; `0` = bottomRL per the SDK enum, which is the natural reading direction through the waveguide — `4` was actually `topLR`).
- 150 ARRunnerCore tests pass (147 prior + 3 new: cfgSet encoder bytes, NUL-terminator across name lengths, connectFrames cmdID guard).
- Merged PR #60, bumped build 22→23 (PR #61), tagged v0.3.0-rc8, watched release-testflight.yml to `UPLOAD SUCCEEDED with no errors` (MARKETING_VERSION=0.3.0 CURRENT_PROJECT_VERSION=23).

## Learnings

1. **Fonts on Engo 2 are configuration-resident, not firmware-resident.** Fonts 1–5 (SourceSansPro at 24/38/64/75/82px) live inside the "ALooK" configuration stored in the glasses' flash, NOT baked into base firmware. The `ActiveLook/Activelook-Visual-Assets` README states verbatim: *"To use the activelook visual asset, use the command: `cfgSet("ALooK")`"*. Without `cfgSet("ALooK")` on every connect, font index 3 (and 1, 2, 4, 5) does not exist in the active namespace; the glasses silently drop our `txt` commands or emit 0xE2 errors. **Rule: before any `txt` command referencing fonts 1–5, layouts, or images, the connection must have called `cfgSet(name: "ALooK")` at least once.** `clear()` and `power(on:true)` succeed without it because they reference no fonts — which is exactly why this bug hid behind a "screen cleared but no draws" symptom.

2. **The four-PR meta-pattern: every prior fix WAS real, but a deeper bug masked visible output.** PR #45 (pairing), #49 (initial HUD plumbing), #53 (connect race), #55 (write serialization), #57 (queryID + flow-control + observability) — none were wrong. Each one fixed a real bug that would have eventually surfaced. But each landed on top of the missing-`cfgSet` issue, so none produced visible text on the glasses, and each one got blamed for "not fixing the blank screen." Lesson: when N consecutive PRs from different agents all "don't fix" the same symptom, the symptom is downstream of a bug none of them is touching. Stop iterating on the same artifact and look orthogonally.

3. **When the spec + SDK source don't give the answer, look for ancillary asset/data repos.** The protocol spec (`Activelook-API-Documentation`) and the iOS SDK source (`ActiveLook/ios-sdk`) were both consulted by prior forensic rounds and BOTH missed the cfgSet requirement — the spec marks `cfgSet` as optional ("if using layouts/images"), and the SDK exposes it as a method without any "you must call this on connect" docstring. The answer was in a third repo, `ActiveLook/Activelook-Visual-Assets`, which exists specifically to ship the default-config asset bundle. Its README is the only place that states `cfgSet("ALooK")` is mandatory. **For any embedded-device SDK, sweep the vendor's full GitHub org for asset/data/config repos — they often carry the operational rules that the protocol spec and SDK source omit.** I'm updating my mental "research checklist" to always include "look for `*-Visual-Assets`, `*-Configurations`, `*-Resources` repos under the vendor org."

4. **One-time lockout overrides are legitimate when the diagnosis becomes spec-backed AND the fix is mechanical.** The strict-lockout protocol exists to force fresh perspective when an artifact has resisted multiple iterations. But once the diagnosis flips from "unknown root cause" to "documented requirement we missed," the override criterion shifts: the original author isn't going to re-introduce the same blind spot when following an explicit recipe. Joe's call to give me rc8 was based on (a) rc7 demonstrated I execute specs correctly when the spec is clear, (b) the demoapp report contained byte-level steps, (c) zero risk (one extra 13-byte BLE write on connect). This is the model for future overrides — diagnosis quality + fix mechanicalness, not "we trust this person more now."
