import Foundation
import MacAwakeCore

public protocol SleepControlService {
    func start(duration: AwakeDuration) throws -> TimerStatus
    func cancel() throws -> TimerStatus
    func status() throws -> TimerStatus
}

public enum SleepControlServiceError: Error, Equatable {
    case invalidPersistedSession
    case missingPreviousDisableSleepValue
}

public final class HelperSleepControlService: SleepControlService {
    private let store: SessionStateStoring
    private let pmsetClient: PMSetClient
    private let now: () -> Date

    public init(
        store: SessionStateStoring,
        pmsetClient: PMSetClient,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.pmsetClient = pmsetClient
        self.now = now

        try? recoverExpiredSessionIfNeeded(requestSleep: true)
    }

    public func start(duration: AwakeDuration) throws -> TimerStatus {
        try recoverExpiredSessionIfNeeded(requestSleep: false)

        let currentState = try store.load()
        let startedAt = now()
        let previousDisableSleepValue: Int
        var didEnableDisableSleep = false

        if currentState.isActive, let previousValue = currentState.previousDisableSleepValue {
            previousDisableSleepValue = previousValue
        } else {
            previousDisableSleepValue = try pmsetClient.readDisableSleepValue()
            try pmsetClient.setDisableSleepValue(1)
            didEnableDisableSleep = true
        }

        let nextState = SessionState.active(
            duration: duration,
            startedAt: startedAt,
            previousDisableSleepValue: previousDisableSleepValue
        )

        do {
            try store.save(nextState)
        } catch {
            if didEnableDisableSleep {
                try? pmsetClient.setDisableSleepValue(previousDisableSleepValue)
            }

            throw error
        }

        guard let snapshot = nextState.activeSnapshot else {
            throw SleepControlServiceError.invalidPersistedSession
        }

        return .active(snapshot)
    }

    public func cancel() throws -> TimerStatus {
        let currentState = try store.load()

        guard currentState.isActive else {
            try store.save(.inactive)
            return .inactive
        }

        guard let previousValue = currentState.previousDisableSleepValue else {
            throw SleepControlServiceError.missingPreviousDisableSleepValue
        }

        try pmsetClient.setDisableSleepValue(previousValue)
        try store.save(.inactive)

        return .inactive
    }

    public func status() throws -> TimerStatus {
        do {
            try recoverExpiredSessionIfNeeded(requestSleep: true)
            return try status(for: store.load())
        } catch SessionStateStoreError.corruptedState {
            return .errorVisible(
                TimerErrorState(message: "Saved Mac Awake session state is unreadable.")
            )
        }
    }

    private func recoverExpiredSessionIfNeeded(requestSleep: Bool) throws {
        let currentState = try store.load()

        guard currentState.isExpired(at: now()) else {
            return
        }

        guard let previousValue = currentState.previousDisableSleepValue else {
            throw SleepControlServiceError.missingPreviousDisableSleepValue
        }

        try pmsetClient.setDisableSleepValue(previousValue)
        try store.save(.inactive)

        if requestSleep {
            try pmsetClient.sleepNow()
        }
    }

    private func status(for state: SessionState) throws -> TimerStatus {
        guard state.isActive else {
            return .inactive
        }

        guard let snapshot = state.activeSnapshot else {
            return .errorVisible(
                TimerErrorState(message: "Saved Mac Awake session state is invalid.")
            )
        }

        return .active(snapshot)
    }
}
