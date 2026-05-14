# watchOS Architecture Plan — AR-Runner

**Date:** 2026-05-14T15:03:23-04:00  
**Owner:** Laughlin  
**Status:** Initial Draft  
**Context:** Single integrated watchOS app (paired with iOS companion) for AR fitness workouts.

---

## 1. App Shape

### Project Structure

- **watchOS Target:** `ARRunner` (main watch app)
- **iOS Companion:** `ARRunnerCompanion` (iPhone app; config authority, display setup)
- **Shared Framework:** `ARRunnerKit` (HealthKit models, WatchConnectivity contracts, workout logic)
- **Shared Assets:** `ARRunnerAssets` (icons, colors, branding)

### Info.plist Entitlements

**watchOS Target** (`ARRunner-Info.plist`):
```xml
<!-- HealthKit -->
<key>NSHealthShareUsageDescription</key>
<string>AR-Runner reads your heart rate and workout data to enhance your fitness experience.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>AR-Runner logs your workouts to the Health app.</string>

<!-- Background Modes (WKApplicationDelegate) -->
<key>UIBackgroundModes</key>
<array>
  <string>workout-processing</string>
  <!-- BLE Central only if watch owns BLE (see § 5 below) -->
  <!-- <string>bluetooth-central</string> -->
</array>

<!-- WatchConnectivity (automatic; no explicit key needed, but confirm in capabilities) -->
```

**iOS Companion Target** (`ARRunnerCompanion-Info.plist`):
```xml
<!-- HealthKit (read-only for display; write handled by watch) -->
<key>NSHealthShareUsageDescription</key>
<string>AR-Runner displays your fitness metrics from the Health app.</string>

<!-- WatchConnectivity (automatic) -->

<!-- BLE Central (if phone owns BLE or is tethered relay) -->
<key>NSBluetoothPeripheralUsageDescription</key>
<string>AR-Runner connects to your AR glasses via Bluetooth.</string>
<key>NSBluetoothCentralUsageDescription</key>
<string>AR-Runner connects to your AR glasses via Bluetooth.</string>

<!-- Background Modes -->
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
</array>
```

### Capability Matrix

| Capability | watchOS | iOS |
|---|---|---|
| HKWorkoutSession creation | ✓ Primary | — (read-only from Health) |
| HKLiveWorkoutBuilder sample collection | ✓ | — |
| HealthKit write (metrics) | ✓ | — |
| WatchConnectivity sender | ✓ | ✓ |
| WatchConnectivity receiver | ✓ | ✓ |
| BLE Central (decision pending § 5) | ? | ? |
| Active complication | ✓ | — |
| Smart Stack widget | ✓ | — |
| Action Button / Shortcuts | ✓ | ✓ (calls watch via WC) |
| Siri support | ✓ | ✓ (calls watch via WC) |

---

## 2. Workout Session Lifecycle

### HKWorkoutSession + HKLiveWorkoutBuilder

**Reference:** WWDC 2023 "Evolve your HealthKit App" + Apple HealthKit docs.

#### Initialization (Watch)
```
User taps launch surface → AppIntent.perform() → WKExtensionDelegate.handle(_:completionHandler:)
  ↓
Create HKWorkoutConfiguration:
  • activity type = .running (or user-selected)
  • location type = .outdoor (for AR trail data)
  • is indoor walkable = false
  ↓
Initialize HKWorkoutSession(configuration:delegate:)
  → Call session.startActivity(with:)
  → Receive delegate callbacks: didChangeToState(.running)
```

#### Live Metrics Collection (Watch Foreground)
- **Builder:** `HKLiveWorkoutBuilder(healthStore, configuration, delegate)`
- **Data:** Distance, pace, heart rate (from watch sensors), cadence (if available)
- **Push Frequency:** 
  - **Watch → Phone sync** (WatchConnectivity): Every 10–15 seconds (battery vs. realtime tradeoff; see § 4)
  - **HealthKit write:** Collected in-memory; flushed to Health on pause/end
  - **Complication update:** Every 1 minute (WKExtensionDelegate.getComplicationDescriptors)

