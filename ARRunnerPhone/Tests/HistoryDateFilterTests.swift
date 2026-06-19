// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import ARRunnerPhone

final class HistoryDateFilterTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var reference: Date {
        // 2026-06-19T12:00:00Z
        DateComponents(
            calendar: calendar, year: 2026, month: 6, day: 19, hour: 12
        ).date!
    }

    func test_default_isThirtyDays() {
        XCTAssertEqual(HistoryViewModel.DateRangeFilter.days30, HistoryViewModel().selectedRange)
    }

    func test_allCases_orderAndCoverage() {
        XCTAssertEqual(
            HistoryViewModel.DateRangeFilter.allCases,
            [.days30, .days60, .days90, .days365, .unlimited]
        )
    }

    func test_startDate_subtractsRawValueDays() {
        for range in [HistoryViewModel.DateRangeFilter.days30, .days60, .days90, .days365] {
            let start = range.startDate(from: reference, calendar: calendar)
            let expected = calendar.date(byAdding: .day, value: -range.rawValue, to: reference)
            XCTAssertEqual(start, expected, "range \(range.displayName)")
            XCTAssertLessThan(start!, reference)
        }
    }

    func test_startDate_unlimitedIsNil() {
        XCTAssertNil(HistoryViewModel.DateRangeFilter.unlimited.startDate(from: reference, calendar: calendar))
    }

    func test_displayNames() {
        XCTAssertEqual(HistoryViewModel.DateRangeFilter.days30.displayName, "Last 30 days")
        XCTAssertEqual(HistoryViewModel.DateRangeFilter.days365.displayName, "Last year")
        XCTAssertEqual(HistoryViewModel.DateRangeFilter.unlimited.displayName, "All time")
    }
}
