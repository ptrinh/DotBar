import AppKit

/// xbar / SwiftBar compatible inline line parameters.
///
/// A script line may end with ` | key=value key2="quoted value"`. Unknown keys are ignored,
/// so plugins written for xbar keep working even when they use keys DotBar does not render.
struct LineParams: Equatable {
    var color: NSColor? = nil
    var fontName: String? = nil
    var size: Double? = nil
    var href: String? = nil
    var bash: String? = nil
    /// `param1=…paramN=` in index order.
    var bashParams: [String] = []
    /// `terminal=true` runs the command in Terminal.app instead of silently.
    var terminal: Bool = false
    /// `refresh=true` refreshes the owning item after the action ran.
    var refresh: Bool = false
    /// `length=N` truncates the displayed text with an ellipsis.
    var length: Int? = nil
    var trim: Bool = true
    var emojize: Bool = true
    /// SF Symbol drawn before the line.
    var sfimage: String? = nil
    /// `alternate=true`: this line is the ⌥ variant of the previous one.
    var alternate: Bool = false
    /// `dropdown=false`: the line is not shown in the menu.
    var dropdown: Bool = true
    var tooltip: String? = nil
    var checked: Bool = false
    var disabled: Bool = false

    var hasAction: Bool { href != nil || bash != nil }

    /// Full shell command for `bash=` plus its `paramN=` arguments.
    var shellCommand: String? {
        guard let bash, !bash.isEmpty else { return nil }
        var cmd = Self.shellQuote(bash)
        for p in bashParams { cmd += " " + Self.shellQuote(p) }
        return cmd
    }

