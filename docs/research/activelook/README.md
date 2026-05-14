# ActiveLook Integration Research

**Compiled:** 2026-05-14  
**Researcher:** Weiss  
**Scope:** Five official ActiveLook repositories—platform, SDK, tooling, and reference implementation

---

## Index

1. **[demo-app](./demo-app.md)** — Reference app showing SDK usage on iOS/Android
2. **[Activelook-API-Documentation](./Activelook-API-Documentation.md)** — BLE GATT protocol specification and command syntax
3. **[ios-sdk](./ios-sdk.md)** — Official Swift SDK for iOS BLE control
4. **[Activelook-Visual-Assets](./Activelook-Visual-Assets.md)** — Prebuilt graphics, animations, layouts, fonts
5. **[Config-Generator](./Config-Generator.md)** — Python tool for building custom graphics configurations

---

## Recommended Integration Path for AR-Runner

### 1. iOS SDK: Swift Package vs. Vendored Source vs. Reimplementation

**Recommendation: Swift Package Manager (SPM) with fallback strategy.**

**Rationale:**
- **Swift Package Manager**: Official iOS SDK available at `https://github.com/ActiveLook/ios-sdk.git` (main branch). Supports CocoaPods or SPM.
  - Pros: Automatic updates, cleaner dependency management, vendor maintains it
  - Cons: Dependency on external repo; upgrade risks if breaking changes in minor versions
- **Vendored source** (copy iOS SDK into repo): Better for shipping/long-term stability, but adds maintenance burden (cherry-picking fixes, security updates).
- **Reimplementation**: Not recommended. SDK abstracts 90% of BLE/GATT complexity; reimplementing gains nothing vs. ~500 lines of Swift to reach parity.

**Path:**
1. Add iOS SDK as SPM dependency in main iPhone app target using tag `v4.5.5` (or latest stable)
2. Pin to tagged release (not `main`) for reproducible builds
3. If watchOS needs direct BLE access (see BLE ownership below), extract public protocol definitions from SDK source and create thin watchOS wrapper

---

### 2. Layout/Config Authoring: Phone App vs. Build-Time vs. Config-Generator Workflow

**Recommendation: Build-time baked config + optional runtime UI in phone app.**

**Rationale:**

The ActiveLook architecture uses **layout templates** defined once per configuration and uploaded to glasses at first connection. Live updates then only change *content* (e.g., HR number) within pre-defined slots, not layout structure. This is efficient for bandwidth/battery but inflexible for runtime UI redesign.

**Path:**

**Phase 1 (MVP): Build-Time Baked Config**
1. Create a custom ActiveLook config using Config-Generator (Python tool):
   - Define layouts tailored to workout HUD (HR, cadence, pace, elevation, time)
   - Use pre-built icons from `Activelook-Visual-Assets` where possible (cadence, HR, distance icons already exist)
   - Output binary config file
2. Embed config binary in iPhone app bundle (`Bundle.main.url(forResource:withExtension:)`)
3. On first glasses connection, upload config via SDK:
   ```swift
   glasses.configSet("AR-Runner") // Or SDK method for binary config upload
   ```
4. Subsequent app launches reuse config on glasses (no re-upload unless firmware upgraded)

**Phase 2 (Future): Runtime Config Authoring** *(open question below)*
- If workout personalization demands it, add a "config builder" view in iPhone app that calls Config-Generator Python as a subprocess or Swift wrapper
- Unlikely needed for initial release

**Build-time integration:**
- Add Config-Generator to CI/CD pipeline (GitHub Actions):
  - Input: `config-src/` folder (JSON descriptor + assets)
  - Output: Binary config file checked into repo or generated at build time
  - Run: `python configGenerator.py --save-file config.bin`
- Xcode build phase copies config binary into app bundle

---

### 3. BLE Ownership: iPhone vs. Watch vs. Both

**Recommendation: iPhone owns BLE connection; Watch reads metrics via WatchConnectivity.**

**Rationale:**

ActiveLook SDK is iOS-only; watchOS support is not officially provided. Three strategies exist:

| Strategy | Pros | Cons | Recommendation |
|----------|------|------|---|
| **iPhone owns BLE** | SDK works as-is; no code duplication | Watch must proxy all requests via WatchConnectivity; increased latency | ✅ **MVP path** |
| **Watch owns BLE** (native watchOS Core Bluetooth) | Lowest latency; direct Watch control | Requires reimplementing SDK logic in Swift for watchOS; no official support; complex state sync with iPhone | ❌ **High risk, post-MVP** |
| **Both devices can connect** | Failover resilience; Watch can take over if iPhone disconnects | Glasses can only hold one BLE connection at a time; conflict resolution logic needed | ❌ **Complex, not recommended** |

**Path for AR-Runner:**

1. **iPhone as BLE Controller:**
   - iPhone app runs the iOS SDK, maintains BLE connection to glasses
   - iPhone updates glasses HUD with metrics from HealthKit
   
2. **Watch as UI Display:**
   - Watch app receives latest metrics from iPhone via WatchConnectivity (per-second sync, ~100ms latency)
   - Watch displays metrics on its own screen (not glasses)
   - If user swipes to iPhone, iPhone also updates glasses display
   
3. **HUD Update Flow:**
   ```
   Watch HealthKit Sample
        ↓
   WatchConnectivity → iPhone
        ↓
   iPhone HealthKit + Core Location
        ↓
   ActiveLook SDK → BLE → Glasses HUD
   ```

