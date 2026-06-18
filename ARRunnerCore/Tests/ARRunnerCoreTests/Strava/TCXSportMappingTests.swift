// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Locks the v0.6.0 activity → TCX/Strava sport-string mapping. Previously the
/// TCX sport was hardcoded "Running"; cycling and walking now map correctly.
final class TCXSportMappingTests: XCTestCase {

    func testTCXSportStringPerActivity() {
        XCTAssertEqual(TCXWorkoutData.tcxSport(for: .running), "Running")
        XCTAssertEqual(TCXWorkoutData.tcxSport(for: .cycling), "Biking")
        XCTAssertEqual(TCXWorkoutData.tcxSport(for: .walking), "Other")
    }

    func testTCXSportStringIgnoresEnvironment() {
        XCTAssertEqual(TCXWorkoutData.tcxSport(for: .indoorBike), "Biking")
        XCTAssertEqual(TCXWorkoutData.tcxSport(for: .outdoorBike), "Biking")
        XCTAssertEqual(TCXWorkoutData.tcxSport(for: .indoorRun), "Running")
    }

    func testActivityNounMapping() {
        XCTAssertEqual(ActivityNaming.activityNoun(for: .running), "Run")
        XCTAssertEqual(ActivityNaming.activityNoun(for: .cycling), "Ride")
        XCTAssertEqual(ActivityNaming.activityNoun(for: .walking), "Walk")
    }
}
