// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation

public protocol GlassesFrameTransport: Sendable {
    func connect() async throws
    func disconnect() async throws
    func pushLayout(_ layout: HUDLayout) async throws
    func updateMetric(_ kind: MetricKind, value: Double) async throws
}
