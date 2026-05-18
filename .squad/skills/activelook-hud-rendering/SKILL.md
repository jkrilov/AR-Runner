# Skill: ActiveLook HUD Rendering (raw `txt` running-HUD pattern)

> **Owner:** Weiss
> **Born:** 2026-05-18 (PR #49 — v0.3.0 HUD MVP)
> **Sibling to:** `activelook-bluetooth-pairing` (pairing UX) — this
> skill covers what to draw on the glasses *after* the link is up.

## Why this skill exists

PR #45 fixed pairing. PR #49 fixed the "what does the user actually
see on the glasses during a workout" gap. Symptom on Joe's bench:
scan/connect succeeds, then "Start a run" leaves the Engo 2 stuck on
the "Connection Successful" splash forever. Root cause was an
on-connect call to `selectLayout(preset: .default)` that activated a
**pre-bake placeholder** layout slot ID. Lesson generalises beyond
ActiveLook: any time a peripheral's "rich" rendering pipeline depends
on a deferred build step, **always also ship a path that works on a
stock device today.**

## The pattern

### 1. Two HUD pipelines, not one

Co-exist them deliberately:

| Pipeline       | When it works                                        | Cost                         |
| -------------- | ---------------------------------------------------- | ---------------------------- |
| Raw `txt` HUD  | Any stock ActiveLook peripheral, zero config         | ~150 LOC, fixed layout       |
| Curated layout | After Config-Generator bakes real slot IDs           | Richer layouts, faster writes |

The watch app should default to **raw** until the curated pipeline can
be proven against real on-device slot IDs. Flip the default in the
adapter init (`defaultPreset: nil` → opt-in once baked) so the
curated path is dormant, not deleted.

### 2. Raw frame sequence

The minimal viable running HUD on Engo 2 (304×256 panel):

```text
[ clear ]
[ txt(x=20, y=40,  rotation=4, font=3, color=15, "MM:SS")    ]   // time
[ txt(x=20, y=120, rotation=4, font=3, color=15, "X.XX mi")  ]   // distance
[ txt(x=20, y=200, rotation=4, font=3, color=15, "MM:SS/mi") ]   // pace
```

- `clear` first so we paint over the splash (and the previous frame).
- `rotation=4` = bottom-RL — the orientation a wearer reads naturally
  when the glasses sit on their nose. Matches ActiveLook's iOS sample
  (`ActiveLook/Activelook-ios-sdk` `Commands.swift` `txt`).
- `fontSize=3` = the largest stock font baked into Engo 2 firmware out
  of the box. Readable at arm's length through the projection.
- `color=15` = full white on the monochrome OLED. Anything dimmer
  hurts readability outdoors.

### 3. `txt` command (cmdID 0x37) wire format

```text
0xFF | 0x37 | format | len | x_hi x_lo | y_hi y_lo | rot | font | color | bytes... | 0x00 | 0xAA
```

- `x`, `y` are **i16 big-endian**, signed (so off-screen negative
  coordinates are legal — test the two's-complement encoding for
  `y = -1` → `0xFF 0xFF`).
- The string is **null-terminated** UTF-8 (even if empty).
- Re-use the `ActiveLookCommand.encode(id:payload:queryID:)` framer
  for the outer envelope so you inherit its two-byte-length promotion
  for long strings.

### 4. Pure builder in Core, side-effect push at the watch boundary

The frame sequence is a pure function of `(elapsedSeconds,
distanceMeters)`. Put the builder in `ARRunnerCore` (Linux-CI-
buildable, fully unit-testable) and the BLE write in the watch
target. Same separation as `GlassesAdvertisementFilter` from
PR #45 — pays for itself in test coverage every time.

```swift
public enum RunningHUDFrame {
    public struct Payload: Sendable, Equatable {
        public let time: String, distance: String, pace: String
    }
    public static func payload(elapsedSeconds:, distanceMeters:) -> Payload
    public static func frames(for payload: Payload) -> [[UInt8]]
    public static func summaryFrames(for payload: Payload) -> [[UInt8]]
}
```

### 5. Reuse the wrist display's formatters

The in-run watch face already formats distance and pace. **Use the
same `RunMetricFormatting.formatMiles` / `formatAveragePacePerMile`
in the HUD builder** so the wrist and the glasses can never disagree.
PR #41 put those formatters in Core specifically so cross-surface
callers could share them.

For elapsed time, SwiftUI's `Text(_:elapsedSince:)` doesn't help
(view-only). Add a tiny `formatElapsed(_:TimeInterval) -> String`
helper in the HUD module: `MM:SS` under an hour, `H:MM:SS` otherwise,
clamping non-finite/negative inputs to `"0:00"`.

### 6. Push on the elapsed ticker, not on metric callbacks

`HKWorkoutBuilder.statistics` callbacks fire at variable cadence
(faster than 1Hz during active phases). Hanging the HUD push off the
existing **1Hz elapsed ticker** instead means:

- Time, distance, and pace all update together in a single frame —
  the wearer never sees a stale time next to a fresh distance.
- Throttling becomes a belt-and-braces safety net rather than the
  primary rate limiter — the ticker IS the rate.

Still pair with a `RunningHUDPushPolicy` that gates on
`(now - lastSent >= 1s) AND payload != lastPayload`. The
change-detection half lets you drop into zero BLE traffic when the
runner stands still (every field's payload is identical).

### 7. Lifecycle hooks

| Trigger                  | Action                                       |
| ------------------------ | -------------------------------------------- |
| Workout start            | Push one initial frame (gives `0:00 / 0.00 mi / --:--/mi` immediately) |
| Glasses (re)connect      | Reset push-policy + push one frame           |
| Per-tick (1Hz)           | Build payload + push if policy allows        |
| Glasses disconnect       | Reset push-policy, no-op the push (D4 — workout never blocks) |
| Workout save             | Push a "Workout Complete" summary frame      |
| Workout cancel           | Skip the HUD splash (user explicitly bailed) |

### 8. Default-no-op protocol extension for the transport capability

When adding a new capability to `GlassesFrameTransport` (here:
`func sendCommands([[UInt8]]) async throws`), give it a **default
no-op** implementation in a protocol extension. Stubs and previews
keep building unchanged; only the real adapter and any test stub
that wants to record need to override. Strict Swift 6 stays quiet,
test surface stays small.

```swift
public protocol GlassesFrameTransport: Sendable {
    /* existing ... */
    func sendCommands(_ frames: [[UInt8]]) async throws
}
extension GlassesFrameTransport {
    public func sendCommands(_ frames: [[UInt8]]) async throws {}
}
```

## Anti-patterns to avoid

- **Don't activate placeholder layout slot IDs on real hardware.**
  `CuratedLayoutCatalog.placeholderDeviceIDs` lists the trap. Pair
  any "shouldn't ship" debug `assert` with a behavioural guard
  (refuse to pre-seed; refuse to activate) so the release build
  doesn't silently mis-render.
- **Don't push HUD frames from the metric callback stream.** Variable
  cadence + multi-field race = the wearer sees inconsistent frames.
  Push from the 1Hz elapsed ticker.
- **Don't reformat the wrist display's numbers in the HUD builder.**
  Use the shared `RunMetricFormatting` helpers — drift between wrist
  and glasses is a UX bug.
- **Don't `throw` from the HUD push back into the workout pipeline.**
  BLE noise stays in BLE (D4). `try?` at the watch-VM boundary and
  log; the watch keeps recording.
- **Don't skip the `clear` command.** Without it you'll either paint
  over the splash with translucent garbage or overlay successive
  frames into a smeared mess.

## When NOT to use this pattern

- **Curated, pre-baked layouts are available.** Once Config-Generator
  bakes real slot IDs, the per-tick `updateField` path is more
  efficient (smaller writes, more fields possible). Use the raw
  pattern as the **fallback** and the dormant default, not the
  forever-pattern.
- **Devices that don't support `txt`.** All ActiveLook peripherals do,
  but other vendor protocols won't. Check the wire spec first.

## Coordinate math for Engo 2

- Panel: 304 × 256 px.
- Three-row left-aligned column, font 3 (~48px tall): x=20, y=40/120/200
  leaves comfortable margins on all four edges.
- Tune at the `RunningHUDFrame.Layout` constants — keep them in one
  place so a future Engo model variant or font tweak is a one-line
  change.

## Test discipline

Pure builders deserve pure tests. Cover at minimum:

1. Payload wiring (delegates to shared formatters; distance-threshold
   pace placeholder; elapsed `MM:SS` vs `H:MM:SS`; non-finite clamp).
2. Frame sequence (clear + 3 txt; per-frame `0xFF / cmd / fmt / len /
   ... / 0x00 / 0xAA` envelope).
3. Encoder wire format (x/y big-endian, negative-y two's-complement,
   empty-string still carries null terminator).
4. Push-policy contract (first-send always passes; identical-within-
   window dropped; changed-within-window passes; at-or-after window
   passes; `reset()` releases the gate).
5. Layout sanity (coordinates fit inside the panel) — guards future
   tuning from accidentally pushing text off-screen.

BLE I/O itself is hard to unit-test without the real device; defer
to on-device bench validation for the actual rendering.

## References

- `ActiveLook/Activelook-ios-sdk` `Sources/Classes/Public/Commands.swift`
  — canonical `txt` command implementation.
- `ActiveLook/Activelook-CommandBridge` — command documentation.
- `Activelook-API-Documentation/ActiveLook_API.md` §5.7 (txt payload).
- AR-Runner `.squad/audits/2026-05-16-weiss-ar-ble.md` P1.4 — original
  flag of the placeholder-layout-ID trap that PR #49 finally retired.
- AR-Runner PR #41 — `RunMetricFormatting` shared formatters.
- AR-Runner PR #49 — initial implementation.
