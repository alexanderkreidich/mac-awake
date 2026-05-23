import XCTest
@testable import MacAwakeCore

final class MacAwakeHelperTests: XCTestCase {
    func testHelperTargetCanAccessSharedDurations() {
        XCTAssertEqual(AwakeDuration.sixtyMinutes.seconds, 3_600)
    }
}
