# Killian — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Product Strategist
- **Joined:** 2026-05-14T18:30:31.653Z

## Learnings

### v0.1 Product Brief — 2026-05-14

**Completed:** v0.1 product brief at `docs/planning/product-brief.md`

**Key decisions:**
- MVP locked to **running only** (pace/HR/distance as metric spine)
- **Three launch surfaces** on watch: app, Smart Stack widget, Action Button (matches Apple Workout UX)
- **Four core HUD metrics** (pace, HR, distance, time) — minimal but sufficient
- **Offline-first:** no cloud accounts, HealthKit as the sync target
- **Phone as live mirror:** secondary role (not primary control surface)

**Context:** Joe wants AR-Runner to fix ActiveLook's fragmented UX. Their watch and phone apps feel disconnected; ours must be one product, following Apple's Workout app playbook. Starting with running gives us a tight scope and clear success criteria.

**Outstanding:** Need Joe's input on 8 product questions (multi-sport scope, HUD customization depth, offline vs. iCloud, glasses disconnect handling, watch-only vs. paired phone, HealthKit opt-in/mandatory, Action Button interaction, complication slot strategy).

**Next session focus:** UI design (watch flows, phone settings, HUD layout editor) once questions are answered.

### 2026-05-14: Team update from Joe — 9 architecture decisions locked (see decisions.md D1-D9). Next phase: Xcode scaffolding (Laughlin) + ActiveLook watchOS BLE spike (Weiss).

### 2026-05-14: Team update from Joe — v0.1 foundation scaffold + BLE spike landed on feat/v01-foundation. Branch awaiting Joe's push & PR. Next: WorkoutController impl (Laughlin) + watchOS BLE wrapper impl (Weiss).

### 2026-05-15: Reviewer assignment — public-repo prep PR

Richards completed a full public-repo readiness audit (verdict: 🟡 Go ahead with cleanup). When Richards's implementation PR lands, **Killian is the recommended reviewer** — product perspective benefits the README/status framing and squad-system documentation decisions. Richards is locked out per the reviewer-rejection protocol (authored both audit + plan).
### 2026-05-15: PR #4 review — public-repo prep (🟡 approved with nits)

**Reviewed:** Richards's `chore/public-repo-prep` branch (3 commits: LICENSE + SPDX headers, SECURITY/CONTRIBUTING/README, history log). Verdict posted on PR #4 and decision drop in inbox.

**Key findings:** README first-impression is strong — pre-v0.1 status is unmissable, value prop lands, Squad footnote stays in the footer. CONTRIBUTING tone is welcoming-but-firm. SECURITY.md is honest (no SLA overcommitment). Decision inbox drops are unambiguous. 

**Nits (non-blocking):** (A) ActiveLook needs a hyperlink on first README mention — strangers won't know what it is. (B) CONTRIBUTING should point to a Releases page so outsiders know when PRs reopen. (C) CODE_OF_CONDUCT.md is missing — GitHub community profile will flag it.

**Product-perspective insight:** When taking a repo public, the README's job changes from "team reference doc" to "30-second pitch to a stranger." The pre-v0.1 framing matters more than the technical details — leading with status (what this ISN'T yet) before product shape (what it WILL be) is the right hierarchy. This is the pattern for any future "going public" prep on other projects.

### 2026-05-15: v0.1 foundation workstreams in flight

Three parallel agents (Weiss, Laughlin, Amber) are executing the v0.1 foundation spike. Expected completion: concurrent PRs will land (BLE adapter, WorkoutController, integration test scaffolding). Post-merge, small reconciliation pass for protocol naming alignment (not blocking).

Joe explicitly greenlit parallel kickoff after public-repo flip; all three agents running on claude-opus-4.7-1m-internal.