#### Foreground Delivery
- **Lock-Screen Complication:** Shows live heart rate + pace via `@Environment(\.activityIsRunning)`
- **Watch Face Complication:** Always visible if pinned
- **Workout App (native iOS Health):** User can swipe over to view real-time stats if iPhone is paired and nearby

#### Auto-Pause Logic
- **Trigger:** Sensor signals zero movement for ~10 seconds (built into HK framework)
- **Behavior:** HKWorkoutSession.pause() → UI shows pause icon
- **Recovery:** resume() when movement detected
- **HealthKit Impact:** Paused time is **excluded** from active duration (automatic)

#### Lock-Screen Behavior
- **During Run:** Complications visible (heart rate, distance, pace)
- **Background Idle (screen locked, workout paused):** Complication shows elapsed time; tapping returns to app
- **Background Idle (no workout):** Standard complications; Action Button can launch via AppIntent

#### Session End
```
User swaps up → Present "End Workout?" dialog
  ↓
If confirmed → builder.endCollection(withEnd: Date())
  → session.end()
  → HKWorkoutBuilder.finishWorkout { [newWorkout] }
    → Save to HealthKit
    → Post to WatchConnectivity: workout summary (distance, duration, energy, peak HR)
    → Return to home screen
```

---

## 3. Launch Surfaces

### Design Principle
Workouts start **on the watch**. All launch surfaces trigger `StartWorkoutIntent : AppIntent` (or a variant). The phone never initiates a workout directly; it may **request** one via WatchConnectivity, which the watch honors if already displaying the intent UI.

### A. Smart Stack Widget

**Technology:** WidgetKit + AppIntent  
**Reference:** WWDC 2023 "Build widgets for Smart Stack on watchOS 10+"

- **Widget type:** Inline or compact (watchOS 10+)
- **Content:** "Start AR Run" + distance history / favorite routes (stretch goal)
- **Intent:** `StartWorkoutIntent(activityType: .running, glassesConfigId: ?)`
- **Behavior:**
  - Tap → Calls `perform()` on intent
  - OS handles app-launching; App Intents framework ensures it's safe to call even if app isn't running
  - Intent runs in extension process; must complete work or transition to app delegate within ~10s

**Implementation notes:**
- Use `@AppIntentVoiceShortcutsLink` or direct link in widget
- Pass `activityType` as a dynamic option (user selects preset "AR Run", "Walk", "Bike")
- Widget refreshes if there are saved routes; data fetches from shared container

---

### B. Action Button / Shortcuts

**Technology:** App Intents (openAppWhenRun behavior)  
**Reference:** Apple Shortcuts docs + WWDC 2023 "Meet App Intents"

#### Desired Behavior
- Side button press → Trigger `StartWorkoutIntent`
- **Ideal:** Intent runs **without** forcing app to foreground (`openAppWhenRun = false`)
  - User still sees complications / smartstack; workout starts silently
  - Watch screen stays on (via `HKWorkoutSession.startActivity` setting WKExtensionDelegate active)

#### Decision Point ⚠️
**Is `openAppWhenRun = false` supported for `StartWorkoutIntent` on watchOS?**

Apple's App Intents docs do not explicitly promise this for custom intents. The HealthKit framework owns the workout session lifecycle, so the OS *may* auto-launch the app regardless of this flag to ensure proper delegate wiring.

**Plan A (if supported):** Set `openAppWhenRun = false` + rely on `WKExtensionDelegate` to receive the action.

**Plan B (if not supported):** Accept that the Action Button shows the app briefly; use `AppIntent.openAppWhenRun = true` but minimize UI load time. Verify via integration testing on hardware.

**Current recommendation:** Assume **Plan B** (app launches) for safety. Test Plan A in beta. Document the result.

#### Shortcut
```
Shortcut: "Start AR Run"
  ↓
  Run Shortcuts action: Open AR-Runner (implicit)
  OR Call app intent: StartWorkoutIntent
```

---

### C. Siri

**Technology:** AppIntent.systemSmall (conversational Siri)  
**Reference:** WWDC 2023 "Meet App Intents"

