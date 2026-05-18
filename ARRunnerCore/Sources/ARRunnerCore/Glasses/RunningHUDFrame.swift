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

        /// Left margin shared by all three lines.
        public static let leftMargin: Int16 = 20

        /// Baseline y-coordinates (top = elapsed time, middle = distance,
        /// bottom = pace). Tuned so the largest stock font (fontSize 3,
        /// ~48px tall on Engo 2) clears the panel edges without crowding.
        public static let timeY:     Int16 = 40
        public static let distanceY: Int16 = 120
        public static let paceY:     Int16 = 200

        /// ActiveLook font index for the runner HUD. `3` is the largest stock
        /// font baked into Engo 2 firmware out of the box; readable at arm's
        /// length through the projection.
        public static let fontSize: UInt8 = 3

        /// `4` = bottom-RL — the orientation a wearer reads naturally when
        /// the glasses sit on their nose. Matches the iOS sample.
        public static let rotation: UInt8 = 4

        /// 15 = full white on the monochrome OLED. Anything dimmer hurts
        /// readability outdoors.
        public static let color: UInt8 = 15
    }

    // MARK: - Pre-formatted payload

    /// The strings the HUD renders, after formatting. Captured as a struct
    /// (not three loose params) so the change-detection check in
    /// `RunningHUDPushPolicy` is a single `==` and so future fields (HR,
    /// splits) can extend the type without re-shaping every call site.
    public struct Payload: Sendable, Equatable {
        public let time: String
        public let distance: String
        public let pace: String

        public init(time: String, distance: String, pace: String) {
            self.time = time
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
    public static func payload(
        elapsedSeconds: TimeInterval,
        distanceMeters: Double
    ) -> Payload {
        Payload(
            time:     formatElapsed(elapsedSeconds),
            distance: RunMetricFormatting.formatMiles(meters: distanceMeters),
            pace:     RunMetricFormatting.formatAveragePacePerMile(
                          elapsedSeconds: elapsedSeconds,
                          distanceMeters: distanceMeters
                      )
        )
    }

    /// Encode a `Payload` into an ActiveLook command sequence ready to ship
    /// over BLE. Order is significant: clear first so we paint over the
    /// "Connection Successful" splash (and any prior frame), then three
    /// `txt` draws top-to-bottom.
    public static func frames(for payload: Payload) -> [[UInt8]] {
        [
            ActiveLookCommand.clear(),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.timeY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.time
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.distanceY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.distance
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.paceY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.pace
            )
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
    /// The sequence below: power on → clear → render a "Ready" line so
    /// the wearer immediately sees that the pairing succeeded. Same `txt`
    /// primitive as the running HUD, so no extra encoder surface.
    public static func connectFrames(banner: String = "AR-Runner Ready") -> [[UInt8]] {
        [
            ActiveLookCommand.power(on: true),
            ActiveLookCommand.clear(),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.timeY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: banner
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.distanceY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: "Start a run"
            )
        ]
    }

    /// Same as `frames(for:)` but prepended with `power(on:true)`. Used
    /// for the first HUD push of a connection (workout start, or first
    /// per-tick frame after a (re)connect) as a belt-and-braces guarantee
    /// that the display is powered on. Subsequent ticks reuse plain
    /// `frames(for:)` to keep the BLE write volume minimal.
    public static func framesWithPowerOn(for payload: Payload) -> [[UInt8]] {
        [ActiveLookCommand.power(on: true)] + frames(for: payload)
    }

    /// Same as `summaryFrames(for:)` but prepended with `power(on:true)`
    /// so the end-of-workout splash renders even if the display happened
    /// to power down between the last tick and the save tap.
    public static func summaryFramesWithPowerOn(for payload: Payload) -> [[UInt8]] {
        [ActiveLookCommand.power(on: true)] + summaryFrames(for: payload)
    }

    /// Convenience for the end-of-workout splash: a single centred-ish
    /// "Workout Complete" line with the final stats below. Same `txt`
    /// primitive so no extra protocol surface needed.
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
                string: payload.distance
            ),
            ActiveLookCommand.text(
                x: Layout.leftMargin, y: Layout.paceY,
                rotation: Layout.rotation, fontSize: Layout.fontSize, color: Layout.color,
                string: payload.pace
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
