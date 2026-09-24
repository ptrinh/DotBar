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
    private var spark: [Double] = []
    private var sparkSlots = 0
    private var sparkPercent = false
    private var sparkColor: NSColor = .labelColor

    static let dotSize: CGFloat = 6, dotGap: CGFloat = 2, hGap: CGFloat = 4
    static let barDotWidth: CGFloat = 3, badgeFontSize: CGFloat = 8.5, labelGap: CGFloat = 3

    func configure(item: Item, output: ScriptOutput?, dotColors: [NSColor], history: [Double] = []) {
        mode = output?.displayModeOverride ?? item.displayMode
        sparkSlots = mode == .dotsOnly ? 0 : item.sparkline
        spark = sparkSlots > 0 ? history : []
        sparkPercent = output?.text.contains("%") ?? false
        sparkColor = Self.baseColor(item: item, output: output)
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

    /// Text ↔ dots gap: tighter when the "text" is only a drawn icon (battery, calendar, symbol),
    /// whose image already carries its own side bearing.
    private var dotGapX: CGFloat {
        let iconOnly = text.length > 0 && !text.string.contains { $0 != "\u{FFFC}" }
        return iconOnly ? 2 : Self.hGap
    }

    /// Fixed width for the configured sample count, so the item doesn't grow as history fills.
    private var sparkWidth: CGFloat { sparkSlots > 0 ? CGFloat(sparkSlots) * Self.sparkStep : 0 }
    static let sparkStep: CGFloat = 1.5, sparkHeight: CGFloat = 14

    override var intrinsicContentSize: NSSize {
        var w = textWidth
        if sparkWidth > 0 { w += sparkWidth + (w > 0 ? Self.hGap : 0) }
        if !dots.isEmpty { w += dotColumnWidth + (textWidth > 0 ? dotGapX : 0) }
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
        if sparkWidth > 0 { drawSpark(in: NSRect(x: 0, y: round((b.height - Self.sparkHeight) / 2), width: sparkWidth, height: Self.sparkHeight)); x += sparkWidth + (tw > 0 || !dots.isEmpty ? Self.hGap : 0) }
        if dotsLeading && !dots.isEmpty { drawDots(atX: x, in: b); x += dotsW + (tw > 0 ? dotGapX : 0) }
        if maxTextWidth > 0 {
            // Bounded rect + .byTruncatingTail paragraph style -> tail ellipsis.
            let h = ceil(ts.height)
            text.draw(with: NSRect(x: x, y: (b.height - h) / 2, width: tw, height: h),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        } else if tw > 0 {
            text.draw(at: NSPoint(x: x, y: (b.height - ts.height) / 2))
        }
        x += tw
        if !dotsLeading && !dots.isEmpty { drawDots(atX: x + (tw > 0 ? dotGapX : 0), in: b) }
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

    /// Area + line of the recent values, right-aligned so new samples enter at the right.
    /// Scale starts at 0 for non-negative data (and tops at 100 for percentages).
    private func drawSpark(in r: NSRect) {
        sparkColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(rect: NSRect(x: r.minX, y: r.minY, width: r.width, height: 1)).fill()     // baseline
        guard spark.count >= 2 else { return }
        var lo = spark.min()!, hi = spark.max()!
        if lo >= 0 { lo = 0 }
        if sparkPercent { hi = max(hi, 100) }
        if hi - lo < .ulpOfOne { hi = lo + 1 }
        let x0 = r.maxX - CGFloat(spark.count - 1) * Self.sparkStep
        let pts = spark.enumerated().map { i, v in
            NSPoint(x: x0 + CGFloat(i) * Self.sparkStep, y: r.minY + 0.5 + CGFloat((v - lo) / (hi - lo)) * (r.height - 1))
        }
        let line = NSBezierPath()
        line.move(to: pts[0]); pts.dropFirst().forEach { line.line(to: $0) }
        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: pts.last!.x, y: r.minY)); area.line(to: NSPoint(x: pts[0].x, y: r.minY)); area.close()
        sparkColor.withAlphaComponent(0.3).setFill(); area.fill()
        sparkColor.setStroke(); line.lineWidth = 1; line.lineJoinStyle = .round; line.stroke()
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

        let color = baseColor(item: item, output: o)

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
                ?? batteryAttachment(name, color: color, font: base)
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

    /// JSON "color" > inline `| color=` param > rule colour > label colour. ANSI runs still win per run.
    static func baseColor(item: Item, output o: ScriptOutput?) -> NSColor {
        if let hex = o?.overrideColor, let c = NSColor(hex: hex) { return c }
        if let c = o?.barParams.color { return c }
        return RuleEngine.color(for: item.textColor, output: o) ?? .labelColor
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

    /// `symbol: "battery:<percent>[:charging|:plugged]"`: the macOS 27 battery turned upright: a slim
    /// solid pill with a half-disc cap on top, level filled from the bottom over a grey track.
    /// Charging: bolt; on power, not charging: plug lying across. Glyphs are drawn in the ink
    /// colour, spill over the outline, and are ringed by a cut-out gap. Yellow in Low Power Mode (`:lowpower`), else red at 20 % or less on battery.
    /// Every edge is snapped to device pixels.
    private static func batteryAttachment(_ name: String, color: NSColor, font base: NSFont) -> NSAttributedString? {
        guard name.hasPrefix("battery:") else { return nil }
        let parts = name.dropFirst("battery:".count).split(separator: ":").map(String.init)
        guard let pct = parts.first.flatMap(Double.init) else { return nil }
        let level = min(max(pct / 100, 0), 1)
        let charging = parts.contains("charging"), plugged = parts.contains("plugged")
        let lowPower = parts.contains("lowpower")
        let h = round(base.pointSize * 1.4), w = round(h * 0.5)
        // Side margin only when a glyph is drawn: it may spill over the outline.
        let mx: CGFloat = charging || plugged ? 1.5 : 0
        let size = NSSize(width: w + 2 * mx, height: h)
        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: mx, y: 0)
            let sc = max(1, ctx.userSpaceToDeviceSpaceTransform.a)
            func px(_ v: CGFloat) -> CGFloat { (v * sc).rounded() / sc }
            let capH = px(1.5), gap = 1 / sc
            let body = NSRect(x: 0, y: 0, width: w, height: px(h - capH - gap))
            let r = px(w * 0.3)
            let pill = NSBezierPath(roundedRect: body, xRadius: r, yRadius: r)
            let track = color.withAlphaComponent(0.4)
            track.setFill(); pill.fill()
            let capW = px(w * 0.46)                                  // half disc
            let cap = NSBezierPath()
            cap.appendArc(withCenter: NSPoint(x: w / 2, y: body.maxY + gap), radius: capW / 2, startAngle: 0, endAngle: 180)
            cap.close()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: body.maxY + gap, width: w, height: capH)).addClip()
            cap.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            pill.addClip()
            (lowPower ? NSColor.systemYellow
                : pct <= 20 && !charging && !plugged ? NSColor.systemRed : color).setFill()
            NSRect(x: 0, y: 0, width: w, height: px(body.height * level)).fill()
            NSGraphicsContext.restoreGraphicsState()
            guard charging || plugged else { return true }
            // Glyph in the ink colour, larger than the body, separated from it by a cut-out gap
            // (the macOS 26 look) so it reads over the fill and past the outline alike.
            let glyph: NSBezierPath
            if charging {
                let gh = px(body.height * 0.68), gw = px(gh * 0.6)
                glyph = boltPath(in: NSRect(x: px((w - gw) / 2), y: px(body.midY - gh / 2), width: gw, height: gh))
            } else {
                let gw = w + 2 * mx - 1, gh = px(gw * 0.62)
                glyph = plugPath(in: NSRect(x: 0.5 - mx, y: px(body.midY - gh / 2), width: gw, height: gh))
            }
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            glyph.lineWidth = 1.5; glyph.lineJoinStyle = .round; glyph.stroke()
            glyph.fill()                                             // so a translucent glyph isn't tinted by the fill
            ctx.restoreGState()
            color.withAlphaComponent(charging ? 0.5 : 1).setFill(); glyph.fill()
            return true
        }
        let att = NSTextAttachment()
        att.image = img
        att.bounds = NSRect(x: 0, y: round((base.capHeight - h) / 2), width: size.width, height: h)
        return NSAttributedString(attachment: att)
    }

    private static func boltPath(in r: NSRect) -> NSBezierPath {
        polygon([(0.66, 1), (0.06, 0.42), (0.46, 0.42), (0.34, 0), (0.94, 0.58), (0.54, 0.58)], in: r)
    }

    /// Plug lying across (cord left, prongs right) as one outline, so the cut-out stays clean.
    private static func plugPath(in r: NSRect) -> NSBezierPath {
        let upright: [(CGFloat, CGFloat)] = [(0.38, 0), (0.62, 0), (0.62, 0.28), (0.82, 0.36), (0.96, 0.52), (0.96, 0.68), (0.8, 0.68),
                 (0.8, 1), (0.62, 1), (0.62, 0.68), (0.38, 0.68), (0.38, 1), (0.2, 1), (0.2, 0.68),
                 (0.04, 0.68), (0.04, 0.52), (0.18, 0.36), (0.38, 0.28)]
        return polygon(upright.map { ($0.1, $0.0) }, in: r)
    }

    private static func polygon(_ pts: [(CGFloat, CGFloat)], in r: NSRect) -> NSBezierPath {
        let p = NSBezierPath()
        for (i, q) in pts.enumerated() {
            let pt = NSPoint(x: r.minX + q.0 * r.width, y: r.minY + q.1 * r.height)
            i == 0 ? p.move(to: pt) : p.line(to: pt)
        }
        p.close()
        p.lineJoinStyle = .round
        return p
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
