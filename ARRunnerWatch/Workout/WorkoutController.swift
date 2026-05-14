import ARRunnerCore
import Foundation
import HealthKit

protocol WorkoutControlling: Sendable {
    func startWorkout(sport: SportType) async throws -> WorkoutSession
    func pauseWorkout() async throws
    func resumeWorkout() async throws
    func endWorkout() async throws -> WorkoutSession?
}

enum WorkoutControllerError: Error {
    case sessionNotStarted
}

actor WorkoutController: WorkoutControlling {
    private let healthStore = HKHealthStore()
    private var hkWorkoutSession: HKWorkoutSession?
    private var liveWorkoutBuilder: HKLiveWorkoutBuilder?
    private var currentSession: WorkoutSession?

    func startWorkout(sport: SportType) async throws -> WorkoutSession {
        let session = WorkoutSession(
            sport: sport,
            startedAt: Date(),
            status: .prepared,
            metricStream: []
        )

        currentSession = session

        // TODO: Create HKWorkoutConfiguration, HKWorkoutSession, and HKLiveWorkoutBuilder.
        _ = healthStore
        _ = hkWorkoutSession
        _ = liveWorkoutBuilder

        return session
    }

    func pauseWorkout() async throws {
        guard let currentSession else {
            throw WorkoutControllerError.sessionNotStarted
        }

        self.currentSession = WorkoutSession(
            id: currentSession.id,
            sport: currentSession.sport,
            startedAt: currentSession.startedAt,
            status: .paused,
            metricStream: currentSession.metricStream
        )

        // TODO: Forward pause to HKWorkoutSession.
    }

    func resumeWorkout() async throws {
        guard let currentSession else {
            throw WorkoutControllerError.sessionNotStarted
        }

        self.currentSession = WorkoutSession(
            id: currentSession.id,
            sport: currentSession.sport,
            startedAt: currentSession.startedAt,
            status: .running,
            metricStream: currentSession.metricStream
        )

        // TODO: Forward resume to HKWorkoutSession.
    }

    func endWorkout() async throws -> WorkoutSession? {
        guard let currentSession else {
            throw WorkoutControllerError.sessionNotStarted
        }

        let endedSession = WorkoutSession(
            id: currentSession.id,
            sport: currentSession.sport,
            startedAt: currentSession.startedAt,
            status: .ended,
            metricStream: currentSession.metricStream
        )

        self.currentSession = endedSession

        // TODO: End HealthKit collection and persist the workout.
        return endedSession
    }
}
