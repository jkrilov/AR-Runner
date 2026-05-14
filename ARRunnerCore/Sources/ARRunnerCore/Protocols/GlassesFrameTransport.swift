import Foundation

public protocol GlassesFrameTransport: Sendable {
    func connect() async throws
    func disconnect() async throws
    func pushLayout(_ layout: HUDLayout) async throws
    func updateMetric(_ kind: MetricKind, value: Double) async throws
}