    static func shellQuote(_ s: String) -> String {
        // A bare word that is obviously already a command line is quoted as a whole only when
        // it contains characters the shell would mangle.
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Parsed line

/// One output line after params, depth markers, emoji shortcodes and ANSI have been resolved.
struct ParsedLine: Equatable {
    /// Submenu nesting: number of leading `--` groups.
    var depth: Int = 0
    var isSeparator: Bool = false
    /// Plain text, ready to display and to copy (params/ANSI stripped, emojized, truncated).
    var text: String = ""
    var runs: [ANSIRun] = []
    var params: LineParams = LineParams()
}

// MARK: - Parser

enum LineParser {

    /// Parse a full output line (bar line or menu line).
    static func parse(_ raw: String, isMenuLine: Bool = true) -> ParsedLine {
        var line = raw
        var out = ParsedLine()

        if isMenuLine {
            let (depth, rest, separator) = stripDepth(line)
            out.depth = depth
            out.isSeparator = separator
            line = rest
            if separator { return out }
        }

        let (body, params) = splitParams(line)
        out.params = params

        var text = body
        if params.trim { text = text.trimmingCharacters(in: .whitespaces) }
        if params.emojize { text = Emoji.emojize(text) }
        out.runs = ANSIParser.parse(text)
        text = out.runs.map(\.text).joined()
        if let n = params.length, n > 0, text.count > n {
            text = String(text.prefix(n)) + "…"
            out.runs = truncateRuns(out.runs, to: n)
        }
        out.text = text
        return out
    }

    /// Cut coloured runs to `n` characters and append the ellipsis to the last surviving run.
    private static func truncateRuns(_ runs: [ANSIRun], to n: Int) -> [ANSIRun] {
        var left = n
        var result: [ANSIRun] = []
        for r in runs {
            if left <= 0 { break }
            if r.text.count <= left {
                result.append(r); left -= r.text.count
            } else {
                result.append(ANSIRun(text: String(r.text.prefix(left)), color: r.color, bold: r.bold))
                left = 0
            }
        }
        if var last = result.last {
            last.text += "…"
            result[result.count - 1] = last
        }
        return result
    }

    // MARK: Depth / separators

    /// Leading `--` groups give the nesting depth. An all-dash line is a separator:
    /// `---` at the top level, `-----` one level in, and so on (`----` stays top level
    /// for backward compatibility).
    static func stripDepth(_ line: String) -> (depth: Int, rest: String, separator: Bool) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, t.allSatisfy({ $0 == "-" }) {
            let n = t.count
            guard n >= 3 else { return (0, line, false) }
            return (max(0, (n - 3) / 2), "", true)
        }
        var depth = 0
        var rest = Substring(t)
        while rest.hasPrefix("--") {
            depth += 1
            rest = rest.dropFirst(2)
        }
        return (depth, String(rest), false)
    }

    // MARK: Params

    /// Split `text | key=value …` into the text and its params. The separator is the last `|`
    /// whose tail parses entirely as `key=value` pairs, so plain pipes in text survive.
    static func splitParams(_ line: String) -> (String, LineParams) {
        let chars = Array(line)
        var idx = chars.count - 1
        while idx >= 0 {
            if chars[idx] == "|" {
                let tail = String(chars[(idx + 1)...])
                if let pairs = keyValuePairs(tail) {
                    return (String(chars[..<idx]), make(from: pairs))
                }
            }
            idx -= 1
        }
        return (line, LineParams())
    }

    /// Tokenize `key=value key2="quoted value"`. Returns nil if anything is not a pair.
    static func keyValuePairs(_ s: String) -> [(String, String)]? {
        var pairs: [(String, String)] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
            if i >= chars.count { break }
            var key = ""
            while i < chars.count, chars[i] != "=", chars[i] != " ", chars[i] != "\t" {
                key.append(chars[i]); i += 1
            }
            guard i < chars.count, chars[i] == "=", !key.isEmpty,
                  key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
            i += 1                                                  // skip '='
            var value = ""
            if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                let quote = chars[i]; i += 1
                while i < chars.count, chars[i] != quote { value.append(chars[i]); i += 1 }
                guard i < chars.count else { return nil }           // unterminated quote
                i += 1
            } else {
                while i < chars.count, chars[i] != " ", chars[i] != "\t" { value.append(chars[i]); i += 1 }
            }
            pairs.append((key.lowercased(), value))
        }
        return pairs.isEmpty ? nil : pairs
    }

    private static func make(from pairs: [(String, String)]) -> LineParams {
        var p = LineParams()
        var indexedParams: [(Int, String)] = []
        for (key, value) in pairs {
            switch key {
            case "color": p.color = color(from: value)
            case "font": p.fontName = value.isEmpty ? nil : value
            case "size": p.size = Double(value)
            case "href": p.href = value.isEmpty ? nil : value
            case "bash", "shell": p.bash = value.isEmpty ? nil : value
            case "terminal": p.terminal = isTrue(value)
            case "refresh": p.refresh = isTrue(value)
            case "length": p.length = Int(value)
            case "trim": p.trim = isTrue(value)
            case "emojize": p.emojize = isTrue(value)
            case "sfimage", "sfimage-": p.sfimage = value.isEmpty ? nil : value
            case "alternate": p.alternate = isTrue(value)
            case "dropdown": p.dropdown = isTrue(value)
            case "tooltip": p.tooltip = value.isEmpty ? nil : value
            case "checked": p.checked = isTrue(value)
            case "disabled": p.disabled = isTrue(value)
            case "md", "symbolize", "templateimage", "image", "ansi", "trim-": break   // accepted, ignored
            default:
                if key.hasPrefix("param"), let n = Int(key.dropFirst(5)) {
                    indexedParams.append((n, value))
                }
            }
        }
        p.bashParams = indexedParams.sorted { $0.0 < $1.0 }.map(\.1)
        return p
    }

    private static func isTrue(_ s: String) -> Bool {
        let v = s.lowercased()
        return v == "true" || v == "yes" || v == "1"
    }

    // MARK: Colors

    /// `red`, `#ff0000`, or a `light,dark` pair like `black,white` resolved per appearance.
    static func color(from value: String) -> NSColor? {
        let parts = value.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.count == 2 {
            guard let light = single(parts[0]), let dark = single(parts[1]) else {
                return single(parts[0]) ?? single(parts[1])
            }
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            }
        }
        return single(value.trimmingCharacters(in: .whitespaces))
    }

    private static func single(_ name: String) -> NSColor? {
        if name.hasPrefix("#") { return NSColor(hex: name) }
        switch name.lowercased() {
        case "red": return NSColor.systemRed
        case "green": return NSColor.systemGreen
        case "blue": return NSColor.systemBlue
        case "orange": return NSColor.systemOrange
        case "yellow": return NSColor.systemYellow
        case "purple": return NSColor.systemPurple
        case "pink": return NSColor.systemPink
        case "teal": return NSColor.systemTeal
        case "indigo": return NSColor.systemIndigo
        case "brown": return NSColor.systemBrown
        case "cyan": return NSColor(srgbRed: 0, green: 0.78, blue: 0.82, alpha: 1)
        case "magenta": return NSColor.magenta
        case "gray", "grey", "silver": return NSColor.systemGray
        case "white": return NSColor.white
        case "black": return NSColor.black
        case "label", "default": return NSColor.labelColor
        default: return NSColor(hex: "#" + name)          // bare "ff0000" still works
        }
    }
}

