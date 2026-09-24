// AppKit only. The entry point must not pull SwiftUI in: PreferencesWindowController
// is the single place that touches it, and it builds nothing until Preferences opens.
import AppKit

@main
struct DotBarMain {
    static func main() {
        if let code = CLI.runIfInvoked() { exit(code) }      // `dotbar …` in a terminal: no menu bar app
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
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

extension AppDelegate {
    /// LSUIElement apps have no menu bar, so ⌘C/⌘V/⌘A/⌘Z do nothing in text fields
    /// unless an Edit menu with the standard key equivalents exists.
    static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit DotBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        return main
    }
}
