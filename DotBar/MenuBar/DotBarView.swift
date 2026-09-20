import AppKit

/// Lightweight AppKit view drawn inside the status item button. No SwiftUI, no layers.
final class DotBarView: NSView {
    private(set) var text: NSAttributedString = NSAttributedString()
    private(set) var dots: [NSColor] = []
    private(set) var dotsLeading = false

    static let dotSize: CGFloat = 6, dotGap: CGFloat = 2, hGap: CGFloat = 4

    func configure(item: Item, output: ScriptOutput?, dotColors: [NSColor]) {
        text = Self.attributed(item: item, output: output)
        dots = dotColors
        dotsLeading = item.dotsPosition == .leading
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        var w = ceil(text.size().width)
        if !dots.isEmpty { w += Self.dotSize + (w > 0 ? Self.hGap : 0) }
        return NSSize(width: w, height: NSStatusBar.system.thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let ts = text.size()
        let dotsW: CGFloat = dots.isEmpty ? 0 : Self.dotSize
        var x: CGFloat = 0
        if dotsLeading && !dots.isEmpty { drawDots(atX: x, in: b); x += dotsW + Self.hGap }
        text.draw(at: NSPoint(x: x, y: (b.height - ts.height) / 2))
        x += ceil(ts.width)
        if !dotsLeading && !dots.isEmpty { drawDots(atX: x + (ts.width > 0 ? Self.hGap : 0), in: b) }
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
        if let o { s = (o.failed && o.text.isEmpty) ? "⚠︎" : o.text }
        else { s = item.source.isScript ? "…" : "" }
        var color: NSColor = .labelColor
        if let hex = o?.overrideColor, let c = NSColor(hex: hex) { color = c }
        else if let c = RuleEngine.color(for: item.textColor, output: o) { color = c }
        return NSAttributedString(string: s, attributes: [.font: font(item.font), .foregroundColor: color])
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
