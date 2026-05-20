// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

final class ActivityNamingTests: XCTestCase {

    /// Build a UTC date and force the calendar to UTC so tests are
    /// location-independent (Strava ingests the local-time wallclock, but
    /// tests must not depend on the machine timezone).
    private func date(hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var dc = DateComponents()
        dc.year = 2024; dc.month = 5; dc.day = 20
        dc.hour = hour; dc.minute = minute
        return cal.date(from: dc)!
    }

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    // MARK: - Boundary sweep

    func testMorningBoundaries() {
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 5),  calendar: utcCalendar), .morning)
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 8),  calendar: utcCalendar), .morning)
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 11, minute: 59), calendar: utcCalendar), .morning)
    }

    func testAfternoonBoundaries() {
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 12), calendar: utcCalendar), .afternoon)
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 15), calendar: utcCalendar), .afternoon)
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 16, minute: 59), calendar: utcCalendar), .afternoon)
    }

    func testEveningBoundaries() {
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 17), calendar: utcCalendar), .evening)
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 19), calendar: utcCalendar), .evening)
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 20, minute: 59), calendar: utcCalendar), .evening)
    }

    func testNightBoundaries() {
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 21), calendar: utcCalendar), .night)
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 23), calendar: utcCalendar), .night)
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 0),  calendar: utcCalendar), .night)
        XCTAssertEqual(ActivityNaming.timeOfDay(for: date(hour: 4, minute: 59),  calendar: utcCalendar), .night)
    }

    // MARK: - Name format

    func testNameFormatMatchesStravaConvention() {
        XCTAssertEqual(ActivityNaming.name(forStart: date(hour: 7),  calendar: utcCalendar), "Morning Run")
        XCTAssertEqual(ActivityNaming.name(forStart: date(hour: 13), calendar: utcCalendar), "Afternoon Run")
        XCTAssertEqual(ActivityNaming.name(forStart: date(hour: 18), calendar: utcCalendar), "Evening Run")
        XCTAssertEqual(ActivityNaming.name(forStart: date(hour: 22), calendar: utcCalendar), "Night Run")
    }

    func testCustomSportSuffix() {
        XCTAssertEqual(ActivityNaming.name(forStart: date(hour: 7),  sport: "Ride", calendar: utcCalendar), "Morning Ride")
    }
}
