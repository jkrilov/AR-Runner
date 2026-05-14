import AppIntents

struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start AR Run"
    static let description = IntentDescription("Foregrounds AR-Runner so the watch workout flow can take over.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        // TODO: Route into the running workout flow on watchOS and iOS.
        return .result()
    }
}
