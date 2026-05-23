import Foundation
import XCTest
import MacAwakeCore

private enum FakePMSetClientError: Error {
    case requestedFailure
    case saveFailure
}

private final class FakePMSetClient: PMSetClient {
    var currentValue: Int
    var valuesThatFailOnSet: Set<Int> = []
    private(set) var currentReadCount = 0
    private(set) var setValues: [Int] = []

    init(currentValue: Int = 0) {
        self.currentValue = currentValue
    }

    func readDisableSleepValue() throws -> Int {
        currentReadCount += 1
        return currentValue
    }

    func setDisableSleepValue(_ value: Int) throws {
        setValues.append(value)

        if valuesThatFailOnSet.contains(value) {
            throw FakePMSetClientError.requestedFailure
        }

        currentValue = value
    }
}

private final class FailingSaveSessionStateStore: SessionStateStoring {
    func load() throws -> SessionState {
        .inactive
    }

    func save(_ state: SessionState) throws {
        throw FakePMSetClientError.saveFailure
    }
}

final class SessionStateTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }

        temporaryDirectories = []
        super.tearDown()
    }

    func testStartCreatesActiveSessionAndStoresPreviousDisableSleepValue() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let (store, _) = makeStore()
        let settings = FakePMSetClient(currentValue: 0)
        let service = HelperSleepControlService(store: store, pmsetClient: settings, now: { now })

        let status = try service.start(duration: .fiveMinutes)

        guard case .active(let snapshot) = status else {
            return XCTFail("Expected active status")
        }

        XCTAssertEqual(snapshot.duration, .fiveMinutes)
        XCTAssertEqual(snapshot.startedAt, now)
        XCTAssertEqual(snapshot.expiresAt, now.addingTimeInterval(300))
        XCTAssertEqual(settings.currentReadCount, 1)
        XCTAssertEqual(settings.setValues, [1])

        let persisted = try store.load()
        XCTAssertTrue(persisted.isActive)
        XCTAssertEqual(persisted.durationSeconds, 300)
        XCTAssertEqual(persisted.startedAt, now)
        XCTAssertEqual(persisted.expiresAt, now.addingTimeInterval(300))
        XCTAssertEqual(persisted.previousDisableSleepValue, 0)
    }

    func testCancelRestoresPreviousDisableSleepValueAndClearsSession() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let (store, _) = makeStore()
        let settings = FakePMSetClient(currentValue: 0)
        let service = HelperSleepControlService(store: store, pmsetClient: settings, now: { now })

        _ = try service.start(duration: .thirtyMinutes)
        let status = try service.cancel()

        XCTAssertEqual(status, .inactive)
        XCTAssertFalse(try store.load().isActive)
        XCTAssertEqual(settings.setValues, [1, 0])
    }

    func testSwitchingDurationKeepsOriginalPreviousDisableSleepValue() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let (store, _) = makeStore()
        let settings = FakePMSetClient(currentValue: 0)
        let service = HelperSleepControlService(store: store, pmsetClient: settings, now: { now })

        _ = try service.start(duration: .fiveMinutes)
        now = Date(timeIntervalSince1970: 1_060)
        settings.currentValue = 1
        let status = try service.start(duration: .sixtyMinutes)

        guard case .active(let snapshot) = status else {
            return XCTFail("Expected active status")
        }

        XCTAssertEqual(snapshot.duration, .sixtyMinutes)
        XCTAssertEqual(snapshot.startedAt, now)
        XCTAssertEqual(snapshot.expiresAt, now.addingTimeInterval(3_600))
        XCTAssertEqual(settings.currentReadCount, 1)
        XCTAssertEqual(settings.setValues, [1])

        let persisted = try store.load()
        XCTAssertEqual(persisted.durationSeconds, 3_600)
        XCTAssertEqual(persisted.previousDisableSleepValue, 0)
    }

    func testExpiredSessionOnLaunchRestoresImmediately() throws {
        let (store, _) = makeStore()
        try store.save(
            SessionState.active(
                duration: .fiveMinutes,
                startedAt: Date(timeIntervalSince1970: 1_000),
                previousDisableSleepValue: 0
            )
        )
        let settings = FakePMSetClient(currentValue: 1)

        _ = HelperSleepControlService(
            store: store,
            pmsetClient: settings,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        XCTAssertEqual(settings.setValues, [0])
        XCTAssertFalse(try store.load().isActive)
    }

    func testStartRestoresPreviousValueIfPersistenceFailsAfterEnable() throws {
        let settings = FakePMSetClient(currentValue: 0)
        let service = HelperSleepControlService(
            store: FailingSaveSessionStateStore(),
            pmsetClient: settings,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        XCTAssertThrowsError(try service.start(duration: .fiveMinutes))
        XCTAssertEqual(settings.setValues, [1, 0])
    }

    func testCancelRestoreFailureLeavesActiveStateVisible() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let (store, _) = makeStore()
        let settings = FakePMSetClient(currentValue: 0)
        let service = HelperSleepControlService(store: store, pmsetClient: settings, now: { now })

        _ = try service.start(duration: .thirtyMinutes)
        settings.valuesThatFailOnSet = [0]

        XCTAssertThrowsError(try service.cancel())
        XCTAssertTrue(try store.load().isActive)

        guard case .active(let snapshot) = try service.status() else {
            return XCTFail("Expected active status after failed restore")
        }

        XCTAssertEqual(snapshot.duration, .thirtyMinutes)
    }

    func testMissingStateLoadsAsInactive() throws {
        let (store, _) = makeStore()
        let settings = FakePMSetClient(currentValue: 0)
        let service = HelperSleepControlService(store: store, pmsetClient: settings)

        XCTAssertEqual(try service.status(), .inactive)
        XCTAssertEqual(settings.setValues, [])
    }

    func testCorruptedStateReportsVisibleError() throws {
        let (store, fileURL) = makeStore()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)
        let settings = FakePMSetClient(currentValue: 0)
        let service = HelperSleepControlService(store: store, pmsetClient: settings)

        let status = try service.status()

        guard case .errorVisible(let errorState) = status else {
            return XCTFail("Expected visible error status")
        }

        XCTAssertEqual(errorState.message, "Saved Mac Awake session state is unreadable.")
        XCTAssertEqual(settings.setValues, [])
    }

    private func makeStore() -> (SessionStateStore, URL) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacAwakeHelperTests-")
            .appendingPathComponent(UUID().uuidString)
        let fileURL = directoryURL.appendingPathComponent("SessionState.json")
        temporaryDirectories.append(directoryURL)

        return (SessionStateStore(fileURL: fileURL), fileURL)
    }
}
