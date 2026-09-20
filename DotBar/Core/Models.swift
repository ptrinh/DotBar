import Foundation

// MARK: - Item

struct Item: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Item"
    var enabled: Bool = true
    var source: Source = .static(text: "Hello")
    var font: FontSpec = FontSpec()
    var textColor: ColorSpec = .fixed(nil)
    var dots: [Dot] = []
    var dotsPosition: DotsPosition = .trailing
    var action: ClickAction = .menu
    /// SF Symbol drawn before the text. Overridden by a `"symbol"` key in JSON output.
    var symbol: String? = nil
    /// Max width of the status item text in points. 0 = unlimited.
    var maxWidth: Double = 0
    var notify: NotifySpec = .off
    var hotkey: Hotkey? = nil
    /// Hide the status item entirely while the output text is empty and no dots are overridden.
    var hideWhenEmpty: Bool = false

    /// 0 for static text and for streams — a stream pushes updates itself, so it has no timer.
    var refreshSeconds: Int {
        if case .script(_, let s) = source { return s }
        return 0
    }

    var isStream: Bool { source.isStream }

    init(id: UUID = UUID(), name: String = "New Item", enabled: Bool = true,
         source: Source = .static(text: "Hello"), font: FontSpec = FontSpec(),
         textColor: ColorSpec = .fixed(nil), dots: [Dot] = [],
         dotsPosition: DotsPosition = .trailing, action: ClickAction = .menu,
         symbol: String? = nil, maxWidth: Double = 0,
         notify: NotifySpec = .off, hotkey: Hotkey? = nil,
         hideWhenEmpty: Bool = false) {
        self.id = id; self.name = name; self.enabled = enabled; self.source = source
        self.font = font; self.textColor = textColor; self.dots = dots
        self.dotsPosition = dotsPosition; self.action = action
        self.symbol = symbol; self.maxWidth = maxWidth
        self.notify = notify; self.hotkey = hotkey
        self.hideWhenEmpty = hideWhenEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, source, font, textColor, dots, dotsPosition, action, symbol, maxWidth, notify, hotkey
        case hideWhenEmpty
    }

    /// Everything is optional with a default so older items.json files keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "New Item"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .static(text: "")
        font = try c.decodeIfPresent(FontSpec.self, forKey: .font) ?? FontSpec()
        textColor = try c.decodeIfPresent(ColorSpec.self, forKey: .textColor) ?? .fixed(nil)
        dots = try c.decodeIfPresent([Dot].self, forKey: .dots) ?? []
        dotsPosition = try c.decodeIfPresent(DotsPosition.self, forKey: .dotsPosition) ?? .trailing
        action = try c.decodeIfPresent(ClickAction.self, forKey: .action) ?? .menu
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        maxWidth = try c.decodeIfPresent(Double.self, forKey: .maxWidth) ?? 0
        notify = try c.decodeIfPresent(NotifySpec.self, forKey: .notify) ?? .off
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        hideWhenEmpty = try c.decodeIfPresent(Bool.self, forKey: .hideWhenEmpty) ?? false
    }
}

/// When to raise a user notification for an item.
enum NotifySpec: String, Codable, CaseIterable, Identifiable {
    case off, onTextChange, onDotColorChange, onAnyChange
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Never"
        case .onTextChange: return "When text changes"
        case .onDotColorChange: return "When a dot color changes"
        case .onAnyChange: return "When text or a dot changes"
        }
    }
}

/// Carbon key code + Carbon modifier flags (cmdKey/optionKey/controlKey/shiftKey).
struct Hotkey: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32
}

enum Source: Codable, Hashable {
    case `static`(text: String)
    case script(command: String, refreshSeconds: Int)
    /// SwiftBar-style "streamable": one long-lived process whose stdout is read block by block.
    case stream(command: String)

    /// True for anything that runs a command — the UI treats a stream like a script with no interval.
    var isScript: Bool {
        switch self { case .script, .stream: return true; case .static: return false }
    }

    var isStream: Bool { if case .stream = self { return true } else { return false } }

    /// The command line, for scripts and streams alike.
    var command: String? {
        switch self {
        case .static: return nil
        case .script(let c, _): return c
        case .stream(let c): return c
        }
    }
}

enum DotsPosition: String, Codable, CaseIterable {
    case leading, trailing
}

enum ClickAction: Codable, Hashable {
    case menu
    case copy
    case script(command: String)
    case openURL(url: String)
}

// MARK: - Dot

struct Dot: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var source: DotSource = .mainValue
    var color: ColorSpec = .rules([], fallback: "#8E8E93")
}

enum DotSource: Codable, Hashable {
    case mainValue
    case script(command: String, refreshSeconds: Int)
}

// MARK: - Colors & Rules

/// Hex color like "#RRGGBB" or "#RRGGBBAA". nil = system label color.
typealias HexColor = String

enum ColorSpec: Codable, Hashable {
    case fixed(HexColor?)
    case rules([Rule], fallback: HexColor?)
}

struct Rule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var condition: Condition = .numberInRange(min: nil, max: nil)
    var color: HexColor = "#34C759"
}

