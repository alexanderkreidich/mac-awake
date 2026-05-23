import Foundation

public struct ActiveTimerSnapshot: Equatable, Sendable {
    public let duration: AwakeDuration
    public let startedAt: Date
    public let expiresAt: Date

    public init(duration: AwakeDuration, startedAt: Date, expiresAt: Date) {
        self.duration = duration
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }
}

public struct TimerErrorState: Equatable, Sendable {
    public let message: String
    public let recoveryCommand: String?
    public let activeTimer: ActiveTimerSnapshot?

    public init(message: String, recoveryCommand: String? = nil, activeTimer: ActiveTimerSnapshot? = nil) {
        self.message = message
        self.recoveryCommand = recoveryCommand
        self.activeTimer = activeTimer
    }
}

public enum TimerStatus: Equatable, Sendable {
    case inactive
    case active(ActiveTimerSnapshot)
    case expired(ActiveTimerSnapshot)
    case errorVisible(TimerErrorState)

    public var activeTimer: ActiveTimerSnapshot? {
        switch self {
        case .active(let snapshot):
            return snapshot
        case .inactive, .expired, .errorVisible:
            return nil
        }
    }

    public var isActive: Bool {
        activeTimer != nil
    }

    public func isActiveDuration(_ duration: AwakeDuration) -> Bool {
        activeTimer?.duration == duration
    }
}
