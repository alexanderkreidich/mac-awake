import Foundation

public protocol PMSetClient {
    func readDisableSleepValue() throws -> Int
    func setDisableSleepValue(_ value: Int) throws
    func isLidClosed() throws -> Bool
    func sleepNow() throws
}

public struct PMSetProcessResult: Equatable, Sendable {
    public let terminationStatus: Int32
    public let standardOutput: String
    public let standardError: String

    public init(terminationStatus: Int32, standardOutput: String, standardError: String) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol PMSetProcessRunning {
    func run(executableURL: URL, arguments: [String]) throws -> PMSetProcessResult
}

public enum PMSetClientError: Error, Equatable {
    case commandFailed(arguments: [String], standardError: String)
    case missingDisableSleepValue
    case unsupportedDisableSleepValue(Int)
}

public struct SystemPMSetClient: PMSetClient {
    private let executableURL: URL
    private let rootDomainExecutableURL: URL
    private let processRunner: PMSetProcessRunning

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/pmset"),
        rootDomainExecutableURL: URL = URL(fileURLWithPath: "/usr/sbin/ioreg"),
        processRunner: PMSetProcessRunning = FoundationPMSetProcessRunner()
    ) {
        self.executableURL = executableURL
        self.rootDomainExecutableURL = rootDomainExecutableURL
        self.processRunner = processRunner
    }

    public func readDisableSleepValue() throws -> Int {
        let arguments = ["-g", "custom"]
        let result = try processRunner.run(executableURL: executableURL, arguments: arguments)
        try validate(result: result, arguments: arguments)

        if let value = try parseDisableSleepValue(from: result.standardOutput) {
            return value
        }

        return try readRootDomainSleepDisabledValue()
    }

    public func setDisableSleepValue(_ value: Int) throws {
        guard value == 0 || value == 1 else {
            throw PMSetClientError.unsupportedDisableSleepValue(value)
        }

        let arguments = ["-a", "disablesleep", String(value)]
        let result = try processRunner.run(executableURL: executableURL, arguments: arguments)
        try validate(result: result, arguments: arguments)
    }

    public func isLidClosed() throws -> Bool {
        let output = try readRootDomainOutput()
        return parseBooleanRootDomainValue(named: "AppleClamshellState", from: output) ?? false
    }

    public func sleepNow() throws {
        let arguments = ["sleepnow"]
        let result = try processRunner.run(executableURL: executableURL, arguments: arguments)
        try validate(result: result, arguments: arguments)
    }

    private func validate(result: PMSetProcessResult, arguments: [String]) throws {
        guard result.terminationStatus == 0 else {
            throw PMSetClientError.commandFailed(
                arguments: arguments,
                standardError: result.standardError
            )
        }
    }

    private func readRootDomainSleepDisabledValue() throws -> Int {
        let output = try readRootDomainOutput()

        guard let value = parseSleepDisabledValue(from: output) else {
            throw PMSetClientError.missingDisableSleepValue
        }

        return value
    }

    private func readRootDomainOutput() throws -> String {
        let arguments = ["-r", "-n", "IOPMrootDomain", "-d", "1"]
        let result = try processRunner.run(executableURL: rootDomainExecutableURL, arguments: arguments)
        try validate(result: result, arguments: arguments)
        return result.standardOutput
    }

    private func parseDisableSleepValue(from output: String) throws -> Int? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split { character in
                character == " " || character == "\t"
            }

            guard parts.first == "disablesleep", let rawValue = parts.last, let value = Int(rawValue) else {
                continue
            }

            guard value == 0 || value == 1 else {
                throw PMSetClientError.unsupportedDisableSleepValue(value)
            }

            return value
        }

        return nil
    }

    private func parseSleepDisabledValue(from output: String) -> Int? {
        parseBooleanRootDomainValue(named: "SleepDisabled", from: output).map { $0 ? 1 : 0 }
    }

    private func parseBooleanRootDomainValue(named key: String, from output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.contains("\"\(key)\"") else {
                continue
            }

            if line.contains("Yes") {
                return true
            }

            if line.contains("No") {
                return false
            }
        }

        return nil
    }
}

public struct FoundationPMSetProcessRunner: PMSetProcessRunning {
    public init() {}

    public func run(executableURL: URL, arguments: [String]) throws -> PMSetProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return PMSetProcessResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? ""
        )
    }
}
