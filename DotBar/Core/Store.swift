import Foundation
import Security

enum Store {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DotBar", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("items.json") }
    /// Scratch space for user scripts; items referring to a file in here are refreshed on change.
    static var scriptsDirectory: URL { directory.appendingPathComponent("scripts", isDirectory: true) }

    /// Fingerprint (content hash + modification date) of the last items.json this process
    /// read or wrote, so the file watcher can tell an external edit from our own save.
    private static var fingerprint: (hash: Int, modified: Date?) = (0, nil)

    static func load() -> [Item] {
        guard let data = try? Data(contentsOf: fileURL) else { return defaults() }
        note(data)
        do { return try decoder.decode([Item].self, from: data) }
        catch { NSLog("DotBar: failed to decode items: \(error)"); return defaults() }
    }

    static func save(_ items: [Item]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
            note(data)
        } catch { NSLog("DotBar: failed to save: \(error)") }
    }

    static func ensureScriptsDirectory() {
        try? FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
    }

    /// Items from disk, but only when the file differs from what we last read or wrote.
    /// Returns nil for our own writes (and for touches that did not change the content).
    static func loadIfChangedExternally() -> [Item]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let current = (data.hashValue, modificationDate())
        guard current.0 != fingerprint.hash || current.1 != fingerprint.modified else { return nil }
        guard let items = try? decoder.decode([Item].self, from: data) else {
            NSLog("DotBar: items.json changed on disk but could not be decoded")
            return nil
        }
        note(data)
        return items
    }

    private static func note(_ data: Data) {
        fingerprint = (data.hashValue, modificationDate())
    }

    private static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
    }

    static func export(_ items: [Item], to url: URL) throws {
        try encoder.encode(items).write(to: url, options: .atomic)
    }

    static func importItems(from url: URL) throws -> [Item] {
        try decoder.decode([Item].self, from: Data(contentsOf: url))
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    static let decoder = JSONDecoder()

    /// First launch: battery icon with CPU/RAM dots, plus the calendar icon. On a Mac without a
    /// battery the battery command prints nothing, so only the two dots show. The AI usage icon
    /// is added when a supported AI sign-in is found.
    static func defaults() -> [Item] {
        var items = [Recipes.batteryWithLoadDots, Recipes.calendarIcon]
        if let ai = detectedAIUsageItem() { items.append(ai) }
        return items
    }

    /// First supported AI sign-in found, in priority order: Claude, then Codex (ChatGPT).
    /// Gemini slots in here once it has a usage source.
    private static func detectedAIUsageItem() -> Item? {
        guard !Recipes.isSandboxed else { return nil }        // the recipes read other apps' sign-ins
        if hasClaudeCodeSignIn { return Recipes.aiUsage }
        if hasCodexSignIn { return Recipes.codexUsage }
        return nil
    }

    /// Codex CLI signed in with ChatGPT (existence only; the token is not read here).
    private static var hasCodexSignIn: Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        return FileManager.default.fileExists(atPath: file.path)
    }

    /// Claude Code's sign-in exists (Keychain item or credentials file). Attributes only: the
    /// secret is never read here, so no Keychain prompt.
    private static var hasClaudeCodeSignIn: Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "Claude Code-credentials",
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess { return true }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        return FileManager.default.fileExists(atPath: file.path)
    }
}
