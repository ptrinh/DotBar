// Composes the App Store screenshots (2880x1800) from the offscreen-rendered UI bitmaps.
// Usage: compose <work-dir> <out-dir> <app-icon.png>

import AppKit

let work = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let iconPath = CommandLine.arguments[3]

_ = NSApplication.shared

let W: CGFloat = 2880, H: CGFloat = 1800

func load(_ name: String) -> NSImage {
    guard let i = NSImage(contentsOfFile: "\(work)/\(name)") else { fatalError("missing \(name)") }
    return i
}

let stripBTC = load("strip-btc.png")
let stripClock = load("strip-clock.png")
let icon = NSImage(contentsOfFile: iconPath)!
let recipeNames = (try? String(contentsOfFile: "\(work)/recipes.txt", encoding: .utf8))?
    .split(separator: "\n").map(String.init) ?? []

// MARK: - Helpers

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let white = NSColor.white
func dim(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }

func font(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: w)
}

enum Align { case left, center, right }

@discardableResult
func text(_ s: String, _ f: NSFont, _ color: NSColor, x: CGFloat, y: CGFloat,
          width: CGFloat? = nil, align: Align = .left, tracking: CGFloat = 0) -> NSSize {
    let ps = NSMutableParagraphStyle()
    ps.alignment = align == .left ? .left : (align == .center ? .center : .right)
    ps.lineBreakMode = .byWordWrapping
    var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: ps]
    if tracking != 0 { attrs[.kern] = tracking }
    let a = NSAttributedString(string: s, attributes: attrs)
    let w = width ?? ceil(a.size().width) + 4
    let h = ceil(a.boundingRect(with: NSSize(width: w, height: 10000),
                                options: [.usesLineFragmentOrigin]).height)
    a.draw(with: NSRect(x: x, y: y, width: w, height: h), options: [.usesLineFragmentOrigin])
    return NSSize(width: w, height: h)
}

func textHeight(_ s: String, _ f: NSFont, width: CGFloat) -> CGFloat {
    let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byWordWrapping
    let a = NSAttributedString(string: s, attributes: [.font: f, .paragraphStyle: ps])
    return ceil(a.boundingRect(with: NSSize(width: width, height: 10000), options: [.usesLineFragmentOrigin]).height)
}

func background() {
    NSGradient(colors: [rgb(28, 32, 46), rgb(14, 15, 22), rgb(8, 8, 12)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -68)
    // Two soft accent glows.
    NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.44, blue: 0.95, alpha: 0.30), ending: .clear)!
        .draw(fromCenter: NSPoint(x: W * 0.22, y: H * 0.88), radius: 0,
              toCenter: NSPoint(x: W * 0.22, y: H * 0.88), radius: 1250, options: [])
    NSGradient(starting: NSColor(srgbRed: 0.95, green: 0.40, blue: 0.35, alpha: 0.16), ending: .clear)!
        .draw(fromCenter: NSPoint(x: W * 0.86, y: H * 0.10), radius: 0,
              toCenter: NSPoint(x: W * 0.86, y: H * 0.10), radius: 1100, options: [])
}

