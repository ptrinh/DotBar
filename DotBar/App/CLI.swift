import Foundation

/// `dotbar` command line, for people and AI agents editing DotBar from a terminal.
///
/// Runs inside the app binary: invoked through a symlink named exactly `dotbar`, or as
/// `DotBar cli …`. It reads and writes items.json directly (validated, with a backup); a
/// running DotBar picks the change up through its file watcher.
enum CLI {
    /// Exit code when this process was started as the CLI, nil to launch the app normally.
    static func runIfInvoked() -> Int32? {
        var args = CommandLine.arguments
        let exe = URL(fileURLWithPath: args.removeFirst()).lastPathComponent
        if exe == "dotbar" { return run(args) }                 // case-sensitive: the app binary is "DotBar"
        if args.first == "cli" { return run(Array(args.dropFirst())) }
        return nil
    }

    static let usage = """
    dotbar — edit DotBar items from the terminal. Changes apply to a running DotBar at once.

      dotbar list [--json]                 items in bar order
      dotbar get <item>                    one item as JSON
      dotbar recipes [--json]              built-in presets
      dotbar add --recipe <name>           add a preset
      dotbar add --json <json|->           add an item (fields you omit get their defaults)
      dotbar update <item> --json <json|-> merge fields into an item (JSON merge patch)
      dotbar enable|disable <item>
      dotbar remove <item>
      dotbar test <item|command> [--json]  run it and show how DotBar reads the output
      dotbar usage <claude|codex>          AI session / weekly usage as DotBar JSON
      dotbar schema                        JSON Schema of items.json
      dotbar path                          location of items.json

    <item> is a name (case-insensitive) or an id (a unique prefix is enough).
    Writes are validated first and back up the previous file to items.json.bak.
    """

    struct Failure: Error { let message: String; var code: Int32 = 1 }

    static func run(_ args: [String]) -> Int32 {
        do {
            try dispatch(args)
            return 0
        } catch let f as Failure {
            FileHandle.standardError.write(Data("dotbar: \(f.message)\n".utf8))
            return f.code
        } catch {
            FileHandle.standardError.write(Data("dotbar: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func dispatch(_ args: [String]) throws {
        guard let cmd = args.first else { print(usage); return }
        var rest = Array(args.dropFirst())
        // `--json` is an output switch for the read commands, and takes a value for add / update.
        let json = ["list", "recipes", "test"].contains(cmd) && take("--json", flagIn: &rest)
        switch cmd {
        case "help", "-h", "--help": print(usage)
        case "path": print(Store.fileURL.path)
        case "schema": print(try schema())
        case "list": try list(json: json)
        case "get": try emit(itemObject(try find(one(rest))))
        case "recipes":
            let names = Recipes.all().map(\.name)
            json ? try emit(names) : print(names.joined(separator: "\n"))
        case "add": try add(rest)
        case "update": try update(rest)
        case "enable", "disable":
            let target = try find(one(rest))
            try mutate { items in items[index(of: target, in: items)].enabled = cmd == "enable" }
            print("\(cmd)d \(target.name)")
        case "remove":
            let target = try find(one(rest))
            try mutate { items in items.remove(at: index(of: target, in: items)) }
            print("removed \(target.name)")
        case "test": try test(rest, json: json)
        case "usage": print(AIUsage.output(for: try one(rest)))
        default: throw Failure(message: "unknown command \"\(cmd)\"\n\n\(usage)", code: 2)
        }
    }

    // MARK: Read

    private static func load() throws -> [Item] {
        guard let data = try? Data(contentsOf: Store.fileURL) else { return Store.defaults() }
        do { return try Store.decoder.decode([Item].self, from: data) }
        catch { throw Failure(message: "items.json does not decode: \(error)") }
    }

    private static func list(json: Bool) throws {
        let items = try load()
        if json { try emit(items.map(itemObject)); return }
        for (i, it) in items.enumerated() {
            let kind: String
            switch it.source {
            case .static: kind = "static"
            case .script(_, let s): kind = s > 0 ? "every \(s)s" : "manual"
            case .stream: kind = "stream"
            }
            let dots = it.dots.isEmpty ? "" : " · \(it.dots.count) dot\(it.dots.count == 1 ? "" : "s")"
            print("\(i + 1). \(it.enabled ? "✓" : "–") \(it.name)  [\(kind)\(dots)]  \(it.id.uuidString.prefix(8))")
        }
    }

    private static func find(_ key: String) throws -> Item {
        let items = try load()
        if let it = items.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame }) { return it }
        if let it = items.first(where: { $0.name == key }) { return it }
        var matches = items.filter { $0.name.caseInsensitiveCompare(key) == .orderedSame }
        if matches.isEmpty, key.count >= 4 {
            matches = items.filter { $0.id.uuidString.lowercased().hasPrefix(key.lowercased()) }
        }
        guard matches.count == 1 else {
            throw Failure(message: matches.isEmpty ? "no item \"\(key)\" (see `dotbar list`)"
                                                   : "\"\(key)\" matches \(matches.count) items; use the id")
        }
        return matches[0]
    }

    private static func index(of item: Item, in items: [Item]) -> Int {
        items.firstIndex { $0.id == item.id }!
    }

    private static func schema() throws -> String {
        // Resolve the symlink first: Bundle.main does not find the bundle from a link in /usr/local/bin.
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundled = exe.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/items.schema.json")
        guard let s = try? String(contentsOf: bundled, encoding: .utf8) else {
            throw Failure(message: "schema not found at \(bundled.path)")
        }
        return s
    }

    // MARK: Write

    private static func add(_ rest: [String]) throws {
        var rest = rest
        var item: Item
        if let name = take("--recipe", valueIn: &rest) {
            guard let r = Recipes.all().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw Failure(message: "no preset \"\(name)\" (see `dotbar recipes`)")
            }
            item = r
        } else if let raw = take("--json", valueIn: &rest) {
            var obj = try object(from: raw)
            obj["id"] = UUID().uuidString                       // a copy of an existing item must not share its id
            item = try decodeItem(obj)
        } else {
            throw Failure(message: "add needs --recipe <name> or --json <json|->", code: 2)
        }
        try mutate { $0.append(item) }
        print("added \(item.name)  \(item.id.uuidString.prefix(8))")
    }

