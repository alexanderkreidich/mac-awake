import XCTest
@testable import MacAwakeCore

final class RemainingTimeFormatterTests: XCTestCase {
    func testInactiveMenuBarLabelIsAwake() {
        XCTAssertEqual(RemainingTimeFormatter.menuBarLabel(for: .inactive), "Awake")
    }

    func testActiveMenuBarLabelRoundsUpRemainingMinutes() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .thirtyMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 + 12)
        )

        XCTAssertEqual(RemainingTimeFormatter.menuBarLabel(for: snapshot, now: now), "25m")
    }

    func testDropdownRemainingTextUsesMinutesAndTwoDigitSeconds() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .thirtyMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 + 12)
        )

        XCTAssertEqual(RemainingTimeFormatter.dropdownRemainingText(for: snapshot, now: now), "24:12 left")
    }

    func testRemainingTimeClampsAtZeroAfterExpiry() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .fiveMinutes,
            startedAt: now.addingTimeInterval(-300),
            expiresAt: now.addingTimeInterval(-1)
        )

        XCTAssertEqual(RemainingTimeFormatter.menuBarLabel(for: snapshot, now: now), "0m")
        XCTAssertEqual(RemainingTimeFormatter.dropdownRemainingText(for: snapshot, now: now), "0:00 left")
    }
}
