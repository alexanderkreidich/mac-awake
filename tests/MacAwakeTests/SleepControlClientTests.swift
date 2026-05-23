import Foundation
import XCTest
import MacAwakeCore

private final class FakeHelperXPCProxy: NSObject, MacAwakeHelperXPCProtocol {
    var startResponse: (NSDictionary?, NSError?) = (nil, nil)
    var cancelResponse: (NSDictionary?, NSError?) = (nil, nil)
    var statusResponse: (NSDictionary?, NSError?) = (nil, nil)
    private(set) var startedDurationSeconds: Int?
    private(set) var didCancel = false
    private(set) var didRequestStatus = false

    func start(durationSeconds: NSNumber, withReply reply: @escaping (NSDictionary?, NSError?) -> Void) {
        startedDurationSeconds = durationSeconds.intValue
        reply(startResponse.0, startResponse.1)
    }

    func cancel(withReply reply: @escaping (NSDictionary?, NSError?) -> Void) {
        didCancel = true
        reply(cancelResponse.0, cancelResponse.1)
    }

    func status(withReply reply: @escaping (NSDictionary?, NSError?) -> Void) {
        didRequestStatus = true
        reply(statusResponse.0, statusResponse.1)
    }
}

private final class NonReplyingHelperXPCProxy: NSObject, MacAwakeHelperXPCProtocol {
    private(set) var didRequestStatus = false

    func start(durationSeconds: NSNumber, withReply reply: @escaping (NSDictionary?, NSError?) -> Void) {}

    func cancel(withReply reply: @escaping (NSDictionary?, NSError?) -> Void) {}

    func status(withReply reply: @escaping (NSDictionary?, NSError?) -> Void) {
        didRequestStatus = true
    }
}

final class SleepControlClientTests: XCTestCase {
    func testStartSendsSupportedDurationAndDecodesStatus() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .thirtyMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(1_800)
        )
        let proxy = FakeHelperXPCProxy()
        proxy.startResponse = (TimerStatusPayload.dictionary(from: .active(snapshot)), nil)
        let client = XPCSleepControlClient { _ in proxy }

        let status = try client.start(duration: .thirtyMinutes)

        XCTAssertEqual(proxy.startedDurationSeconds, 1_800)
        XCTAssertEqual(status, .active(snapshot))
    }

    func testCancelDecodesInactiveStatus() throws {
        let proxy = FakeHelperXPCProxy()
        proxy.cancelResponse = (TimerStatusPayload.dictionary(from: .inactive), nil)
        let client = XPCSleepControlClient { _ in proxy }

        let status = try client.cancel()

        XCTAssertTrue(proxy.didCancel)
        XCTAssertEqual(status, .inactive)
    }

    func testStatusDecodesHelperStatus() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .fiveMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(300)
        )
        let proxy = FakeHelperXPCProxy()
        proxy.statusResponse = (TimerStatusPayload.dictionary(from: .active(snapshot)), nil)
        let client = XPCSleepControlClient { _ in proxy }

        let status = try client.status()

        XCTAssertTrue(proxy.didRequestStatus)
        XCTAssertEqual(status, .active(snapshot))
    }

    func testHelperErrorIsUserVisible() {
        let proxy = FakeHelperXPCProxy()
        proxy.startResponse = (
            nil,
            NSError(
                domain: "com.sasha.MacAwake.helper",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Admin permission is required."]
            )
        )
        let client = XPCSleepControlClient { _ in proxy }

        XCTAssertThrowsError(try client.start(duration: .fiveMinutes)) { error in
            XCTAssertEqual(error as? SleepControlClientError, .helper("Admin permission is required."))
        }
    }

    func testMissingPayloadAndErrorIsInvalidResponse() {
        let proxy = FakeHelperXPCProxy()
        let client = XPCSleepControlClient { _ in proxy }

        XCTAssertThrowsError(try client.status()) { error in
            XCTAssertEqual(error as? SleepControlClientError, .invalidResponse)
        }
    }

    func testTimesOutWhenHelperDoesNotReply() {
        let proxy = NonReplyingHelperXPCProxy()
        let client = XPCSleepControlClient(
            remoteProxyProvider: { _ in proxy },
            responseTimeout: .milliseconds(1)
        )

        XCTAssertThrowsError(try client.status()) { error in
            XCTAssertEqual(error as? SleepControlClientError, .timedOut)
        }
        XCTAssertTrue(proxy.didRequestStatus)
    }
}
