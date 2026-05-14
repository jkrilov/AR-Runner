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

### 2026-05-14: watchOS BLE Spike Completed — Feasibility Confirmed (🟢)

**Spike Output:** `docs/research/activelook/watchos-ble-spike.md` (430 lines)

**Key Findings:**

1. **GATT Profile Mapped:**
   - Service: `0783B03E-8535-B5A0-7140-A304D2495CB7`
   - RX (write): `0x...CBA`; TX (notify): `0x...CB8`; Control/Gesture/Touch available
   - Binary frame format: `0xFF + CommandID + Format + Length + QueryID? + Data + 0xAA` (simple, no special challenges)
   - ActiveLook command surface includes 8 required families for v0.1 (power, clear, layout display, text/widget updates, luma, battery)

2. **CoreBluetooth on watchOS 11:**
   - ✅ `CBCentralManager`, `CBPeripheral`, `CBCharacteristic` all available on watchOS 11+
   - ❌ No peripheral role (watch is always central; acceptable per D1)
   - Background BLE **requires** active `HKWorkoutSession` (privileged background execution during workouts)
   - Connection interval: 15–30ms negotiable; typical ATT MTU 512–1024 bytes (safe assumption: 20-byte chunks)
   - No restore identifiers on watchOS; reconnection logic must be explicit (risk #2 mitigated by auto-reconnect + backoff)

3. **v0.1 Protocol Budget:**
   - Required commands (🟢): Power, Clear, Layout Display/Position, Text/Widget Update, Luma, Battery
   - Typical update: 20–40 bytes per command
   - Sustainable rate: 1–2 Hz for 4–5 simultaneous metrics = ~100 bytes/sec (7% of BLE practical limit)
   - BLE MTU concerns: Mitigated by fragmentation support; worst case is slower refresh (acceptable)

4. **watchOS + HKWorkoutSession Constraints:**
   - BLE connection persists only while workout active (session-tied, no standalone background BLE)
   - Reconnection on session loss: implement exponential backoff (1s, 2s, 4s, 8s) to avoid radio spam
   - Duty cycle recommendations: 1 Hz HR/pace/timer; 2 Hz cadence; 0.2 Hz elevation (D6 aligns with this)
   - Battery impact: ~5–10% per hour; mitigable via dynamic throttling if battery < 20%

5. **Risk Assessment:**
   - Top risks: MTU negotiation (Medium), HKWorkoutSession drops (Low), latency > 200ms (Low)
   - All mitigated by early prototyping + hardware stress-test
   - No blockers for v0.1 build

**Verdict: 🟢 Feasible. Scope: Medium (2–3 weeks). Recommendation: Proceed with watchOS BLE wrapper in v0.1.**

**Critical Path Items:**
- Week 1: BLE discovery + connection state machine (~200 lines)
- Week 2: Command framing + flow control + reconnection (~300 lines)
- Week 3: Integration with `WorkoutSessionManager` + metrics pipeline (~100 lines)
- Hardware stress-test: profile latency with real Watch SE + glasses; target p95 < 150ms

**Integration Dependencies:**
- Tie BLE lifecycle to Laughlin's `HKWorkoutSession` management (in `WorkoutSessionManager`)
- Define protocol `GlassesFrameTransport` in ARRunnerCore (architecture ADR-007 placeholder)
- Wire `WorkoutTick` → `updateField(layoutId:fieldIndex:value:)` pipeline
- Log BLE drops in run metadata (per D9, side store)

### 2026-05-14: Team update from Joe — v0.1 foundation scaffold + BLE spike landed on feat/v01-foundation. Branch awaiting Joe's push & PR. Next: WorkoutController impl (Laughlin) + watchOS BLE wrapper impl (Weiss).
