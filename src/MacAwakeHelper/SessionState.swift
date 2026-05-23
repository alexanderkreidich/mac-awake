import Foundation
import MacAwakeCore

public struct SessionState: Codable, Equatable, Sendable {
    public var isActive: Bool
    public var durationSeconds: Int?
    public var startedAt: Date?
    public var expiresAt: Date?
    public var previousDisableSleepValue: Int?

    public init(
        isActive: Bool,
        durationSeconds: Int? = nil,
        startedAt: Date? = nil,
        expiresAt: Date? = nil,
        previousDisableSleepValue: Int? = nil
    ) {
        self.isActive = isActive
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.previousDisableSleepValue = previousDisableSleepValue
    }

    public static let inactive = SessionState(isActive: false)

    public static func active(
        duration: AwakeDuration,
        startedAt: Date,
        previousDisableSleepValue: Int
    ) -> SessionState {
        SessionState(
            isActive: true,
            durationSeconds: duration.seconds,
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(TimeInterval(duration.seconds)),
            previousDisableSleepValue: previousDisableSleepValue
        )
    }

    public var activeSnapshot: ActiveTimerSnapshot? {
        guard
            isActive,
            let durationSeconds,
            let duration = try? AwakeDuration(seconds: durationSeconds),
            let startedAt,
            let expiresAt
        else {
            return nil
        }

        return ActiveTimerSnapshot(duration: duration, startedAt: startedAt, expiresAt: expiresAt)
    }

    public func isExpired(at date: Date) -> Bool {
        guard isActive, let expiresAt else {
            return false
        }

        return expiresAt <= date
    }
}
