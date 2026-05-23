import XCTest
@testable import MacAwakeCore

@MainActor
private final class StubSafetyNoticePresenter: SafetyNoticePresenter {
    private let result: Bool
    private(set) var callCount = 0

    init(result: Bool) {
        self.result = result
    }

    func confirmFirstRunSafetyNotice() -> Bool {
        callCount += 1
        return result
    }
}

@MainActor
private final class StubUserAlertPresenter: UserAlertPresenter {
    private(set) var messages: [String] = []

    func showError(message: String) {
        messages.append(message)
    }
}

private final class ConfigurableSleepControlClient: SleepControlClient {
    var statusResult: Result<TimerStatus, Error>
    var startResult: Result<TimerStatus, Error>
    var cancelResult: Result<TimerStatus, Error>
    private(set) var statusCallCount = 0
    private(set) var didCancel = false

    init(
        statusResult: Result<TimerStatus, Error> = .success(.inactive),
        startResult: Result<TimerStatus, Error> = .success(.inactive),
        cancelResult: Result<TimerStatus, Error> = .success(.inactive)
    ) {
        self.statusResult = statusResult
        self.startResult = startResult
        self.cancelResult = cancelResult
    }

    func start(duration: AwakeDuration) throws -> TimerStatus {
        try startResult.get()
    }

    func cancel() throws -> TimerStatus {
        didCancel = true
        return try cancelResult.get()
    }

    func status() throws -> TimerStatus {
        statusCallCount += 1
        return try statusResult.get()
    }
}

final class AwakeTimerStoreTests: XCTestCase {
    @MainActor
    func testSelectingInactiveDurationStartsAfterSafetyNotice() {
        let now = Date(timeIntervalSince1970: 1_000)
        let client = FakeSleepControlClient(now: { now })
        let safetyNotice = StubSafetyNoticePresenter(result: true)
        let store = AwakeTimerStore(client: client, safetyNoticePresenter: safetyNotice, now: { now })

        store.select(.fiveMinutes)

        XCTAssertTrue(store.isActiveDuration(.fiveMinutes))
        XCTAssertEqual(safetyNotice.callCount, 1)
    }

    @MainActor
    func testDecliningSafetyNoticeDoesNotStartTimer() {
        let now = Date(timeIntervalSince1970: 1_000)
        let client = FakeSleepControlClient(now: { now })
        let safetyNotice = StubSafetyNoticePresenter(result: false)
        let store = AwakeTimerStore(client: client, safetyNoticePresenter: safetyNotice, now: { now })

        store.select(.fiveMinutes)

        XCTAssertFalse(store.status.isActive)
        XCTAssertEqual(safetyNotice.callCount, 1)
    }

    @MainActor
    func testClickingActiveDurationCancelsTimer() {
        let now = Date(timeIntervalSince1970: 1_000)
        let client = FakeSleepControlClient(now: { now })
        let safetyNotice = StubSafetyNoticePresenter(result: true)
        let store = AwakeTimerStore(client: client, safetyNoticePresenter: safetyNotice, now: { now })

        store.select(.thirtyMinutes)
        store.select(.thirtyMinutes)

        XCTAssertFalse(store.status.isActive)
    }

    @MainActor
    func testClickingDifferentDurationSwitchesTimer() {
        let now = Date(timeIntervalSince1970: 1_000)
        let client = FakeSleepControlClient(now: { now })
        let safetyNotice = StubSafetyNoticePresenter(result: true)
        let store = AwakeTimerStore(client: client, safetyNoticePresenter: safetyNotice, now: { now })

        store.select(.fiveMinutes)
        store.select(.sixtyMinutes)

        XCTAssertTrue(store.isActiveDuration(.sixtyMinutes))
        XCTAssertEqual(safetyNotice.callCount, 1)
    }

    @MainActor
    func testDisplayedActiveStateUsesRemainingTime() {
        let now = Date(timeIntervalSince1970: 1_000)
        let client = FakeSleepControlClient(now: { now })
        let safetyNotice = StubSafetyNoticePresenter(result: true)
        let store = AwakeTimerStore(client: client, safetyNoticePresenter: safetyNotice, now: { now })

        store.select(.thirtyMinutes)

        XCTAssertEqual(store.menuBarTitle, "30m")
        XCTAssertEqual(store.dropdownRemainingText(for: .thirtyMinutes), "30:00 left")
    }

