import AppKit

/// One stretch of text sharing the same SGR attributes.
struct ANSIRun: Equatable {
    var text: String
    var color: NSColor?
    var bold: Bool
}

/// Minimal ANSI SGR (Select Graphic Rendition) parser: enough for colored script output.
///
/// Understands the real ESC introducer plus the literal forms scripts often emit unescaped
/// (`\e[`, `\033[`, `\x1b[`). Non-SGR CSI sequences are dropped, never rendered.
enum ANSIParser {

    // MARK: Public

    /// Splits `s` into runs. Always returns at least one run for non-empty input.
    static func parse(_ s: String) -> [ANSIRun] {
        guard containsCodes(s) else { return s.isEmpty ? [] : [ANSIRun(text: s, color: nil, bold: false)] }

        var runs: [ANSIRun] = []
        var buffer = ""
        var color: NSColor?
        var bold = false
        let chars = Array(s)
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(ANSIRun(text: buffer, color: color, bold: bold))
            buffer = ""
        }

        while i < chars.count {
            guard let skip = introducerLength(chars, i) else {
                buffer.append(chars[i]); i += 1; continue
            }
            // Collect parameter bytes until the final letter.
            var j = i + skip
            var params = ""
            while j < chars.count, !chars[j].isLetter { params.append(chars[j]); j += 1 }
            guard j < chars.count else { break }          // truncated sequence: drop the tail
            let final = chars[j]
            if final == "m" {
                flush()
                apply(params, color: &color, bold: &bold)
            }
            i = j + 1                                     // non-SGR CSI: swallowed
        }
        flush()
        return runs
    }

    /// Text with every ANSI sequence removed.
    static func strip(_ s: String) -> String {
        guard containsCodes(s) else { return s }
        return parse(s).map(\.text).joined()
    }

    static func containsCodes(_ s: String) -> Bool {
        s.contains("\u{1B}[") || s.contains("\\e[") || s.contains("\\033[") || s.contains("\\x1b[")
    }

    // MARK: Private

    /// Number of characters the CSI introducer at `i` occupies, or nil if there isn't one.
    private static func introducerLength(_ c: [Character], _ i: Int) -> Int? {
        if c[i] == "\u{1B}" { return i + 1 < c.count && c[i + 1] == "[" ? 2 : nil }
        guard c[i] == "\\" else { return nil }
        if matches(c, i + 1, "e[") { return 3 }
        if matches(c, i + 1, "033[") { return 5 }
        if matches(c, i + 1, "x1b[") || matches(c, i + 1, "x1B[") { return 5 }
        return nil
    }

    private static func matches(_ c: [Character], _ start: Int, _ s: String) -> Bool {
        let t = Array(s)
        guard start + t.count <= c.count else { return false }
        for k in 0..<t.count where c[start + k] != t[k] { return false }
        return true
    }

    private static func apply(_ params: String, color: inout NSColor?, bold: inout Bool) {
        let codes = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        if codes.isEmpty { color = nil; bold = false; return }   // bare "\e[m" == reset
        var k = 0
        while k < codes.count {
            let c = codes[k]
            switch c {
            case 0: color = nil; bold = false
            case 1: bold = true
            case 22: bold = false
            case 30...37: color = standard(c - 30, bright: false)
            case 90...97: color = standard(c - 90, bright: true)
            case 39: color = nil
            case 38:
                if k + 1 < codes.count, codes[k + 1] == 5, k + 2 < codes.count {
                    color = xterm256(codes[k + 2]); k += 2
                } else if k + 1 < codes.count, codes[k + 1] == 2, k + 4 < codes.count {
                    color = rgb(codes[k + 2], codes[k + 3], codes[k + 4]); k += 4
                }
            case 48:                                              // background: parsed, ignored
                if k + 1 < codes.count, codes[k + 1] == 5 { k += 2 }
                else if k + 1 < codes.count, codes[k + 1] == 2 { k += 4 }
            default: break                                        // italic/underline/bg: ignored
            }
            k += 1
        }
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(min(255, max(0, r))) / 255,
                green: CGFloat(min(255, max(0, g))) / 255,
                blue: CGFloat(min(255, max(0, b))) / 255, alpha: 1)
    }

    /// The 8 basic colours, tuned a little brighter than the classic values so they stay
    /// readable on both light and dark menu bars.
    private static func standard(_ i: Int, bright: Bool) -> NSColor? {
        switch i {
        case 0: return bright ? rgb(128, 128, 128) : rgb(90, 90, 90)      // black -> grey
        case 1: return bright ? rgb(255, 105, 97) : rgb(215, 58, 48)
        case 2: return bright ? rgb(80, 220, 100) : rgb(40, 160, 70)
        case 3: return bright ? rgb(255, 200, 60) : rgb(190, 145, 20)
        case 4: return bright ? rgb(100, 160, 255) : rgb(50, 100, 220)
        case 5: return bright ? rgb(230, 130, 240) : rgb(175, 70, 190)
        case 6: return bright ? rgb(90, 215, 220) : rgb(30, 160, 165)
        case 7: return bright ? rgb(240, 240, 240) : rgb(180, 180, 180)
        default: return nil
        }
    }

    private static func xterm256(_ n: Int) -> NSColor? {
        switch n {
        case 0...7: return standard(n, bright: false)
        case 8...15: return standard(n - 8, bright: true)
        case 16...231:
            let v = n - 16
            let steps = [0, 95, 135, 175, 215, 255]
            return rgb(steps[v / 36], steps[(v / 6) % 6], steps[v % 6])
        case 232...255:
            let g = 8 + (n - 232) * 10
            return rgb(g, g, g)
        default: return nil
        }
    }
}