    private static func update(_ rest: [String]) throws {
        var rest = rest
        guard let raw = take("--json", valueIn: &rest) else {
            throw Failure(message: "update needs --json <json|->", code: 2)
        }
        let target = try find(one(rest))
        var obj = itemObject(target)
        let patch = try object(from: raw)
        guard patch["id"] == nil || (patch["id"] as? String) == target.id.uuidString else {
            throw Failure(message: "the id cannot be changed")
        }
        merge(patch, into: &obj)
        let updated = try decodeItem(obj)
        try mutate { items in items[index(of: target, in: items)] = updated }
        print("updated \(updated.name)")
    }

    /// JSON merge patch, with one DotBar rule: two single-key objects with different keys are
    /// different enum cases (`{"static":…}` → `{"script":…}`), so the patch replaces instead of merging.
    private static func merge(_ patch: [String: Any], into obj: inout [String: Any]) {
        for (k, v) in patch {
            if v is NSNull { obj.removeValue(forKey: k); continue }
            if let pv = v as? [String: Any], var ov = obj[k] as? [String: Any],
               !(pv.count == 1 && ov.count == 1 && pv.keys.first != ov.keys.first) {
                merge(pv, into: &ov)
                obj[k] = ov
            } else {
                obj[k] = v
            }
        }
    }

