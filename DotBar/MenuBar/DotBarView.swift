import AppKit

/// Lightweight AppKit view drawn inside the status item button. No SwiftUI, no layers.
final class DotBarView: NSView {
    private(set) var text: NSAttributedString = NSAttributedString()
    private(set) var dots: [NSColor] = []
    private(set) var dotsLeading = false
    private var maxTextWidth: CGFloat = 0

    static let dotSize: CGFloat = 6, dotGap: CGFloat = 2, hGap: CGFloat = 4

    func configure(item: Item, output: ScriptOutput?, dotColors: [NSColor]) {
        text = Self.attributed(item: item, output: output)
        dots = dotColors
        dotsLeading = item.dotsPosition == .leading
        maxTextWidth = item.maxWidth > 0 ? CGFloat(item.maxWidth) : 0
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// Text width after the per-item max-width cap.
    private var textWidth: CGFloat {
        let w = ceil(text.size().width)
        return maxTextWidth > 0 ? min(w, maxTextWidth) : w
    }

    override var intrinsicContentSize: NSSize {
        var w = textWidth
        if !dots.isEmpty { w += Self.dotSize + (w > 0 ? Self.hGap : 0) }
        return NSSize(width: w, height: NSStatusBar.system.thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let ts = text.size()
        let tw = textWidth
        let dotsW: CGFloat = dots.isEmpty ? 0 : Self.dotSize
        var x: CGFloat = 0
        if dotsLeading && !dots.isEmpty { drawDots(atX: x, in: b); x += dotsW + Self.hGap }
        if maxTextWidth > 0 {
            // Bounded rect + .byTruncatingTail paragraph style -> tail ellipsis.
            let h = ceil(ts.height)
            text.draw(with: NSRect(x: x, y: (b.height - h) / 2, width: tw, height: h),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        } else {
            text.draw(at: NSPoint(x: x, y: (b.height - ts.height) / 2))
        }
        x += tw
        if !dotsLeading && !dots.isEmpty { drawDots(atX: x + (tw > 0 ? Self.hGap : 0), in: b) }
    }

    private func drawDots(atX x: CGFloat, in b: NSRect) {
        let n = CGFloat(dots.count)
        let total = n * Self.dotSize + (n - 1) * Self.dotGap
        var y = (b.height - total) / 2 + total - Self.dotSize   // top dot first
        for c in dots {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: Self.dotSize, height: Self.dotSize)).fill()
            y -= Self.dotSize + Self.dotGap
        }
    }

    // MARK: Text

    static func attributed(item: Item, output o: ScriptOutput?) -> NSAttributedString {
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
        if let hex = o?.overrideColor, let c = NSColor(hex: hex) { color = c }
        else if let c = RuleEngine.color(for: item.textColor, output: o) { color = c }

        let base = font(item.font)
        let result = NSMutableAttributedString()
        for run in runs {
            // ANSI colour wins over the rule / JSON colour for that run.
            let f = run.bold ? bolder(base) : base
            result.append(NSAttributedString(string: run.text,
                                             attributes: [.font: f, .foregroundColor: run.color ?? color]))
        }
        if let name = o?.symbol ?? item.symbol, !name.isEmpty,
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
