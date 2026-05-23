import Foundation

public enum AwakeDurationValidationError: Error, Equatable, Sendable {
    case unsupportedDuration(Int)
}

public enum AwakeDuration: Int, CaseIterable, Identifiable, Sendable {
    case fiveMinutes = 300
    case thirtyMinutes = 1_800
    case sixtyMinutes = 3_600

    public static let allCases: [AwakeDuration] = [
        .fiveMinutes,
        .thirtyMinutes,
        .sixtyMinutes,
    ]

    public var id: Int { rawValue }
    public var seconds: Int { rawValue }

    public var menuTitle: String {
        switch self {
        case .fiveMinutes:
            return "5 minutes"
        case .thirtyMinutes:
            return "30 minutes"
        case .sixtyMinutes:
            return "60 minutes"
        }
    }

    public var menuBarTitle: String {
        switch self {
        case .fiveMinutes:
            return "5m"
        case .thirtyMinutes:
            return "30m"
        case .sixtyMinutes:
            return "60m"
        }
    }

    public init(seconds: Int) throws {
        guard let duration = AwakeDuration(rawValue: seconds) else {
            throw AwakeDurationValidationError.unsupportedDuration(seconds)
        }

        self = duration
    }
}
