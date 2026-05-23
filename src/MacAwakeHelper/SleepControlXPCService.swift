import Foundation
import MacAwakeCore

final class SleepControlXPCService: NSObject, MacAwakeHelperXPCProtocol {
    private let service: SleepControlService
    private let queue = DispatchQueue(label: "com.sasha.MacAwake.helper.sleep-control")

    init(service: SleepControlService) {
        self.service = service
    }

    func start(durationSeconds: NSNumber, withReply reply: @escaping (NSDictionary?, NSError?) -> Void) {
        run(reply: reply) { [self] in
            let duration = try AwakeDuration(seconds: durationSeconds.intValue)
            return try self.service.start(duration: duration)
        }
    }

    func cancel(withReply reply: @escaping (NSDictionary?, NSError?) -> Void) {
        run(reply: reply) { [self] in
            try self.service.cancel()
        }
    }

    func status(withReply reply: @escaping (NSDictionary?, NSError?) -> Void) {
        run(reply: reply) { [self] in
            try self.service.status()
        }
    }

    private func run(
        reply: @escaping (NSDictionary?, NSError?) -> Void,
        operation: @escaping () throws -> TimerStatus
    ) {
        queue.async {
            do {
                let status = try operation()
                reply(TimerStatusPayload.dictionary(from: status), nil)
            } catch {
                reply(nil, HelperErrorMapper.error(from: error))
            }
        }
    }
}

final class HelperXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedObject: SleepControlXPCService

    init(service: SleepControlService) {
        self.exportedObject = SleepControlXPCService(service: service)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = SleepControlXPC.makeInterface()
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}

enum HelperErrorMapper {
    private static let domain = "com.sasha.MacAwake.helper"

    static func error(from error: Error) -> NSError {
        NSError(
            domain: domain,
            code: code(for: error),
            userInfo: [NSLocalizedDescriptionKey: message(for: error)]
        )
    }

    private static func code(for error: Error) -> Int {
        switch error {
        case is AwakeDurationValidationError:
            return 10
        case is PMSetClientError:
            return 20
        case is SessionStateStoreError:
            return 30
        case is SleepControlServiceError:
            return 40
        default:
            return 1
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case AwakeDurationValidationError.unsupportedDuration:
            return "Mac Awake only supports 5, 30, and 60 minute timers."
        case PMSetClientError.missingDisableSleepValue:
            return "This Mac does not expose pmset disablesleep, so Mac Awake cannot keep it awake while closed."
        case PMSetClientError.unsupportedDisableSleepValue:
            return "This Mac returned an unsupported pmset disablesleep value."
        case PMSetClientError.commandFailed(_, let standardError):
            if standardError.isEmpty {
                return "pmset rejected the sleep setting change."
            }

            return "pmset rejected the sleep setting change: \(standardError)"
        case SessionStateStoreError.corruptedState:
            return "Saved Mac Awake session state is unreadable."
        case SleepControlServiceError.invalidPersistedSession:
            return "Saved Mac Awake session state is invalid."
        case SleepControlServiceError.missingPreviousDisableSleepValue:
            return "Mac Awake cannot restore normal sleep behavior because the previous setting was not saved. Run: sudo pmset -a disablesleep 0"
        default:
            return error.localizedDescription
        }
    }
}
