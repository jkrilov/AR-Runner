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

        /// Framebuffer y-anchors for the SUMMARY (finish) screen.
        ///
        /// topLR places its anchor at the TOP of the block and grows
        /// downward in framebuffer space. The Engo 2 lens flips
        /// `y_wearer = 255 − y_fb`, so for a target wearer-visible top T
        /// with font 3 (49 px tall): `y_fb = 255 − T − 49 = 206 − T`.
        /// T = 40 → 166 (top); T = 120 → 86 (middle); T = 200 → 6 (bottom).
        /// rc11 used the wearer-space values directly without the
        /// lens-flip transform. These three slots host the 3-line finish
        /// screen (title / time / distance — rc14 dropped pace from the
        /// finish card per Joe's "final stats = Time + Distance only"
        /// directive).
        public static let timeY:     Int16 = 166
        public static let distanceY: Int16 = 86
        public static let paceY:     Int16 = 6

        // MARK: - Live HUD (4-field, rc14)
        //
        // rc14 bench feedback (Joe): "During the run we should see Time,
        // HR, Distance, Avg Pace." Live HUD jumped from 3 fields to 4.
        // HR is pulled forward from the v0.4.0-rc1 scope into v0.3.0
        // polish — the HealthKit substrate already emits `.heartRate`
        // metrics (`HealthKitWorkoutSubstrate.metric(for:)`) and the
        // WorkoutViewModel already captures them via `apply(metric:)`;
        // the only missing wiring was the HUD payload extension below.
        //
        // Layout choice: 4 vertical lines at font 3 (Option A from the
        // rc14 task brief). Font 3 stays because per-tick strings stay
        // short ("12:34", "165 bpm", "2.34 mi", "8:30/mi" — all ≤ 7
        // chars, well under the ~14-char clipping limit at leftMargin =
        // 284). Vertical spacing tightens from 80 px wearer-space
        // (3-field) to 55 px wearer-space (4-field) so all four lines
        // fit inside the 256 px panel:
        //   y_fb = 206 − T
        //     T =  20 (top: time)     → 186
        //     T =  75 (next: HR)      → 131
        //     T = 130 (next: distance)→  76
        //     T = 185 (bottom: pace)  →  21
        // 49 px glyph + 6 px gap between rows. Tested-tight but legible
        // outdoors. Option B (right-justified secondary metric in 2
        // rows) was rejected because pixel-width-aware right-alignment
        // under topLR's right-anchored coords requires per-string
        // measurement against an unknown stock-font advance table; we
        // already lost rc11+rc12 cycles to coordinate-math drift and
        // the rc14 task brief explicitly authorized "whichever is
        // cleanest."
        public static let liveTimeY:     Int16 = 186
        public static let liveHRY:       Int16 = 131
        public static let liveDistanceY: Int16 = 76
        public static let livePaceY:     Int16 = 21

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

        public init(time: String, heartRate: String = "-- bpm", distance: String, pace: String) {
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
    public static func payload(
        elapsedSeconds: TimeInterval,
        distanceMeters: Double,
        heartRate: Double? = nil
    ) -> Payload {
        Payload(
            time:      formatElapsed(elapsedSeconds),
            heartRate: formatHeartRate(heartRate),
            distance:  RunMetricFormatting.formatMiles(meters: distanceMeters),
            pace:      RunMetricFormatting.formatAveragePacePerMile(
                           elapsedSeconds: elapsedSeconds,
                           distanceMeters: distanceMeters
                       )
        )
    }

    /// Format an HK heart-rate sample for the HUD. Mirrors the on-wrist
    /// display string (`WorkoutView.swift:169 → "\(Int($0)) bpm"`) so
    /// the lens and the wrist never show different numbers.
    /// `nil` → `"-- bpm"` placeholder (pre-first-sample state).
    /// Values < 30 BPM are also treated as placeholder — sub-30 readings
    /// in a running workout indicate a sensor dropout, not a real low
    /// HR, and rendering "12 bpm" mid-run would alarm the user. Cap not
    /// applied at the high end; if HK ever emits 220 BPM we want to see
    /// it.
    public static func formatHeartRate(_ beatsPerMinute: Double?) -> String {
        guard let bpm = beatsPerMinute, bpm.isFinite, bpm >= 30 else {
            return "-- bpm"
        }
        return "\(Int(bpm.rounded())) bpm"
    }

    /// Encode a `Payload` into an ActiveLook command sequence ready to ship
    /// over BLE. Order is significant: clear first so we paint over the
    /// "Connection Successful" splash (and any prior frame), then four
    /// `txt` draws top-to-bottom (rc14 added HR between time and distance).
    ///
    /// Wrapped in `holdFlush(hold:true)` … `holdFlush(hold:false)` so the
    /// `clear` + 4×`txt` sequence commits atomically to the display.
    /// Without the wrap, each BLE write paints to the framebuffer
    /// immediately and the wearer sees a brief blank between `clear` and
    /// the first `txt`, plus tearing between `txt` writes — the
    /// "flashes every second" artifact Joe reported on rc8. Per
    /// ActiveLook spec §4.6 and `hud-api-spec-report.md` §"Fix 3".
    /// `connectFrames()` deliberately does NOT use holdFlush — the connect
    /// banner is a one-shot draw where the user only sees the final state.
    public static func frames(for payload: Payload) -> [[UInt8]] {
        [
            ActiveLookCommand.holdFlush(hold: true),
            ActiveLookCommand.clear(),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.liveTimeY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.time
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.liveHRY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.heartRate
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.liveDistanceY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.distance
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.livePaceY,
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

    /// Convenience for the end-of-workout finish screen: a "Workout
    /// Complete" banner above the two final stats — **Time and
    /// Distance only** (no pace, no HR). rc14 dropped pace from the
    /// summary per Joe's bench directive: "Those [time + distance] are
    /// supposed to be the final stats. During the run we should see
    /// Time, HR, Distance, Avg Pace." Live = 4 fields, finish = 2
    /// fields. Same `txt` primitive as the run HUD, no new protocol
    /// surface.
    public static func summaryFrames(for payload: Payload) -> [[UInt8]] {
        [
            ActiveLookCommand.clear(),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.timeY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: "Workout Complete"
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.distanceY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.time
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.paceY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.distance
            )
        ]
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
    private var lastPayload: RunningHUDFrame.Payload?

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
        if let last = lastSentAt,
           now.timeIntervalSince(last) < minimumInterval,
           lastPayload == payload {
            return false
        }
        lastSentAt = now
        lastPayload = payload
        return true
    }

    /// Drop all state. Call on (re)connect so the first frame after the
    /// link comes up is delivered immediately even if the payload happens
    /// to match the pre-disconnect one.
    public mutating func reset() {
        lastSentAt = nil
        lastPayload = nil
    }
}