// MARK: - Emoji shortcodes

enum Emoji {
    /// Replace `:shortcode:` with the emoji. Small built-in table, no dependency.
    static func emojize(_ s: String) -> String {
        guard s.contains(":") else { return s }
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            guard s[i] == ":" else { result.append(s[i]); i = s.index(after: i); continue }
            let after = s.index(after: i)
            if let close = s[after...].firstIndex(of: ":") {
                let name = String(s[after..<close])
                if let e = table[name] {
                    result.append(e)
                    i = s.index(after: close)
                    continue
                }
            }
            result.append(s[i])
            i = after
        }
        return result
    }

    static let table: [String: String] = [
        "smile": "😄", "smiley": "😃", "grin": "😁", "laughing": "😆", "joy": "😂",
        "wink": "😉", "blush": "😊", "sunglasses": "😎", "heart_eyes": "😍",
        "thinking": "🤔", "neutral_face": "😐", "confused": "😕", "cry": "😢",
        "sob": "😭", "rage": "😡", "scream": "😱", "sleeping": "😴", "skull": "💀",
        "ghost": "👻", "robot": "🤖", "alien": "👽", "poop": "💩",
        "thumbsup": "👍", "+1": "👍", "thumbsdown": "👎", "-1": "👎",
        "ok_hand": "👌", "clap": "👏", "wave": "👋", "pray": "🙏", "muscle": "💪",
        "eyes": "👀", "point_right": "👉", "raised_hands": "🙌",
        "heart": "❤️", "broken_heart": "💔", "star": "⭐️", "star2": "🌟",
        "sparkles": "✨", "fire": "🔥", "boom": "💥", "zap": "⚡️", "bulb": "💡",
        "rocket": "🚀", "tada": "🎉", "gift": "🎁", "bell": "🔔",
        "warning": "⚠️", "exclamation": "❗️", "question": "❓",
        "white_check_mark": "✅", "heavy_check_mark": "✔️", "x": "❌", "no_entry": "⛔️",
        "red_circle": "🔴", "large_blue_circle": "🔵", "green_circle": "🟢",
        "yellow_circle": "🟡", "orange_circle": "🟠", "purple_circle": "🟣",
        "white_circle": "⚪️", "black_circle": "⚫️",
        "computer": "💻", "desktop_computer": "🖥", "iphone": "📱", "battery": "🔋",
        "electric_plug": "🔌", "floppy_disk": "💾", "cd": "💿", "lock": "🔒",
        "unlock": "🔓", "key": "🔑", "mag": "🔍", "wrench": "🔧", "hammer": "🔨",
        "gear": "⚙️", "package": "📦", "memo": "📝", "chart_with_upwards_trend": "📈",
        "chart_with_downwards_trend": "📉", "bar_chart": "📊", "calendar": "📅",
        "clock": "🕐", "hourglass": "⌛️", "coffee": "☕️", "beer": "🍺", "pizza": "🍕",
        "sunny": "☀️", "cloud": "☁️", "rain_cloud": "🌧", "snowflake": "❄️",
        "moon": "🌙", "earth_americas": "🌎", "house": "🏠", "car": "🚗",
        "airplane": "✈️", "bug": "🐛", "snake": "🐍", "cat": "🐱", "dog": "🐶",
        "whale": "🐳", "penguin": "🐧", "apple": "🍎", "money_with_wings": "💸",
        "dollar": "💵", "credit_card": "💳", "email": "📧", "phone": "📞",
    ]
}
