import SwiftUI
import AppKit

@main
struct TaskWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore.shared
    @StateObject private var poller = Poller.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
                .environmentObject(poller)
        } label: {
            Image(systemName: poller.hasUnseenActivity ? "bell.badge.fill" : "eye")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Handles app lifecycle: notification permission, polling start, and the
/// first-launch Preferences prompt when credentials are missing.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.requestAuthorization()
        Poller.shared.start()

        // Defer one runloop tick so the menu bar scene is fully up before we
        // try to front a window.
        DispatchQueue.main.async {
            if !AppStore.shared.hasCredentials {
                PreferencesWindowController.show()
            }
        }
    }
}

/// Manages the Preferences window directly via AppKit. The SwiftUI `Settings`
/// scene and its `showSettingsWindow:` selector are unreliable for menu-bar-only
/// (`LSUIElement`) apps, so we own the NSWindow and can front it deterministically
/// from both the popover button and the first-launch check.
@MainActor
enum PreferencesWindowController {
    private static var window: NSWindow?

    static func show() {
        // An accessory app must activate before a window can become key.
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: PreferencesView().environmentObject(AppStore.shared)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "TaskWatch Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 520))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