    /// Validate, back up, write atomically. The running app reloads on its own.
    private static func mutate(_ change: (inout [Item]) throws -> Void) throws {
        var items = try load()
        try change(&items)
        let data = try Store.encoder.encode(items)
        _ = try Store.decoder.decode([Item].self, from: data)   // round-trip before touching the file
        let fm = FileManager.default
        try fm.createDirectory(at: Store.directory, withIntermediateDirectories: true)
        let backup = Store.fileURL.appendingPathExtension("bak")
        if fm.fileExists(atPath: Store.fileURL.path) {
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: Store.fileURL, to: backup)
        }
        try data.write(to: Store.fileURL, options: .atomic)
    }

    // MARK: Test

    private static func test(_ rest: [String], json: Bool) throws {
        let arg = try one(rest)
        var runs: [(label: String, command: String, isMenu: Bool)] = []
        if let item = try? find(arg) {
            if let c = item.source.command { runs.append(("command", c, false)) }
            else if case .static(let t) = item.source { runs.append(("static", "printf %s \(LineParams.shellQuote(t))", false)) }
            if !item.menuCommand.isEmpty { runs.append(("menuCommand", item.menuCommand, true)) }
        } else {
            runs.append(("command", arg, false))
        }
        var reports: [[String: Any]] = []
        for r in runs {
            let t0 = Date()
            let out = ScriptRunner.runSync(r.command, timeout: 15)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            var rep: [String: Any] = ["run": r.label, "ms": ms, "failed": out.failed]
            if let e = out.errorMessage { rep["error"] = e }
            // menuCommand output is menu lines only; a script's first line is the bar.
            let lines = r.isMenu ? nonEmptyLines(out.raw) : out.menuLines
            if !r.isMenu {
                var bar: [String: Any] = ["text": out.text]
                if let s = out.symbol ?? out.barParams.sfimage { bar["symbol"] = s }
                if let c = out.overrideColor { bar["color"] = c }
                if let d = out.overrideDots { bar["dots"] = d }
                if let b = out.badge { bar["badge"] = b }
                if let m = out.displayModeOverride { bar["mode"] = m.rawValue }
                if let n = out.number { bar["number"] = n }
                if out.barParams.hasAction { bar["action"] = out.barParams.href ?? out.barParams.shellCommand ?? "" }
                rep["bar"] = bar
            }
            rep["menu"] = lines.map { line -> [String: Any] in
                let pl = LineParser.parse(line)
                var m: [String: Any] = ["depth": pl.depth]
                if pl.isSeparator { m["separator"] = true; return m }
                m["text"] = pl.text
                if let h = pl.params.href { m["click"] = "open \(h)" }
                else if let c = pl.params.shellCommand { m["click"] = "run \(c)" }
                else { m["click"] = "copy text" }
                if !pl.params.dropdown { m["hidden"] = true }
                return m
            }
            reports.append(rep)
        }
        if json { try emit(reports); return }
        for rep in reports { printReport(rep) }
    }

    private static func printReport(_ rep: [String: Any]) {
        let failed = rep["failed"] as? Bool ?? false
        print("\(rep["run"]!)  \(rep["ms"]!) ms\(failed ? "  FAILED: \(rep["error"] ?? "")" : "")")
        if let bar = rep["bar"] as? [String: Any] {
            let extras = bar.filter { $0.key != "text" }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            print("  bar   \"\(bar["text"] ?? "")\"" + (extras.isEmpty ? "" : "  " + extras.joined(separator: "  ")))
        }
        for m in rep["menu"] as? [[String: Any]] ?? [] {
            let indent = String(repeating: "    ", count: m["depth"] as? Int ?? 0)
            if m["separator"] != nil { print("  menu  \(indent)──────"); continue }
            print("  menu  \(indent)\(m["text"] ?? "")   → \(m["click"] ?? "")")
        }
    }

    // MARK: Helpers

    private static func one(_ rest: [String]) throws -> String {
        guard rest.count == 1 else { throw Failure(message: "expected one <item> argument\n\n\(usage)", code: 2) }
        return rest[0]
    }

    private static func take(_ flag: String, flagIn args: inout [String]) -> Bool {
        guard let i = args.firstIndex(of: flag) else { return false }
        args.remove(at: i)
        return true
    }

    private static func take(_ flag: String, valueIn args: inout [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        args.removeSubrange(i...i + 1)
        return v
    }

    /// JSON object from an argument, or from stdin when the argument is "-".
    private static func object(from raw: String) throws -> [String: Any] {
        let text = raw == "-" ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : raw
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw Failure(message: "--json must be a JSON object")
        }
        return obj
    }

    private static func decodeItem(_ obj: [String: Any]) throws -> Item {
        let data = try JSONSerialization.data(withJSONObject: obj)
        do { return try Store.decoder.decode(Item.self, from: data) }
        catch { throw Failure(message: "not a valid item: \(error) (see `dotbar schema`)") }
    }

    private static func itemObject(_ item: Item) -> [String: Any] {
        let data = (try? Store.encoder.encode(item)) ?? Data("{}".utf8)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func emit(_ value: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func nonEmptyLines(_ s: String) -> [String] {
        var lines = s.components(separatedBy: .newlines)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines
    }
}
