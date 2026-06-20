// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pure-Swift builder for the v0.3 raw-text running HUD (time / distance /
/// pace) displayed on Engo 2 glasses during an active workout.
///
/// **Why this exists.** v0.2 wired a curated-layout pipeline
/// (`RunningHUDPreset` → `selectLayout(id:)` → per-tick `updateField`) but
/// the `CuratedLayoutCatalog` device IDs are still **pre-bake placeholders**
/// (0x01 / 0x02 / 0x03) — no such layout slot exists on the actual glasses
/// until the Config-Generator bake step ships. Activating one of those
/// placeholders on real hardware is precisely the bug Joe's bench test
/// surfaced: scan/connect succeeds, but the glasses stay frozen on
/// "Connection Successful" because every `updateField` writes into a layout
/// that was never baked.
///
/// The v0.3 fix is to skip the curated-layout machinery entirely for v1 and
/// render the three runner-critical stats directly with the ActiveLook `txt`
/// command (cmdID 0x37 — draw text at absolute (x, y)). This works on any
/// stock Engo 2 with no on-device configuration.
///
/// Pure value type; trivially `Sendable`.
public enum RunningHUDFrame {
    // MARK: - HUD geometry

    /// Display geometry constants for Engo 2.
    ///
    /// The native panel is 304 × 256 px (per ActiveLook hardware spec). The
    /// three-row layout below targets a left-aligned column with vertical
    /// spacing tuned for the largest stock font (`fontSize = 3`). Coordinates
    /// mirror the ActiveLook iOS sample app's running-HUD demo.
    public enum Layout {
        public static let screenWidth: Int16  = 304
        public static let screenHeight: Int16 = 256

        /// Framebuffer x-anchor for all three lines.
        ///
        /// `rotation = 4` (topLR) anchors at the TOP-RIGHT of the text block
        /// and grows LEFTWARD. To land the wearer-visible LEFT edge at
        /// x_wearer ≈ 20 we solve the Engo 2 lens 180° flip
        /// `x_wearer = 303 − x_fb` → `x_fb = 283 ≈ 284`. rc11 used 20 here
        /// with rotation=4 and went blank: the text block extended into
        /// negative x and was silently clipped per spec §5.5.6.
        public static let leftMargin: Int16 = 284

        /// Framebuffer y-anchors for the SUMMARY (finish) screen — **rc2
        /// (2026-05-20) 3-line / 4-data layout** per Joe's 5K bench
        /// feedback:
        ///
        /// ```
        /// Line 1: "Finished!"
        /// Line 2: <distance>                e.g. "3.11 mi"
        /// Line 3: <time>      <avg pace>    e.g. "27:43    8:56/mi"
        /// ```
        ///
        /// **Two-field rule supersession.** rc14→rc17 enforced "finish
        /// screen = Time + Distance only" (Richards's rc13→rc16 review:
        /// "discard HR/pace at the encoder"). Joe's rc2 directive
        /// overrides that — the finish screen now hosts 4 data items
        /// (banner, distance, time, pace) across 3 visual lines, with
        /// time on the left of line 3 and avg-pace right-justified on
        /// the same line. Documented as a deliberate evolution in
        /// `.squad/decisions/inbox/laughlin-rc2-bench-feedback.md`;
        /// the live HUD's 4-fields/3-lines shape is unchanged.
        ///
        /// **rc17 lens-flip formula still canonical.** All three line
        /// tops use `y_fb = 255 − wearer_top` with NO font-height
        /// subtraction. The Y constants are unchanged from rc17 — the
        /// 3-line layout happens to land at the same wearer-tops
        /// (16 / 96 / 176) under the recomputed font-3 height of 64. The
        /// rename surfaces the new responsibility: line 1 is no longer
        /// "banner" semantically (it's still a banner string), line 2
        /// no longer "time" (it's distance), line 3 no longer "distance"
        /// (it's a two-field row).
        public static let finishLine1Y: Int16 = 239   // 255 − 16  — "Finished!"
        public static let finishLine2Y: Int16 = 159   // 255 − 96  — distance
        public static let finishLine3Y: Int16 = 79    // 255 − 176 — time + pace

        @available(*, deprecated, renamed: "finishLine1Y",
                   message: "rc2 finish-screen reshape: line 1 is now \"Finished!\" (was \"Workout Complete\" banner). Same Y, new semantic.")
        public static let finishBannerY:   Int16 = finishLine1Y
        @available(*, deprecated, renamed: "finishLine2Y",
                   message: "rc2 finish-screen reshape: line 2 is now distance (was time). Same Y, new semantic.")
        public static let finishTimeY:     Int16 = finishLine2Y
        @available(*, deprecated, renamed: "finishLine3Y",
                   message: "rc2 finish-screen reshape: line 3 is now time+pace shared (was distance). Same Y, new semantic.")
        public static let finishDistanceY: Int16 = finishLine3Y

        @available(*, deprecated, renamed: "finishLine1Y",
                   message: "Renamed per Richards rc16 review rec #3; reshaped to 3-line/4-data layout in rc2.")
        public static let timeY:     Int16 = finishLine1Y
        @available(*, deprecated, renamed: "finishLine2Y",
                   message: "Renamed per Richards rc16 review rec #3; reshaped to 3-line/4-data layout in rc2.")
        public static let distanceY: Int16 = finishLine2Y
        @available(*, deprecated, renamed: "finishLine3Y",
                   message: "Renamed per Richards rc16 review rec #3; reshaped to 3-line/4-data layout in rc2.")
        public static let paceY:     Int16 = finishLine3Y

