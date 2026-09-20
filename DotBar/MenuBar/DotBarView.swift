import AppKit

/// Lightweight AppKit view drawn inside the status item button. No SwiftUI, no layers.
final class DotBarView: NSView {
    private(set) var text: NSAttributedString = NSAttributedString()
    private(set) var dots: [NSColor] = []
    private var dotLabels: [NSAttributedString] = []
    private(set) var dotsLeading = false
    private var maxTextWidth: CGFloat = 0
    private var mode: DisplayMode = .textAndDots
    private var dotStyle: DotStyle = .circle
    private var dotSize: CGFloat = DotBarView.dotSize
    private var badge: String = ""
    private var badgeColor: NSColor = .systemRed

    static let dotSize: CGFloat = 6, dotGap: CGFloat = 2, hGap: CGFloat = 4
    static let barDotWidth: CGFloat = 3, badgeFontSize: CGFloat = 8.5

    func configure(item: Item, output: ScriptOutput?, dotColors: [NSColor]) {
        mode = output?.displayModeOverride ?? item.displayMode
        text = Self.attributed(item: item, output: output, mode: mode)
        dots = mode.showsDots ? dotColors : []
        dotLabels = dots.isEmpty ? [] : item.dots.map { Self.dotLabel(String($0.label.prefix(1)), size: CGFloat(item.dotSize)) }
        dotsLeading = item.dotsPosition == .leading
        maxTextWidth = item.maxWidth > 0 ? CGFloat(item.maxWidth) : 0
        dotStyle = item.dotStyle
        dotSize = CGFloat(min(max(item.dotSize, 3), 20))
        badge = String((output?.badge ?? "").prefix(3))
        badgeColor = (output?.badgeColor.flatMap { NSColor(hex: $0) }) ?? .systemRed
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// Width of the dot column for the current style, including the optional label column.
    private var dotColumnWidth: CGFloat { dotShapeWidth + labelColumnWidth }
    private var dotShapeWidth: CGFloat { dotStyle == .bar ? Self.barDotWidth : dotSize }
    /// Widest label (0 when no dot has one) plus a 1pt gap to the dot.
    private var labelColumnWidth: CGFloat {
        let w = dotLabels.map { ceil($0.size().width) }.max() ?? 0
        return w > 0 ? w + 1 : 0
    }

    /// Label glyph sized so its cap height ≈ the dot diameter.
    private static func dotLabel(_ ch: String, size: CGFloat) -> NSAttributedString {
        guard !ch.isEmpty else { return NSAttributedString() }
        let font = NSFont.systemFont(ofSize: round(size * 1.2), weight: .semibold)
        return NSAttributedString(string: ch, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
    }

    private var badgeSize: NSSize {
        guard !badge.isEmpty else { return .zero }
        let s = Self.badgeString(badge).size()
        return NSSize(width: max(ceil(s.width) + 5, dotSize + 3), height: ceil(s.height) + 2)
    }

    /// Text width after the per-item max-width cap.
    private var textWidth: CGFloat {
        let w = ceil(text.size().width)
        return maxTextWidth > 0 ? min(w, maxTextWidth) : w
    }

    override var intrinsicContentSize: NSSize {
        var w = textWidth
        if !dots.isEmpty { w += dotColumnWidth + (w > 0 ? Self.hGap : 0) }
        w += badgeSize.width > 0 ? badgeSize.width * 0.6 : 0
        if mode == .dotsOnly { w = max(w, dotSize + 4) }
        return NSSize(width: w, height: NSStatusBar.system.thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let ts = text.size()
        let tw = textWidth
        let dotsW: CGFloat = dots.isEmpty ? 0 : dotColumnWidth
        var x: CGFloat = 0
        if dotsLeading && !dots.isEmpty { drawDots(atX: x, in: b); x += dotsW + (tw > 0 ? Self.hGap : 0) }
        if maxTextWidth > 0 {
            // Bounded rect + .byTruncatingTail paragraph style -> tail ellipsis.
            let h = ceil(ts.height)
            text.draw(with: NSRect(x: x, y: (b.height - h) / 2, width: tw, height: h),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        } else if tw > 0 {
            text.draw(at: NSPoint(x: x, y: (b.height - ts.height) / 2))
        }
        x += tw
        if !dotsLeading && !dots.isEmpty { drawDots(atX: x + (tw > 0 ? Self.hGap : 0), in: b) }
        drawBadge(in: b)
    }

    private func drawDots(atX x: CGFloat, in b: NSRect) {
        let n = CGFloat(dots.count)
        let h = dotSize                                          // bar = same height, 3pt wide
        let w = dotShapeWidth
        let total = n * h + (n - 1) * Self.dotGap
        var y = round((b.height - total) / 2) + total - h        // top dot first
        let lw = labelColumnWidth
        let ix = round(x + lw)
        for (i, c) in dots.enumerated() {
            if lw > 0, i < dotLabels.count, dotLabels[i].length > 0 {
                let ls = dotLabels[i].size()
                // Right-align the glyph in the label column; center it on the dot (visual cap height ≈ 0.7 em).
                let capH = ls.height * 0.72
                dotLabels[i].draw(at: NSPoint(x: round(x + lw - 1 - ls.width), y: round(y + (h - capH) / 2 - (ls.height - capH) * 0.5)))
            }
            c.setFill()
            let r = NSRect(x: ix, y: round(y), width: w, height: h)
            switch dotStyle {
            case .circle: NSBezierPath(ovalIn: r).fill()
            case .square: NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
            case .bar:    NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1).fill()
            }
            y -= h + Self.dotGap
        }
    }

    // MARK: Badge

    private static func badgeString(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: badgeFontSize, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
    }

    /// Small rounded pill at the top-right of the content. Integer-aligned, no layers.
    private func drawBadge(in b: NSRect) {
        guard !badge.isEmpty else { return }
        let str = Self.badgeString(badge)
        let size = badgeSize
        let rect = NSRect(x: round(b.maxX - size.width),
                          y: round(b.maxY - size.height - 1),
                          width: round(size.width), height: round(size.height))
        badgeColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        let ss = str.size()
        str.draw(at: NSPoint(x: round(rect.midX - ss.width / 2), y: round(rect.midY - ss.height / 2)))
    }

    // MARK: Text

    static func attributed(item: Item, output o: ScriptOutput?,
                           mode: DisplayMode = .textAndDots) -> NSAttributedString {
        if mode == .dotsOnly { return NSAttributedString() }
        let s: String
        var runs: [ANSIRun]
        if let o {
            s = (o.failed && o.text.isEmpty) ? "⚠︎" : o.text
            runs = (s == o.text) ? o.textRuns : []
        } else {
            s = item.source.isScript ? "…" : ""
            runs = []
        }
        if runs.isEmpty && !s.isEmpty { runs = [ANSIRun(text: s, color: nil, bold: false)] }

        var color: NSColor = .labelColor
        // JSON "color" > inline `| color=` param > rule colour. ANSI runs still win per run.
        if let hex = o?.overrideColor, let c = NSColor(hex: hex) { color = c }
        else if let c = o?.barParams.color { color = c }
        else if let c = RuleEngine.color(for: item.textColor, output: o) { color = c }

        let base = font(item.font)
        let result = NSMutableAttributedString()
        let symbolName = o?.symbol ?? o?.barParams.sfimage ?? item.symbol
        if mode == .symbolOnly {
            // Symbol alone; fall back to the text when there is no usable symbol.
            if let name = symbolName, !name.isEmpty,
               let attachment = symbolAttachment(name, color: color, font: base) {
                return attachment
            }
        }
        for run in runs {
            // ANSI colour wins over the rule / JSON colour for that run.
            let f = run.bold ? bolder(base) : base
            result.append(NSAttributedString(string: run.text,
                                             attributes: [.font: f, .foregroundColor: run.color ?? color]))
        }
        if let name = symbolName, !name.isEmpty,
           let attachment = symbolAttachment(name, color: color, font: base) {
            if result.length > 0 { result.insert(NSAttributedString(string: " "), at: 0) }
            result.insert(attachment, at: 0)
        }
        if item.maxWidth > 0 {
            let ps = NSMutableParagraphStyle()
            ps.lineBreakMode = .byTruncatingTail
            result.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    /// SF Symbol as a template image tinted with the text colour, sized to the font.
    private static func symbolAttachment(_ name: String, color: NSColor, font f: NSFont) -> NSAttributedString? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let cfg = NSImage.SymbolConfiguration(pointSize: f.pointSize, weight: .regular)
        let sized = img.withSymbolConfiguration(cfg) ?? img
        let size = sized.size
        guard size.width > 0, size.height > 0 else { return nil }

        let tinted = NSImage(size: size)
        tinted.lockFocus()
        sized.draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let att = NSTextAttachment()
        att.image = tinted
        att.bounds = NSRect(x: 0, y: (f.capHeight - size.height) / 2, width: size.width, height: size.height)
        return NSAttributedString(attachment: att)
    }

    private static func bolder(_ f: NSFont) -> NSFont {
        NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
    }

    static func font(_ spec: FontSpec) -> NSFont {
        let w: NSFont.Weight = switch spec.weight {
        case .light: .light; case .regular: .regular; case .medium: .medium; case .semibold: .semibold; case .bold: .bold
        }
        var f: NSFont
        if let fam = spec.family, !fam.isEmpty,
           let base = NSFontManager.shared.font(withFamily: fam, traits: [], weight: nsWeight(spec.weight), size: spec.size) {
            f = base
        } else {
            f = NSFont.systemFont(ofSize: spec.size, weight: w)
        }
        if spec.monospacedDigits {
            let d = f.fontDescriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
            f = NSFont(descriptor: d, size: spec.size) ?? f
        }
        return f
    }

    private static func nsWeight(_ w: FontSpec.Weight) -> Int {
        switch w { case .light: 3; case .regular: 5; case .medium: 6; case .semibold: 8; case .bold: 9 }
    }
}