func canvas(_ body: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    background()
    body()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

func withShadow(blur: CGFloat, offsetY: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: offsetY)
    s.shadowColor = NSColor(white: 0, alpha: alpha)
    s.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    let sized = img.withSymbolConfiguration(cfg) ?? img
    let tinted = NSImage(size: sized.size)
    tinted.lockFocus()
    sized.draw(in: NSRect(origin: .zero, size: sized.size))
    color.set()
    NSRect(origin: .zero, size: sized.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

/// Draws a rendered status-item strip so that its 24pt height maps to `height` px.
@discardableResult
func drawStrip(_ img: NSImage, x: CGFloat, midY: CGFloat, height: CGFloat) -> CGFloat {
    let scale = height / img.size.height
    let w = img.size.width * scale
    img.draw(in: NSRect(x: x, y: midY - height / 2, width: w, height: height),
             from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    return w
}

// MARK: - A menu-bar mockup containing the two DotBar items

func menuBar(rect: NSRect, itemHeight: CGFloat, radius: CGFloat, compact: Bool = false) {
    withShadow(blur: 60, offsetY: -18, alpha: 0.55) {
        rgb(30, 30, 34, 0.96).setFill()
        rounded(rect, radius).fill()
    }
    dim(0.12).setStroke()
    let p = rounded(rect.insetBy(dx: 1, dy: 1), radius)
    p.lineWidth = 2
    p.stroke()

    let midY = rect.midY
    // Left: faux app menu titles.
    var x = rect.minX + 46
    if let apple = symbol("apple.logo", size: itemHeight * 0.62, color: dim(0.85)) {
        apple.draw(in: NSRect(x: x, y: midY - apple.size.height / 2, width: apple.size.width, height: apple.size.height))
        x += apple.size.width + 44
    }
    let f = font(itemHeight * 0.58, .regular)
    for (i, t) in (compact ? ["Finder"] : ["Finder", "File", "Edit", "View"]).enumerated() {
        let bold = i == 0 ? font(itemHeight * 0.58, .semibold) : f
        let sz = text(t, bold, dim(i == 0 ? 0.92 : 0.62), x: x, y: midY - itemHeight * 0.42)
        x += sz.width + 40
    }

    // Right: system-ish icons, then the two DotBar items to their left.
    var rx = rect.maxX - 56
    for name in compact ? ["battery.75", "wifi", "control"] : ["battery.75", "wifi", "magnifyingglass", "control"] {
        if let img = symbol(name, size: itemHeight * 0.66, color: dim(0.75)) {
            rx -= img.size.width
            img.draw(in: NSRect(x: rx, y: midY - img.size.height / 2, width: img.size.width, height: img.size.height))
            rx -= 42
        }
    }

    // DotBar items (real rendered views), highlighted with a soft pill behind them.
    let clockW = stripClock.size.width * (itemHeight / stripClock.size.height)
    rx -= clockW
    drawStrip(stripClock, x: rx, midY: midY, height: itemHeight)
    rx -= 56

    let btcW = stripBTC.size.width * (itemHeight / stripBTC.size.height)
    rx -= btcW
    let pill = NSRect(x: rx - 26, y: midY - itemHeight * 0.62, width: btcW + 52, height: itemHeight * 1.24)
    NSColor(srgbRed: 0.42, green: 0.52, blue: 1.0, alpha: 0.22).setFill()
    rounded(pill, pill.height / 2).fill()
    drawStrip(stripBTC, x: rx, midY: midY, height: itemHeight)
}


// MARK: - Preferences bitmap patch
//
// cacheDisplay() cannot capture AppKit's vibrant materials: in the offscreen capture the
// selected sidebar row comes out as a black block and the checkbox glyphs are missing.
// Repaint those two elements exactly as macOS draws them, over the real capture.

func brightness(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
    guard let c = rep.colorAt(x: x, y: y) else { return 0 }
    let s = c.usingColorSpace(.sRGB) ?? c
    return (s.redComponent + s.greenComponent + s.blueComponent) / 3
}

/// Bounding box (top-left origin, pixels) of pixels matching `test` inside a region.
func blob(_ rep: NSBitmapImageRep, x0: Int, x1: Int, y0: Int, y1: Int,
          _ test: (CGFloat) -> Bool) -> NSRect? {
    var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
    for y in stride(from: y0, to: min(y1, rep.pixelsHigh), by: 2) {
        for x in stride(from: x0, to: min(x1, rep.pixelsWide), by: 2) where test(brightness(rep, x, y)) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard minX <= maxX else { return nil }
    return NSRect(x: minX, y: minY, width: maxX - minX + 2, height: maxY - minY + 2)
}

/// Rows of near-white pixels, split into vertical clusters (the two checkboxes).
func whiteBoxes(_ rep: NSBitmapImageRep, x0: Int, x1: Int, y0: Int, y1: Int) -> [NSRect] {
    var runs: [(Int, Int, Int)] = []      // y, minX, maxX
    for y in y0..<min(y1, rep.pixelsHigh) {
        var lo = Int.max, hi = Int.min
        for x in x0..<min(x1, rep.pixelsWide) where brightness(rep, x, y) > 0.88 {
            lo = min(lo, x); hi = max(hi, x)
        }
        if lo <= hi { runs.append((y, lo, hi)) }
    }
    var boxes: [NSRect] = []
    var cur: [(Int, Int, Int)] = []
    for r in runs {
        if let last = cur.last, r.0 - last.0 > 3 {
            boxes.append(box(cur)); cur = []
        }
        cur.append(r)
    }
    if !cur.isEmpty { boxes.append(box(cur)) }
    return boxes.filter { $0.width > 20 && $0.height > 20 }

    func box(_ rs: [(Int, Int, Int)]) -> NSRect {
        let minY = rs.first!.0, maxY = rs.last!.0
        let minX = rs.map(\.1).min()!, maxX = rs.map(\.2).max()!
        return NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

func patchedPrefs(_ image: NSImage) -> NSImage {
    guard let src = image.representations.first as? NSBitmapImageRep else { return image }
    let w = src.pixelsWide, h = src.pixelsHigh
    let scale = CGFloat(w) / image.size.width          // 2 (the capture is @2x)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)             // draw in pixel units
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h),
               from: .zero, operation: .copy, fraction: 1)

    // Flip a top-left rect into the bottom-up bitmap.
    func flip(_ r: NSRect) -> NSRect { NSRect(x: r.minX, y: CGFloat(h) - r.maxY, width: r.width, height: r.height) }

    let sideMaxX = Int(240 * scale)                    // sidebar width in px
    let searchTop = Int(28 * scale), searchBottom = Int(300 * scale)

    // 1. Selected row: the black block (rows that are mostly pure black).
    func selectedRow() -> NSRect? {
        var ys: [Int] = []
        var minX = Int.max, maxX = Int.min
        for y in searchTop..<min(searchBottom, h) {
            var n = 0, lo = Int.max, hi = Int.min
            for x in 4..<sideMaxX where brightness(src, x, y) < 0.05 {
                n += 1; lo = min(lo, x); hi = max(hi, x)
            }
            if n > Int(100 * scale) { ys.append(y); minX = min(minX, lo); maxX = max(maxX, hi) }
        }
        guard let first = ys.first, let last = ys.last, minX < maxX else { return nil }
        return NSRect(x: minX, y: first, width: maxX - minX + 1, height: last - first + 1)
    }
    let selected = selectedRow()

    if let dark = selected {
        let r = flip(dark)
        NSColor(srgbRed: 0.04, green: 0.36, blue: 0.85, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 10 * scale, yRadius: 10 * scale).fill()
    }

    // 2. Checkboxes (both rows): accent-filled box with a white check.
    let boxes = whiteBoxes(src, x0: Int(10 * scale), x1: Int(45 * scale), y0: searchTop, y1: searchBottom)
    for b in boxes {
        let r = flip(b)
        NSColor(srgbRed: 0.18, green: 0.52, blue: 1.0, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 4 * scale, yRadius: 4 * scale).fill()
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.minX + r.width * 0.24, y: r.minY + r.height * 0.52))
        p.line(to: NSPoint(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.30))
        p.line(to: NSPoint(x: r.minX + r.width * 0.78, y: r.minY + r.height * 0.72))
        p.lineWidth = max(2, r.width * 0.12)
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        NSColor.white.setStroke()
        p.stroke()
    }

    // 3. The selected row's label, which the black block swallowed.
    if let dark = selected, let cb = boxes.first {
        let r = flip(dark)
        let x = CGFloat(cb.maxX) + 18 * scale
        let nameFont = NSFont.systemFont(ofSize: 13 * scale, weight: .regular)
        let subFont = NSFont.systemFont(ofSize: 10 * scale, weight: .regular)
        let name = NSAttributedString(string: "BTC 3 digits + CPU/RAM dots",
                                      attributes: [.font: nameFont, .foregroundColor: NSColor.white])
        let sub = NSAttributedString(string: "60s · 2 dots",
                                     attributes: [.font: subFont, .foregroundColor: NSColor(white: 1, alpha: 0.75)])
        name.draw(at: NSPoint(x: x, y: r.minY + r.height * 0.50))
        sub.draw(at: NSPoint(x: x, y: r.minY + r.height * 0.16))
    }

    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(work)/prefs-patched.png"))
    let img = NSImage(size: image.size)
    img.addRepresentation(rep)
    return img
}

// MARK: - 1. Hero

let hero = canvas {
    // App icon, top-left corner.
    let iconSide: CGFloat = 220
    withShadow(blur: 40, offsetY: -12, alpha: 0.5) {
        icon.draw(in: NSRect(x: 170, y: H - 150 - iconSide, width: iconSide, height: iconSide),
                  from: .zero, operation: .sourceOver, fraction: 1,
                  respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    }
    text("DotBar", font(66, .semibold), white, x: 170 + iconSide + 40, y: H - 150 - iconSide + 78)
    text("for macOS", font(40, .regular), dim(0.55), x: 170 + iconSide + 44, y: H - 150 - iconSide + 28)

    text("Your text. Your dots.\nIn the menu bar.", font(150, .bold), white,
         x: 200, y: 1010, width: W - 400, align: .center)

    text("Static text or any shell script, with up to 3 rule-driven status dots.",
         font(54, .regular), dim(0.72), x: 200, y: 930, width: W - 400, align: .center)

    menuBar(rect: NSRect(x: 240, y: 560, width: W - 480, height: 240), itemHeight: 96, radius: 46)

    // Three short, truthful feature labels.
    let features = [("timer", "Interval or streaming scripts"),
                    ("circle.grid.2x1.fill", "1–3 rule-driven dots"),
                    ("terminal", "xbar / SwiftBar syntax")]
    let colW = (W - 400) / 3
    for (i, f) in features.enumerated() {
        let cx = 200 + colW * CGFloat(i)
        if let img = symbol(f.0, size: 64, color: dim(0.8)) {
            img.draw(in: NSRect(x: cx + colW / 2 - img.size.width / 2, y: 330,
                                width: img.size.width, height: img.size.height))
        }
        text(f.1, font(44, .medium), dim(0.8), x: cx, y: 230, width: colW, align: .center)
    }
}
write(hero, "01-hero-2880x1800.png")

// MARK: - 2. Preferences

let prefs = patchedPrefs(load("prefs.png"))

let prefsShot = canvas {
    let targetH: CGFloat = 1340
    let targetW = targetH * prefs.size.width / prefs.size.height
    let r = NSRect(x: (W - targetW) / 2, y: 320, width: targetW, height: targetH)
    withShadow(blur: 90, offsetY: -30, alpha: 0.65) {
        NSColor.black.setFill()
        rounded(r.insetBy(dx: 12, dy: 12), 26).fill()
    }
    NSGraphicsContext.saveGraphicsState()
    let clip = rounded(r, 26)
    clip.addClip()
    prefs.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1,
               respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
    dim(0.14).setStroke()
    clip.lineWidth = 2
    clip.stroke()

    text("Rules, gradients, fonts, hotkeys, notifications",
         font(72, .semibold), white, x: 200, y: 140, width: W - 400, align: .center)
}
write(prefsShot, "02-preferences-2880x1800.png")

// MARK: - 3. Menu + recipes

let menuRows: [(String, Bool, Bool)] = [      // title, isHeader/dimmed, hasCheck
    ("Updated: today 14:05", true, false),
    ("Copy", false, false),
    ("Refresh", false, false),
    ("Refresh All", false, false),
    ("SEPARATOR", false, false),
    ("Edit “BTC 3 digits + CPU/RAM dots”…", false, false),
    ("Preferences…", false, false),
    ("Launch at Login", false, true),
    ("About DotBar", false, false),
    ("Quit DotBar", false, false),
]

let menuShot = canvas {
    text("Click an item for its menu", font(58, .semibold), white, x: 200, y: H - 210)
    text("Ready-made recipes", font(58, .semibold), white, x: 1700, y: H - 210)

    // Small menu bar strip at the top of the left column.
    menuBar(rect: NSRect(x: 200, y: H - 430, width: 1320, height: 150), itemHeight: 62, radius: 30, compact: true)

    // Menu-like panel hanging under the strip.
    let rowH: CGFloat = 78
    let padV: CGFloat = 26
    let panelW: CGFloat = 900
    let sepExtra: CGFloat = -30
    let panelH = padV * 2 + rowH * CGFloat(menuRows.count) + sepExtra
    let panel = NSRect(x: 690, y: H - 470 - panelH, width: panelW, height: panelH)
    withShadow(blur: 70, offsetY: -22, alpha: 0.6) {
        rgb(44, 44, 48, 0.98).setFill()
        rounded(panel, 26).fill()
    }
    dim(0.12).setStroke()
    let pp = rounded(panel, 26); pp.lineWidth = 2; pp.stroke()

    var y = panel.maxY - padV
    for (title, dimmed, check) in menuRows {
        if title == "SEPARATOR" {
            y -= rowH / 2
            dim(0.16).setFill()
            NSRect(x: panel.minX + 26, y: y + 8, width: panelW - 52, height: 2).fill()
            y -= rowH / 2 + sepExtra
            continue
        }
        y -= rowH
        if title == "Copy" {   // one highlighted row, like a hovered menu item
            NSColor(srgbRed: 0.28, green: 0.42, blue: 0.95, alpha: 0.95).setFill()
            rounded(NSRect(x: panel.minX + 12, y: y + 6, width: panelW - 24, height: rowH - 8), 12).fill()
        }
        let f = font(dimmed ? 38 : 44, dimmed ? .regular : .regular)
        text(title, f, dimmed ? dim(0.45) : dim(title == "Copy" ? 1.0 : 0.92),
             x: panel.minX + 42, y: y + (rowH - 56) / 2 + 4)
        if check, let img = symbol("checkmark", size: 34, color: dim(0.9)) {
            img.draw(in: NSRect(x: panel.maxX - 60, y: y + rowH / 2 - img.size.height / 2,
                                width: img.size.width, height: img.size.height))
        }
    }

    // Right column: the recipe list.
    let colors = [rgb(52, 199, 89), rgb(255, 159, 10), rgb(255, 69, 58),
                  rgb(100, 210, 255), rgb(191, 90, 242), rgb(255, 214, 10)]
    var ry: CGFloat = H - 330
    for (i, name) in recipeNames.enumerated() {
        let d: CGFloat = 22
        colors[i % colors.count].setFill()
        NSBezierPath(ovalIn: NSRect(x: 1700, y: ry + 16, width: d, height: d)).fill()
        text(name, font(46, .regular), dim(0.88), x: 1700 + d + 26, y: ry)
        ry -= 76
    }

    text("xbar-compatible output · streaming scripts · Homebrew or App Store",
         font(56, .semibold), white, x: 200, y: 120, width: W - 400, align: .center)
}
write(menuShot, "03-menu-recipes-2880x1800.png")