        /// rc2 — wearer-x of the RIGHT edge for the right-justified pace
        /// text on finish line 3. Symmetric to the left margin (~19 px
        /// from edge: leftMargin=284 ⇒ wearer-left ≈ 19; we use wearer-
        /// right = 303 − 19 = 284). The framebuffer-anchor x for the
        /// pace text is computed at render time via
        /// `summaryPaceXFB(for:)` because topLR (rotation=4) text in
        /// wearer space anchors at the LEFT edge and grows RIGHT, so a
        /// right-justified column needs to subtract the measured width.
        public static let finishLine3PaceWearerRight: Int16 = 284

        /// rc2 — font for the shared time+pace line 3 (font 2, ~18 px
        /// per glyph). Two metrics share the line; at font 3 (~28 px)
        /// they collide for any reasonably long pace string ("8:30/mi"
        /// ≈ 196 px vs. only ~144 px of free space after a 5-char time).
        /// Font 2 mirrors the live HUD's line-1 two-metric trick (rc16
        /// `liveLine1Font`) and leaves ~49 px of breathing room for the
        /// canonical 5-char time + 7-char pace pair.
        public static let finishLine3Font: UInt8 = 2

        // MARK: - Live HUD (3-line mixed-font + preloaded icons, rc16)
        //
        // rc15 (PR #75, build 30) shipped 3 mixed-font lines based on
        // the assumption that ActiveLook font 3 was 49 px tall. Joe's
        // bench test of build 30 reported (verbatim):
        //   "ok, the layout is almost there. The top line is just
        //    slightly cutoff, 1 or two pixels on the 'm' in 'BPM' are
        //    missing on the right side. After that there's a large gap
        //    before the distance, then the pace is almost completely
        //    off the screen, I can see just one pixel at the bottom of
        //    the screen. Can we try to fix the layout and add the icons
        //    in the next PR?"
        //
        // Root cause: **font height under-estimation**. The
        // ActiveLook-Visual-Assets repo README (which ships the ALooK
        // config) confirms the real preloaded-font heights:
        //   Font 1 = 24 px, Font 2 = 38 px, Font 3 = 64 px,
        //   Font 4 = 75 px, Font 5 = 82 px.
        // rc15 had assumed Font 3 = 49 px (the spec §5.9 "txt-font"
        // table — a different font table than what's actually in
        // ALooK). 49 → 64 = 15 px taller per font-3 line, accumulating
        // to 30+ px of "too much text crammed in" that pushed the pace
        // line off the bottom of the panel.
        //
        // Also: empirically, the topLR (rotation=4) anchor maps to
        // wearer coords via `y_fb = 255 − wearer_top` (NOT
        // `255 − wearer_top − font_height` as the rc12/14/15 derivation
        // assumed). Walking the rc15 bench evidence:
        //   - rc15 livePaceY = 26, font 3 → wearer_top = 255 − 26 = 229,
        //     wearer_bottom = 229 + 64 = 293 → 38 px off the bottom.
        //     Matches Joe's "just one pixel at bottom" exactly.
        //   - rc15 liveLine1Y = 187 (font 2) → wearer 68..106;
        //     rc15 liveDistanceY = 106 (font 3) → wearer 149..213.
        //     Gap = 43 px. Matches Joe's "large gap before distance".
        // Both observations only line up under the
        // `y_fb = 255 − wearer_top` interpretation; rc12 happened to
        // place text in visible regions by coincidence, not because
        // the derivation was correct.
        //
        // rc16 LAYOUT (wearer coords, T = top-of-glyph):
        //   Top margin     : 15
        //   Line 1 (F2 h=38, Time + chrono icon + HR + heart icon): T=15..53
        //   Gap            : 32
        //   Line 2 (F3 h=64, Distance + distance icon)            : T=85..149
        //   Gap            : 29
        //   Line 3 (F3 h=64, Avg Pace + pace icon)                : T=178..242
        //   Bottom margin  : 13
        //   ──────────────────────────────────────────────── total: 255
        //
        // Text anchors (topLR — anchor at top-right of glyph block,
        // grows LEFT; `y_fb = 255 − T`):
        //   liveLine1Y    = 255 − 15  = 240
        //   liveDistanceY = 255 − 85  = 170
        //   livePaceY     = 255 − 178 = 77
        //
        // Horizontal: text starts at wearer-x = 60, leaving wearer-x
        // [15..55] for the line-1 chrono icon (40 wide) and [27..55]
        // for the smaller 28-wide line-2/3 icons (right-aligned with
        // the chrono icon's right edge, looks tidy). Text anchor
        // (right-edge in wearer space, since topLR text grows left
        // from anchor):
        //   liveLeftMargin = 303 − 60  = 243   (Time/Distance/Pace text)
        //   liveHRX        = 303 − 220 = 83    (HR text wearer-left=220)
        // HR icon at wearer-x [187..215] sits between Time (ends at
        // wearer-x ≈ 186 for a long "1:23:45") and HR text (wearer-x
        // [220..274] for "165" at font 2 ≈ 18 px/char).
        //
        // **The "BPM" text suffix is dropped from the HR string** —
        // that's what frees up the rightmost pixels Joe saw clipped
        // ("1 or two pixels on the 'm' in 'BPM' are missing"). The
        // heart icon now carries the "this is heart rate" semantic;
        // see `formatHeartRate(_:)` below.
        //
        // **Icons are framebuffer-direct (no rotation flag in
        // imgDisplay).** For an icon of size `w × h` to appear at
        // wearer rect `[wL, wL+w] × [wT, wT+h]` (after the Engo 2
        // 180° lens flip), pass framebuffer top-left:
        //   x_fb = 303 − wL − w
        //   y_fb = 255 − wT − h
        // The preloaded ALooK icons ship pre-rotated 180° (per the
        // Visual-Assets repo convention) so the post-lens result reads
        // upright to the wearer. If build 31 shows icons upside-down
        // on bench, that hypothesis is wrong and rc17 will pre-rotate
        // at upload time — but our rc16 path is encoder-only (no
        // upload required since icons are preloaded), so iteration is
        // cheap.
        public static let liveLeftMargin: Int16 = 243   // 303 − 60
        public static let liveLine1Y:     Int16 = 240   // 255 − 15
        public static let liveDistanceY:  Int16 = 170   // 255 − 85
        public static let livePaceY:      Int16 = 77    // 255 − 178

