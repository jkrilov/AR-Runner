# Richards — History (Compacted 2026-05-20)

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead / Architect
- **Joined:** 2026-05-14T18:30:31.650Z

## Session 2026-05-27: v0.5.20 Release Guard Tag-Push Validated

**v0.5.20 shipped — release-guard fix end-to-end validated.** PR #117 (chore/release-monotonicity-guard-fix, merge `13c8f7a`) fixed two interacting bugs in `release-testflight.yml`: self-collision on tag-push + SemVer misordering in `sort -V`. Tag `v0.5.20-1` auto-triggered workflow run 26511705252, guard PASS, build 50 shipped to TestFlight. First v0.5.x pre-release to traverse tag-push cleanly (v0.5.5–v0.5.19 all required `workflow_dispatch` workaround). Release path now functional; all future pre-releases auto-trigger reliably.

---

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

---

## 2026-05-21T11:46:12-04:00: Cloudflare Worker source landed in git

**Trigger:** The Strava OAuth proxy at `strava-connect.ar-runner.app` was already deployed and serving `POST /token`, but only `.wrangler/` and `node_modules/` were on disk — the source was never tracked. Joe asked me to reconstruct the source and add `/deauthorize`.

**What I created under `infrastructure/auth-worker/`:**
- `wrangler.toml` — `name=strava-connect`, `main=src/index.js`, custom domain route `strava-connect.ar-runner.app/*` (zone `ar-runner.app`), compatibility_date `2025-05-01`. `STRAVA_CLIENT_SECRET` is **not** declared as a `[vars]` entry — it's set via `wrangler secret put` so it never lands in git.
- `src/index.js` — ES-module Worker (`export default { fetch }`) with a route table dispatcher. Three POST endpoints (`/token`, `/refresh`, `/deauthorize`) plus OPTIONS preflight, JSON-body validation, 400/404/405/500 error envelopes (`{error, message}` shape), CORS `*` headers, upstream response pass-through preserving Strava's HTTP status. Strava is called with `application/x-www-form-urlencoded` (token endpoint requires it); `/deauthorize` passes the token via `Authorization: Bearer` header, which is the form Strava's docs prefer.
- `package.json`, `.gitignore` (ignores `node_modules/`, `.wrangler/`, `.dev.vars`), `README.md` with deploy + endpoint reference.

**Architecture notes worth keeping:**

1. **Worker hostname correction.** History had the old hostname (`strava-auth-worker.jkrilov.workers.dev`) from the v0.5 ship notes. The live worker is now `strava-connect.ar-runner.app` — custom domain on the `ar-runner.app` zone, same zone we use for the Strava OAuth callback (`arrunner://ar-runner.app/callback` redirect handler). Update the Strava ADR if the iOS client still references the workers.dev hostname.

2. **Source-of-truth gap was a real risk.** A deployed-but-untracked Worker means a single Cloudflare dashboard accident or account loss vaporizes the service. Going forward: any new Worker we deploy must land its source under `infrastructure/` in the **same PR** that creates the deployment. Treat this as a standing rule — the auth-worker omission was an oversight, not a pattern.

3. **`/refresh` was the load-bearing addition I almost missed.** Joe called it out — Strava access tokens expire every 6h, and without a refresh endpoint the iOS client would have to ship `client_secret` itself the moment a token expired. Adding `/refresh` here keeps the "secret lives only in the Worker" invariant intact for the full token lifecycle, not just the initial code exchange.

4. **`/deauthorize` shape: Bearer header vs form field.** Strava's deauth endpoint accepts the token either as `access_token=...` form field or `Authorization: Bearer ...` header. I picked the header form because it (a) matches what the iOS client would do if calling Strava directly someday, and (b) keeps the request body empty so we don't accidentally log secrets if request-body logging gets enabled at the Worker edge.

5. **Route dispatcher over if/else chain.** Three endpoints is the inflection point where a `ROUTES[path][method]` table beats a switch — adds 405 handling for free (path matches, method doesn't) and makes the 404 path obvious. Worth reusing the pattern if we add a v2 worker for App Attest or webhook ingestion.

**Files touched:**
- `infrastructure/auth-worker/wrangler.toml` (new)
- `infrastructure/auth-worker/package.json` (new)
- `infrastructure/auth-worker/.gitignore` (new)
- `infrastructure/auth-worker/src/index.js` (new)
- `infrastructure/auth-worker/README.md` (new)
- `.squad/agents/richards/history.md` (this entry)
- `.squad/decisions/inbox/richards-worker-source.md` (new)

**Status:** Files created and `node --check` clean. Not committed — per task, another agent handles the iOS side and the eventual PR. When that PR lands, the iOS Strava ADR should be updated to reference `strava-connect.ar-runner.app` as the canonical worker host (and add `/refresh` + `/deauthorize` to its API surface).

---

## 2026-05-26 — Cross-agent note: v0.5.19 shipped + release-testflight.yml guard bug

**From:** Scribe (on behalf of parallel session: Amber + Laughlin + Laughlin-1)

**Heads-up:** v0.5.19 shipped to TestFlight. Discard dialog message corrected (v0.2 stale text → clear message). VERSION bumped 0.5.18→0.5.19, all CI green, PR #116 merged.

**Tech debt discovered:** `release-testflight.yml` has a self-colliding tag-monotonicity guard. When a pre-release tag `v*.*.*-*` is pushed, the guard calculates `LATEST_TAG = $(git tag --list 'v*' | sort -V | tail -n 1)` which includes the trigger tag itself, so `LATEST_TAG` always equals the new tag and the guard fires `::error::Version X matches an existing tag (vX)`. Workaround: delete the tag and re-dispatch via `workflow_dispatch` with `version=X.Y.Z`. (This is what Laughlin-1 did for v0.5.19.)

**Action for future:** A v0.5.20 chore should fix the guard to exclude its own trigger tag and use semver-correct sort ordering (pre-release suffix < bare release). This is low-urgency but load-bearing for any future pre-release cycle.

---

## Learnings

### 2026-06-17 — Strava OAuth 401 diagnosis

- The user-facing “Couldn't complete Strava sign-in (HTTP 401)” string comes only from `SettingsViewModel.userMessage(for:)` mapping `StravaOAuthError.tokenExchangeFailed`, so this error identifies the initial OAuth code-to-token exchange, not TCX upload.
- The iOS app posts the auth `code` plus `StravaConfig.clientID` to `https://strava-connect.ar-runner.app/token` in `ARRunnerPhone/Strava/StravaOAuthService.swift`; the Cloudflare Worker then forwards to `https://www.strava.com/oauth/token` with `client_id`, Worker-held `STRAVA_CLIENT_SECRET`, `code`, and `grant_type=authorization_code`.
- `ARRunnerPhone/Strava/StravaConfig.swift` ships only the public client ID. It resolves from runtime env, then Info.plist key `StravaClientID`, then placeholder. Info.plist gets `StravaClientID: $(STRAVA_CLIENT_ID)` from `project.yml`; `Config/Strava.xcconfig` is gitignored and included indirectly by generated `Config/Signing.xcconfig`.
- Most likely bench failure class: the app’s `STRAVA_CLIENT_ID` and the Worker’s `STRAVA_CLIENT_SECRET` are not the same Strava API application, or the Worker secret is absent/stale. Redirect domain still matters, but a successful return with a code makes it less likely than token credential mismatch.
