import Foundation

public struct ARWorkoutMetadata: Sendable, Codable, Equatable {
    public let layoutID: String
    public let bleDropCount: Int
    public let glassesBatteryAtEnd: Int?

    public init(layoutID: String, bleDropCount: Int, glassesBatteryAtEnd: Int?) {
        self.layoutID = layoutID
        self.bleDropCount = bleDropCount
        self.glassesBatteryAtEnd = glassesBatteryAtEnd
    }
}

public protocol ARMetadataStore: Sendable {
    func loadMetadata(for workoutID: UUID) async throws -> ARWorkoutMetadata?
    func saveMetadata(_ metadata: ARWorkoutMetadata, for workoutID: UUID) async throws
}

public enum ARMetadataStoreError: Error, Equatable {
    case appGroupContainerUnavailable
}

public actor JSONARMetadataStore: ARMetadataStore {
    private let baseDirectoryProvider: @Sendable () throws -> URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseDirectoryProvider: @escaping @Sendable () throws -> URL?) {
        self.baseDirectoryProvider = baseDirectoryProvider
    }

    public func loadMetadata(for workoutID: UUID) async throws -> ARWorkoutMetadata? {
        let fileURL = try metadataFileURL(for: workoutID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ARWorkoutMetadata.self, from: data)
    }

    public func saveMetadata(_ metadata: ARWorkoutMetadata, for workoutID: UUID) async throws {
        let fileURL = try metadataFileURL(for: workoutID)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try encoder.encode(metadata)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func metadataFileURL(for workoutID: UUID) throws -> URL {
        guard let baseDirectory = try baseDirectoryProvider() else {
            throw ARMetadataStoreError.appGroupContainerUnavailable
        }

        return baseDirectory
            .appendingPathComponent("ARMetadata", isDirectory: true)
            .appendingPathComponent("\(workoutID.uuidString).json", isDirectory: false)
    }
}