enum Condition: Codable, Hashable {
    case numberInRange(min: Double?, max: Double?)
    case regex(pattern: String)
    case contains(text: String)
    case equals(text: String)
    case isEmpty
    case scriptFailed

    var kind: Kind {
        switch self {
        case .numberInRange: return .numberInRange
        case .regex: return .regex
        case .contains: return .contains
        case .equals: return .equals
        case .isEmpty: return .isEmpty
        case .scriptFailed: return .scriptFailed
        }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case numberInRange = "Number in range"
        case regex = "Regex matches"
        case contains = "Contains"
        case equals = "Equals"
        case isEmpty = "Is empty"
        case scriptFailed = "Script failed"
        var id: String { rawValue }

        func makeDefault() -> Condition {
            switch self {
            case .numberInRange: return .numberInRange(min: nil, max: nil)
            case .regex: return .regex(pattern: "")
            case .contains: return .contains(text: "")
            case .equals: return .equals(text: "")
            case .isEmpty: return .isEmpty
            case .scriptFailed: return .scriptFailed
            }
        }
    }
}

// MARK: - Font

struct FontSpec: Codable, Hashable {
    /// nil = system font
    var family: String? = nil
    var size: Double = 13
    var weight: Weight = .regular
    var monospacedDigits: Bool = true

    enum Weight: String, Codable, CaseIterable {
        case light, regular, medium, semibold, bold
    }
}

// MARK: - Runtime output (not persisted)

struct ScriptOutput: Equatable {
    var raw: String = ""
    /// Bar text, ANSI-stripped so rules and number parsing keep working.
    var text: String = ""
    /// Coloured runs for `text` (single plain run when the output has no ANSI codes).
    var textRuns: [ANSIRun] = []
    /// Extra output lines shown at the top of the menu. "----" / "---" means a separator.
    /// Kept raw: xbar-style `| key=value` params and `--` nesting are parsed when the menu is built.
    var menuLines: [String] = []
    /// xbar-style params of the bar line (`color=`, `sfimage=`, `href=`, `bash=`, `length=`, …).
    var barParams: LineParams = LineParams()
    var overrideColor: HexColor? = nil
    var overrideDots: [HexColor]? = nil
    /// SF Symbol name from JSON `"symbol"`.
    var symbol: String? = nil
    /// JSON `"refresh"`: refresh interval in seconds for this item until an output without it.
    var refreshOverride: Int? = nil
    /// JSON `"action"`: overrides the item's left-click action.
    var actionOverride: ClickAction? = nil
    var failed: Bool = false
    var errorMessage: String? = nil
    var updatedAt: Date? = nil

    static let separatorToken = "----"

    static func isSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "----" || t == "---"
    }

    /// Parse script output.
    ///
    /// Plain text: first non-empty line is the bar text, the rest become `menuLines`.
    /// JSON object: `{"text":..,"color":..,"dots":[..],"menu":[..],"symbol":..,"refresh":..,"action":..}`.
    static func parse(_ raw: String, failed: Bool = false, error: String? = nil) -> ScriptOutput {
        var out = ScriptOutput(raw: raw, failed: failed, errorMessage: error, updatedAt: Date())
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = obj["text"] as? String { out.text = t }
            else if let t = obj["text"] as? NSNumber { out.text = t.stringValue }
            if let c = obj["color"] as? String { out.overrideColor = c }
            if let d = obj["dots"] as? [String] { out.overrideDots = d }
            if let m = obj["menu"] as? [String] { out.menuLines = m }
            if let sym = obj["symbol"] as? String, !sym.isEmpty { out.symbol = sym }
            if let r = obj["refresh"] as? NSNumber, r.intValue > 0 { out.refreshOverride = r.intValue }
            else if let r = obj["refresh"] as? String, let v = Int(r), v > 0 { out.refreshOverride = v }
            out.actionOverride = parseAction(obj["action"])
        } else {
            var lines = raw.components(separatedBy: .newlines)
            var barLine = ""
            if let idx = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                barLine = lines[idx]
                lines.removeFirst(idx + 1)
            } else {
                lines = []
            }
            // Drop trailing blank lines, keep the inner ones (they may be deliberate spacers).
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            out.menuLines = lines

            // xbar-style inline params on the bar line: text is stripped of them.
            let parsed = LineParser.parse(barLine, isMenuLine: false)
            out.barParams = parsed.params
            out.text = parsed.text
            out.textRuns = parsed.runs
            return out
        }

        out.textRuns = ANSIParser.parse(out.text)
        out.text = out.textRuns.map(\.text).joined()
        return out
    }

    private static func parseAction(_ any: Any?) -> ClickAction? {
        if let s = any as? String {
            switch s.lowercased() {
            case "copy": return .copy
            case "menu": return .menu
            default: return nil
            }
        }
        if let d = any as? [String: Any] {
            if let u = d["url"] as? String, !u.isEmpty { return .openURL(url: u) }
            if let c = d["script"] as? String, !c.isEmpty { return .script(command: c) }
        }
        return nil
    }

    /// First number found in text.
    var number: Double? {
        let pattern = #"-?\d+(?:[.,]\d+)?"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(text[r].replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - Item decoding (backward compatible)