        /// Framebuffer x-anchor for the HR text block on line 1.
        ///
        /// rc16: shifted from rc15's 133 → 83. Two changes drive this:
        /// (a) HR text now omits " bpm" (just digits like "165"),
        ///     freeing ~72 px of width;
        /// (b) the heart icon needs its own slot at wearer-x [187..215]
        ///     between Time and HR text.
        /// Wearer-left of HR text at 220 → x_fb = 303 − 220 = 83.
        public static let liveHRX:        Int16 = 83

        /// Font index for the shared Time+HR line. Font 2 (38 px tall,
        /// ~18 px/char) instead of font 3 — two metrics share a line
        /// and would collide at font 3's wider glyphs. Single-metric
        /// lines 2 and 3 stay on `fontSize` (3).
        public static let liveLine1Font: UInt8 = 2

        // MARK: - Preloaded ALooK icon IDs (rc16)
        //
        // These are flash IDs (the leading number in each asset filename
        // in `ActiveLook/Activelook-Visual-Assets`). The stock ALooK
        // configuration ships them preloaded — they are addressable by
        // `imgDisplay(id, x, y)` (cmdID 0x42) as long as
        // `cfgSet("ALooK")` has run (which it does, at the top of
        // `connectFrames()` and `framesWithPowerOn(for:)`).
        public static let chronoIconID:   UInt8 = 40   // 40_chrono_40x40
        public static let heartIconID:    UInt8 = 12   // 12_heart-beat_28x28
        public static let distanceIconID: UInt8 = 9    // 9_distance_28x28
        public static let paceIconID:     UInt8 = 17   // 17_pace-avg_28x28

        // Icon framebuffer top-left coords. Derived from wearer-target
        // rect via the lens-flip formulas in the doc block above.
        //
        //   chrono  (40×40): wearer x [15..55], y [15..55]
        //   heart   (28×28): wearer x [187..215], y [20..48]
        //                    (vertically centered on the 38-px line 1)
        //   distance(28×28): wearer x [27..55], y [103..131]
        //                    (vertically centered on the 64-px line 2)
        //   pace    (28×28): wearer x [27..55], y [196..224]
        //                    (vertically centered on the 64-px line 3)
        public static let chronoIconX:    UInt16 = 248  // 303 − 15  − 40
        public static let chronoIconY:    UInt16 = 200  // 255 − 15  − 40
        public static let heartIconX:     UInt16 = 88   // 303 − 187 − 28
        public static let heartIconY:     UInt16 = 207  // 255 − 20  − 28
        public static let distanceIconX:  UInt16 = 248  // 303 − 27  − 28
        public static let distanceIconY:  UInt16 = 124  // 255 − 103 − 28
        public static let paceIconX:      UInt16 = 248  // 303 − 27  − 28
        public static let paceIconY:      UInt16 = 31   // 255 − 196 − 28

        /// ActiveLook font index for the runner HUD. `3` is the largest stock
        /// font baked into Engo 2 firmware out of the box; readable at arm's
        /// length through the projection.
        public static let fontSize: UInt8 = 3

        // MARK: - Splash banner (font 2)
        //
        // rc12 bench test (Joe): the `connectFrames()` splash strings
        // ("AR-Runner Ready" + "Start a run") rendered with the last few
        // characters cut off — Joe saw "AR-Runner" and "Start a ru". With
        // `rotation = 4` (topLR — anchor at top-right, text grows LEFT),
        // a 15-char string at font 3 (~28 px/char) spans ~420 px starting
        // at `x_fb = 284` and extends to `x_fb ≈ −136`. Spec §5.5.6
        // silently clips the off-screen chars, so the wearer sees only
        // the portion that landed in `0 ≤ x_fb ≤ 303`.
        //
        // **Fix:** render the splash banner at font 2 (38 px tall, ~18 px
        // wide per glyph). 15 chars × ~18 px ≈ 270 px ≤ 284 px → the
        // whole string lands in valid framebuffer x. The run HUD stays on
        // font 3 because its strings are short ("0:00", "0.00 mi",
        // "8:30/mi" ≤ 8 chars).
        //
        // Banner y coords compensate for the shorter glyph (38 vs 49 px)
        // so the wearer-visible top of each line stays at the same
        // wearer-y as before (T = 40, 120):
        //   y_fb = 255 − T − 38 = 217 − T  →  T=40 → 177, T=120 → 97.
        public static let bannerFontSize: UInt8 = 2
        public static let bannerLine1Y:   Int16 = 177
        public static let bannerLine2Y:   Int16 = 97

