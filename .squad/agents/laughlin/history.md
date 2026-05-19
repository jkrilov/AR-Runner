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
