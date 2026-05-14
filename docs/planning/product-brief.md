# AR-Runner v0.1 Product Brief

**Date:** 2026-05-14  
**Product Lead:** Killian  
**Status:** v0.1 MVP scope definition

---

## Vision

AR-Runner unifies the running experience across Apple Watch, iPhone, and ActiveLook AR glasses into a single, native product—eliminating the fractured experience of ActiveLook's official apps. You start a workout from your wrist (app, Smart Stack widget, or Action Button), watch real-time metrics on the glasses HUD, mirror the live run on your phone, and sync results to Apple Health. It's what Apple Workout app expects of AR: seamless, native, performant.

---

## Target User

**Primary persona: Joe (founder)**
- Serious runner; owns Apple Watch and ActiveLook glasses
- Wants to use Apple's Workout app paradigm—start on watch, glance at wrist metrics, phone is secondary mirror
- Abhors friction: launch from multiple surfaces (not just app tap); HUD should be obvious without configuration
- Values health integration: post-run data must flow to HealthKit so Apple Fitness and third-party apps see it

**Personas to validate:**
- Runners who switch between outdoor and treadmill routes (need route map display)
- Fitness enthusiasts who want custom HUD layouts (minimalist vs. full telemetry)
- Users on older iPhones or in areas without network (offline-first assumption)

---

## Competitive Read

**Apple Workout app (baseline):**
- ✓ Start from three surfaces: app, complications, Action Button  
- ✓ Live wrist metrics; secondary display on phone
- ✓ Automatic HealthKit integration post-workout
- ✗ No AR HUD option (our white space)

**ActiveLook official apps (what to avoid):**
- ✓ Basic AR HUD display for glasses  
- ✗ **Fragmented:** watch app and phone app feel disconnected; no Apple Workout integration
- ✗ No Smart Stack widget or Action Button launch
- ✗ Manual sync friction; no native HealthKit flow
- ✗ HUD is clunky; ergonomics not optimized for running

**Our advantage:** Single product where watch, phone, and glasses are one system, following Apple's UX patterns and HealthKit as the source of truth.

---

## MVP Scope (v0.1 — Must-Have)

- **Watch app:** Start workout from three surfaces
  - App icon tap  
  - Smart Stack widget (glanceable state: paused/running)
  - Action Button (long-press mapping)
- **Live HUD (glasses):** Real-time display via ActiveLook SDK
  - Pace (min/km or min/mi)
  - Heart rate (BPM)
  - Distance (km or mi)
  - Elapsed time
- **Live mirror (phone):** Same four metrics + map (visual context only, no interaction)
- **Workout end & summary:**
  - Tap "Finish" on watch; surface summary card
  - Save metrics to HealthKit (duration, distance, active energy, HR zone)
  - Ensure Apple Fitness and other HealthKit clients see the data
- **Offline operation:** No cloud accounts, no mandatory sign-in; everything local to device
- **Single workout type:** Running only (pace/HR/distance paradigm)

---

## v1 Stretch (Nice-to-Have)

- **Route map** on phone (visual playback of GPS trace, elevation)
- **Custom HUD layouts** (curated presets: minimal, full telemetry, split focus)
- **Splits** (per-km or per-mile pace/HR breakdowns)
- **Audio cues** (pace alerts, halfway notification)
- **Multi-workout types** (cycling, walking, hiking) with appropriate metric defaults
- **Workout history** (on phone; review past runs)

---

## Out of Scope (v0 & v1)

- Social features (sharing, leaderboards, challenges)
- Training plans or coaching
- Cloud sync or cross-device accounts
- Music player integration
- Elevation or weather widgets
- Third-party app integrations (beyond HealthKit)

---

## Key User Journeys

1. **Launch from Action Button**  
   I'm stretching before a run → long-press Action Button → AR-Runner starts → watch shows 0:00, glasses ready for pace feed → I run.

2. **Glance at glasses during run**  
   Running at target pace → glance at glasses HUD → pace (6:30/km), HR (165 BPM), distance (2.3 km) all visible at a glance → back to running.

3. **Live phone mirror**  
   My partner is tracking me on phone → sees real-time pace, HR, distance, and map trace → can see if I'm slowing down.

4. **Post-run summary**  
   Finish button → watch summary card shows total distance, time, avg pace, max HR → swipe to confirm → data syncs to HealthKit → Apple Fitness and Strava (if authorized) pick it up.

5. **Configure HUD the night before**  
   Evening: open AR-Runner on phone → tap Settings → choose "minimal" HUD layout (pace + HR only) → tomorrow's run will use this preset.

---

## Open Product Questions for Joe

1. **Multi-sport or running-only MVP?**  
   Should v0.1 lock to running only, or do we scaffold for cycling/walking with pace/HR as the metric spine?

2. **HUD customization: curated presets or free-form?**  
   Do you want 3–5 presets (minimal, standard, telemetry), or allow any user to reorder/hide metrics? (Presets are faster to ship; freeform is more flexible later.)

3. **Offline-first or iCloud optional?**  
   Can we ship v0.1 with zero cloud account requirement? If you want cross-device sync later, we do it in v2. OK?

4. **What happens if glasses disconnect mid-run?**  
   Should we pause the workout, keep going (and log the gap), or surface an alert? (This affects error handling & UX significantly.)

5. **Phone secondary or equally important?**  
   Is the phone *always* running alongside the watch (carrier is always on), or can users run watch-only and sync phone later? (Changes architecture for real-time sync.)

6. **HealthKit mandatory or optional?**  
   Must every run sync to HealthKit, or is it opt-in? (Affects privacy settings, app permissions, and how we frame post-run flow.)

7. **Action Button: long-press or double-tap?**  
   Do you prefer long-press for "start workout" (clear intent) or double-tap (faster)? (Watch interaction model matters for muscle memory.)

8. **Watch app complications: which slots?**  
   Should the Smart Stack widget show current pace, or just "Running / Stopped"? (Determines complexity of data flow to complications.)

---

## Success Metrics (v0.1 Soft Launch)

- App launches from all three watch surfaces without crashes
- HUD displays all four metrics with <500ms latency
- Post-run data appears in Apple Health within 1 minute
- No manual configuration required for first run (defaults work)
- Glasses battery drain ≤ 1% per 10-minute run

---

## Next Steps

- **Validate questions above** with Joe  
- **Design watch UI** (start screen, in-run summary, end card)  
- **Design phone UI** (settings, HUD editor, live mirror layout)  
- **ActiveLook SDK integration plan** (HUD rendering, BLE lifecycle)  
- **HealthKit write schema** (sample format and test data)