        // rotation=4 (topLR) stays from rc11. The rc11 blank was NOT
        // firmware rejection of rotation=4 — it was off-screen clipping
        // (spec §5.5.6): topLR anchors at top-right and grows LEFT, so at
        // x=20 the string landed at negative x and was silently dropped.
        // The fix is to move the anchor (see leftMargin/timeY/distanceY/
        // paceY above), not the rotation. Glyphs are rendered 180°-flipped
        // by topLR; the Engo 2 lens applies another 180° point-symmetric
        // flip, so the net result is right-side-up to the wearer.
        // ALooK system layout #10 (the demo app's running-time layout)
        // ships with rotation=4, confirming this is the canonical choice.
        public static let rotation: UInt8 = 4

        /// 15 = full white on the monochrome OLED. Anything dimmer hurts
        /// readability outdoors.
        public static let color: UInt8 = 15
    }

    // MARK: - Pre-formatted payload

    /// The strings the HUD renders, after formatting. Captured as a struct
    /// (not loose params) so the change-detection check in
    /// `RunningHUDPushPolicy` is a single `==` and so future fields
    /// (splits, cadence) can extend the type without re-shaping every
    /// call site. rc14 added `heartRate` (live HUD) — finish-screen
    /// builders ignore it.
    public struct Payload: Sendable, Equatable {
        public let time: String
        public let heartRate: String
        public let distance: String
        public let pace: String

        public init(time: String, heartRate: String = "--", distance: String, pace: String) {
            self.time = time
            self.heartRate = heartRate
            self.distance = distance
            self.pace = pace
        }
    }

    // MARK: - Builders

    /// Build a HUD `Payload` from raw workout numbers, reusing the same
    /// formatters as Laughlin's PR #41 in-run watch display so the wrist
    /// and the glasses never disagree.
    ///
    /// - Parameters:
    ///   - elapsedSeconds: cumulative workout time.
    ///   - distanceMeters: cumulative HK distance.
    ///   - heartRate: latest HK heart-rate reading in BPM (`nil` before
    ///     the first sample lands).
    ///   - unitSystem: measurement system for distance + pace. Defaults to
    ///     `.imperial` so legacy call sites (and the summary screen before
    ///     the user picks a system) keep their miles/`/mi` rendering.
    public static func payload(
        elapsedSeconds: TimeInterval,
        distanceMeters: Double,
        heartRate: Double? = nil,
        unitSystem: UnitSystem = .imperial
    ) -> Payload {
        Payload(
            time:      formatElapsed(elapsedSeconds),
            heartRate: formatHeartRate(heartRate),
            distance:  RunMetricFormatting.formatDistance(
                           meters: distanceMeters,
                           unitSystem: unitSystem
                       ),
            pace:      RunMetricFormatting.formatAveragePace(
                           elapsedSeconds: elapsedSeconds,
                           distanceMeters: distanceMeters,
                           unitSystem: unitSystem
                       )
        )
    }

    /// Format an HK heart-rate sample for the HUD as **just digits**.
    /// rc16 dropped the " bpm" suffix Joe's rc15 bench saw clipped on
    /// the panel's right edge ("1 or two pixels on the 'm' in 'BPM' are
    /// missing"); the line-1 heart icon now carries the "this number
    /// is BPM" semantic, freeing ~72 px of horizontal room.
    /// `nil` → `"--"` placeholder (pre-first-sample state).
    /// Values < 30 BPM are also treated as placeholder — sub-30 readings
    /// in a running workout indicate a sensor dropout, not a real low
    /// HR, and rendering "12" mid-run next to a heart icon would alarm
    /// the user. Cap not applied at the high end; if HK ever emits
    /// 220 BPM we want to see it.
    public static func formatHeartRate(_ beatsPerMinute: Double?) -> String {
        guard let bpm = beatsPerMinute, bpm.isFinite, bpm >= 30 else {
            return "--"
        }
        return "\(Int(bpm.rounded()))"
    }

