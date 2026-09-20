import Foundation

enum Store {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DotBar", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("items.json") }

    static func load() -> [Item] {
        guard let data = try? Data(contentsOf: fileURL) else { return defaults() }
        do { return try decoder.decode([Item].self, from: data) }
        catch { NSLog("DotBar: failed to decode items: \(error)"); return defaults() }
    }

    static func save(_ items: [Item]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch { NSLog("DotBar: failed to save: \(error)") }
    }

    static func export(_ items: [Item], to url: URL) throws {
        try encoder.encode(items).write(to: url, options: .atomic)
    }

    static func importItems(from url: URL) throws -> [Item] {
        try decoder.decode([Item].self, from: Data(contentsOf: url))
    }

    static var encoder: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
    static var decoder: JSONDecoder { JSONDecoder() }

    static func defaults() -> [Item] {
        var cpu = Item(name: "CPU Load",
                       source: .script(command: #"uptime | sed -E 's/.*load averages?: ([0-9.,]+).*/\1/'"#, refreshSeconds: 10))
        cpu.dots = [Dot(source: .mainValue, color: .rules([
            Rule(condition: .numberInRange(min: nil, max: 2), color: "#34C759"),
            Rule(condition: .numberInRange(min: 2, max: 6), color: "#FF9F0A"),
            Rule(condition: .numberInRange(min: 6, max: nil), color: "#FF453A"),
            Rule(condition: .scriptFailed, color: "#FF453A"),
        ], fallback: "#8E8E93"))]
        return [cpu]
    }
}
