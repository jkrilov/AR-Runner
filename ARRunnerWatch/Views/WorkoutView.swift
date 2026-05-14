import SwiftUI

@MainActor
struct WorkoutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AR-Runner")
                .font(.headline)
            Text("Workout UI scaffold")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            Label("Start, pause, and finish flow pending", systemImage: "figure.run")
            Label("HUD reconnect indicators pending", systemImage: "eyeglasses")
            Label("HealthKit live metrics pending", systemImage: "heart.text.square")
        }
        .padding()
        .navigationTitle("Run")
    }
}

#Preview {
    WorkoutView()
}
