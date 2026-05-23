import Foundation
import MacAwakeCore

protocol SleepControlClient {
    func start(duration: AwakeDuration) throws -> TimerStatus
    func cancel() throws -> TimerStatus
    func status() throws -> TimerStatus
}

enum SleepControlClientError: Error, Equatable, LocalizedError {
    case invalidRemoteProxy
    case invalidResponse
    case timedOut
    case helper(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidRemoteProxy:
            return "Could not connect to the Mac Awake helper."
        case .invalidResponse:
            return "The Mac Awake helper returned an invalid response."
        case .timedOut:
            return "Timed out waiting for the Mac Awake helper."
        case .helper(let message), .transport(let message):
            return message
        }
    }
}

final class XPCSleepControlClient: SleepControlClient {
    private struct RemoteProxySession {
        let proxy: MacAwakeHelperXPCProtocol
        let invalidate: () -> Void
    }

    private let makeRemoteProxySession: (@escaping (Error) -> Void) throws -> RemoteProxySession
    private let responseTimeout: DispatchTimeInterval

    init(
        machServiceName: String = SleepControlXPC.machServiceName,
        responseTimeout: DispatchTimeInterval = .seconds(5)
    ) {
        self.responseTimeout = responseTimeout
        self.makeRemoteProxySession = { errorHandler in
            let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
            connection.remoteObjectInterface = SleepControlXPC.makeInterface()
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler) as? MacAwakeHelperXPCProtocol else {
                connection.invalidate()
                throw SleepControlClientError.invalidRemoteProxy
            }

            return RemoteProxySession(proxy: proxy, invalidate: { connection.invalidate() })
        }
    }

    init(
        remoteProxyProvider: @escaping (@escaping (Error) -> Void) throws -> MacAwakeHelperXPCProtocol,
        responseTimeout: DispatchTimeInterval = .seconds(5)
    ) {
        self.responseTimeout = responseTimeout
        self.makeRemoteProxySession = { errorHandler in
            RemoteProxySession(
                proxy: try remoteProxyProvider(errorHandler),
                invalidate: {}
            )
        }
    }

    func start(duration: AwakeDuration) throws -> TimerStatus {
        try perform { proxy, reply in
            proxy.start(durationSeconds: NSNumber(value: duration.seconds), withReply: reply)
        }
    }

    func cancel() throws -> TimerStatus {
        try perform { proxy, reply in
            proxy.cancel(withReply: reply)
        }
    }

    func status() throws -> TimerStatus {
        try perform { proxy, reply in
            proxy.status(withReply: reply)
        }
    }

    private func perform(
        _ call: @escaping (MacAwakeHelperXPCProtocol, @escaping (NSDictionary?, NSError?) -> Void) -> Void
    ) throws -> TimerStatus {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<TimerStatus, Error>?

        func complete(_ nextResult: Result<TimerStatus, Error>) {
            lock.lock()
            defer { lock.unlock() }

            guard result == nil else {
                return
            }

            result = nextResult
            semaphore.signal()
        }

        let session = try makeRemoteProxySession { error in
            complete(.failure(SleepControlClientError.transport(error.localizedDescription)))
        }
        defer { session.invalidate() }

        call(session.proxy) { payload, error in
            if let error {
                complete(.failure(SleepControlClientError.helper(error.localizedDescription)))
                return
            }

            guard let payload else {
                complete(.failure(SleepControlClientError.invalidResponse))
                return
            }

            do {
                complete(.success(try TimerStatusPayload.status(from: payload)))
            } catch {
                complete(.failure(error))
            }
        }

        guard semaphore.wait(timeout: .now() + responseTimeout) == .success else {
            throw SleepControlClientError.timedOut
        }

        guard let result else {
            throw SleepControlClientError.invalidResponse
        }

        return try result.get()
    }
}

final class FakeSleepControlClient: SleepControlClient {
    private var currentStatus: TimerStatus = .inactive
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func start(duration: AwakeDuration) throws -> TimerStatus {
        let startedAt = now()
        let snapshot = ActiveTimerSnapshot(
            duration: duration,
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(TimeInterval(duration.seconds))
        )
        currentStatus = .active(snapshot)
        return currentStatus
    }

    func cancel() throws -> TimerStatus {
        currentStatus = .inactive
        return currentStatus
    }

    func status() throws -> TimerStatus {
        currentStatus
    }
}
