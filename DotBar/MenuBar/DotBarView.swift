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
    static let barDotWidth: CGFloat = 3, badgeFontSize: CGFloat = 8.5, labelGap: CGFloat = 3

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
    /// Widest label (0 when no dot has one) plus a 3pt gap to the dot.
    private var labelColumnWidth: CGFloat {
        let w = dotLabels.map { ceil($0.size().width) }.max() ?? 0
        return w > 0 ? w + Self.labelGap : 0
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

    /// Opacity used on the menu bar of an inactive display.
    static let inactiveAlpha: CGFloat = 0.5

    /// Other displays get a bitmap snapshot of the item, drawn with the plain (non-vibrant)
    /// appearance; the live item on the active menu bar is always vibrant. macOS only dims
    /// its own plain titles in that snapshot, so custom drawing has to dim itself.
    private var isInactiveReplicant: Bool {
        let m = effectiveAppearance.bestMatch(from: [.vibrantDark, .vibrantLight, .darkAqua, .aqua])
        return m == .darkAqua || m == .aqua
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isInactiveReplicant, let ctx = NSGraphicsContext.current?.cgContext else { return drawContent() }
        ctx.setAlpha(Self.inactiveAlpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawContent()
        ctx.endTransparencyLayer()
    }

    private func drawContent() {
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
                dotLabels[i].draw(at: NSPoint(x: round(x + lw - Self.labelGap - ls.width), y: round(y + (h - capH) / 2 - (ls.height - capH) * 0.5)))
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
        // Multi-line text (JSON "text" with \n): small lines stacked to fit the bar, with a larger symbol.
        let stacked = result.string.contains("\n")
        if stacked, let att = stackedAttachment(result, font: base) {
            result.setAttributedString(att)
        }
        if let name = symbolName, !name.isEmpty,
           let attachment = calendarAttachment(name, color: color, font: base)
                ?? symbolAttachment(name, color: color, font: base, scale: stacked ? 1.35 : 1) {
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

    /// Stacked-text metrics: small font, baseline-to-baseline pitch, and the height from the
    /// first line's cap top to the last baseline for `lines` lines.
    private static func stackMetrics(_ base: NSFont, lines: Int = 2) -> (font: NSFont, pitch: CGFloat, height: CGFloat) {
        let size = round(base.pointSize * 0.72 * 2) / 2
        let f = base.fontName.hasPrefix(".") ? NSFont.systemFont(ofSize: size, weight: .medium)
                                             : NSFontManager.shared.convert(base, toSize: size)
        let pitch = size
        return (f, pitch, round(f.capHeight + pitch * CGFloat(lines - 1)))
    }

    /// Lines of `text` re-set in a smaller font, stacked tight and drawn into one image attachment.
    /// The block (first cap top → last baseline) is centred on the bar's text line.
    /// Drawn lazily so dynamic colours (labelColor) follow the appearance at draw time.
    private static func stackedAttachment(_ text: NSAttributedString, font base: NSFont) -> NSAttributedString? {
        let lines = text.string.components(separatedBy: "\n")
        guard lines.count > 1 else { return nil }
        let m = stackMetrics(base, lines: lines.count)
        var loc = 0
        let parts: [NSAttributedString] = lines.map { line in
            let len = (line as NSString).length
            let p = NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: loc, length: len)))
            loc += len + 1
            p.enumerateAttribute(.font, in: NSRange(location: 0, length: p.length)) { v, r, _ in
                let bold = (v as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
                p.addAttribute(.font, value: bold ? bolder(m.font) : m.font, range: r)
            }
            return p
        }
        let desc = ceil(-m.font.descender)
        let size = NSSize(width: ceil(parts.map { $0.size().width }.max() ?? 0), height: m.height + desc)
        guard size.width > 0 else { return nil }
        let capTop = ceil(m.font.capHeight)
        let img = NSImage(size: size, flipped: true) { _ in
            for (i, p) in parts.enumerated() {
                p.draw(at: NSPoint(x: 0, y: capTop + CGFloat(i) * m.pitch - m.font.ascender))
            }
            return true
        }
        let att = NSTextAttachment()
        att.image = img
        att.bounds = NSRect(x: 0, y: round((base.capHeight - m.height) / 2) - desc, width: size.width, height: size.height)
        return NSAttributedString(attachment: att)
    }

    /// `symbol: "calendar:<day>"`: a calendar page (dark header strip, light body, day number),
    /// as tall as two stacked lines so it lines up with month/weekday beside it.
    /// `symbol: "calendar:<day>:<label>[:<color>]"`: a taller page with the label (e.g. weekday)
    /// in the header; `color` (`red`, `blue`, `#hex`, …) fills the header, white label on top.
    private static func calendarAttachment(_ name: String, color: NSColor, font base: NSFont) -> NSAttributedString? {
        guard name.hasPrefix("calendar:") else { return nil }
        let parts = name.dropFirst("calendar:".count).split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first else { return nil }
        let day = String(first.prefix(2))
        let label = parts.count > 1 ? parts[1] : ""
        let headerColor = parts.count > 2 ? LineParser.color(from: parts[2]) : nil
        let h = label.isEmpty ? stackMetrics(base).height : round(base.pointSize * 1.65)
        let headerH = round(h * (label.isEmpty ? 0.25 : 0.44))
        let size = NSSize(width: round(h * (label.isEmpty ? 1.06 : 1)), height: h)
        let img = NSImage(size: size, flipped: false) { r in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let paper = dark ? NSColor.black : NSColor.white
            let body = NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5)
            color.withAlphaComponent(0.83).setFill(); body.fill()
            // Header strip: the chosen colour, or the ink's hue but faint.
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            let header = NSRect(x: 0, y: r.maxY - headerH, width: r.width, height: headerH)
            if let headerColor {
                headerColor.setFill(); header.fill()
            } else {
                paper.setFill(); header.fill()
                color.withAlphaComponent(0.27).setFill(); header.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            if !label.isEmpty {
                // 1px cut between strip and body, so a strip as dark as the body (black in light mode) still reads.
                let s = NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 1
                NSRect(x: 0, y: header.minY - 1 / max(s, 1), width: r.width, height: 1 / max(s, 1)).fill(using: .clear)
                // Same face as the stacked month/weekday text; shrink only if the label is too wide.
                var lf = NSFont.systemFont(ofSize: round(headerH * 0.64 / 0.7 * 2) / 2, weight: .medium)
                let lw = NSAttributedString(string: label, attributes: [.font: lf]).size().width
                if lw > r.width - 3 { lf = NSFont.systemFont(ofSize: lf.pointSize * (r.width - 3) / lw, weight: .medium) }
                drawCentered(label, font: lf, color: headerColor == nil ? color : .white, in: header)
            }
            // Day number, centred in the body below the strip.
            let nf = NSFont.monospacedDigitSystemFont(ofSize: round(label.isEmpty ? h * 0.68 : (h - headerH) * 0.95),
                                                      weight: .regular)
            drawCentered(day, font: nf, color: paper,
                         in: NSRect(x: 0, y: 0, width: r.width, height: r.height - headerH))
            return true
        }
        let att = NSTextAttachment()
        att.image = img
        att.bounds = NSRect(x: 0, y: round((base.capHeight - h) / 2), width: size.width, height: size.height)
        return NSAttributedString(attachment: att)
    }

    /// Draws `s` with its ink (glyph bounds, not font metrics) centred in `rect`, pixel-aligned.
    private static func drawCentered(_ s: String, font: NSFont, color: NSColor, kern: CGFloat = 0, in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if kern != 0 { attrs[.kern] = kern }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.setShouldSmoothFonts(false)          // no stem thickening: crisper tiny caps
        let ink = CTLineGetImageBounds(line, ctx)
        let scale = ctx.userSpaceToDeviceSpaceTransform.a > 0 ? ctx.userSpaceToDeviceSpaceTransform.a : 1
        func px(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        ctx.textPosition = CGPoint(x: px(rect.midX - ink.midX), y: px(rect.midY - ink.midY))
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// SF Symbol as a template image tinted with the text colour, sized to the font.
    private static func symbolAttachment(_ name: String, color: NSColor, font f: NSFont, scale: CGFloat = 1) -> NSAttributedString? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let cfg = NSImage.SymbolConfiguration(pointSize: round(f.pointSize * scale), weight: .regular)
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