**Fallback (future post-MVP):** If Watch-to-Glasses direct connection is essential for autonomy (e.g., Watch needs to update HUD even if iPhone is in backpack), spawn a separate watchOS BLE task to reimplement core SDK functionality. This is substantial work (~1–2 weeks) and should be deferred unless product requirements demand it.

---

### 4. Frame/Render Budget for Live Workout HUD Updates

**Current Reality: ~20–100 bytes per layout update; BLE MTU limits meaningful refresh rate to 2–10 Hz for live metrics.**

**Analysis:**

From the API documentation:
- **BLE MTU (Maximum Transmission Unit):** ~20 bytes per packet (standard BLE); ActiveLook uses fragmented GATT writes for larger payloads
- **Typical command sizes:**
  - Update text in pre-existing layout slot: ~20–40 bytes (e.g., `layout(id=1, slot=2, text="142")` for HR)
  - Update image: 50–500 bytes depending on compression
  - Full layout redraw: 100+ bytes
- **Latency:** BLE connection interval 15–30ms (preferred per spec); real-world round-trip for command + response ~50–150ms
- **Bandwidth:** At 20 byte MTU with 50ms latency, theoretical max is ~400 bytes/sec (practical: 200–300 bytes/sec due to BLE overhead)

**Recommended Refresh Rates by Metric:**

| Metric | Source Frequency | HUD Update Freq | Rationale |
|--------|---|---|---|
| Heart Rate | HealthKit 1 Hz (typical) | 1 Hz | ~20 bytes/update; well within budget |
| Cadence | GPS/accelerometer 10 Hz | 2–5 Hz | Every 200–500ms; smoother feel |
| Pace / Speed | GPS 1–2 Hz | 1 Hz | GPS limited; no point updating faster |
| Elevation | GPS 1 Hz | 0.2 Hz | Slow-changing; update every 5 sec |
| Timer / Elapsed | Always | 1 Hz | ~15 bytes; negligible cost |
| Power (if cycling) | Sensor 10 Hz | 2 Hz | ~30 bytes; every 500ms |

**Practical Budget:**
- Max sustainable rate: **4–5 active metric slots updating at 2–5 Hz** = ~40–100 bytes/sec
- Avoid **simultaneous full-screen redraws** and high-frequency updates; batch updates into single command if possible
- Use **pre-configured layouts** from Config-Generator; avoid drawing primitives (shapes) on every frame (expensive)

**Optimization Strategies:**
1. **Batch updates:** Combine multiple metric slots into single layout command (if SDK supports it)
2. **Conditional updates:** Only send HUD command if metric changed by >threshold (e.g., HR only if delta >2 bpm)
3. **Off-peak updates:** Send static UI (labels, icons) once per session; only update numeric values live
4. **Heatshrink compression:** For any image updates, use Config-Generator's compression to minimize payload

---

## Open Questions & Next Steps

### Critical Path Items (for Joe to decide):

1. **Watch BLE Autonomy?**
   - Does the Watch need to update glasses *independently* of iPhone?
   - Or is iPhone-as-proxy acceptable for MVP?
   - **Impact:** If yes, we need watchOS BLE wrapper (2–3 week effort post-iOS MVP).

2. **Config Licensing & Commercial Use?**
   - ActiveLook's Config-Generator and Visual-Assets are CC BY-NC-ND 4.0 (non-commercial).
   - Can AR-Runner use these assets if monetized (freemium model, in-app purchases)?
   - **Action:** Clarify with ActiveLook support (contact@activelook.net) or license custom assets separately.

3. **Layout Authoring Workflow?**
   - Should config be fully static (baked at app build) or configurable in-app?
   - If in-app customization needed, how often? (workout type selection, user preferences?)
   - **Impact:** Determines if Config-Generator integration is build-time only or runtime.

4. **Real-World BLE Latency Testing?**
   - Before shipping, we should stress-test with 4–5 simultaneous metric updates at 2 Hz; measure actual round-trip latency on real iPhone + glasses + Watch over WatchConnectivity.
   - **Action:** Spike after SDK proof-of-concept.

### Deferred (Post-MVP Exploration):

- Custom animation library (currently leaning on default `ALooK` animations)
- Multi-sport layout switching (running vs. cycling vs. climbing HUD layouts)
- Gesture-based glasses interaction (swipe to pause, tap to split) if supported by hardware

---

## Repository Quick Reference

| Repo | Key Asset | Use in AR-Runner |
|------|-----------|---|
| **demo-app** | iOS/Android reference impl | Study BLE state machine; adapt scan/connect flow |
| **Activelook-API-Documentation** | BLE GATT spec | Reference during SDK integration; BLE troubleshooting |
| **ios-sdk** | Swift SDK | SPM dependency; primary API for glasses control |
| **Activelook-Visual-Assets** | Prebuilt graphics catalog | Reuse sport icons; reference for layout design |
| **Config-Generator** | Config authoring tool | Build custom config in CI/CD; embed binary in app |

---

## Suggested Spike Order

1. **Sprint 1:** Proof-of-concept iOS app + iOS SDK integration (scan, connect, send simple commands)
2. **Sprint 2:** Custom config via Config-Generator; upload and render on glasses
3. **Sprint 3:** Watch app scaffold; WatchConnectivity integration for metric sync
4. **Sprint 4:** End-to-end test: Watch HealthKit → iPhone → Glasses HUD
5. **(Optional) Sprint 5:** Stress-test BLE latency; optimize refresh rates based on real hardware

---

**Document maintained by:** Weiss  
**Last updated:** 2026-05-14  
**Status:** Recommendation ready for team review
