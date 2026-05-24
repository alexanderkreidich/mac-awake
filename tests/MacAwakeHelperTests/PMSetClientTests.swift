import Foundation
import XCTest

private final class RecordingPMSetProcessRunner: PMSetProcessRunning {
    var results: [PMSetProcessResult]
    private(set) var invocations: [(executableURL: URL, arguments: [String])] = []

    init(results: [PMSetProcessResult]) {
        self.results = results
    }

    func run(executableURL: URL, arguments: [String]) throws -> PMSetProcessResult {
        invocations.append((executableURL, arguments))
        return results.removeFirst()
    }
}

final class PMSetClientTests: XCTestCase {
    func testReadDisableSleepValueUsesFixedPMSetArguments() throws {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "Battery Power:\n disablesleep 0\n",
                    standardError: ""
                ),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        let value = try client.readDisableSleepValue()

        XCTAssertEqual(value, 0)
        XCTAssertEqual(runner.invocations.map { $0.executableURL.path }, ["/usr/bin/pmset"])
        XCTAssertEqual(runner.invocations.map { $0.arguments }, [["-g", "custom"]])
    }

    func testReadDisableSleepValueFallsBackToRootDomainSleepDisabledValue() throws {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "Battery Power:\n sleep 15\n",
                    standardError: ""
                ),
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "    \"SleepDisabled\" = No\n",
                    standardError: ""
                ),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        let value = try client.readDisableSleepValue()

        XCTAssertEqual(value, 0)
        XCTAssertEqual(runner.invocations.map { $0.executableURL.path }, ["/usr/bin/pmset", "/usr/sbin/ioreg"])
        XCTAssertEqual(
            runner.invocations.map { $0.arguments },
            [
                ["-g", "custom"],
                ["-r", "-n", "IOPMrootDomain", "-d", "1"],
            ]
        )
    }

    func testReadDisableSleepValueFallsBackToEnabledRootDomainSleepDisabledValue() throws {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "Battery Power:\n sleep 15\n",
                    standardError: ""
                ),
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "    \"SleepDisabled\" = Yes\n",
                    standardError: ""
                ),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        XCTAssertEqual(try client.readDisableSleepValue(), 1)
    }

    func testIsLidClosedReadsClosedClamshellState() throws {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "    \"AppleClamshellState\" = Yes\n",
                    standardError: ""
                ),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        XCTAssertTrue(try client.isLidClosed())
        XCTAssertEqual(runner.invocations.map { $0.executableURL.path }, ["/usr/sbin/ioreg"])
        XCTAssertEqual(runner.invocations.map { $0.arguments }, [["-r", "-n", "IOPMrootDomain", "-d", "1"]])
    }

    func testIsLidClosedReadsOpenClamshellState() throws {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "    \"AppleClamshellState\" = No\n",
                    standardError: ""
                ),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        XCTAssertFalse(try client.isLidClosed())
    }

    func testIsLidClosedDefaultsToOpenWhenClamshellStateIsMissing() throws {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "    \"SleepDisabled\" = No\n",
                    standardError: ""
                ),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        XCTAssertFalse(try client.isLidClosed())
    }

    func testSetDisableSleepValueUsesFixedPMSetArguments() throws {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(terminationStatus: 0, standardOutput: "", standardError: ""),
                PMSetProcessResult(terminationStatus: 0, standardOutput: "", standardError: ""),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        try client.setDisableSleepValue(1)
        try client.setDisableSleepValue(0)

        XCTAssertEqual(runner.invocations.map { $0.executableURL.path }, ["/usr/bin/pmset", "/usr/bin/pmset"])
        XCTAssertEqual(
            runner.invocations.map { $0.arguments },
            [
                ["-a", "disablesleep", "1"],
                ["-a", "disablesleep", "0"],
            ]
        )
    }

    func testSleepNowUsesFixedPMSetArguments() throws {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(terminationStatus: 0, standardOutput: "", standardError: ""),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        try client.sleepNow()

        XCTAssertEqual(runner.invocations.map { $0.executableURL.path }, ["/usr/bin/pmset"])
        XCTAssertEqual(runner.invocations.map { $0.arguments }, [["sleepnow"]])
    }

    func testSetDisableSleepValueRejectsUnsupportedValuesBeforeRunningPMSet() {
        let runner = RecordingPMSetProcessRunner(results: [])
        let client = SystemPMSetClient(processRunner: runner)

        XCTAssertThrowsError(try client.setDisableSleepValue(2)) { error in
            XCTAssertEqual(error as? PMSetClientError, .unsupportedDisableSleepValue(2))
        }
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testReadDisableSleepValueRejectsUnsupportedOutputValue() {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "disablesleep 7\n",
                    standardError: ""
                ),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        XCTAssertThrowsError(try client.readDisableSleepValue()) { error in
            XCTAssertEqual(error as? PMSetClientError, .unsupportedDisableSleepValue(7))
        }
    }

    func testReadDisableSleepValueReportsMissingWhenBothSourcesOmitValue() {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "Battery Power:\n sleep 15\n",
                    standardError: ""
                ),
                PMSetProcessResult(
                    terminationStatus: 0,
                    standardOutput: "    \"AppleClamshellState\" = No\n",
                    standardError: ""
                ),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        XCTAssertThrowsError(try client.readDisableSleepValue()) { error in
            XCTAssertEqual(error as? PMSetClientError, .missingDisableSleepValue)
        }
    }

    func testCommandFailureReportsFixedArgumentsAndStandardError() {
        let runner = RecordingPMSetProcessRunner(
            results: [
                PMSetProcessResult(
                    terminationStatus: 1,
                    standardOutput: "",
                    standardError: "pmset failed"
                ),
            ]
        )
        let client = SystemPMSetClient(processRunner: runner)

        XCTAssertThrowsError(try client.setDisableSleepValue(1)) { error in
            XCTAssertEqual(
                error as? PMSetClientError,
                .commandFailed(arguments: ["-a", "disablesleep", "1"], standardError: "pmset failed")
            )
        }
    }
}
