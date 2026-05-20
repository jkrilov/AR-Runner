# Richards — History (Summarized 2026-05-19)

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

---

## 2026-05-19: ADR — BLE Link Lifecycle (User-Managed, Not Workout-Scoped)

**Trigger:** Joe's rc16 bench report: connection drops on workout-stop, finish screen never lands, manual re-pair required. Confirmed NOT a regression — that was always the contract. rc17's confirmSave/confirmCancel already comply (no teardownTransport), but contract was undocumented.

**What I wrote:** `.squad/decisions/inbox/richards-adr-ble-link-lifecycle.md` — full ADR with:
- **4 invariants (I1–I4):** Link persists, finish frame persists until user action, subscriptions per-link, phone never precondition
- **5 tear-down rules (R1–R5):** confirmSave/confirmCancel MUST NOT disconnect, only two legal paths
- **5 reconnect-policy clauses (P1–P5):** Unbounded attempts, 1/2/5/15/30/60 s backoff, adaptive throttle
- **4 subscription rules (S1–S4):** Per-link, survive workout boundaries, battery 0x2A19 on every .connected
- **3 phone-optional clauses (PO1–PO3):** Battery authoritative on watch, opportunistic mirror on phone, phone offline = no watch impact

**Architectural insight:** "peripheral session ⊥ application session" — they observe each other but neither owns the other's lifecycle. Once workout-finish drives peripheral teardown, you've created coupling that breaks finish-HUD, battery telemetry, post-workout review. The fix is declaring orthogonality as a contract.

**Heuristic:** If tear-down lives in application shutdown path, ask "who else needs this resource after this event?" If anyone, the resource is mis-scoped. Promote to user-managed.

**Promoted to skill:** `.squad/skills/paired-hardware-lifecycle-contract/SKILL.md` (generalizes for any paired BLE/USB/HID device).

**Implications:**
- Weiss: audit adapter disconnect() sites, implement P1–P5 backoff, subscriptions idempotent, battery 0x2A19 on-connect
- Laughlin: add regression test asserting disconnect() NOT called in confirmSave/confirmCancel
- Amber: battery-on-phone is WatchConnectivityService mirror, never critical path

**Status:** Scribe merged ADR to decisions.md 2026-05-19T22:25Z. rc17 implementation (Laughlin + Weiss + Amber) validated compliant. Canonical contract now in place for v0.4+.

---

## Key Learnings Retained

1. **Peripheral lifecycle is a first-class design concern.** Treat it as orthogonal to application lifecycle; never gate on transient events.
2. **Coordinate systems need canonical transforms, not derived recipes.** The lens-flip formula `y_fb = 255 − wearer_top` is now authoritative; any new screen must validate against it.
3. **Preloaded peripheral assets >> custom upload pipelines.** Check vendor asset catalog before invoking upload machinery.
4. **Bundled-bump pattern cuts release cycle in half.** Feature + version + xcodegen + tag + TestFlight in single PR; now team standard.
5. **BLE protocol layering matters.** ATT response gating is necessary but not sufficient; peripherals have application-layer flow control above it.

---

## 2026-05-20: Strava ingestion gap diagnostic

**Trigger:** Joe ran a 5k, workout reached Apple Fitness/Health but did NOT propagate to Strava. Path #1 (Strava-side toggle) pre-ruled-out by Joe in earlier clarification. Asked for a diagnostic, not code, not yet an ADR.

**What I found:** `HealthKitWorkoutSubstrate` writes `HKWorkout(activityType=.running, locationType=.outdoor)` with distance/energy/HR samples — but **no `HKWorkoutRoute` and no `CLLocationManager`**. Repo-wide grep for `HKWorkoutRoute|CLLocation|workoutRouteBuilder` returns zero matches. Story 3 in v030-roadmap-proposal listed route-writing as a deliverable; the route half never shipped.

**Root cause:** Outdoor workout with no route = Strava's auto-import filter drops/suppresses it. Same root cause as Joe's bench item #1 (GPS not recorded). **One bug, two symptoms.** Loud-coupling observation: Laughlin's GPS fix is the Strava fix.

**Secondary hypothesis named (not load-bearing):** Strava may additionally filter by source-app (only Apple Workout app auto-imports). Counter-evidence exists (WorkOutDoors, iSmoothRun work). Treat as fallback diagnostic if GPS fix doesn't close gap.

**Recommendation written:** Land GPS fix, re-bench, expect both items to clear together. Escalation path A (HealthFit/RunGap middleware FAQ) if not. Path B (direct Strava API + OAuth) deferred — name the trigger (≥3 TestFlight complaints OR strategic v0.6 social-export decision), don't pre-build it.

**Output:** `.squad/decisions/inbox/richards-strava-integration-diagnosis.md`.

### Key learning retained

