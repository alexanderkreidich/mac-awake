import XCTest
@testable import MacAwakeCore

final class AwakeDurationTests: XCTestCase {
    func testSupportedDurationsAreExactlyFiveThirtyAndSixtyMinutes() throws {
        XCTAssertEqual(AwakeDuration.allCases.map(\.seconds), [300, 1_800, 3_600])
        XCTAssertEqual(try AwakeDuration(seconds: 300), .fiveMinutes)
        XCTAssertEqual(try AwakeDuration(seconds: 1_800), .thirtyMinutes)
        XCTAssertEqual(try AwakeDuration(seconds: 3_600), .sixtyMinutes)
    }

    func testRejectsUnsupportedDurations() {
        XCTAssertThrowsError(try AwakeDuration(seconds: 299)) { error in
            XCTAssertEqual(error as? AwakeDurationValidationError, .unsupportedDuration(299))
        }

        XCTAssertThrowsError(try AwakeDuration(seconds: 3_601)) { error in
            XCTAssertEqual(error as? AwakeDurationValidationError, .unsupportedDuration(3_601))
        }
    }
}
