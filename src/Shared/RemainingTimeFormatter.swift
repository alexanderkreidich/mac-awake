import Foundation

public enum RemainingTimeFormatter {
    public static func remainingSeconds(until expiresAt: Date, now: Date) -> Int {
        max(0, Int(ceil(expiresAt.timeIntervalSince(now))))
    }

    public static func menuBarLabel(for status: TimerStatus, now: Date = Date()) -> String {
        switch status {
        case .inactive, .expired:
            return "Awake"
        case .active(let snapshot):
            return menuBarLabel(for: snapshot, now: now)
        case .errorVisible:
            return "Error"
        }
    }

    public static func menuBarLabel(for snapshot: ActiveTimerSnapshot, now: Date = Date()) -> String {
        let seconds = remainingSeconds(until: snapshot.expiresAt, now: now)
        guard seconds > 0 else {
            return "0m"
        }

        let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
        return "\(minutes)m"
    }

    public static func dropdownRemainingText(for snapshot: ActiveTimerSnapshot, now: Date = Date()) -> String {
        let seconds = remainingSeconds(until: snapshot.expiresAt, now: now)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        return String(format: "%d:%02d left", minutes, remainingSeconds)
    }
}
