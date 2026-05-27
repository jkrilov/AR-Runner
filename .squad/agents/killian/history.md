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

---

### 2026-05-19T09:00:00Z — v0.4.0 roadmap proposal + scope decision

**Work:** Delivered complete v0.4.0 roadmap proposal with five open questions for Joe, covering:
- Core features (Live HR, Finish Screen)
- Suggested additions (Battery, HR zone brightness, Gesture layout switch)
- Iterative rc-per-feature release strategy matching v0.3.0 pattern
- Effort estimates and dependencies

**Joe's answers (2026-05-19T12:50:00Z):** All 5 questions answered and v0.4.0 scope locked:
1. HR zone brightness → DEFERRED to v0.4.1 (keep HR text at default brightness for v0.4.0)
2. Finish screen asset ID 10 → Confirmed, use Path B1 (imgDisplay)
3. Gesture layout switch → DEFERRED to v0.5.0 (Weiss needs bench time)
4. Release timing → Iterative rc-per-feature confirmed
5. GA target → No fixed deadline; iterative cadence

**Scope locked:** rc1 = Live HR, rc2 = Finish Screen, rc3 = Battery indicator. All v0.4.0 work blocked on Joe's rc9 bench confirmation.

**Learnings:** Roadmap proposals with explicit open questions are more valuable to leadership than narrative proposals. Joe answered all 5 questions in a single pass, suggesting the question structure made decision-making faster. The "pick 0-2" suggestions framework (with effort/signal labels) enables product trade-offs at the decision point rather than mid-implementation.

### 2026-05-19: Post-rc17 docs cleanup sweep (PR #78)

**Work:** README refresh + Swift comment hygiene pass. Branch `cleanup/post-rc17-docs-sweep`, two commits, no functional change, no version bump.

**README pattern that landed** (Joe-flavoured, for future hardware-app READMEs):

1. Status badge tells the truth — actual rc/build, not "scaffolding".
2. Lead with the contract, not the marketing line — for AR-Runner that's "Watch + glasses is the product, phone is optional."
3. "What works today" before "What's planned." Bullets are concrete shipped capabilities, not narrative.
4. One "Architecture notes worth knowing" section for the 3-5 non-obvious facts a new contributor needs (lens-flip framebuffer, BLE serialization, curated-layout-not-runtime-upload). Each bullet links to where the long form lives.
5. Release-pattern section names the convention explicitly (bundled bumps, auto-release, immutable tags) — it's not folklore.
6. Bench-testing section just points at `.squad/decisions.md` rather than duplicating the matrix. Decisions ledger is the source of truth.
7. No fluff, no roadmaps, no emoji. ~140 lines is the budget.

**Comment hygiene heuristics applied** (kept the bar high — only deleted when both stale and redundant):

- **Drop** "v0.X audit Py.z" tags when the audit's fix is now obvious from the code shape and captured in a skill or ADR. The tag is archaeology, not signal.
- **Drop** dated provenance ("v0.2.0 device feedback (Joe)") on features that have long-shipped — the rationale stays, the date tag goes.
- **Replace** version-numbered references to old per-release decisions (`v0.2 decision #3`) with the canonical contract language now used everywhere (`phone-optional`). One vocabulary, one place to update.
- **Drop** "not yet exposed in vX.Y UI" qualifiers that are now technically true but misleadingly versioned.
- **Keep** lens-flip formulas, BLE wire-byte annotations, ADR references, skill citations, "why" rationale, fall-through-order explanations. Cost of a stale comment is small; cost of deleting context Weiss/Laughlin needs next month is large.
- **Conservative rule of thumb:** if shortening required more than ~3 lines of net change to a single comment block, it was too aggressive.

Final touch: 10 files, 21 net lines removed, 186/186 still green. Wrote skill `swift-comment-hygiene-checklist` capturing the rubric.

---

### 2026-05-20T14:50:00Z — Cross-agent note: rc2 feature surface evolved

**From:** Scribe (on behalf of rc2 batch agents)  
**Heads-up:** README item-level features have evolved in rc2 (PR #79, pending merge).

**What changed:**
- Item #1 (GPS): Now recorded end-to-end via CLLocationManager + HKWorkoutRouteBuilder (was: not implemented in rc1).
- Item #2 (Strava): Richards diagnostic confirmed it couples to item #1; likely unblocks for free once GPS fix ships. README can mention "Strava auto-import support via Apple Health" as planned.
- Item #3 (Finish screen): Layout reflowed to 3-line / 4-data (was: 2-line / 3-data in rc1). Readability improved.

**Action for you:** After Joe's rc2 bench validates and PR #79 merges, README feature list may need a bump to reflect:
- "GPS tracking and route recording ✓"
- "Strava auto-import via Apple Health (post-rc2)" or similar
- Finish-screen description if the new layout changes the marketing story

**No action needed now** — just flagging so you're not surprised when Joe asks for the README refresh. The v0.4.0 "What works today" section will be the main surface area to touch.

**Link:** See decisions.md entries 2026-05-20T for full rc2 context (richards diagnostic, weiss coords, amber criteria, laughlin implementation).

---

## 2026-05-26 — Cross-agent note: v0.5.19 shipped + v0.5.20 chore recommendation

**From:** Scribe (on behalf of parallel session: Amber + Laughlin + Laughlin-1)

**Heads-up:** v0.5.19 shipped to TestFlight. Joe's discard regression report resolved: code is correct, UX message was stale v0.2 text that contradicted the rc2 fix. Message updated, VERSION bumped 0.5.18→0.5.19, all CI green, PR #116 merged.

**Tech debt flagged:** `release-testflight.yml` tag-monotonicity guard self-collides on pre-release tags. When `v*.*.*-*` is pushed, the guard includes the trigger tag in its own comparison, always fires an error. Workaround: delete tag + re-dispatch via `workflow_dispatch`. Load-bearing issue for next pre-release cycle.

**Recommendation:** v0.5.20 roadmap should include a small chore to fix the guard logic (exclude trigger tag, use semver-correct sort). Laughlin-1's ship log has the diagnostic details.

---

## 2026-05-27 — Cross-agent note: v0.5.20 shipped via tag-push (first to do so cleanly)

**From:** Scribe

**Heads-up:** v0.5.20 shipped to TestFlight. The v0.5.20 chore (release-guard fix) that Laughlin-1 had prepared is now complete and validated end-to-end. PR #117 merged (`13c8f7a`), tag `v0.5.20-1` pushed, workflow run 26511705252 PASS (monotonicity guard did NOT self-reject). Build 50 shipped.

**Release infrastructure impact:** This is the first v0.5.x pre-release in project history to traverse the tag-push path cleanly. All prior releases (v0.5.5–v0.5.19) required `workflow_dispatch` workaround. The fix works. All future pre-releases will auto-trigger reliably.

**What this unblocks:** Streamlined release cadence. No more manual workflow_dispatch fallback. Next pre-release will reconfirm the pattern; by then we'll have high confidence that the release path is robust.
