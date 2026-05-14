import SwiftUI

@main
@MainActor
struct ARRunnerWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WorkoutView()
            }
        }
    }
}
