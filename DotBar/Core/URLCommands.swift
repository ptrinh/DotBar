import AppKit

/// `dotbar://` URL scheme, so scripts and other apps can drive DotBar:
///
///     dotbar://refresh
///     dotbar://refresh?name=CPU%20Load        (or ?id=<uuid>)
///     dotbar://set?name=Build&text=passing
///     dotbar://enable?name=Build&value=false
///     dotbar://prefs
///     dotbar://welcome                        (the first-launch tour again)
///     dotbar://grant?what=codex               (App Store build: allow reading ~/.codex/auth.json)
///     dotbar://grant?what=claude              (App Store build: install the Claude Code usage hook)
///
/// Names match case-insensitively.
@MainActor
enum URLCommands {
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "dotbar" else { return }

        // dotbar://refresh -> host; dotbar:/refresh or dotbar:refresh -> path.
        let raw = url.host?.isEmpty == false
            ? url.host!
            : url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let command = raw.lowercased()

        var query: [String: String] = [:]
        for q in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            query[q.name.lowercased()] = q.value
        }

        let state = AppState.shared
        switch command {
        case "refresh":
            if let item = item(matching: query, in: state) { state.refresh(item) }
            else if query["name"] == nil && query["id"] == nil { state.refreshAll() }
        case "set":
            guard let item = item(matching: query, in: state), let text = query["text"] else { return }
            state.applyExternalOutput(text, for: item.id)
        case "enable":
            guard var item = item(matching: query, in: state) else { return }
            item.enabled = boolValue(query["value"])
            state.update(item)
        case "prefs", "preferences":
            PreferencesWindowController.shared.show()
        case "welcome":
            OnboardingWindowController.shared.show()
        case "grant":
            if query["what"] == "codex" { grantCodexAccess() }
            if query["what"] == "claude" { setUpClaudeUsage() }
        default:
            break
        }
    }

    /// Sandbox only: the user picks ~/.codex/auth.json once; a security-scoped bookmark keeps the
    /// read access so `dotbar usage codex` sees Codex CLI's current sign-in on every refresh.
    private static func grantCodexAccess() {
        let panel = NSOpenPanel()
        panel.message = "Select auth.json in ~/.codex so DotBar can read your Codex usage."
        panel.prompt = "Allow"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = AIUsage.realHome.appendingPathComponent(".codex", isDirectory: true)
        let onlyAuth = OnlyAuthJSON()                       // other files in ~/.codex are greyed out
        panel.delegate = onlyAuth
        NSApp.activate(ignoringOtherApps: true)
        defer { panel.delegate = nil }
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        UserDefaults.standard.set(bookmark, forKey: AIUsage.codexBookmarkKey)
        let state = AppState.shared
        for item in state.items where item.source.command?.contains("dotbar usage codex") == true { state.refresh(item) }
    }

    /// Sandbox only: the user picks ~/.claude once; DotBar installs a Claude Code `Stop` hook there
    /// that saves the usage response to ~/.claude/dotbar-usage.json, and reads that file.
    private static func setUpClaudeUsage() {
        let claudeDir = AIUsage.realHome.appendingPathComponent(".claude", isDirectory: true)
        let panel = NSOpenPanel()
        panel.message = "Select the .claude folder. DotBar adds a small hook to Claude Code's settings.json that saves your usage (not your sign-in) to dotbar-usage.json after each reply."
        panel.prompt = "Set Up"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = claudeDir.deletingLastPathComponent()
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.lastPathComponent == ".claude" else {
            alert("Please choose the .claude folder in your home folder.")
            return
        }
        do {
            try AIUsage.installClaudeHook(in: url)
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: AIUsage.claudeDirBookmarkKey)
        } catch {
            alert("Could not set up Claude usage: \(error.localizedDescription)")
            return
        }
        let state = AppState.shared
        for item in state.items where item.source.command?.contains("dotbar usage claude") == true { state.refresh(item) }
    }

    private static func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.runModal()
    }

    private static func item(matching query: [String: String], in state: AppState) -> Item? {
        if let idString = query["id"], let id = UUID(uuidString: idString) {
            return state.items.first { $0.id == id }
        }
        if let name = query["name"] {
            let wanted = name.lowercased()
            return state.items.first { $0.name.lowercased() == wanted }
        }
        return nil
    }

    private static func boolValue(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return true }
        return !["false", "0", "no", "off"].contains(s)
    }
}

/// Open panel filter: folders (to navigate) and files named auth.json only.
private final class OnlyAuthJSON: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        url.hasDirectoryPath || url.lastPathComponent == "auth.json"
    }
}
