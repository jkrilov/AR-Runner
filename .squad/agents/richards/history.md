# Richards — History (Compacted 2026-05-20)

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead / Architect
- **Joined:** 2026-05-14T18:30:31.650Z

## Session 2026-05-18: Release v0.3.0-rc6 (BLE Fix)

**BLE Write Serialization Root Cause (PR #55):** rc5 failed with blank HUD. Root cause: ActiveLook protocol requires two serialization layers: (1) write-response gating per `didWriteValueFor`, (2) flow-control subscription gate (`GlassesInitializer.isReady()` confirms `flowControlCharacteristic.isNotifying == true`). Our adapter violated both, firing 4 frames back-to-back into an unprepared peripheral.

**Fix:** Gate `.connected` on flow-control notify confirmation (2s timeout), replace fire-and-forget with `CheckedContinuation`-based `write()` awaiting didWriteValueFor, add os_log.

**Key learning:** "Write returned" ≠ "peripheral processed command." Read vendor SDK's write-path BEFORE building your own. ATT `.withResponse` is necessary but not sufficient.

**Result:** 145 tests passing; PR #55 merged into rc6.

---

## Earlier Sessions — Archive Summary

**rc1–rc15:** TestFlight platform engineering (signing identity, App ID capabilities, provisioning profiles, export signing). Comprehensive SKILL at `.squad/skills/ios-testflight-ci-via-actions/SKILL.md`.

**rc12–rc16:** Bundled-bump release pattern validated (5 releases, feature + version + xcodegen in single PR, no follow-up bump).

**rc13–rc16 Architecture Review:**
- **Lens-flip formula canonicalized:** `y_fb = 255 − wearer_top` (empirically pinned by Joe's rc16 bench evidence)
- **Tech debt accruing:** Layout enum god-bag (25+ constants), font metrics hardcoded in prose (needs ALookFontMetrics helper)
- **Solid patterns:** Per-link BLE subscription gating, preloaded ALooK assets over custom upload, 4-field live HUD + 2-field finish HUD
- **Open recommendations:** #1 geometry helper, #2 font metrics table, #5 finish-screen Y recompute (→ rc17)


## Recent Sessions (Compacted)

### 2026-05-19 — ADR: BLE link lifecycle
- Formalized the paired-hardware contract: workout end must not own disconnect, reconnects are effectively unbounded with capped backoff, battery subscription is per-link, and the phone is optional.
- Durable heuristic: if teardown lives in app shutdown but another user action still needs the resource, the resource is mis-scoped and should become user-managed.

### 2026-05-20 — Strava ingestion gap diagnostic
- The first pass correctly traced a missing route-writing subsystem and collapsed “no GPS” + “no Strava” into one investigation, but that coupling stayed a hypothesis until rc3 bench data arrived.
- Durable heuristic: verify receiver config, audit the exact HealthKit shape we write, and name the falsifying experiment up front.

### 2026-05-20T13:19 — rc3 falsification: source-app filter confirmed
- rc3 proved route data was present but Strava still dropped AR-Runner workouts; the load-bearing cause is Strava's source-app filter, and `HKObject.sourceRevision` cannot be spoofed from app code.
- Practical takeaway: document HealthFit/RunGap in the short term, and treat receiver-side source filters as first-class constraints in future integrations.

---

## 2026-05-20T13:43:51-04:00: Strava direct-integration architecture plan (Path B, promoted v0.6→v0.5)

**Trigger:** Joe accepted that source-app filter is the load-bearing cause (rc3 falsified the route hypothesis) and chose to pull Path B forward from v0.6 to v0.5. He has a Strava account, can register an API app, wants a thorough plan BEFORE implementation.

**What I delivered:** `.squad/decisions/inbox/richards-strava-api-architecture.md` — full architecture covering:
- API app setup (steps, credentials, rate limits, approval thresholds)
- OAuth options analysis (A=phone+share recommended; B/C/D ruled out — Strava does not implement RFC 8628 or any device-grant variant)
- Upload format selection: **TCX over FIT/GPX** (best fidelity-to-dependency ratio; zero third-party libs)
- Token storage: shared keychain (App Group) + WatchConnectivity mirror; `client_secret` on watch (with Cloudflare-worker proxy as user-choice alternative)
- 5 architectural decisions to lock (D-Strava-1..5)
- 5 open questions to Joe
- Scope/effort: ~850 LOC across 6 core files + UI + tests, ~1 week, no dependencies
- Three-PR sequencing (Amber: TCX encoder → Laughlin: OAuth+tokens → Laughlin: uploader+queue+wiring)

### Architect-level learnings retained

1. **"Phone-optional" is a runtime invariant, not a setup invariant.** I almost framed Option A as a violation of the phone-optional contract (D5). It isn't. D5 says the phone is not required *during workouts*; it does not say the phone can never be required *once at pairing*. Recovering that distinction unlocked Option A as the only feasible path. **Architectural invariants need precise scope qualifiers — "during X" and "for Y" — or they overconstrain future decisions.**

2. **The watch can do its own URLSession + OAuth refresh.** Easy to forget when the team has been heads-down on BLE + HealthKit. Watch is a full HTTPS client with keychain; the only thing it lacks vs. phone is the OAuth-consent-rendering surface. **Distinguish "can't render UI" from "can't do network" — they collapse together in mental models and they shouldn't.**

3. **Scope estimates inflate when you actually enumerate files.** The earlier diagnostic said 200–500 LOC for Path B. Concrete file-by-file estimate is 850 LOC (encoder + queue + token store add the ~350 LOC the rough estimate elided). **When the cost matters for milestone planning, do the per-file enumeration; the round-number estimate will lie by 2x.**

4. **`client_secret` on watch is the right call for a personal-tier app — and it's the kind of decision that needs to be named in writing.** The instinct is to feel uncomfortable about duplicating a secret. The pragmatic reality is that for a personal Strava app, the secret rotates easily and the attacker payoff is near-zero. The alternative (server-side proxy) adds a runtime dependency that violates "no servers" doctrine. Naming the trade-off explicitly in the ADR is what lets future-team revisit it confidently if the threat model changes.

5. **TCX deserves a closer look than its reputation suggests.** Industry chatter treats FIT as the only "serious" upload format. For our payload — workout + route + HR + lap — TCX has every field we need, ships as plain XML, and adds zero dependencies. FIT's wins (developer fields, training-effect metadata) are fields we don't capture anyway. **Format-fitness depends on what you actually have to encode, not on which format is "best in class."**

### Skill candidates

The "phone-optional invariant has scope qualifiers" pattern from learning #1 is a candidate for a generalizable skill — applies anywhere there's a "device-optional" or "offline-first" invariant. Watching for a second instance before promoting to a SKILL.md. The existing `phone-optional-companion-qa` skill is QA-flavored; what's missing is the architect-side discipline of pinning down the scope quantifier when an invariant gets cited.

### Files touched

- `.squad/decisions/inbox/richards-strava-api-architecture.md` (new architecture plan)
- `.squad/agents/richards/history.md` (this entry)

### Status

Awaiting Joe's review of the architecture plan and answers to the five open questions. No agent dispatch until Joe signs off the plan. After sign-off: Scribe merges to decisions.md as ADR-Strava, milestone v0.5 opens, three-PR sequence begins.
