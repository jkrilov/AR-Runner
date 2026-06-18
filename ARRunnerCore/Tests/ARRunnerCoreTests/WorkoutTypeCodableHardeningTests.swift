// SPDX-FileCopyrightText: 2026 Joe Krilov
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import ARRunnerCore

/// Hardening for the `WorkoutType` wire contract beyond the round-trips in
/// `WorkoutTypeTests`: encode *determinism* (Strava/idempotency-grade byte
/// stability), raw-value distinctness across the full 3×2 product, and the
/// non-throwing fallback for the awkward unknown inputs (empty string,
/// whitespace, wrong JSON type) a malformed peer can actually send.
final class WorkoutTypeCodableHardeningTests: XCTestCase {

    // MARK: - Determinism

    func testEncodeIsDeterministicAcrossRepeatedEncodes() throws {
        let encoder = JSONEncoder()
        for type in WorkoutType.allCases {
            let first = try encoder.encode(type)
            let second = try encoder.encode(type)
            XCTAssertEqual(first, second, "encode of \(type.rawValue) is not byte-stable")
        }
    }

    func testEncodeEmitsExactlyTheRawValueString() throws {
        for type in WorkoutType.allCases {
            let json = String(data: try JSONEncoder().encode(type), encoding: .utf8)
            XCTAssertEqual(json, "\"\(type.rawValue)\"")
        }
    }

    // MARK: - Distinctness

    func testAllRawValuesAreDistinct() {
        let raws = WorkoutType.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "raw values collide: \(raws)")
        XCTAssertEqual(raws.count, 6)
    }

    func testAllCasesCoversFullActivityEnvironmentProduct() {
        var seen = Set<String>()
        for activity in ActivityKind.allCases {
            for environment in WorkoutEnvironment.allCases {
                seen.insert(WorkoutType(activity: activity, environment: environment).rawValue)
            }
        }
        XCTAssertEqual(seen, Set(WorkoutType.allCases.map(\.rawValue)))
    }

    // MARK: - Awkward unknown inputs degrade, never throw

    func testEmptyStringDecodesToFallback() throws {
        let decoded = try JSONDecoder().decode(WorkoutType.self, from: Data("\"\"".utf8))
        XCTAssertEqual(decoded, .fallback)
    }

    func testWhitespaceAndCaseMismatchDecodeToFallback() throws {
        // Raw values are exact, lowercase tokens — anything else falls back.
        for raw in ["\" running \"", "\"Running\"", "\"RUNNING\"", "\"run\""] {
            let decoded = try JSONDecoder().decode(WorkoutType.self, from: Data(raw.utf8))
            XCTAssertEqual(decoded, .fallback, "\(raw) should fall back, not match")
        }
    }

    func testWrongJSONTypeStillThrows() {
        // A non-string (number) is a structural decode error, not an unknown
        // sport — that should still surface rather than silently fall back.
        XCTAssertThrowsError(try JSONDecoder().decode(WorkoutType.self, from: Data("42".utf8)))
    }

    // MARK: - RawRepresentable identity

    func testRawValueInitRoundTripsForEverySupportedCase() {
        for type in WorkoutType.allCases {
            XCTAssertEqual(WorkoutType(rawValue: type.rawValue), type)
        }
    }
}
