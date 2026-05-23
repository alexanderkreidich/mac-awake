import SwiftUI
import MacAwakeCore

struct MenuBarController: View {
    @ObservedObject var store: AwakeTimerStore

    var body: some View {
        Text("Keep awake with lid closed")

        ForEach(AwakeDuration.allCases) { duration in
            Button {
                store.select(duration)
            } label: {
                if store.isActiveDuration(duration) {
                    Label(rowTitle(for: duration), systemImage: "checkmark")
                } else {
                    Text(duration.menuTitle)
                }
            }
        }

        Divider()

        Button("Quit Mac Awake") {
            store.quit()
        }
    }

    private func rowTitle(for duration: AwakeDuration) -> String {
        if let remainingText = store.dropdownRemainingText(for: duration) {
            return "\(duration.menuTitle)    \(remainingText)"
        }

        return duration.menuTitle
    }
}
