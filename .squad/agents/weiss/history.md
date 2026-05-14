# Weiss — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** AR Integration
- **Joined:** 2026-05-14T18:30:31.656Z

## Learnings

### 2026-05-14: ActiveLook Integration Research & Recommendation

**Repositories Catalogued:**
1. **demo-app** — Reference iOS/Android implementation; BLE state machine + command examples
2. **Activelook-API-Documentation** — BLE GATT protocol spec (Custom Service `0783B03E-8535-B5A0-7140-A304D2495CB7`); layout-based rendering architecture; ~20–100 bytes per metric update
3. **ios-sdk** — Official Swift SDK (Apache 2.0); available via SPM or CocoaPods; singleton pattern with closure-based callbacks
4. **Activelook-Visual-Assets** — Prebuilt graphics catalog (50+ icons, 14 animations, 5 fonts); CC BY-NC-ND 4.0 license (non-commercial constraint)
5. **Config-Generator** — Python tool for custom config authoring; outputs Heatshrink-compressed binary uploaded at first connection

**Key Technical Insights:**
- Layout system: Configurations pre-loaded on glasses; live updates only modify content within slots (efficient for BLE bandwidth)
- BLE bandwidth: ~300 bytes/sec practical limit; sustainable 2–5 Hz update rate for 4–5 metric slots
- Advertising spec: 25ms interval at startup; filter on manufacturer ID ending `0x08F2`; connection interval 15–30ms
- Gesture/sensor events available via BLE notifications (touch, gesture detection, ambient light)

**Integration Path Recommended:**
- **iOS SDK**: Use as SPM dependency (tag `v4.5.5` or latest stable); avoid reimplementation
- **Config**: Build-time baked binary (static layouts + metrics); defer runtime authoring to post-MVP
- **BLE ownership**: iPhone owns connection; Watch reads metrics via WatchConnectivity (MVP path). Direct Watch BLE is post-MVP (requires watchOS wrapper, ~2–3 week effort)
- **Refresh rates**: HR/pace 1 Hz, cadence 2–5 Hz, elevation 0.2 Hz (every 5 sec)

**Open Questions Flagged for Joe:**
1. Does Watch need independent BLE control, or iPhone-as-proxy OK for MVP?
2. Can AR-Runner use CC BY-NC-ND assets, or must we license custom graphics?
3. Should config be fully static or runtime-customizable?
4. Need real-world latency spike before shipping (measure WatchConnectivity + BLE round-trip)

**Deliverables Created:**
- `docs/research/activelook/` — Five one-page repo briefs + comprehensive integration README
- Repo briefs include: purpose, platform, activity status, key folders, constraints, open questions
- README includes: integration path (SDK, config, BLE ownership), frame budget analysis, spike order

**Licenses & Constraints Noted:**
- iOS SDK: Apache 2.0 (permissive)
- Visual Assets & Config-Generator: CC BY-NC-ND 4.0 (non-commercial use only; commercial app may need separate licensing)
- Info.plist requirements for iOS 13+ BLE access documented

### 2026-05-14: Team update from Joe — 9 architecture decisions locked (see decisions.md D1-D9). Next phase: Xcode scaffolding (Laughlin) + ActiveLook watchOS BLE spike (Weiss).
