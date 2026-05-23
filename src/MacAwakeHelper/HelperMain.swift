import Foundation
import MacAwakeCore

@main
struct MacAwakeHelperMain {
    static func main() {
        let service = HelperSleepControlService(
            store: SessionStateStore(fileURL: sessionStateURL()),
            pmsetClient: SystemPMSetClient()
        )
        let delegate = HelperXPCListenerDelegate(service: service)
        let listener = NSXPCListener(machServiceName: SleepControlXPC.machServiceName)
        listener.delegate = delegate
        listener.resume()

        RunLoop.current.run()
    }

    private static func sessionStateURL() -> URL {
        URL(fileURLWithPath: "/Library/Application Support/Mac Awake/SessionState.json")
    }
}
