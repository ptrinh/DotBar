// AppKit only. The entry point must not pull SwiftUI in: PreferencesWindowController
// is the single place that touches it, and it builds nothing until Preferences opens.
import AppKit

@main
struct DotBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
        if AppState.shared.items.isEmpty { PreferencesWindowController.shared.show() }
    }

    /// Quitting must not leave a streaming child process behind.
    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutdownStreams()
    }

    /// dotbar:// URLs (see URLCommands).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { URLCommands.handle(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PreferencesWindowController.shared.show()
        return true
    }
}
