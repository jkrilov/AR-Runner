# Skill: ActiveLook HUD Rendering (raw `txt` running-HUD pattern)

> **Owner:** Weiss (BLE protocol fix by Richards; encoder + observability fix by Laughlin in PR #57; cfgSet activation by Laughlin in PR #60)
> **Born:** 2026-05-18 (PR #49 — v0.3.0 HUD MVP; PR #55 — BLE serialization fix; PR #57 — queryID + flow-control fix; PR #60 — cfgSet("ALooK") activation)
> **Confidence:** HIGH — Joe's bench test of rc8 confirmed text renders end-to-end on the Engo 2 (both the "AR-Runner Start a run" connect banner AND the live workout HUD: time / distance / pace). rc9 (PR #63) added rotation calibration + holdFlush anti-flicker polish. The full working stack is the cumulative product of seven PRs (see "🟢 CONFIRMED WORKING STACK" section below) — every prior fix is load-bearing.
> **Sibling to:** `activelook-bluetooth-pairing` (pairing UX) — this
> skill covers what to draw on the glasses *after* the link is up.
>
> ## 🚨 CRITICAL — `txt` rotation: ALL 8 values are in the SDK enum; choose based on glyph orientation AND anchor corner (rc12 lesson)
>
> The ActiveLook SDK `TextRotation` enum exposes **all eight** values
> (0–7) — see `ActiveLookTypes.swift:41-50` in the official iOS SDK.
> An earlier note here said "only 0 and 4 are documented" — that was
> wrong; it has been removed. The real failure mode behind rc9's blank
> at `rotation=2` was almost certainly the same off-screen-clipping
> bug we hit at rc11 with `rotation=4` + `x=20`, NOT firmware
> rejection of the rotation byte.
>
> **When choosing a `txt` rotation, account for BOTH:**
>
> 1. **Glyph orientation** (how the character is drawn into the
>    framebuffer): some values render glyphs 180°-rotated.
> 2. **Anchor corner + growth direction** (where the `(x, y)` you
>    pass lands relative to the text block, and which way the block
>    extends):
>    - `0` bottomRL → anchor at bottom-LEFT, text grows right + up
>    - `4` topLR → anchor at top-RIGHT, text grows LEFT + down
>    - (the other six values cover the remaining 8-way combinations)
>
> **Picking the wrong rotation for your anchor coords puts the text
> off-screen → silent clip per spec §5.5.6 → blank.** This is what
> killed rc11 (`topLR` + `x=20` ⇒ string extended into negative x).
>
> **Engo 2 lens flip is point-symmetric 180°:**
> `x_wearer = 303 − x_fb`, `y_wearer = 255 − y_fb`. For wearer-readable
> text the canonical combo is:
>
> - `rotation = 4` (topLR — 180°-flipped glyphs cancel the lens flip)
> - `x_fb = 303 − x_wearer_left` (so the LEFT edge of text lands where
>   the wearer expects it; for x_wearer=20 → `x_fb=283 ≈ 284`)
> - `y_fb = 255 − y_wearer_top − font_height` (top edge; font 3 is
>   49 px tall → `y_fb = 206 − y_wearer_top`)
>
> AR-Runner currently ships with `RunningHUDFrame.Layout.rotation = 4`
> (rc12) and lens-flip-corrected anchor coords (`leftMargin = 284`,
> `timeY = 166`, `distanceY = 86`, `paceY = 6`). ALooK system layout
> #10 (the demo app's running-time layout) also ships with
> `rotation=4` at high textX (238), confirming this is the canonical
> choice for topLR.
>
> **Rules:**
>
> 1. **Default to `rotation = 4` (topLR) with lens-flip-corrected
>    framebuffer anchors.** This is the AR-Runner bench-validated
>    combo as of rc12.
> 2. **Before claiming a rotation value is "firmware-rejected," verify
>    the coords actually keep the text on-screen** in the
>    rotation/anchor-specific bounding box. A blank screen with no
>    0xE2 error is almost always silent off-screen clipping (spec
>    §5.5.6), not firmware rejection.
> 3. **If a different orientation is needed, test ONE rotation +
>    anchor combo at a time in its OWN PR.** The failure mode (works
>    / blank) is binary and indistinguishable from other render-path
>    bugs, so multi-change PRs force a bisect cycle to isolate.
> 4. **If you see a totally blank HUD on a connection where the rc8+
>    working stack is otherwise intact (cfgSet, power-on, queryID,
>    flow control, holdFlush), suspect off-screen coordinates FIRST,
>    rotation-byte rejection second.** Both produce identical
>    symptoms; coords are far more often the culprit.
>
> ## 🚨 CRITICAL — `cfgSet("ALooK")` is mandatory on every connect (PR #60, rc8)
>
> **Fonts 1–5 on Engo 2 are NOT baked into base firmware.** They live
> inside the "ALooK" configuration stored in the glasses' flash. Per
> the [ActiveLook-Visual-Assets](https://github.com/ActiveLook/Activelook-Visual-Assets)
> repo README: *"To use the activelook visual asset, use the command:
> `cfgSet("ALooK")`"*. The official demo app calls
> `glasses.cfgSet(name: "ALooK")` before EVERY display command — not
> "sometimes" — every one.
>
> **Before any `txt` command referencing fonts 1–5, layouts, or
> images:** the connection must have called `cfgSet(name: "ALooK")`
> (cmdID `0xD2`, payload = config-name UTF-8 + `0x00` NUL terminator)
> at least once. AR-Runner ships this as the first frame of
> `RunningHUDFrame.connectFrames()` and also at the head of
> `framesWithPowerOn(for:)` (defense for the case where the
> connect-screen push got skipped and `needsHUDPowerOn` stays true
> into the first per-tick frame). cfgSet is idempotent per-connect, so
> sending it again does no harm; OMITTING it leaves the screen blank
> because font index 3 doesn't exist in the active namespace.
>
> **Why this was the rc4–rc7 "blank screen" bug:** `clear()` and
> `power(on:true)` succeed without cfgSet (they reference no fonts),
> so the screen would visibly clear after connect — but every `txt`
> draw was silently dropped or 0xE2-rejected. None of PRs #49/#53/#55/#57
> were wrong; each fixed a real bug; they were all just MASKED by the
> missing cfgSet underneath.
>
> 🟠 **ENCODER + OBSERVABILITY FIXED (2026-05-19, PR #57):** rc5/rc6 blank
> screen was actually TWO bugs missed by PRs #49/#53/#55:
> 1. **Missing queryID byte.** Every command frame lacked the 1-byte
>    queryID with `format = 0x01` that the official ActiveLook iOS SDK
>    always emits. Engo 2 firmware silently misparses missing-queryID
>    frames — reads `power(on:true)`'s on-byte as the queryID and renders
>    `txt` text 5000+ pixels off-screen.
> 2. **Silent flow-control + error notifications.** `didUpdateValueFor`
>    routed only the battery characteristic; runtime flow-control values
>    (0x01 ON / 0x02 OFF) and TX-channel 0xE2 error notifications were
>    dropped. All commands could be rejected by the firmware with zero
>    feedback to the watch.
> Both fixed in PR #57. See decisions inbox entry
> `laughlin-hud-queryid-fix.md` for the full cross-research forensic.
>
> ## 🚨 CRITICAL — `holdFlush(hold:true) … (hold:false)` requires CALLER-SIDE serialization (rc13 lesson, PR #72)
>
> Per-tick `RunningHUDFrame.frames(for:)` wraps the 4-frame
> `[clear, txt, txt, txt]` core in `holdFlush(hold:true)` … `holdFlush(hold:false)`
> for atomic commit (anti-flicker, rc9). **The BLE actor's `pendingWrite`
> continuation only serializes ONE BLE write at a time — it does NOT
> serialize across the prologue↔epilogue span of a multi-frame
> sequence.** `ActiveLookGlassesAdapter.sendCommands(_:)` iterates
> `for frame in frames { try await write(frame) }`; between each
> `await`, the actor is reentrant, so a second concurrent
> `sendCommands(_:)` from another caller will interleave its writes.
> A foreign `holdFlush(hold:false)` landing mid-sequence commits the
> partial buffer and strands the rest — Joe's rc12 bench symptom
> ("HUD stays on splash through entire active run; final stats appear
> at stop") was exactly this: the only sequences that landed cleanly
> were the ones without holdFlush wrap (connect splash, summary).
>
> **Rules for any caller issuing holdFlush-wrapped multi-frame bursts:**
> 1. **The caller MUST await the push.** Do NOT spawn it as
>    `Task { await sendCommands(...) }` from a timer or fan-out point.
>    Awaiting serializes against the next iteration of the same
>    caller. AR-Runner's `WorkoutViewModel.tickElapsed()` is `async`
>    and awaits `pushHUDFrameIfConnected()` directly (rc13 fix).
> 2. **The caller MUST serialize against OTHER callers issuing
>    holdFlush-wrapped bursts to the same transport.** In AR-Runner
>    today, the only other caller is the connect-state task's
>    `pushHUDConnectScreenIfConnected`, which sends an
>    UN-wrapped splash (no holdFlush) and only runs on
>    `.connected` edges — so callers are de facto non-overlapping in
>    practice. If a future feature adds a second wrapped path
>    (e.g., notification banners during a run), either route them
>    through a single MainActor-isolated serial pipeline or extend
>    the adapter with a coarser per-burst lock that holds across the
>    entire `sendCommands` call.
> 3. **NEVER add an explicit `holdFlush(hold:false)` outside a
>    paired prologue/epilogue.** It will commit whatever buffer is
>    pending, including another caller's mid-sequence writes.
>
> ## 🚨 CRITICAL — splash banner and run HUD CAN use different fonts (rc13 lesson, PR #72)
>
> `connectFrames()` uses `bannerFontSize = 2` (38 px tall) with
> `bannerLine1Y = 177`, `bannerLine2Y = 97`; the per-tick run HUD
> uses `fontSize = 3` (49 px tall) with `timeY = 166`,
> `distanceY = 86`, `paceY = 6`. The split exists because the splash
> strings ("AR-Runner Ready", "Start a run") are long (15 and 11
> chars) and at font 3 (~28 px/char) overflow `x_fb = 284`'s left-
> extending bounding box per spec §5.5.6; font 2 (~18 px/char) fits.
> Run-HUD strings ("0:00", "0.00 mi", "8:30/mi") stay on font 3 for
> readability at arm's length.
>
> **When choosing the Y for a different-font draw, recompute with
> the new height:** `y_fb = 255 − T − font_height` (lens-flip + top-
> of-glyph anchor offset for `rotation = 4`). Font 2 height = 38 px →
> `y_fb = 217 − T`. Font 3 height = 49 px → `y_fb = 206 − T`.
> Pinned in `test_bannerYCoords_compensateForShorterFontHeight`
> (`RunningHUDFrameTests`). A blanket "make everything font 2" or
> "make everything font 3" without re-deriving Y will silently push
> a line off-screen (clipped per spec §5.5.6) — the same failure
> mode that killed rc11.

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
- `rotation=0` = bottom-RL per the ActiveLook SDK `TextRotation`
  enum — the natural reading direction a wearer sees through the
  Engo 2 waveguide. PR #57's rc7 used `4` (`topLR`), which renders
  text in a non-natural orientation; PR #60 corrected this to `0` to
  match the demo app's standard display orientation. The
  `ActiveLookCommand.text` encoder still defaults to `rotation: 4`
  for backward compatibility with prior callers; pass the
  `RunningHUDFrame.Layout.rotation` constant (now `0`) explicitly
  when using the running-HUD geometry.
- `fontSize=3` = the largest stock font baked into Engo 2 firmware out
  of the box. Readable at arm's length through the projection.
- `color=15` = full white on the monochrome OLED. Anything dimmer
  hurts readability outdoors.

### 3. `txt` command (cmdID 0x37) wire format

```text
0xFF | 0x37 | format=0x01 | len | queryID | x_hi x_lo | y_hi y_lo | rot | font | color | bytes... | 0x00 | 0xAA
```

- **`format` MUST be `0x01`** — that's the low-nibble queryID byte count.
  The spec marks queryID as "optional 0–15 bytes" but Engo 2 firmware
  silently misparses any frame with `format = 0x00`. The official iOS
  SDK always emits `format = 0x01` + 1 queryID byte for every
  application command; only DFU ops (`qspiErase`, `qspiWrite`, `reset`)
  use `withoutQueryId: true`. PRs #49/#53/#55 all shipped `format =
  0x00` frames; PR #57 fixed the encoder.
- `queryID` is a unique 1-byte per-command correlation ID. The
  `ActiveLookCommand` encoder writes `0x00` as a deterministic
  placeholder so unit tests can pin exact bytes; the adapter stamps a
  real incrementing value (wrapping `0xFF → 0x01`, with `0x00`
  reserved as the placeholder) just before `peripheral.writeValue`.
- `x`, `y` are **i16 big-endian**, signed (so off-screen negative
  coordinates are legal — test the two's-complement encoding for
  `y = -1` → `0xFF 0xFF`).
- The string is **null-terminated** UTF-8 (even if empty).
- Re-use the `ActiveLookCommand.encode(id:payload:queryID:withoutQueryId:)`
  framer for the outer envelope so you inherit its two-byte-length
  promotion for long strings AND the default queryID handling.

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

### 7a. Display power — **always send `power(on:true)` before the first draw** (PR #53)

**This is the trap rc4 caught.** Engo 2 firmware boots with the display
in a low-power state after every BLE link-up. The "Connection
Successful" splash is visible because firmware paints it as part of
the link-up handshake — but every host-driven `txt` (cmdID 0x37) is
silently dropped until the host sends `power(on:true)` (cmdID 0x00)
at least once per connection. `clear` (cmdID 0x01) operates on the
display buffer regardless of power state, so it visibly removes the
splash, leaving a *clean blank panel* that masks the real cause.

Implementation contract:

1. Add a **per-connection `needsHUDPowerOn: Bool` flag** that resets
   to true on every `.disconnected / .reconnecting / .failed` edge.
2. On `.connected`, push a one-shot connect screen led by `power(on:
   true)`: `[power on, clear, txt("Ready"), txt("Start a run")]`.
   Use `RunningHUDFrame.connectFrames()`.
3. **First per-tick / first summary frame after (re)connect** uses
   `framesWithPowerOn(for:)` / `summaryFramesWithPowerOn(for:)`
   (prepend `power(on:true)`) as a belt-and-braces guarantee, in
   case the on-connect push raced or failed. Clear the flag after
   any successful power-on send.
4. Subsequent ticks use plain `frames(for:)` — keep BLE writes
   minimal.

Don't infer "display is on" from "I can see text". The splash is the
only host-independent visible state.

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

- **Don't emit command frames with `format = 0x00` (no queryID byte) —
  EVER, except for DFU ops (PR #57 root cause).** Spec marks queryID as
  optional (0–15 bytes) but Engo 2 firmware parses every application
  command as if the 1-byte queryID is always present. Missing-queryID
  frames misparse silently: `power(on:true)`'s on-byte becomes the
  queryID, `txt` coordinates shift by 1 byte and render 5000+ px
  off-screen. Always use `format = 0x01` + 1-byte queryID; opt out
  ONLY for `qspiErase` / `qspiWrite` / `reset` via `withoutQueryId:
  true`, matching the official iOS SDK convention.
- **Don't route only the battery characteristic in `didUpdateValueFor`
  (PR #57 secondary root cause).** The Coordinator MUST also route the
  control characteristic (0xCB9 — flow-control + 0x03/0x04/0x06
  error codes) and the TX characteristic (0xCB8 — 0xE2 error
  notification frames carrying `[cmdId][error][subError]`). Without
  these, command rejections are completely invisible to the watch and
  every "blank screen" debug session has to start from byte-level
  capture instead of console logs. The flow-control runtime gate
  (`flowControlAllowsWrite` flag flipped by the 0x01/0x02 values) is
  separate from and required in addition to the subscription
  confirmation (`flowControlNotifyConfirmed`) added in PR #55.
- **Don't blast multiple BLE commands without waiting for write
  acknowledgment between each.** The ActiveLook protocol requires serial
  command delivery: send one frame → wait for `didWriteValueFor` → send
  next. Fire-and-forget `writeValue` loops drop commands silently. This
  was the rc4/rc5 root cause — both the placeholder fix and the power-on
  fix encoded correct commands that never reached the glasses' command
  processor.
- **Don't transition to `.connected` before flow control notifications
  are confirmed active.** The ActiveLook SDK polls
  `flowControlCharacteristic!.isNotifying == true` before allowing any
  writes (`GlassesInitializer.isReady()`). Without this gate, the
  glasses' firmware drops early commands.
- **Don't send `clear` / `txt` without first sending `power(on:true)`
  on every BLE connection (rc4 regression, PR #53).** Engo 2's display
  is in a low-power state after link-up; `clear` works on the buffer
  but `txt` is silently dropped until the display is powered on. The
  symptom is a clean blank panel — looks like a render bug, is
  actually a power-state bug. Track with a `needsHUDPowerOn` flag
  that resets on every disconnect edge; prepend `power(on:true)` to
  the first frame of every connection.
- **Don't infer "display is on" from "I can see text on the glasses".**
  Firmware splashes bypass the display-power gate; only host-driven
  draws prove the display is actually powered on.
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
- AR-Runner PR #53 — rc4 regression fix: display-power-on prefix +
  on-connect "Ready" screen.
- AR-Runner PR #55 — write serialization + flow-control subscription gate.
- AR-Runner PR #57 — encoder queryID byte + flow-control runtime gate +
  TX/control char notification routing for 0xE2 error observability.
- `.squad/files/hud-forensic-report.md` — SDK-source forensic comparison.
- `.squad/files/hud-api-spec-report.md` — protocol-spec deep dive.
- `.squad/decisions/inbox/laughlin-hud-queryid-fix.md` (after Scribe merge,
  in `decisions.md`) — cross-research methodology and resolution.

---

## 🟢 CONFIRMED WORKING STACK (rc8 bench-validated 2026-05-19)

Joe's bench test of v0.3.0-rc8 on a real Engo 2 confirmed text renders end-to-end. The cumulative working configuration is the product of **seven PRs across three coders** — each one fixes a real bug; removing any single one breaks the chain:

| PR | Author   | Layer            | Fix                                                                                          |
|----|----------|------------------|----------------------------------------------------------------------------------------------|
| #45 | Weiss    | Pairing          | BLE scan / GATT discovery filter (excludes non-ActiveLook peripherals reliably)              |
| #48 | (CI)     | Build pipeline   | Tag → MARKETING_VERSION; run-number → CURRENT_PROJECT_VERSION (TestFlight upload pipeline)   |
| #49 | Weiss    | HUD MVP          | `RunningHUDFrame` raw-`txt` path (bypasses curated-layout machinery)                          |
| #53 | Richards | Power-on         | `power(on:true)` prefix + on-connect "Ready" banner (rc4 regression fix)                     |
| #55 | Weiss    | Serialization    | Write queue + flow-control subscription gate (rc5/rc6 partial fix)                            |
| #57 | Laughlin | Encoder + obs.   | 1-byte queryID with `format = 0x01` on every command + flow-control runtime gate + TX/control char notification routing for 0xE2 error observability |
| #60 | Laughlin | Config namespace | `cfgSet("ALooK")` prepended to `connectFrames()` and `framesWithPowerOn(for:)` — activates the font/layout/image namespace that fonts 1–5 live in. **The keystone fix; without this every prior fix is invisible because fonts don't resolve.** |
| #63 | Laughlin | Polish (rc9)     | `Layout.rotation: 0 → 2` (Engo 2 lens flip calibration) + holdFlush(0x39) wrap around per-tick `frames(for:)` for atomic display commit (eliminates flicker) |
| rc12 | Laughlin | Polish (rc12)    | `Layout` coordinates corrected for Engo 2 lens 180° flip: rotation stays at 4 (topLR — correct glyph-orient × anchor-corner combo); `leftMargin: 20 → 284` (anchor at top-RIGHT, text extends LEFT); `timeY/distanceY/paceY = 206 − y_wearer` (top-of-glyph anchor under lens flip). rc11 blank was off-screen clipping per spec §5.5.6, not firmware rejection. |

**Removing any one of these breaks the chain.** When debugging future "blank screen" or "garbled HUD" symptoms on rc8+, confirm all seven layers are still present before assuming a new bug.

## 🚨 Calibration patterns discovered on rc8/rc9 hardware

### Rotation is wearer-perceived, not framebuffer-oriented

Engo 2's optical projection flips/mirrors the framebuffer relative to what the wearer sees through the waveguide. The `rotation` parameter in `txt`/`layout` commands encodes glyph orientation in framebuffer space (per ActiveLook spec §5.7); the lens flip is **undocumented** and must be discovered empirically.

| rotation value | SDK enum  | Wearer-perceived orientation on Engo 2 |
|----------------|-----------|----------------------------------------|
| `0`            | bottomRL  | upside-down (rc8 ship value — bug)     |
| `2`            | topRL     | **right-side-up (rc9 ship value — confirmed)** |
| `4`            | topLR     | rotated 90° / sideways (rc7 ship value — bug) |

**Rule:** rotation is calibrated per device. When bringing up a new ActiveLook hardware target, start with `rotation = 2` and trial-and-error against the wearer's POV. The SDK enum is reliable; the lens behaviour is not.

### holdFlush wrapping for atomic per-tick updates

Per-tick HUD sequences that contain `clear` + multiple `txt` writes will visibly flicker if each write commits to the framebuffer independently. Per ActiveLook spec §4.6 and `hud-api-spec-report.md` §"Fix 3", wrap the sequence:

```
holdFlush(action: 0x00 HOLD)
clear
txt(time)
txt(distance)
txt(pace)
holdFlush(action: 0x01 FLUSH)
```

The HOLD/FLUSH pair defers framebuffer commits until the FLUSH, making the entire batch appear as one atomic transition.

- **Apply to:** `frames(for:)` (per-tick HUD update) and any future multi-write sequence the user perceives as "one update."
- **Do NOT apply to:** `connectFrames()`, `summaryFrames()`, or any one-shot draw where the user only ever sees the final state. Wrapping these adds protocol surface without visible benefit.
- **Encoder:** `ActiveLookCommand.holdFlush(hold: Bool)` — `hold:true` → HOLD (0x00), `hold:false` → FLUSH (0x01). cmdID `0x39`. Standard `format = 0x01` 1-byte queryID like every other application command.
