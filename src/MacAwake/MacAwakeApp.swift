import AppKit
import Combine
import SwiftUI
import MacAwakeCore

@main
struct MacAwakeApp: App {
    @NSApplicationDelegateAdaptor(MacAwakeAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class MacAwakeAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: MacAwakeStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = AwakeTimerStore(
            client: XPCSleepControlClient(responseTimeout: .seconds(2))
        )
        statusItemController = MacAwakeStatusItemController(store: store)
    }
}

@MainActor
private final class MacAwakeStatusItemController: NSObject, NSMenuDelegate {
    private let store: AwakeTimerStore
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var durationMenuItems: [AwakeDuration: NSMenuItem] = [:]
    private var statusCancellable: AnyCancellable?
    private var menuTrackingTimer: Timer?

    init(store: AwakeTimerStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusButton()
        configureMenu()

        statusCancellable = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        button.image = MacAwakeMenuBarIcon.image
        button.imagePosition = .imageOnly
        updateStatusButton(button)
    }

    private func updateStatusItem() {
        if let button = statusItem.button {
            updateStatusButton(button)
        }

        refreshMenuItems()
    }

    private func updateStatusButton(_ button: NSStatusBarButton) {
        let title = store.menuBarTitle
        button.title = ""
        button.toolTip = "Mac Awake \(title)"
        button.setAccessibilityLabel("Mac Awake \(title)")
    }

    private func configureMenu() {
        menu.delegate = self

        let headerItem = NSMenuItem(title: "Keep awake with lid closed", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        for duration in AwakeDuration.allCases {
            let item = NSMenuItem(title: rowTitle(for: duration), action: #selector(selectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: duration.rawValue)
            durationMenuItems[duration] = item
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Mac Awake", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenuItems()
    }

    private func refreshMenuItems() {
        for duration in AwakeDuration.allCases {
            guard let item = durationMenuItems[duration] else {
                continue
            }

            item.title = rowTitle(for: duration)
            item.state = store.isActiveDuration(duration) ? .on : .off
        }
    }

    private func rowTitle(for duration: AwakeDuration) -> String {
        if let remainingText = store.dropdownRemainingText(for: duration) {
            return "\(duration.menuTitle)    \(remainingText)"
        }

        return duration.menuTitle
    }

    @objc private func selectDuration(_ sender: NSMenuItem) {
        guard
            let rawValue = (sender.representedObject as? NSNumber)?.intValue,
            let duration = AwakeDuration(rawValue: rawValue)
        else {
            return
        }

        store.select(duration)
        updateStatusItem()
    }

    @objc private func quit() {
        store.quit()
        updateStatusItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatusItem()
        startMenuTrackingTimer()
    }

    func menuDidClose(_ menu: NSMenu) {
        stopMenuTrackingTimer()
    }

    private func startMenuTrackingTimer() {
        stopMenuTrackingTimer()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.refreshForTimerTick()
                self?.updateStatusItem()
            }
        }
        menuTrackingTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func stopMenuTrackingTimer() {
        menuTrackingTimer?.invalidate()
        menuTrackingTimer = nil
    }
}

private enum MacAwakeMenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.black.setStroke()

        let rays = NSBezierPath()
        rays.lineWidth = 1.5
        rays.lineCapStyle = .round
        rays.move(to: NSPoint(x: 9.0, y: 15.0))
        rays.line(to: NSPoint(x: 9.0, y: 12.8))
        rays.move(to: NSPoint(x: 5.8, y: 14.2))
        rays.line(to: NSPoint(x: 7.0, y: 12.4))
        rays.move(to: NSPoint(x: 12.2, y: 14.2))
        rays.line(to: NSPoint(x: 11.0, y: 12.4))
        rays.stroke()

        let lid = NSBezierPath(roundedRect: NSRect(x: 4.4, y: 5.6, width: 9.2, height: 6.0), xRadius: 1.2, yRadius: 1.2)
        lid.lineWidth = 1.5
        lid.stroke()

        let base = NSBezierPath()
        base.lineWidth = 1.5
        base.lineCapStyle = .round
        base.move(to: NSPoint(x: 3.2, y: 4.2))
        base.line(to: NSPoint(x: 14.8, y: 4.2))
        base.move(to: NSPoint(x: 6.3, y: 3.1))
        base.line(to: NSPoint(x: 11.7, y: 3.1))
        base.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}