**When two user-reported bugs share a missing subsystem, name the coupling out loud and re-cost the prioritization.** Joe was about to treat "GPS recording" and "Strava sync" as two separate workstreams; they collapsed into one ~half-day fix the moment I traced the substrate and saw the route builder was simply absent. The architect's value here was not picking the path — it was preventing two parallel investigations into one underlying gap.

### Pattern → skill candidate

Generalizable triage pattern: **"third-party fitness platform integration triage"** — diagnose third-party-platform ingestion failures by (1) verify platform-side config first, (2) audit what HK shape we actually write vs. what the receiver's filter expects, (3) look for missing-subsystem coupling to other open bugs before recommending integration work. Wrote as `.squad/skills/third-party-fitness-platform-integration-triage/SKILL.md`.

---

## 2026-05-20T13:19: Strava ingestion — rc3 falsifies route-shape hypothesis; source-app filter confirmed

**Trigger:** Joe — rc3 shipped (GPS-route auth fix). Apple Fitness now shows the polyline on AR-Runner runs. Strava still does not auto-import. Apple Workout app → Strava continues to work on the same device.

**What that evidence proves:** The original diagnostic's primary hypothesis (Path #2 — missing `HKWorkoutRoute` is Strava's gate) is **falsified**. We shipped the route; Strava still drops the workout. The "2-for-1" coupling between GPS recording and Strava sync was illusory — GPS was a real bug that rc3 fixed, but Strava is driven by a different gate entirely.

**Root cause (now load-bearing):** Strava's Apple Health auto-import filters `HKWorkout` by source app — only Apple's first-party Workout app is auto-imported. `HKObject.sourceRevision` is system-assigned from the writing bundle ID and cannot be overridden. **No HK payload change from inside `HealthKitWorkoutSubstrate.swift` will resolve this.**

**Decision path written:** `.squad/decisions/inbox/richards-strava-source-filter-confirmed.md`
- **Path A (recommended, v0.4):** README/FAQ pointing users to HealthFit / RunGap as the bridge. Zero code, zero maintenance, ~60–80% coverage.
- **Path B (v0.6, ADR-gated):** Direct Strava OAuth + `POST /uploads` on iPhone companion. ~200–500 LOC + ongoing OAuth / rate-limit maintenance. Schedule, don't panic-build.
- **Path C (do nothing):** Not viable for a running app — Strava is table-stakes.

**No watch-side code change recommended.** The substrate is correct as of rc3. Resisting the urge to add metadata "just in case" — rc3 evidence shows it cannot help.

### Architect-level learnings retained

1. **Falsification needs an explicit forcing function.** The original diagnostic's "GPS fix is the Strava fix" framing was a hypothesis, not a fact, but I let it carry diagnostic weight. The rc3 bench was the right falsifier — if I'd designed the diagnostic with "what bench outcome would prove this 2-for-1 wrong?" up front, I'd have caught my own confidence inflation faster.
2. **Source-app filters are a real and documented receiver-side gate, not a tinfoil-hat fallback.** I named it as a counter-evidenced fallback in the original; rc3 evidence + Strava's own help-centre wording promote it to the dominant cause. The counter-evidence I cited (WorkOutDoors, iSmoothRun) turns out to be wrong — those apps work because they ship **direct Strava integrations**, not because they bypass the source-app filter via clever HK writes. Next time, distinguish "third-party app whose data appears in Strava" from "third-party app that uses Apple Health as the bridge to Strava" — these are entirely different topologies.
3. **`HKObject.sourceRevision` is a hard system boundary.** Worth remembering for any future "make Health treat us like Apple" hypothesis — answer is always no; the API physically does not permit it.
4. **Middleware-as-product-recipe (HealthFit / RunGap) is an underrated v1 move for any HK-write app needing third-party integration.** Documenting the bridge in the README costs nothing and ships ~80% of the value. Direct integration is correct strategy long-term; bridge-and-docs is correct tactics short-term.

### Skill updated

`.squad/skills/third-party-fitness-platform-integration-triage/SKILL.md`:
- Step 2 (audit payload) is necessary but not sufficient — receiver-side source-app filters must be tested independently with a controlled bench (our app vs. the platform's native app, same device, same auth state).
- Step 3 (2-for-1 coupling) requires a named falsifying experiment up front; otherwise the coupling can be a confidence-inflation trap.

### Files touched

- `.squad/decisions/inbox/richards-strava-source-filter-confirmed.md` (new follow-up diagnostic)
- `.squad/agents/richards/history.md` (this entry)
- `.squad/skills/third-party-fitness-platform-integration-triage/SKILL.md` (post-rc3 lessons)

### Status

Awaiting Scribe to merge the inbox diagnostic into `decisions.md`. No agent dispatch needed for Path A — Joe can land the FAQ wording himself or hand it to whichever agent owns onboarding/docs. Path B is a v0.6 milestone item; do not start design until the milestone opens.

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