- **Utterance:** "Hey Siri, start an AR run"
- **Intent:** `StartWorkoutIntent`
- **Behavior:** Siri invokes `perform()` → same flow as Smart Stack tap
- **Localization:** Provide `.en-US` and other languages in intent definition
- **Confirmation:** Optional (Siri may ask "Which activity?" if multiple types available)

---

### D. Complications (Tradeoffs)

**Technology:** WidgetKit complications + ClockKit (deprecated on watchOS 9+; migrate to WidgetKit)  
**Reference:** WWDC 2023 "Complications in watchOS 10 and beyond"

| Feature | Feasibility | Tradeoff |
|---|---|---|
| Tap complication → start workout | ✓ (via Intent link) | Small tap target; conflicts with swiping to other apps |
| Show upcoming workouts | ✓ | Requires calendar data; adds complexity |
| Show last workout summary | ✓ (via HealthKit snapshot) | Data is stale after workout; not actionable |

**Recommendation:** Use complications for **display** (live stats during run) rather than **launch**. Rely on Smart Stack for intent-based launch.

---

## 4. Watch ↔ Phone Sync (WatchConnectivity)

### Architecture

```
Watch App
  ↓ (WCSession.default.sendMessage / transferUserInfo)
iPhone Companion
  ↓ (WCSession.default.sendMessage / updateApplicationContext)
Watch App (receives)
```

### Message Contract (Data Schema)

All payloads use `Codable` JSON over WatchConnectivity.

#### 4.1 Live Workout Metrics (Watch → Phone, Push)

**Direction:** Watch → Phone  
**Frequency:** Every 10–15 seconds (during active workout)  
**Transport:** `WCSession.default.sendMessage(...)` (requires reachability) or `transferCurrentComplicationUserInfo(...)` (queued if unreachable)

```swift
struct WorkoutMetricsPush: Codable {
    let sessionId: UUID            // Unique per workout session
    let timestamp: Date            // Server time on watch
    let heartRate: Int             // bpm
    let distance: Double           // meters
    let pace: Double               // seconds per 100m (or mm:ss string)
    let cadence: Int               // steps/min (if available)
    let elevation: Double?         // meters above sea level (optional)
    let state: String              // "running" | "paused" | "ended"
    let estimatedCalories: Double  // kcal
}
```

**Decision:** Use `sendMessage` if phone is reachable (`WCSession.default.isReachable`), fallback to `transferCurrentComplicationUserInfo` if not. Phone displays "last known" stats if complication view outdated.

---

#### 4.2 Glasses Config Push (Phone → Watch, Pre-Workout)

**Direction:** Phone → Watch  
**Timing:** Before/at workout start (or on-demand via watch request)  
**Transport:** `WCSession.default.sendMessage(...)` (requires reachability) + fallback to `updateApplicationContext(...)` (reliable, eventual consistency)

```swift
struct GlassesConfigPush: Codable {
    let configId: UUID
    let displayMode: String         // "hud" | "metrics" | "navigation"
    let metricsLayout: [String]    // ["heartRate", "pace", "distance"]
    let refreshRate: Int            // Hz (e.g., 10 for complication update)
    let bleDeviceId: String?        // ActiveLook device identifier (set by phone)
    let timestamp: Date
}
```

**Semantics:**
- Phone is the **config authority**. User sets up glasses display in companion app.
- Watch fetches config on app launch (if not in UserDefaults) or receives push.
- Watch applies config to BLE command stream (see § 5).

---

#### 4.3 Workout Summary (Watch → Phone, Push-on-End)

**Direction:** Watch → Phone  
**Timing:** Immediately after workout ends + HealthKit save completes  
**Transport:** `sendMessage(...)` (best-effort; acceptable to lose if phone asleep)

```swift
struct WorkoutSummaryPush: Codable {
    let sessionId: UUID
    let activityType: String        // "running", "walking", etc.
    let startTime: Date
    let endTime: Date
    let totalDistance: Double       // meters
    let totalElevation: Double?     // meters (if available)
    let totalEnergy: Double         // kcal
    let averageHeartRate: Int       // bpm
    let peakHeartRate: Int          // bpm
    let healthKitWorkoutId: UUID?   // For phone to sync later
}
```

