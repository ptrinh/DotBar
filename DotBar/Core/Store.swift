import Foundation

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
    /// battery the battery command prints nothing, so only the two dots show.
    static func defaults() -> [Item] {
        [Recipes.batteryWithLoadDots, Recipes.calendarIcon]
    }
}
