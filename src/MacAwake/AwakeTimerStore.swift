import AppKit
import Foundation
import MacAwakeCore

@MainActor
protocol SafetyNoticePresenter {
    func confirmFirstRunSafetyNotice() -> Bool
}

struct AppKitSafetyNoticePresenter: SafetyNoticePresenter {
    func confirmFirstRunSafetyNotice() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Mac Awake can keep your Mac running while closed."
        alert.informativeText = "Use it only when the Mac has ventilation and enough battery or power. Normal sleep will be restored when the timer ends or when you cancel it."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        return alert.runModal() == .alertFirstButtonReturn
    }
}

@MainActor
protocol UserAlertPresenter {
    func showError(message: String)
}

struct AppKitUserAlertPresenter: UserAlertPresenter {
    func showError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Mac Awake"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
final class AwakeTimerStore: ObservableObject {
    @Published private(set) var status: TimerStatus {
        didSet {
            scheduleStatusPollingIfNeeded()
        }
    }
    @Published var visibleErrorMessage: String?

    private let client: SleepControlClient
    private let safetyNoticePresenter: SafetyNoticePresenter
    private let userAlertPresenter: UserAlertPresenter
    private let terminateApplication: () -> Void
    private let now: () -> Date
    private var hasAcceptedSafetyNotice = false
    private var statusPollingTask: Task<Void, Never>?

    init(
        client: SleepControlClient,
        safetyNoticePresenter: SafetyNoticePresenter = AppKitSafetyNoticePresenter(),
        userAlertPresenter: UserAlertPresenter = AppKitUserAlertPresenter(),
        terminateApplication: @escaping () -> Void = { NSApplication.shared.terminate(nil) },
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.safetyNoticePresenter = safetyNoticePresenter
        self.userAlertPresenter = userAlertPresenter
        self.terminateApplication = terminateApplication
        self.now = now
        self.status = (try? client.status()) ?? .inactive
        scheduleStatusPollingIfNeeded()
    }

    deinit {
        statusPollingTask?.cancel()
    }

    var menuBarTitle: String {
        RemainingTimeFormatter.menuBarLabel(for: status, now: now())
    }

    func isActiveDuration(_ duration: AwakeDuration) -> Bool {
        status.isActiveDuration(duration)
    }

    func dropdownRemainingText(for duration: AwakeDuration) -> String? {
        guard let activeTimer = status.activeTimer, activeTimer.duration == duration else {
            return nil
        }

        return RemainingTimeFormatter.dropdownRemainingText(for: activeTimer, now: now())
    }

    func select(_ duration: AwakeDuration) {
        if status.isActiveDuration(duration) {
            cancel()
        } else {
            start(duration)
        }
    }

    func quit() {
        if status.isActive {
            cancel()

            guard !status.isActive else {
                return
            }
        }

        terminateApplication()
    }

    func refreshForTimerTick() {
        guard let activeTimer = status.activeTimer else {
            stopStatusPolling()
            return
        }

        objectWillChange.send()

        guard now() >= activeTimer.expiresAt else {
            return
        }

        refreshStatusAfterExpiry()
    }

    private func start(_ duration: AwakeDuration) {
        guard hasAcceptedSafetyNotice || safetyNoticePresenter.confirmFirstRunSafetyNotice() else {
            return
        }

        hasAcceptedSafetyNotice = true

        do {
            status = try client.start(duration: duration)
            visibleErrorMessage = nil
        } catch {
            showError(UserVisibleSleepControlMessage.startFailure(error))
        }
    }

    private func cancel() {
        do {
            status = try client.cancel()
            visibleErrorMessage = nil
        } catch {
            showError(UserVisibleSleepControlMessage.restoreFailure(error))
        }
    }

    private func refreshStatusAfterExpiry() {
        do {
            status = try client.status()
            visibleErrorMessage = nil
        } catch {
            stopStatusPolling()
            showError(UserVisibleSleepControlMessage.restoreFailure(error))
        }
    }

    private func scheduleStatusPollingIfNeeded() {
        guard status.activeTimer != nil else {
            stopStatusPolling()
            return
        }

        guard statusPollingTask == nil else {
            return
        }

        statusPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                guard !Task.isCancelled else {
                    return
                }

                self?.refreshForTimerTick()
            }
        }
    }

    private func stopStatusPolling() {
        statusPollingTask?.cancel()
        statusPollingTask = nil
    }

    private func showError(_ message: String) {
        visibleErrorMessage = message
        userAlertPresenter.showError(message: message)
    }
}

private enum UserVisibleSleepControlMessage {
    private static let recoveryCommand = "sudo pmset -a disablesleep 0"

    static func startFailure(_ error: Error) -> String {
        switch error as? SleepControlClientError {
        case .invalidRemoteProxy, .timedOut, .transport(_):
            return "Mac Awake helper is not installed or could not be reached. Install the helper and grant admin permission before starting a timer."
        case .invalidResponse:
            return "The Mac Awake helper returned an invalid response. Try reinstalling the helper."
        case .helper(let message):
            return message
        case nil:
            return "Could not start Mac Awake: \(error.localizedDescription)"
        }
    }

    static func restoreFailure(_ error: Error) -> String {
        let message: String

        switch error as? SleepControlClientError {
        case .invalidRemoteProxy, .timedOut, .transport(_):
            message = "Could not reach the Mac Awake helper to restore normal sleep behavior."
        case .invalidResponse:
            message = "The Mac Awake helper returned an invalid response while restoring normal sleep behavior."
        case .helper(let helperMessage):
            message = helperMessage
        case nil:
            message = "Could not restore normal sleep behavior: \(error.localizedDescription)"
        }

        if message.contains(recoveryCommand) {
            return message
        }

        return "\(message) Run: \(recoveryCommand)"
    }
}