    /// Encode a `Payload` into an ActiveLook command sequence ready to ship
    /// over BLE. Order is significant: clear first so we paint over any
    /// prior frame, then 4 preloaded-icon `imgDisplay` blits + 4 `txt`
    /// draws interleaved so each line's icon and text land in the same
    /// holdFlush batch.
    ///
    /// **rc16** (Joe's bench on rc15, verbatim):
    ///   *"ok, the layout is almost there. The top line is just
    ///    slightly cutoff, 1 or two pixels on the 'm' in 'BPM' are
    ///    missing on the right side. After that there's a large gap
    ///    before the distance, then the pace is almost completely off
    ///    the screen, I can see just one pixel at the bottom of the
    ///    screen. Can we try to fix the layout and add the icons in
    ///    the next PR?"*
    ///
    /// Three layout corrections (all driven by the corrected font-3
    /// height of 64 px per the ActiveLook-Visual-Assets repo README,
    /// and the empirically-validated `y_fb = 255 − wearer_top` formula
    /// — see the `Layout` doc block):
    ///   1. New Y coords: liveLine1Y=240, liveDistanceY=170, livePaceY=77.
    ///   2. Drop " bpm" from the HR string; the heart icon now carries
    ///      the semantic.
    ///   3. Add 4 preloaded ALooK icons (chrono, heart, distance, pace)
    ///      via `imgDisplay` (cmdID 0x42), one per metric.
    ///
    /// Sequence (11 frames):
    ///   0. holdFlush(HOLD)
    ///   1. clear
    ///   2. imgDisplay(chrono)            — line 1 icon
    ///   3. txt(Time)                     — line 1 text (font 2)
    ///   4. imgDisplay(heart)             — line 1 right icon
    ///   5. txt(HR digits)                — line 1 right text (font 2)
    ///   6. imgDisplay(distance)          — line 2 icon
    ///   7. txt(Distance)                 — line 2 text (font 3)
    ///   8. imgDisplay(pace)              — line 3 icon
    ///   9. txt(Avg Pace)                 — line 3 text (font 3)
    ///  10. holdFlush(FLUSH)
    ///
    /// All 4 icons are preloaded into the stock ALooK configuration
    /// (cfgSet("ALooK") at connect time activates the namespace —
    /// rc8 PR #60). No upload pipeline needed for rc16; the
    /// cfgWrite/imgSave iceberg documented in
    /// `.squad/files/hud-icon-research.md` (rc15) applies only to
    /// custom artwork. Wrapped in holdFlush so the wearer sees one
    /// atomic frame transition instead of intermediate blank/torn
    /// states between the 9 inner writes.
    public static func frames(for payload: Payload) -> [[UInt8]] {
        [
            ActiveLookCommand.holdFlush(hold: true),
            ActiveLookCommand.clear(),
            // Line 1: chrono icon + Time text (font 2)
            ActiveLookCommand.imgDisplay(
                id: Layout.chronoIconID, x: Layout.chronoIconX, y: Layout.chronoIconY
            ),
            ActiveLookCommand.text(
                x: Layout.liveLeftMargin, y: Layout.liveLine1Y,
                rotation: Layout.rotation, fontSize: Layout.liveLine1Font, color: Layout.color,
                string: payload.time
            ),
            // Line 1 (right): heart icon + HR digits (font 2)
            ActiveLookCommand.imgDisplay(
                id: Layout.heartIconID, x: Layout.heartIconX, y: Layout.heartIconY
            ),
            ActiveLookCommand.text(
                x: Layout.liveHRX, y: Layout.liveLine1Y,
                rotation: Layout.rotation, fontSize: Layout.liveLine1Font, color: Layout.color,
                string: payload.heartRate
            ),
            // Line 2: distance icon + Distance text (font 3)
            ActiveLookCommand.imgDisplay(
                id: Layout.distanceIconID, x: Layout.distanceIconX, y: Layout.distanceIconY
            ),
            ActiveLookCommand.text(
                x: Layout.liveLeftMargin, y: Layout.liveDistanceY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.distance
            ),
            // Line 3: pace icon + Avg Pace text (font 3)
            ActiveLookCommand.imgDisplay(
                id: Layout.paceIconID, x: Layout.paceIconX, y: Layout.paceIconY
            ),
            ActiveLookCommand.text(
                x: Layout.liveLeftMargin, y: Layout.livePaceY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.pace
            ),
            ActiveLookCommand.holdFlush(hold: false)
        ]
    }

