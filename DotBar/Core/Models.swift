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
    var notify: NotifySpec = .off
    var hotkey: Hotkey? = nil

    var refreshSeconds: Int {
        if case .script(_, let s) = source { return s }
        return 0
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

    var isScript: Bool { if case .script = self { return true } else { return false } }
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
    var text: String = ""
    var overrideColor: HexColor? = nil
    var overrideDots: [HexColor]? = nil
    var failed: Bool = false
    var errorMessage: String? = nil
    var updatedAt: Date? = nil

    /// Parse plain text or JSON `{"text":..,"color":..,"dots":[..]}`.
    static func parse(_ raw: String, failed: Bool = false, error: String? = nil) -> ScriptOutput {
        var out = ScriptOutput(raw: raw, text: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                               failed: failed, errorMessage: error, updatedAt: Date())
        let trimmed = out.text
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = obj["text"] as? String { out.text = t }
            else if let t = obj["text"] as? NSNumber { out.text = t.stringValue }
            if let c = obj["color"] as? String { out.overrideColor = c }
            if let d = obj["dots"] as? [String] { out.overrideDots = d }
        }
        return out
    }

    /// First number found in text.
    var number: Double? {
        let pattern = #"-?\d+(?:[.,]\d+)?"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(text[r].replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - Item decoding (backward compatible)

extension Item {
    enum CodingKeys: String, CodingKey {
        case id, name, enabled, source, font, textColor, dots, dotsPosition, action, notify, hotkey
    }

    /// Every field is optional on the way in so older items.json files keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? source
        font = try c.decodeIfPresent(FontSpec.self, forKey: .font) ?? font
        textColor = try c.decodeIfPresent(ColorSpec.self, forKey: .textColor) ?? textColor
        dots = try c.decodeIfPresent([Dot].self, forKey: .dots) ?? dots
        dotsPosition = try c.decodeIfPresent(DotsPosition.self, forKey: .dotsPosition) ?? dotsPosition
        action = try c.decodeIfPresent(ClickAction.self, forKey: .action) ?? action
        notify = try c.decodeIfPresent(NotifySpec.self, forKey: .notify) ?? .off
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
    }
}