**Phone behavior:** Displays summary card, offers to share / export.

---

#### 4.4 BLE State & Control (Watch ↔ Phone, Bidirectional)

**Direction:** Both  
**Timing:** On-demand or continuous during workout  
**Transport:** `sendMessage` (reachable) or `updateApplicationContext` (background safe)

```swift
struct BLEStatePush: Codable {
    let isConnected: Bool           // BLE connection status
    let deviceName: String?         // "ActiveLook ..." or nil
    let rssi: Int?                  // Signal strength
    let lastError: String?          // e.g., "Connection timeout"
    let timestamp: Date
}
```

**Direction:** Either device can report state change. The other updates UI accordingly.

---

### WatchConnectivity Setup

```swift
// AppDelegate or scene init
let session = WCSession.default
if WCSession.isSupported() {
    session.delegate = self
    session.activate()
}

// Send metrics during workout
if session.isReachable {
    do {
        try session.sendMessage(metrics, replyHandler: { _ in
            // Phone received; no action needed
        }) { error in
            // Fallback to transferCurrentComplicationUserInfo
            session.transferCurrentComplicationUserInfo(metrics)
        }
    } catch {
        session.transferCurrentComplicationUserInfo(metrics)
    }
} else {
    // Phone asleep or out of range
    session.transferCurrentComplicationUserInfo(metrics)
}
```

### Reachability & Reliability

| Scenario | Tactic |
|---|---|
| Phone is awake & paired nearby | `sendMessage(...)` (realtime, ~100ms latency) |
| Phone is asleep & paired | `transferCurrentComplicationUserInfo(...)` (queued, eventual) |
| Phone out of range | `transferCurrentComplicationUserInfo(...)` (queued until reachable) |
| Watch has buffered metrics; phone comes back online | Phone receives latest via complication info; historical backfill is non-goal for v1 |

**Frequency Rationale:**
- 10–15s push interval balances battery (watch stays awake anyway for HK sampling) vs. phone screen update cadence (1 min for complications).
- If phone is off-wrist, complication updates are throttled by OS anyway.

---

## 5. Who Owns BLE to the Glasses?

### Options

#### Option A: Watch Owns BLE
**Pros:**
- Single BLE connection; no relay overhead
- Watch has all workout context (HKWorkoutSession, metrics)
- Simpler state machine

**Cons:**
- Watch battery drain: BLE is power-hungry; watch on-wrist battery budget is tight (~18 hours typical)
- Watch development complexity: SDK integration + error handling on small device
- If watch loses BLE during workout, glasses go dark (risky UX)

**Reference:** WWDC 2023 "Optimize for watchOS performance & battery" notes BLE as a significant drain.

---

#### Option B: Phone Owns BLE (Tethered Relay)
**Pros:**
- Phone has larger battery; BLE is less critical constraint
- Phone always connected via WiFi; can act as failover proxy
- Watch only pushes metrics via WatchConnectivity (lower power)

**Cons:**
- Relies on phone being present and in range (watch-only workouts cannot update glasses)
- Relay latency adds ~100ms per message (WC round-trip)
- Phone becomes bottleneck if it goes to sleep

---

#### Option C: Hybrid (Watch Primary, Phone Fallback)
**Pros:**
- Watch is primary if in range; phone relays if watch loses BLE
- Robust failover; works even if phone asleep (eventual delivery via complication info)

**Cons:**
- Most complex; state machine must track which device owns BLE
- Requires agreement protocol (who backs off if both connected?)

---

### Recommendation (Pending Weiss's BLE Findings)

**Current assumption: Option A (Watch Owns BLE)**, with the following rationale:

1. **Workout autonomy:** Watch-only runs should work; phone optional.
2. **Lower latency:** No relay means BLE commands apply instantly.
3. **Battery mitigation:** Use BLE sparingly (e.g., HUD refresh at 2 Hz instead of 10 Hz).