    /// First frame batch after a fresh BLE link comes up.
    ///
    /// **Why this exists (rc4 regression).** Engo 2 ships with a firmware
    /// splash ("Connection Successful") that's visible immediately after
    /// connect, but the *display* is in a low-power state — subsequent
    /// `txt` draws are no-ops until we explicitly send `power(on:true)`
    /// (cmdID 0x00). PR #49 began clearing the splash without first
    /// powering the display on, which is why Joe's rc4 bench test saw a
    /// blank screen on connect AND no HUD during the run.
    ///
    /// **Why cfgSet leads (rc8 fix).** Fonts 1–5 live in the "ALooK"
    /// configuration stored in the glasses' flash, NOT baked into base
    /// firmware. Per the ActiveLook-Visual-Assets repo README, every
    /// display command that references stock fonts/layouts/images must be
    /// preceded by `cfgSet("ALooK")` to activate that configuration's
    /// asset namespace. Without it, our `txt(font:3)` calls were silently
    /// dropped — the rc4–rc7 "blank screen" bug. cfgSet is idempotent
    /// per-connect, so calling it once at the top of this sequence is
    /// sufficient for the whole connection lifetime.
    ///
    /// The sequence below: select ALooK config → power on → clear →
    /// render a "Ready" line so the wearer immediately sees that the
    /// pairing succeeded. Same `txt` primitive as the running HUD, so no
    /// extra encoder surface.
    public static func connectFrames(banner: String = "AR-Runner") -> [[UInt8]] {
        [
            ActiveLookCommand.cfgSet(name: "ALooK"),
            ActiveLookCommand.power(on: true),
            ActiveLookCommand.clear(),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.bannerLine1Y,
                rotation: Layout.rotation, fontSize: Layout.bannerFontSize, color: Layout.color,
                string: banner
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.bannerLine2Y,
                rotation: Layout.rotation, fontSize: Layout.bannerFontSize, color: Layout.color,
                string: "Start a run"
            )
        ]
    }

    /// Same as `frames(for:)` but prepended with `cfgSet("ALooK")` and
    /// `power(on:true)`. Used for the first HUD push of a connection
    /// (workout start, or first per-tick frame after a (re)connect) as a
    /// belt-and-braces guarantee that the display is powered on AND the
    /// ALooK font configuration is active. Subsequent ticks reuse plain
    /// `frames(for:)` to keep the BLE write volume minimal.
    ///
    /// cfgSet is mirrored here (in addition to `connectFrames()`) because
    /// `WorkoutViewModel.pushHUDFrameIfConnected` falls back to this path
    /// whenever `needsHUDPowerOn == true` — including the case where the
    /// dedicated connect-screen push raced or got skipped and cfgSet was
    /// never sent. cfgSet is idempotent per-connect, so a duplicate is
    /// harmless; a missing one leaves the screen blank.
    public static func framesWithPowerOn(for payload: Payload) -> [[UInt8]] {
        [
            ActiveLookCommand.cfgSet(name: "ALooK"),
            ActiveLookCommand.power(on: true)
        ] + frames(for: payload)
    }

    /// Same as `summaryFrames(for:)` but prepended with `power(on:true)`
    /// so the end-of-workout splash renders even if the display happened
    /// to power down between the last tick and the save tap.
    public static func summaryFramesWithPowerOn(for payload: Payload) -> [[UInt8]] {
        [ActiveLookCommand.power(on: true)] + summaryFrames(for: payload)
    }

    /// Convenience for the end-of-workout finish screen — **rc2 (3-line
    /// 4-data layout)**:
    ///
    /// ```
    /// Line 1: "Finished!"
    /// Line 2: <distance>                e.g. "3.11 mi"
    /// Line 3: <time>      <avg pace>    e.g. "27:43    8:56/mi"
    /// ```
    ///
    /// Pace on line 3 is **right-justified**: ALooK's `txt` (0x37) under
    /// rotation=4 anchors text in wearer space at the LEFT edge and grows
    /// RIGHT, so a right-justified column needs the x anchor computed from
    /// the measured string width
    /// (`ALookFontMetrics.width(of:fontSize:)`). The framebuffer x for
    /// pace is therefore `303 − (finishLine3PaceWearerRight − width)`.
    ///
    /// **rc14 "Time + Distance only" rule superseded.** rc14→rc17 enforced
    /// a two-field finish screen at the encoder level. Joe's rc2 directive
    /// reshapes it to four data items (banner, distance, time, pace) on
    /// three visual lines. The supersession is documented in
    /// `.squad/decisions/inbox/laughlin-rc2-bench-feedback.md`; the live
    /// HUD's 4-fields/3-lines shape (rc16) is unchanged.
    public static func summaryFrames(for payload: Payload) -> [[UInt8]] {
        [
            ActiveLookCommand.clear(),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.finishLine1Y,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: "Finished!"
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.finishLine2Y,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.distance
            ),
            // Line 3 left: time, anchored to the same left margin as the
            // other lines so the wearer-left edges visually align. Font 2
            // (shared two-metric line — see `Layout.finishLine3Font`).
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.finishLine3Y,
                rotation: Layout.rotation, fontSize: Layout.finishLine3Font, color: Layout.color,
                string: payload.time
            ),
            // Line 3 right: avg pace, right-justified against
            // `finishLine3PaceWearerRight` (wearer-x 284 ≈ symmetric to
            // the wearer-left margin of 19). Width-based anchor — see
            // `summaryPaceXFB(for:)`.
            ActiveLookCommand.text(
                x: summaryPaceXFB(for: payload.pace),
                y: Layout.finishLine3Y,
                rotation: Layout.rotation, fontSize: Layout.finishLine3Font, color: Layout.color,
                string: payload.pace
            )
        ]
    }

    /// rc2 — compute the framebuffer x anchor for a right-justified pace
    /// string on finish line 3. The string's right edge in wearer space
    /// must equal `Layout.finishLine3PaceWearerRight`; we subtract the
    /// measured width to get the wearer-left, then map to framebuffer
    /// via the lens-flip identity `x_fb = 303 − wearer_left`.
    ///
    /// Width comes from `ALookFontMetrics` — a small font-metric table
    /// extracted (per Richards's rc13 nudge) so widths/heights live in
    /// one place instead of being scattered as inline magic numbers.
    public static func summaryPaceXFB(for paceString: String) -> Int16 {
        let width = ALookFontMetrics.width(of: paceString, fontSize: Layout.finishLine3Font)
        let wearerLeft = max(0, Int(Layout.finishLine3PaceWearerRight) - width)
        return Int16(clamping: 303 - wearerLeft)
    }

    // MARK: - Elapsed formatter

    /// `MM:SS` under an hour, `H:MM:SS` otherwise. Kept here (not in
    /// `RunMetricFormatting`) because the in-run watch display surfaces
    /// elapsed time via SwiftUI's `Text(_:elapsedSince:)` — there was no
    /// pure-Foundation formatter to reuse for the HUD payload.
    public static func formatElapsed(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Per-type, unit-aware live HUD (v0.6.0)

    /// A preloaded ALooK icon and its pixel footprint. The stock ALooK
    /// configuration ships these images addressable by `imgDisplay`; the
    /// width/height let the renderer centre an icon of any size on its slot
    /// line via the lens-flip formula.
    public struct HUDIcon: Sendable, Equatable {
        public let id: UInt8
        public let width: UInt16
        public let height: UInt16

        public init(id: UInt8, width: UInt16, height: UInt16) {
            self.id = id
            self.width = width
            self.height = height
        }
    }

    /// The preloaded icon for a metric, or `nil` for metrics that ship no
    /// stock ALooK glyph (`.speed`, `.cadence`, `.energy`, `.elevation`).
    /// Those render text-only — acceptable for v0.6.x per the custom-layout
    /// feasibility decision; the unit suffix in the value string carries the
    /// semantic (e.g. "27.4 km/h", "350 kcal").
    public static func icon(for metric: MetricKind) -> HUDIcon? {
        switch metric {
        case .duration:  return HUDIcon(id: Layout.chronoIconID,   width: 40, height: 40)
        case .heartRate: return HUDIcon(id: Layout.heartIconID,    width: 28, height: 28)
        case .distance:  return HUDIcon(id: Layout.distanceIconID, width: 28, height: 28)
        case .pace:      return HUDIcon(id: Layout.paceIconID,     width: 28, height: 28)
        case .speed, .cadence, .energy, .elevation, .heading:
            return nil
        }
    }

    /// Raw live-workout numbers the HUD formats. Captured as a struct so the
    /// per-type renderer and the push-policy change-detection share one
    /// value, and so future metrics extend the type without re-shaping call
    /// sites. All fields are optional except elapsed time — a missing value
    /// renders the metric's `--` placeholder.
    public struct HUDMetricSnapshot: Sendable, Equatable {
        public let elapsedSeconds: TimeInterval
        public let distanceMeters: Double?
        public let heartRate: Double?
        public let speedMetersPerSecond: Double?
        public let cadence: Double?
        public let activeKilocalories: Double?
        public let elevationMeters: Double?
        /// Compass heading in degrees 0–359 (magnetometer). `nil` renders the
        /// `--` placeholder.
        public let headingDegrees: Double?

        public init(
            elapsedSeconds: TimeInterval,
            distanceMeters: Double? = nil,
            heartRate: Double? = nil,
            speedMetersPerSecond: Double? = nil,
            cadence: Double? = nil,
            activeKilocalories: Double? = nil,
            elevationMeters: Double? = nil,
            headingDegrees: Double? = nil
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.distanceMeters = distanceMeters
            self.heartRate = heartRate
            self.speedMetersPerSecond = speedMetersPerSecond
            self.cadence = cadence
            self.activeKilocalories = activeKilocalories
            self.elevationMeters = elevationMeters
            self.headingDegrees = headingDegrees
        }
    }

    /// Format every `MetricKind` the HUD can render into a glanceable string,
    /// unit-aware and sport-aware so the glasses match the watch UI exactly
    /// (`RunMetricFormatting` is the shared source of truth). Cadence is
    /// RPM for cycling, steps/min otherwise; missing values become `--`.
    public static func metricStrings(
        snapshot: HUDMetricSnapshot,
        activity: ActivityKind,
        unitSystem: UnitSystem
    ) -> [MetricKind: String] {
        [
            .duration: formatElapsed(snapshot.elapsedSeconds),
            .heartRate: formatHeartRate(snapshot.heartRate),
            .distance: RunMetricFormatting.formatDistance(
                meters: snapshot.distanceMeters ?? .nan,
                unitSystem: unitSystem
            ),
            .pace: RunMetricFormatting.formatAveragePace(
                elapsedSeconds: snapshot.elapsedSeconds,
                distanceMeters: snapshot.distanceMeters ?? 0,
                unitSystem: unitSystem
            ),
            .speed: RunMetricFormatting.formatSpeed(
                metersPerSecond: snapshot.speedMetersPerSecond ?? .nan,
                unitSystem: unitSystem
            ),
            .cadence: formatCadence(snapshot.cadence, activity: activity),
            .energy: snapshot.activeKilocalories.map { String(format: "%.0f kcal", $0) } ?? "--",
            .elevation: snapshot.elevationMeters.map {
                RunMetricFormatting.formatElevation(meters: $0, unitSystem: unitSystem)
            } ?? "--",
            .heading: snapshot.headingDegrees.map {
                RunMetricFormatting.formatHeading(degrees: $0)
            } ?? "--",
        ]
    }

    /// Cadence string. Cycling cadence is crank RPM; run/walk cadence is
    /// steps per minute. `nil` → `--` placeholder (no sensor / pre-sample).
    public static func formatCadence(_ value: Double?, activity: ActivityKind) -> String {
        guard let value, value.isFinite, value >= 0 else { return "--" }
        let suffix = activity == .cycling ? "rpm" : "spm"
        return String(format: "%.0f \(suffix)", value)
    }

    /// The ordered list of value strings the per-type renderer will paint,
    /// in slot order, skipping empty (`nil`) layout slots. Feed this to
    /// `RunningHUDPushPolicy.shouldSend(_:now:)` so change-detection tracks
    /// exactly what's on the panel.
    public static func orderedSlotStrings(
        metricStrings: [MetricKind: String],
        layout: HUDLayout,
        grid: HUDGridDefinition
    ) -> [String] {
        var out: [String] = []
        let count = min(grid.slots.count, layout.slots.count)
        for index in 0..<count where layout.slots[index] != nil {
            let metric = layout.slots[index]!
            out.append(metricStrings[metric] ?? "--")
        }
        return out
    }

    /// Render a per-workout-type live HUD frame batch from a layout's
    /// slot→metric assignment and a fixed-slot grid geometry.
    ///
    /// Each non-empty layout slot paints (optional preloaded icon +) its
    /// metric value at the matching grid slot's anchor/font. Slots whose
    /// metric has no value render the `--` placeholder; empty (`nil`) layout
    /// slots paint nothing. The whole batch is wrapped in `holdFlush` so the
    /// wearer sees one atomic transition. Backward compatible — the existing
    /// `frames(for: Payload)` (fixed running layout) is unchanged.
    public static func frames(
        metricStrings: [MetricKind: String],
        layout: HUDLayout,
        grid: HUDGridDefinition
    ) -> [[UInt8]] {
        var commands: [[UInt8]] = [
            ActiveLookCommand.holdFlush(hold: true),
            ActiveLookCommand.clear(),
        ]
        let count = min(grid.slots.count, layout.slots.count)
        for index in 0..<count {
            guard let metric = layout.slots[index] else { continue }
            let slot = grid.slots[index]
            let value = metricStrings[metric] ?? "--"
            if let icon = icon(for: metric) {
                let position = iconFramebuffer(slot: slot, icon: icon)
                commands.append(
                    ActiveLookCommand.imgDisplay(id: icon.id, x: position.x, y: position.y)
                )
            }
            commands.append(
                ActiveLookCommand.text(
                    x: slot.textX, y: slot.textY,
                    rotation: Layout.rotation, fontSize: slot.font, color: Layout.color,
                    string: value
                )
            )
        }
        commands.append(ActiveLookCommand.holdFlush(hold: false))
        return commands
    }

    /// Per-type live HUD prefixed with `cfgSet("ALooK")` + `power(on:true)`
    /// — the first frame of a (re)connection. Mirrors the legacy
    /// `framesWithPowerOn(for:)` belt-and-braces guarantee.
    public static func framesWithPowerOn(
        metricStrings: [MetricKind: String],
        layout: HUDLayout,
        grid: HUDGridDefinition
    ) -> [[UInt8]] {
        [
            ActiveLookCommand.cfgSet(name: "ALooK"),
            ActiveLookCommand.power(on: true),
        ] + frames(metricStrings: metricStrings, layout: layout, grid: grid)
    }

    /// Framebuffer top-left for a slot's icon, centred vertically on the
    /// slot line via the rc16 lens-flip identities:
    ///   `x_fb = 303 − wearerLeft − width`
    ///   `y_fb = 255 − (centerY − height/2) − height`
    static func iconFramebuffer(slot: HUDGridDefinition.Slot, icon: HUDIcon) -> (x: UInt16, y: UInt16) {
        let wearerTop = Int(slot.iconWearerCenterY) - Int(icon.height) / 2
        let xFB = 303 - Int(slot.iconWearerLeft) - Int(icon.width)
        let yFB = 255 - wearerTop - Int(icon.height)
        return (UInt16(clamping: xFB), UInt16(clamping: yFB))
    }
}

