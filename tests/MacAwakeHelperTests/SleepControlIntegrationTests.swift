import Foundation
import XCTest
import MacAwakeCore

private final class IntegrationPMSetClient: PMSetClient {
    var currentValue: Int
    var lidClosed = false
    private(set) var setValues: [Int] = []
    private(set) var sleepNowCount = 0

    init(currentValue: Int) {
        self.currentValue = currentValue
    }

    func readDisableSleepValue() throws -> Int {
        currentValue
    }

    func setDisableSleepValue(_ value: Int) throws {
        setValues.append(value)
        currentValue = value
    }

    func isLidClosed() throws -> Bool {
        lidClosed
    }

    func sleepNow() throws {
        sleepNowCount += 1
    }
}

final class SleepControlIntegrationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }

        temporaryDirectories = []
        super.tearDown()
    }

    func testClientCanStartReadAndCancelThroughXPCAdapterAndHelperService() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = makeStore()
        let settings = IntegrationPMSetClient(currentValue: 0)
        let helperService = HelperSleepControlService(
            store: store,
            pmsetClient: settings,
            now: { now }
        )
        let xpcService = SleepControlXPCService(service: helperService)
        let client = XPCSleepControlClient(
            remoteProxyProvider: { _ in xpcService },
            responseTimeout: .seconds(1)
        )

        let startedStatus = try client.start(duration: .fiveMinutes)
        let helperStatus = try client.status()
        let cancelledStatus = try client.cancel()

        let expectedSnapshot = ActiveTimerSnapshot(
            duration: .fiveMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(300)
        )
        XCTAssertEqual(startedStatus, .active(expectedSnapshot))
        XCTAssertEqual(helperStatus, .active(expectedSnapshot))
        XCTAssertEqual(cancelledStatus, .inactive)
        XCTAssertEqual(settings.setValues, [1, 0])
        XCTAssertEqual(try store.load(), .inactive)
    }

    private func makeStore() -> SessionStateStore {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAwakeIntegrationTests-")
            .appendingPathComponent(UUID().uuidString)
        temporaryDirectories.append(directoryURL)

        return SessionStateStore(fileURL: directoryURL.appendingPathComponent("SessionState.json"))
    }
}
