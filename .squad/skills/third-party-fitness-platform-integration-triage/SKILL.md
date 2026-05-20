# SKILL: third-party-fitness-platform-integration-triage

**Owner:** Richards (Lead / Architect)
**Created:** 2026-05-20
**Trigger phrase:** "Why isn't our workout showing up in {Strava | Garmin Connect | TrainingPeaks | Komoot | Suunto | RunKeeper}?"

## When to reach for this skill

Any time a user reports that a workout AR-Runner wrote to HealthKit (or an equivalent platform sink) is not appearing in a third-party fitness service. Applies symmetrically to any "we write to platform X, expect bridge into platform Y, Y doesn't see it" report.

## The 4-step triage

Do these in order. Stop at the first step that yields a fix.

### 1. Verify the platform-side configuration FIRST. Cheapest possible win.

Before reading any of our code, confirm the receiver has the bridge enabled at all:

- Does the third-party app have the Apple Health permission toggle ON for the relevant data classes (Workouts, Heart Rate, Route)?
- Does the receiver have a per-source filter that excludes our bundle ID? (Some platforms maintain allow-lists.)
- Has the user previously denied background refresh / auto-import for the receiver app?

If YES to a config gap → fix is a one-line user instruction + a README FAQ entry. Done. No code change.

**Skip-condition:** If the user explicitly reports "other apps' workouts DO sync, only ours don't" — this step is already eliminated. Move to step 2.

### 2. Audit what shape we actually write vs. what the receiver's filter expects.

Read our HealthKit (or equivalent) write path end-to-end. Build a table:

| Field the receiver filters on | Our value | Receiver expectation |
|---|---|---|

Common rejection shapes:
- Wrong `HKWorkoutActivityType` enum case (e.g., `.other` instead of `.running`).
- `locationType=.outdoor` but no `HKWorkoutRoute` companion sample (receivers treat as low-fidelity / manual entry).
- `locationType=.unknown` defaults that downstream maps refuse to render.
- Missing cumulative samples (distance/energy as scalars on the workout, but no per-second `HKQuantitySample` time series).
- Source bundle metadata pointing at an old app ID or a development bundle the receiver hasn't been told about.

Use `grep -rniE "<sample-type>"` to confirm a sample type is genuinely written somewhere, not just declared in the authorization set.

### 3. Look for missing-subsystem coupling to OTHER open bugs before scoping the fix.

This is the highest-value step and the one most easily skipped.

Before recommending integration work, scan the open-bugs list for any report that names the same underlying primitive. Example from AR-Runner 2026-05-20:

- Bug A: "GPS not recorded during runs."
- Bug B: "Strava doesn't see our workouts."
- Root cause for both: `HKWorkoutRoute` is never written; no `CLLocationManager` exists in the substrate.

These collapse to one fix. If you scope them separately, you either (a) double-count effort, or (b) ship the integration work first and discover the platform now imports a workout with broken/missing route data. Always check.

**Heuristic:** if two user-reported symptoms share a missing subsystem, name the coupling **loudly** in the diagnostic. It changes prioritization (one fix unblocks two complaints) and protects future agents from picking up the second bug as a separate workstream.

### 4. Only if 1–3 don't yield a fix: scope a direct API integration as the heavy fallback.

Direct integration (OAuth + upload endpoint + retry queue + token storage) is typically 200–500 LOC + a developer account + ongoing maintenance of rate-limit handling and OAuth token rotation. It is correct when:

- The platform's bridge truly filters us out by source app (verify with controlled test after step 2 fix lands).
- We need to preserve payload fidelity the platform's HK bridge strips (.fit/.gpx file vs. lossy HK sample reconstruction).
- The integration is strategically core (e.g., social-sharing for a running app — table-stakes long-term).

It is NOT correct when:
- We haven't yet shipped step 2's fix and observed the failure persist.
- The user has acceptable middleware options (HealthFit, RunGap) we can document in a FAQ.
- We're reacting to a single bug report rather than a sustained pattern.

Name the **escalation trigger** explicitly in the diagnostic (e.g., "ADR direct integration if ≥N user complaints OR strategic vX.Y product decision").

## Output shape

Always deliver as a `decisions/inbox/{agent}-{slug}.md` diagnostic, NOT an ADR. The diagnostic feeds the decision-maker's path-selection; the ADR follows once the path is picked. The diagnostic must include:

1. **Most likely root cause** — one sentence, evidence-cited.
2. **Cheapest fix likely to work** — with a cost estimate in human terms ("flip toggle, 30s" or "half-day Laughlin + onboarding tweak").
3. **Coupling to other open bugs** — stated loudly with a "2-for-1" callout if applicable.
4. **Recommended next step** — single sentence.
5. **Escalation path** — ordered list, lowest cost first, with explicit ADR triggers for heavy paths.
6. **Trade-off named** — per architect-charter doctrine: every decision has a trade-off; name it.

## Anti-patterns this skill prevents

- **Premature OAuth.** Building a direct API integration before confirming the cheap fix doesn't work. Burns weeks; usually unnecessary.
- **Symptom-scoped fixes.** Treating "Strava sync broken" and "GPS missing" as independent workstreams when they share one root cause.
- **Blame-the-receiver loops.** Spending hours on the third-party platform's settings UI when our HK write path is the actual gap.
- **Configuration-only conclusions on first pass.** Recommending "tell the user to toggle a setting" without auditing what we actually write — sometimes the toggle is already on and our payload is the problem.

## Related skills

- `healthkit-derived-metrics-watchos` — pairs with step 2 when the gap is sample-shape (sum vs. most-recent).
- `healthkit-error-7-preflight-diagnostic` — pairs when authorization is the gap rather than payload shape.

## Citations / evidence

- AR-Runner 2026-05-20 Strava ingestion gap: `.squad/decisions/inbox/richards-strava-integration-diagnosis.md`. The triage pattern was extracted from that diagnostic and generalized.