/// Push-rate gate for the running HUD.
///
/// HKWorkoutBuilder.statistics can fire faster than 1Hz, and the elapsed
/// ticker fires at exactly 1Hz; without a gate we'd flood the BLE link.
/// Two backstops:
///   * **Minimum interval** — at most one frame per `minimumInterval` (1s
///     by default; matches `HUDFieldThrottle.defaultMinimumInterval`).
///   * **Change detection** — within the window we still skip identical
///     payloads. While distance < 0.01 mi the pace text is stuck at
///     `--:--/mi` and elapsed only ticks once a second, so repeated calls
///     with the same payload collapse to zero BLE traffic.
///
/// Pure value type; caller owns serialisation.
public struct RunningHUDPushPolicy: Sendable, Equatable {
    public static let defaultMinimumInterval: TimeInterval = 1.0

    public let minimumInterval: TimeInterval
    private var lastSentAt: Date?
    private var lastSignature: [String]?

    public init(minimumInterval: TimeInterval = RunningHUDPushPolicy.defaultMinimumInterval) {
        precondition(minimumInterval >= 0, "minimumInterval must be non-negative")
        self.minimumInterval = minimumInterval
    }

    /// Returns `true` if the caller should send `payload` now. Records the
    /// timestamp + payload so subsequent calls inside the window with the
    /// same payload are dropped. A *different* payload inside the window
    /// still passes — pace flipping from `--:--/mi` to `8:30/mi` should
    /// reach the glasses immediately, not wait out the gate.
    public mutating func shouldSend(_ payload: RunningHUDFrame.Payload, now: Date) -> Bool {
        shouldSend([payload.time, payload.heartRate, payload.distance, payload.pace], now: now)
    }

    /// Generalized change-detection for the per-type live HUD: gate on the
    /// ordered slot value strings (see
    /// `RunningHUDFrame.orderedSlotStrings(...)`). Same 1 Hz minimum +
    /// identical-frame suppression as the `Payload` overload, so a layout
    /// whose visible values haven't changed collapses to zero BLE traffic.
    public mutating func shouldSend(_ signature: [String], now: Date) -> Bool {
        if let last = lastSentAt,
           now.timeIntervalSince(last) < minimumInterval,
           lastSignature == signature {
            return false
        }
        lastSentAt = now
        lastSignature = signature
        return true
    }

    /// Drop all state. Call on (re)connect so the first frame after the
    /// link comes up is delivered immediately even if the payload happens
    /// to match the pre-disconnect one.
    public mutating func reset() {
        lastSentAt = nil
        lastSignature = nil
    }
}
