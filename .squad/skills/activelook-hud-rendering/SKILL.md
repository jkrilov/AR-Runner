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
>
> ## 🚨 CRITICAL — right-justifying one of two metrics on a shared line (rc2 lesson, 2026-05-20)
>
> When two metrics share a single line (e.g. finish-screen line 3:
> `TIME    PACE` with TIME left-anchored and PACE right-anchored), the
> ActiveLook `txt` primitive has NO built-in alignment — there is one
> anchor per write and it lands wherever `(x, y)` says. Two viable
> strategies; **pick (b) until `ALookFontMetrics` is extracted**:
>
> - **(a) Single write, padded string.** Build one combined string with
>   inter-metric spaces (`"27:43          8:56/mi"`) and a single
>   `txt`. Looks clean in code; **fails on proportional fonts** because
>   space glyphs are narrower than digit glyphs, so the right-end
>   position varies with the actual metric values. Acceptable only for
>   a confirmed-monospace font (no ActiveLook stock font qualifies).
>
> - **(b) Two writes per line, shared y, different x.** TIME at
>   `leftMargin` (canonical wearer-left). PACE at a *fixed* second
>   anchor computed for the **worst-case pace string** using a
>   conservative per-glyph width ceiling (font 2 → 20 px/char with
>   ~11 % headroom over the empirical ~18; font 3 → 28 px/char). The
>   constant lives in `Layout` with its derivation in a comment.
>   Cost: one extra `txt` command per finish-frame push (one-shot,
>   not per-tick) — negligible under the rc8+ write-serialization
>   contract.
>
> **Formula for the right-justified anchor under `rotation = 4`
> (topLR) + the Engo 2 lens flip:**
>
> ```text
> rightAnchorX_fb = (303 − wearerRight) + (maxChars × fontWidthCeiling)
> ```
>
> The anchor under topLR + lens flip lands on the wearer-LEFT edge of
> the text block (see live-HUD `liveLeftMargin = 303 − 60 = 243`
> derivation). So to pin the wearer-RIGHT edge of the *longest legal
> pace string* at `wearerRight = 283` (20-px right margin), solve for
> x_fb using the worst-case width. Shorter strings render with a
> slight right inset — visually "right-aligned with a small gutter,"
> acceptable trade-off vs. the precision of a measure-and-shift
> implementation.
>
> **Rules:**
>
> 1. **Pin `payload.<metric>.count <= maxChars` in the formatter** for
>    every metric whose anchor is computed against `maxChars`. A
>    runtime overflow silently regresses the worst-case overlap math.
> 2. **Add a `test_<line>_noHorizontalOverlap_worstCase` test** that
>    asserts `wearer_right(leftMetric_worst) < wearer_left(rightMetric_worst)`
>    using the same width ceiling. This catches a formatter regression
>    OR a too-loose ceiling.
> 3. **When `ALookFontMetrics` ships** (Richards rec #2), collapse the
>    fixed-anchor constant to a computed expression
>    `(303 − rightMargin) + ALookFontMetrics.width(string, font:)` and
>    delete the width-ceiling magic numbers from `Layout`. The
>    transition is a pure widening (precision goes up, on-panel
>    invariants preserved).
> 4. **Do NOT introduce a new `rotation` value for the right-justified
>    half** (e.g. `topL` for left, `topR` for right). Two writes at
>    the same bench-validated rotation is strictly safer than one
>    write at a novel rotation under the Engo 2 lens flip.
>
> ## 🚨 CRITICAL — validate X extent for EVERY finish/banner string, not just Y (rc1 lesson, 2026-05-20)
>
> rc17's finish-screen tests pinned the Y formula (`y_fb = 255 − wearer_top`)
> but did NOT pin string-width-fits-in-leftMargin. Joe's rc1 bench saw
> "text cut off" on the finish screen; the most likely cause is the
> 16-char "Workout Complete" banner overflowing the 284-px
> left-extending bounding box at font 3 (16 × ~28 ≈ 448 > 284), with
> the leading characters silently clipped per spec §5.5.6 — exact
> same failure class as rc11 splash and rc15 "BPM" tail.
>
> **Add an X-extent test alongside every Y-extent test:**
>
> ```swift
> for (string, font, anchor) in finishScreenStrings {
>     let w = string.count * fontWidthCeiling(font)
>     XCTAssertLessThanOrEqual(w, Int(anchor),
>         "\(string) at font \(font) overflows \(anchor)-px left-extending box")
> }
> ```
>
> The rc17 finish-screen Y coords (239 / 159 / 79) were
> mathematically correct under the rc16 lens-flip formula. The bug
> was that nobody tested whether the *strings* fit the *anchor*. A
> validated formula is not a validated layout.
>

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

### Live HR + finish-screen field-split pattern (rc14)

Two related conventions captured here so future contributors don't have to
rediscover them.

**HR formatter.** `RunningHUDFrame.formatHeartRate(_:)`:

- `nil` → `"-- bpm"` (pre-first-sample placeholder)
- `!isFinite` → `"-- bpm"` (sensor garbage)
- `< 30 BPM` → `"-- bpm"` (sub-30 in a running workout = dropped contact;
  rendering "12 bpm" mid-run would alarm the user)
- otherwise → `"\(Int(round(bpm))) bpm"` (mirrors the wrist UI at
  `WorkoutView.swift:169`)

Do **not** cap the high end. A real 220 BPM max-effort reading is useful
telemetry; silencing it as "noise" is the same anti-pattern as silently
clipping off-screen text (`spec §5.5.6`).

**Live HUD vs Finish HUD field split.** rc14 directive from Joe (bench
test on rc13): live HUD shows 4 fields (Time, HR, Distance, Avg Pace),
finish HUD shows 2 fields (Time, Distance) under a "Workout Complete"
banner. `summaryFrames(for:)` takes a fully-populated `Payload` and
**deliberately discards** `heartRate` and `pace` from the encoded frames.
Pinned in `test_summaryFrames_renderTimeAndDistanceOnlyPerFinishScreenDirective`.

Adding a future field to the live HUD: extend `Payload`, add a new
`liveXxxY` constant (use `y_fb = 206 − T` lens-flip formula with the
55-px wearer-space step the rc14 4-field layout pins), update `frames(for:)`.
Adding a future field to the finish screen: explicitly opt-in by passing
the value into the `summaryFrames(for:)` encoder; don't assume "payload
has it → render it." The two builders have **separate field contracts**.

**HealthKit HR subscription is already wired upstream.** Future "pull HR
forward" work for a new lens or layout is essentially zero-cost on the
HealthKit side — `HealthKitWorkoutSubstrate.workoutBuilder(_:didCollect
DataOf:)` already subscribes to `HKQuantityTypeIdentifier.heartRate`,
already mapped through `WorkoutMetric(kind: .heartRate, …)`, and
`WorkoutViewModel.apply(metric:)` already captures into `heartRate:
Double?`. **Before scoping a v0.4.0+ metric pull-forward as a new
"observer pattern" subtask, walk the substrate end-to-end first** — the
real work is usually one of: (a) a new `MetricKind` case in Core (cf. the
2026-05-16 `MetricKind.energy` saga), (b) a payload-field extension on
`RunningHUDFrame.Payload`, or (c) zero — already wired, just unhooked
from the HUD encoder.

---

## rc15 — Mixed-font 3-line live HUD; icon pipeline deferred to rc16

**Confidence:** HIGH (layout). DEFERRED (icons — see below).

rc14 shipped 4 × font 3 lines; Joe's bench reported overlapping text.
rc15 redesigns to **3 lines with mixed fonts**:

| Line | Content                  | Font     | Why                                  |
|------|--------------------------|----------|--------------------------------------|
| 1    | Time (left) + HR (right) | 2 (38 px)| Two metrics share line — narrower glyphs needed |
| 2    | Distance                 | 3 (49 px)| Single metric — keep large + readable|
| 3    | Avg Pace                 | 3 (49 px)| Single metric — keep large + readable|

**Two-metric line pattern:** two `txt` commands sharing
`liveLine1Y`, with different `x_fb`. Time anchors at
`leftMargin = 284` (wearer-left ≈ 20); HR anchors at
`liveHRX = 133` (wearer-left ≈ 170, mid-panel). Pick the second
column's x_fb empirically — don't try width-aware right-alignment
under topLR without a documented font-advance table.

**Constants (`RunningHUDFrame.Layout`):**

* `liveLine1Y = 187` (font 2 → `y_fb = 217 − T`, T = 30)
* `liveDistanceY = 106` (font 3 → `y_fb = 206 − T`, T = 100)
* `livePaceY = 26` (font 3 → `y_fb = 206 − T`, T = 180)
* `liveHRX = 133` (line-1 right-column anchor)
* `liveLine1Font = 2` (sits alongside the unchanged `fontSize = 3`)

**Frame sequence per tick (unchanged shape from rc14):**
`holdFlush(hold) + clear + 4×txt + holdFlush(flush)` = 7 BLE
writes. Same wire volume; mixed fonts cost nothing on the wire.

## 🚨 IMAGES / ICONS: cfgWrite is a HARD prerequisite (rc15 finding, rc16 work)

The rc15 brief originally scoped icon rendering via `imgSave` /
`imgDisplay` / `imgList`. Phase-0 spec research (see
`.squad/files/hud-icon-research.md`) found:

* Spec §5.5 prelude: *"⚠ The `cfgWrite` command is required before
  images upload."* `imgSave` into the stock ALooK config requires
  Microoled-supplied credentials we don't have; the alternative is
  installing a brand-new user config — but **fonts live per-config**,
  so `cfgSet("ARRunner")` would lose access to the stock fonts the
  current HUD depends on, forcing a parallel font-upload pipeline.
* Modern command IDs (spec §4.7): `imgList = 0x47`,
  `imgDisplay = 0x42`, `imgSave = 0x41`. The deprecated IDs at
  §4.16 (`0x40`, `0x44`) should NOT be used in new code; they're
  retained only for backward compatibility.
* Image data is sent in **chunks ≤ 512 bytes** with
  **WRITE WITH RESPONSE** — adapter `write(_:)` doesn't currently
  model either. First-chunk and continuation-chunk semantics
  differ; encoder needs new helpers.
* `imgList` response is variable-length on the TX notification
  characteristic; requires queryID-correlated response demux that
  doesn't exist today (only battery is currently consumed).
* PNG → 4bpp pixel-pair packing requires a build-time script
  (Python/Pillow → blob) or runtime CoreGraphics work.
* Engo 2 lens applies the same 180° flip to images as to text;
  `imgDisplay` accepts only `id; x; y` (no rotation flag), so
  icons must be pre-rotated 180° at build time. Recommend
  `scripts/prepare-glasses-icons.py` shipping the rotated bytes
  as a Swift `[UInt8]` literal.

**rc16 plan when icon work is picked up:**

1. Prototype with `imgStream` (0x44) — one-shot, no `cfgWrite`
   required. Validates pixel packing + rotation visually first.
2. Decide ALooK-overwrite vs. new-user-config (and font re-upload)
   based on whether Microoled credentials are obtainable.
3. Add `writeWithResponse` mode + chunk-split helper (max 512 B/chunk)
   + TX-notification response demux to the adapter.
4. Build-time PNG → 4bpp pipeline; commit the rotated blob.
5. THEN add the encoder helpers (`imgSave`, `imgDisplay`, `imgList`)
   wired into the new chunk-split path.

---

## rc16 — Preloaded ALooK icons + corrected font heights + corrected lens-flip formula

**Confidence:** HIGH (encoder + flash IDs + layout). MEDIUM (icon orientation — under bench test on rc16).

### Real ActiveLook font heights (USE THIS TABLE, not spec §5.9)

Per the `ActiveLook/Activelook-Visual-Assets` repo README which ships the
stock ALooK configuration the firmware loads:

| Font index | Height (px) | Chars range |
|-----------:|------------:|-------------|
|     **1**  |      **24** | Space to ~  |
|     **2**  |      **38** | Space to ~  |
|     **3**  |      **64** | Space to ~  |
|     **4**  |      **75** | Space to ;  |
|     **5**  |      **82** | Space to ;  |

**Do NOT use spec §5.9's generic txt-font height table** — that's a
different (smaller) font table that does NOT match what ALooK actually
preloads. rc12/14/15 assumed font 3 = 49 px (from §5.9) and accumulated
~15 px/line of unmodeled height that pushed the rc15 pace line off-screen.

### The corrected topLR lens-flip formula

For `rotation = 4` (topLR) text on Engo 2, the empirically-validated
framebuffer-to-wearer Y mapping is:

```
y_fb = 255 − wearer_top      (NOT 255 − wearer_top − font_height)
wearer_top    = 255 − y_fb
wearer_bottom = 255 − y_fb + font_height
```

The X mapping is unchanged from rc12:

```
x_fb = 303 − wearer_left     (topLR anchors at the RIGHT edge of the
                              text block in wearer space — block extends
                              LEFT from there)
```

**Evidence:** rc15 livePaceY=26 + font_3=64 → wearer_top=229, wearer_bottom=293
(38 px off screen bottom) matches Joe's "just one pixel at bottom" bench
observation *exactly*. The rc12-era `y_fb = 255 − T − font_height` formula
predicts wearer 165..229 — fully visible — which Joe definitively didn't see.
**Trust the bench data over the derivation.**

### Preloaded ALooK icons — `imgDisplay` (0x42) without `cfgWrite`

The stock ALooK configuration (which we activate via `cfgSet("ALooK")` at
connect time, rc8 PR #60) ships with 40+ preloaded icons. The `Activelook-
Visual-Assets` repo lists them; the **leading number in each asset filename
is the literal flash ID** the firmware indexes by. Examples used in the
rc16 live HUD:

| Asset filename            | Flash ID | Size  |
|---------------------------|---------:|-------|
| `40_chrono_40x40`         |    **40** | 40×40 |
| `12_heart-beat_28x28`     |    **12** | 28×28 |
| `9_distance_28x28`        |     **9** | 28×28 |
| `17_pace-avg_28x28`       |    **17** | 28×28 |

To render one: `imgDisplay(id, x, y)` (cmdID 0x42, spec §4.7). Wire format:
`id(u8) | x(u16 BE) | y(u16 BE)`. **No upload pipeline needed for these** —
the `cfgWrite` / chunked `imgSave` iceberg documented in
`.squad/files/hud-icon-research.md` (rc15) applies only to *custom*
user-supplied artwork that isn't already in the active configuration.

**Icon framebuffer coords.** `imgDisplay` has no rotation flag and treats
(x, y) as the bitmap's top-left in framebuffer space. The Engo 2 lens
still applies its 180° flip, so a `w × h` icon at fb `(x, y)` appears to
the wearer at wearer rect `[303 − x − w, 303 − x] × [255 − y − h, 255 − y]`
rotated 180°. The preloaded ALooK icons are **shipped pre-rotated** to
match the demo app's expected lens orientation (per the Visual-Assets
README convention) — they should read upright with no compensation when
displayed through the lens.

**If bench shows them upside-down**, the convention is wrong; pre-rotate
at upload time (which puts us back on the custom-asset path with all its
machinery) or accept and ship our own rotated copies. The encoder is the
same either way.

### Recipe for adding a new HUD line/field with an icon

1. Pick the wearer-space target rect (T = top, H = height).
2. Text Y anchor (topLR): `y_fb = 255 − T`. Always use the corrected
   formula — never re-derive.
3. Text X anchor (topLR, wearer-left edge of text at L): `x_fb = 303 − L`.
4. Pick an icon from the ALooK preloaded set (see Visual-Assets repo).
   Verify the flash ID = leading number in the asset filename.
5. Icon framebuffer top-left for icon `w × h` at wearer rect
   `[wL, wL+w] × [wT, wT+h]`:
   `x_fb = 303 − wL − w`, `y_fb = 255 − wT − h`.
6. Pin a test that asserts the (id, x, y) tuple end-to-end (encoder
   byte sequence + frame index inside the `frames(for:)` output).
7. Verify all icon and text rects stay inside `[0, 304] × [0, 256]`
   in framebuffer space — off-screen coords are silently clipped
   (spec §5.5.6).
8. Use the corrected font-height table above when computing line
   spacing — F2=38 px, F3=64 px (NOT 49). Total text+icon height +
   gaps must sum to ≤ 256.
