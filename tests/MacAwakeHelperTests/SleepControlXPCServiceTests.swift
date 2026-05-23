import Foundation
import XCTest
import MacAwakeCore

private final class FakeSleepControlService: SleepControlService {
    var startResult: Result<TimerStatus, Error> = .success(.inactive)
    var cancelResult: Result<TimerStatus, Error> = .success(.inactive)
    var statusResult: Result<TimerStatus, Error> = .success(.inactive)
    private(set) var startedDuration: AwakeDuration?
    private(set) var didCancel = false
    private(set) var didRequestStatus = false

    func start(duration: AwakeDuration) throws -> TimerStatus {
        startedDuration = duration
        return try startResult.get()
    }

    func cancel() throws -> TimerStatus {
        didCancel = true
        return try cancelResult.get()
    }

    func status() throws -> TimerStatus {
        didRequestStatus = true
        return try statusResult.get()
    }
}

final class SleepControlXPCServiceTests: XCTestCase {
    func testStartValidatesDurationAndEncodesStatus() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .sixtyMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(3_600)
        )
        let service = FakeSleepControlService()
        service.startResult = .success(.active(snapshot))
        let xpcService = SleepControlXPCService(service: service)

        let response = waitForReply { reply in
            xpcService.start(durationSeconds: NSNumber(value: 3_600), withReply: reply)
        }

        XCTAssertEqual(service.startedDuration, .sixtyMinutes)
        XCTAssertNil(response.error)
        XCTAssertEqual(try TimerStatusPayload.status(from: XCTUnwrap(response.payload)), .active(snapshot))
    }

    func testUnsupportedDurationRepliesWithError() {
        let service = FakeSleepControlService()
        let xpcService = SleepControlXPCService(service: service)

        let response = waitForReply { reply in
            xpcService.start(durationSeconds: NSNumber(value: 42), withReply: reply)
        }

        XCTAssertNil(service.startedDuration)
        XCTAssertNil(response.payload)
        XCTAssertEqual(response.error?.localizedDescription, "Mac Awake only supports 5, 30, and 60 minute timers.")
    }

    func testCancelEncodesStatus() throws {
        let service = FakeSleepControlService()
        service.cancelResult = .success(.inactive)
        let xpcService = SleepControlXPCService(service: service)

        let response = waitForReply { reply in
            xpcService.cancel(withReply: reply)
        }

        XCTAssertTrue(service.didCancel)
        XCTAssertNil(response.error)
        XCTAssertEqual(try TimerStatusPayload.status(from: XCTUnwrap(response.payload)), .inactive)
    }

    func testStatusEncodesStatus() throws {
        let service = FakeSleepControlService()
        service.statusResult = .success(.inactive)
        let xpcService = SleepControlXPCService(service: service)

        let response = waitForReply { reply in
            xpcService.status(withReply: reply)
        }

        XCTAssertTrue(service.didRequestStatus)
        XCTAssertNil(response.error)
        XCTAssertEqual(try TimerStatusPayload.status(from: XCTUnwrap(response.payload)), .inactive)
    }

    private func waitForReply(
        operation: (@escaping (NSDictionary?, NSError?) -> Void) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (payload: NSDictionary?, error: NSError?) {
        let expectation = expectation(description: "XPC reply")
        var response: (payload: NSDictionary?, error: NSError?) = (nil, nil)

        operation { payload, error in
            response = (payload, error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        return response
    }
}