**Flag:** This is a **joint decision point** with Weiss (AR glasses specialist). Weiss's findings on ActiveLook SDK power profile & latency requirements should inform this choice.

**Questions for Weiss:**
- What is the minimum HUD refresh rate (Hz) for acceptable UX?
- Does ActiveLook SDK support batching / queuing BLE commands?
- What is the typical BLE radio duty cycle (% time transmitting)?

If ActiveLook requires high-frequency updates (>2 Hz) or if BLE consumes >10% watch battery per hour, **Option B (phone relay)** becomes more attractive.

---

## 6. Open Decision Points

| # | Decision | Impact | Owner | Notes |
|---|---|---|---|---|
| 1 | **Action Button behavior:** Does `openAppWhenRun = false` work for custom AppIntents on watchOS? | UX polish; user expects background launch | Laughlin (Eng) | Requires integration test on hardware. Plan B (app launches) is safe fallback. |
| 2 | **BLE ownership:** Watch primary vs. phone relay vs. hybrid? | Battery, robustness, latency | Laughlin + Weiss | Blocked on Weiss's ActiveLook performance data. Recommend watch-primary; Weiss's findings may override. |
| 3 | **Workout start from phone:** Can phone request watch to start workout? | Feature parity with Workout app; out-of-scope for v1 | Joe (Product) | Defer to v2. Current: watch-initiated only. |
| 4 | **Historical metrics backfill:** If phone misses live pushes, should watch cache & replay on reconnect? | UX completeness; watch storage is limited | Laughlin (Eng) | Out-of-scope v1. Show "last known" on phone; full history fetches from HealthKit. |
| 5 | **Complication design:** Which metric (heart rate, distance, pace, time) on lock screen? | User attention during run | Amber (Design) | Defer to Amber's design specs. Watch shows most relevant stat; swipe to see all. |
| 6 | **Siri localization:** Which languages on launch? | I18n scope | Joe (Product) | Recommend .en-US for v1. Add others based on target markets. |

---

## 7. Reference Materials

### Apple Docs & WWDC Sessions

1. **HealthKit:**
   - [WWDC 2023: Evolve your HealthKit App](https://developer.apple.com/videos/play/wwdc2023/10034/)
   - [HKWorkoutSession](https://developer.apple.com/documentation/healthkit/hkworkoutsession)
   - [HKLiveWorkoutBuilder](https://developer.apple.com/documentation/healthkit/hklivewotkoutbuilder)

2. **watchOS / Complications:**
   - [WWDC 2023: Complications in watchOS 10 and beyond](https://developer.apple.com/videos/play/wwdc2023/10047/)
   - [WidgetKit for watchOS](https://developer.apple.com/documentation/widgetkit/visualizing-data-on-the-apple-watch)
   - [WKExtensionDelegate](https://developer.apple.com/documentation/watchkit/wkextensiondelegate)

3. **App Intents & Shortcuts:**
   - [WWDC 2023: Meet App Intents](https://developer.apple.com/videos/play/wwdc2023/10101/)
   - [App Intents](https://developer.apple.com/documentation/appintents)
   - [Shortcuts User Guide](https://support.apple.com/guide/shortcuts/welcome/ios)

4. **WatchConnectivity:**
   - [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
   - [WWDC 2021: What's new in WatchKit](https://developer.apple.com/videos/play/wwdc2021/10041/) (still relevant for session patterns)

5. **Performance & Battery:**
   - [WWDC 2023: Optimize for watchOS performance & battery](https://developer.apple.com/videos/play/wwdc2023/10097/)

---

## 8. Next Steps

1. **Eng approval:** Laughlin + Joe review this architecture; flag any concerns.
2. **Weiss coordination:** Share § 5 (BLE ownership) with Weiss; request ActiveLook performance data.
3. **Amber feedback:** Complication design (§ 6.5); UI layout for complications.
4. **Decision resolution:** Joe answers decision points (§ 6) by date TBD.
5. **Implementation kickoff:** Once decisions locked, Laughlin starts Swift scaffolding (AppDelegate, WCSession, AppIntent stubs).

---

