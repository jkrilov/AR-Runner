import ARRunnerCore
import Foundation

actor GlassesService {
    private let transport: any GlassesFrameTransport
    private(set) var isConnected = false

    init(transport: any GlassesFrameTransport) {
        self.transport = transport
    }

    func connect() async throws {
        try await transport.connect()
        isConnected = true
    }

    func disconnect() async throws {
        try await transport.disconnect()
        isConnected = false
    }

    func push(layout: HUDLayout) async throws {
        try await transport.pushLayout(layout)
    }

    func update(metric: WorkoutMetric) async throws {
        try await transport.updateMetric(metric.kind, value: metric.value)
    }
}
