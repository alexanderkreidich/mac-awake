import Foundation

@objc(MacAwakeHelperXPCProtocol)
public protocol MacAwakeHelperXPCProtocol {
    func start(durationSeconds: NSNumber, withReply reply: @escaping (NSDictionary?, NSError?) -> Void)
    func cancel(withReply reply: @escaping (NSDictionary?, NSError?) -> Void)
    func status(withReply reply: @escaping (NSDictionary?, NSError?) -> Void)
}

public enum SleepControlXPC {
    public static let machServiceName = "com.sasha.MacAwakeHelper"

    public static func makeInterface() -> NSXPCInterface {
        NSXPCInterface(with: MacAwakeHelperXPCProtocol.self)
    }
}

public enum TimerStatusPayloadError: Error, Equatable, LocalizedError {
    case missingKind
    case unsupportedKind(String)
    case missingSnapshotField(String)
    case missingErrorMessage
    case unsupportedDuration(Int)

    public var errorDescription: String? {
        switch self {
        case .missingKind:
            return "The helper returned a status without a kind."
        case .unsupportedKind(let kind):
            return "The helper returned an unsupported status kind: \(kind)."
        case .missingSnapshotField(let field):
            return "The helper returned an active timer without \(field)."
        case .missingErrorMessage:
            return "The helper returned an error status without a message."
        case .unsupportedDuration(let seconds):
            return "The helper returned an unsupported duration: \(seconds) seconds."
        }
    }
}

public enum TimerStatusPayload {
    private enum Kind {
        static let inactive = "inactive"
        static let active = "active"
        static let expired = "expired"
        static let errorVisible = "errorVisible"
    }

    private enum Key {
        static let kind = "kind"
        static let durationSeconds = "durationSeconds"
        static let startedAt = "startedAt"
        static let expiresAt = "expiresAt"
        static let message = "message"
        static let recoveryCommand = "recoveryCommand"
        static let activeTimer = "activeTimer"
    }

    public static func dictionary(from status: TimerStatus) -> NSDictionary {
        switch status {
        case .inactive:
            return [Key.kind: Kind.inactive] as NSDictionary
        case .active(let snapshot):
            let payload = snapshotDictionary(from: snapshot).mutableCopy() as! NSMutableDictionary
            payload[Key.kind] = Kind.active
            return payload
        case .expired(let snapshot):
            let payload = snapshotDictionary(from: snapshot).mutableCopy() as! NSMutableDictionary
            payload[Key.kind] = Kind.expired
            return payload
        case .errorVisible(let errorState):
            let payload = NSMutableDictionary()
            payload[Key.kind] = Kind.errorVisible
            payload[Key.message] = errorState.message

            if let recoveryCommand = errorState.recoveryCommand {
                payload[Key.recoveryCommand] = recoveryCommand
            }

            if let activeTimer = errorState.activeTimer {
                payload[Key.activeTimer] = snapshotDictionary(from: activeTimer)
            }

            return payload
        }
    }

    public static func status(from payload: NSDictionary) throws -> TimerStatus {
        guard let kind = stringValue(payload[Key.kind]) else {
            throw TimerStatusPayloadError.missingKind
        }

        switch kind {
        case Kind.inactive:
            return .inactive
        case Kind.active:
            return .active(try snapshot(from: payload))
        case Kind.expired:
            return .expired(try snapshot(from: payload))
        case Kind.errorVisible:
            guard let message = stringValue(payload[Key.message]) else {
                throw TimerStatusPayloadError.missingErrorMessage
            }

            let recoveryCommand = stringValue(payload[Key.recoveryCommand])
            let activeTimerPayload = payload[Key.activeTimer] as? NSDictionary
            let activeTimer = try activeTimerPayload.map(snapshot(from:))

            return .errorVisible(
                TimerErrorState(
                    message: message,
                    recoveryCommand: recoveryCommand,
                    activeTimer: activeTimer
                )
            )
        default:
            throw TimerStatusPayloadError.unsupportedKind(kind)
        }
    }

    private static func snapshotDictionary(from snapshot: ActiveTimerSnapshot) -> NSDictionary {
        [
            Key.durationSeconds: NSNumber(value: snapshot.duration.seconds),
            Key.startedAt: snapshot.startedAt as NSDate,
            Key.expiresAt: snapshot.expiresAt as NSDate,
        ] as NSDictionary
    }

    private static func snapshot(from payload: NSDictionary) throws -> ActiveTimerSnapshot {
        guard let durationSeconds = intValue(payload[Key.durationSeconds]) else {
            throw TimerStatusPayloadError.missingSnapshotField(Key.durationSeconds)
        }
        guard let startedAt = dateValue(payload[Key.startedAt]) else {
            throw TimerStatusPayloadError.missingSnapshotField(Key.startedAt)
        }
        guard let expiresAt = dateValue(payload[Key.expiresAt]) else {
            throw TimerStatusPayloadError.missingSnapshotField(Key.expiresAt)
        }

        let duration: AwakeDuration
        do {
            duration = try AwakeDuration(seconds: durationSeconds)
        } catch {
            throw TimerStatusPayloadError.unsupportedDuration(durationSeconds)
        }

        return ActiveTimerSnapshot(duration: duration, startedAt: startedAt, expiresAt: expiresAt)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }

        if let string = value as? NSString {
            return string as String
        }

        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }

        return value as? Int
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }

        if let date = value as? NSDate {
            return date as Date
        }

        return nil
    }
}
