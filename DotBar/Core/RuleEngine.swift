import AppKit

enum RuleEngine {
    static func color(for spec: ColorSpec, output: ScriptOutput?) -> NSColor? {
        switch spec {
        case .fixed(let hex):
            return NSColor(hex: hex)
        case .rules(let rules, let fallback):
            guard let output else { return NSColor(hex: fallback) }
            for rule in rules where matches(rule.condition, output) {
                return NSColor(hex: rule.color)
            }
            return NSColor(hex: fallback)
        }
    }

    static func matches(_ c: Condition, _ o: ScriptOutput) -> Bool {
        switch c {
        case .scriptFailed:
            return o.failed
        case .isEmpty:
            return o.text.isEmpty
        case .numberInRange(let min, let max):
            guard let n = o.number else { return false }
            if let min, n < min { return false }
            if let max, n > max { return false }
            return true
        case .regex(let pattern):
            guard !pattern.isEmpty else { return false }
            return o.text.range(of: pattern, options: .regularExpression) != nil
        case .contains(let t):
            return !t.isEmpty && o.text.localizedCaseInsensitiveContains(t)
        case .equals(let t):
            return o.text == t
        }
    }
}

extension NSColor {
    /// Parses "#RGB", "#RRGGBB", "#RRGGBBAA". nil / invalid -> nil.
    convenience init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int(round(c.redComponent * 255)), g = Int(round(c.greenComponent * 255)), b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