    @MainActor
    func testInitializesFromClientStatus() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .sixtyMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(3_600)
        )
        let client = ConfigurableSleepControlClient(statusResult: .success(.active(snapshot)))
        let store = AwakeTimerStore(client: client, now: { now })

        XCTAssertTrue(store.isActiveDuration(.sixtyMinutes))
        XCTAssertEqual(store.menuBarTitle, "60m")
    }

    @MainActor
    func testStartFailureShowsHelperMessage() {
        let client = ConfigurableSleepControlClient(
            startResult: .failure(
                SleepControlClientError.helper("This Mac does not expose pmset disablesleep, so Mac Awake cannot keep it awake while closed.")
            )
        )
        let safetyNotice = StubSafetyNoticePresenter(result: true)
        let alerts = StubUserAlertPresenter()
        let store = AwakeTimerStore(
            client: client,
            safetyNoticePresenter: safetyNotice,
            userAlertPresenter: alerts
        )

        store.select(.fiveMinutes)

        XCTAssertEqual(store.visibleErrorMessage, "This Mac does not expose pmset disablesleep, so Mac Awake cannot keep it awake while closed.")
        XCTAssertEqual(alerts.messages, ["This Mac does not expose pmset disablesleep, so Mac Awake cannot keep it awake while closed."])
    }

    @MainActor
    func testStartFailureWhenHelperIsUnavailableShowsAdminPermissionMessage() {
        let client = ConfigurableSleepControlClient(startResult: .failure(SleepControlClientError.timedOut))
        let safetyNotice = StubSafetyNoticePresenter(result: true)
        let alerts = StubUserAlertPresenter()
        let store = AwakeTimerStore(
            client: client,
            safetyNoticePresenter: safetyNotice,
            userAlertPresenter: alerts
        )

        store.select(.fiveMinutes)

        XCTAssertEqual(
            alerts.messages,
            ["Mac Awake helper is not installed or could not be reached. Install the helper and grant admin permission before starting a timer."]
        )
    }

    @MainActor
    func testActiveTimerTickRefreshesStatusAfterExpiry() {
        var now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .fiveMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(300)
        )
        let client = ConfigurableSleepControlClient(statusResult: .success(.active(snapshot)))
        let store = AwakeTimerStore(
            client: client,
            userAlertPresenter: StubUserAlertPresenter(),
            now: { now }
        )

        now = snapshot.expiresAt
        client.statusResult = .success(.inactive)
        store.refreshForTimerTick()

        XCTAssertEqual(client.statusCallCount, 2)
        XCTAssertEqual(store.status, .inactive)
    }

    @MainActor
    func testActiveTimerTickFailureKeepsActiveAndShowsRecoveryCommand() {
        var now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .fiveMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(300)
        )
        let client = ConfigurableSleepControlClient(statusResult: .success(.active(snapshot)))
        let alerts = StubUserAlertPresenter()
        let store = AwakeTimerStore(
            client: client,
            userAlertPresenter: alerts,
            now: { now }
        )

        now = snapshot.expiresAt
        client.statusResult = .failure(SleepControlClientError.timedOut)
        store.refreshForTimerTick()

        XCTAssertEqual(store.status, .active(snapshot))
        XCTAssertEqual(alerts.messages, ["Could not reach the Mac Awake helper to restore normal sleep behavior. Run: sudo pmset -a disablesleep 0"])
    }

    @MainActor
    func testQuitWhileActiveCancelsBeforeTerminating() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .thirtyMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(1_800)
        )
        let client = ConfigurableSleepControlClient(
            statusResult: .success(.active(snapshot)),
            cancelResult: .success(.inactive)
        )
        var didTerminate = false
        let store = AwakeTimerStore(
            client: client,
            userAlertPresenter: StubUserAlertPresenter(),
            terminateApplication: { didTerminate = true },
            now: { now }
        )

        store.quit()

        XCTAssertTrue(client.didCancel)
        XCTAssertTrue(didTerminate)
        XCTAssertEqual(store.status, .inactive)
    }

    @MainActor
    func testQuitWhileActiveRestoreFailureKeepsRunningAndShowsRecoveryCommand() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = ActiveTimerSnapshot(
            duration: .thirtyMinutes,
            startedAt: now,
            expiresAt: now.addingTimeInterval(1_800)
        )
        let client = ConfigurableSleepControlClient(
            statusResult: .success(.active(snapshot)),
            cancelResult: .failure(SleepControlClientError.helper("pmset rejected the sleep setting change."))
        )
        let alerts = StubUserAlertPresenter()
        var didTerminate = false
        let store = AwakeTimerStore(
            client: client,
            userAlertPresenter: alerts,
            terminateApplication: { didTerminate = true },
            now: { now }
        )

        store.quit()

        XCTAssertTrue(client.didCancel)
        XCTAssertFalse(didTerminate)
        XCTAssertEqual(store.status, .active(snapshot))
        XCTAssertEqual(alerts.messages, ["pmset rejected the sleep setting change. Run: sudo pmset -a disablesleep 0"])
    }
}
