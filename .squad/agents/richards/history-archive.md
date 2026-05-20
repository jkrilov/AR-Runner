# Richards — History Archive

**Archive created:** 2026-05-17T00:48:29Z

Summarized entries from 2026-05-14 and early 2026-05-15; see active `history.md` for recent sessions.

## 2026-05-14–2026-05-15: Foundation Architecture & CI Groundwork

**Accomplishments:**
- GitHub Remote Setup: SSH-configured, 126-file Squad scaffolding committed to `main` (fd2faad)
- CI/Simulator Runtime Matrix: Linux (ARRunnerCore purity, Swift 6.0-jammy enforcer) + macOS (Xcode 16.4 pin solved watchOS 11 runtime gap on macos-15 runner image)
- Swift 6 StrictConcurrency: Redundant `enableUpcomingFeature` flags stripped; language mode is SSOT
- System Architecture (ADR-001–007): `docs/planning/architecture.md` v0.1 delivered; D1–D9 locked by Joe
- Public-Repo Readiness: Verdict 🟡 (go after small cleanup); 5 open policy questions for Joe on LICENSE/copyright/visual-assets

**Key learnings:**
- Linux CI as architecture enforcement: Any Apple-framework leak into ARRunnerCore fails Linux build immediately
- Runner image manifest is SSOT for installed simulators/SDKs (asymmetric failures like ARRunnerPhone ✅ + ARRunnerWidgetsPhone ❌ traced to this)
- Xcode version pins ≠ simulator runtime catalog; test against CI toolchain version, not local
- `xcrun altool --upload-app` deprecated post-Xcode 15; migration planned before WWDC drop
- `@unchecked Sendable` audit pattern: all 3 production sites are NSObject + delegate bridges (canonical correct pattern)
- WCMessage `schemaVersion` guard is backward-compat but NOT forward-compat; negotiation step needed for multi-user distribution

**Non-blocking nits pending Joe's decision:**
- README hyperlink to ActiveLook website on first mention (UX for strangers)
- CONTRIBUTING.md one-liner pointing to Releases page
- Minimal CODE_OF_CONDUCT.md (GitHub community profile will flag absence)

**Reviewer rejection status:** Richards locked out of follow-up revisions on that branch per reviewer-rejection-protocol. Killian or Amber must implement nit fold-ins if Joe requests.

## Parallel Workstream Coordination (2026-05-15)

Three agents completed and opened PRs:
- **Weiss** (PR #5, `feat/ble-wrapper`): GlassesFrameTransport + ActiveLook watchOS adapter; 24 tests, CI green
- **Laughlin** (PR #7, `feat/workout-controller`): WorkoutController + HealthKit substrate; 14 tests, CI green
- **Amber** (PR #6, `feat/integration-mocks`): Integration mocks + D4 happy-path tests; 12 tests + CodeQL green

**XcodeGen stale-pbxproj incident (2026-05-15):** "Cannot find X in scope" reported for GlassesTransportFactory + ActiveLookGlassesAdapterHardwareTests; both files existed on disk. Root cause: `AR-Runner.xcodeproj/` is gitignored (generated from `project.yml`), Joe's local was simply stale. Fix: `xcodegen generate`. **Skill recorded:** `.squad/skills/xcodegen-stale-generated-project/SKILL.md`. **Lesson:** Always ask `git check-ignore AR-Runner.xcodeproj/` first before diagnosing Xcode target-membership bugs.

## Key Durable Patterns

- **Linux CI as boundary enforcement** — best architecture guard for Swift SPM projects
- **Xcode version pinning with cache** — unversioned `brew install xcodegen` breaks on format changes
- **Gitignored xcconfig + `configFiles` in xcodegen** — `bootstrap-signing.sh` required in ALL workflows, not just release
- **Runner image manifest** — SSOT for simulator catalog; match CI toolchain version locally before committing

## 2026-05-20T21:28:21Z — History compaction archive (richards)

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
