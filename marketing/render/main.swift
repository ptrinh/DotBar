// Offscreen renderer for App Store screenshots.
//
// Compiled together with every app source EXCEPT DotBar/App/DotBarApp.swift (which owns @main).
// Renders, without ever showing anything on screen:
//   - prefs.png      the real SwiftUI Preferences window (900x640 @2x)
//   - strip-*.png    the real AppKit DotBarView per item (4x, transparent background)
//   - recipes.txt    the recipe names, for the composer
//
// HOME is redirected to a temp dir by the calling script, so the user's items.json is untouched.

import AppKit
import SwiftUI

let outDir = CommandLine.arguments[1]
func out(_ name: String) -> URL { URL(fileURLWithPath: outDir).appendingPathComponent(name) }

@MainActor
func run() {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let dark = NSAppearance(named: .darkAqua)!
    app.appearance = dark

    // Safety: refuse to run against the real home directory.
    precondition(NSHomeDirectory().contains("screenshots-home"), "HOME not redirected: \(NSHomeDirectory())")
    print("store dir: \(Store.directory.path)")

    // MARK: Items

    // Screenshot items, with fixed outputs: nothing hits the network or reads a sign-in.
    func preset(_ name: String) -> Item { Recipes.all().first { $0.name == name }! }
    func fixed(_ item: Item, _ output: String) -> Item {
        var i = item; i.source = .static(text: output); return i
    }
    let claude = fixed(preset("AI Usage Icon (Claude)"), #"{"text":"","symbol":"usage:38:64:Claude"}"#)
    let codex = fixed(preset("AI Usage Icon (Codex)"), #"{"text":"","symbol":"usage:12:47:Codex"}"#)
    var battery = fixed(preset("Battery + CPU/RAM dots"), #"{"text":"","symbol":"battery:82"}"#)
    // Deterministic dot inputs (the real recipe runs iostat / vm_stat).
    battery.dots[0].source = .script(command: "echo 86", refreshSeconds: 10)
    battery.dots[1].source = .script(command: "echo 91", refreshSeconds: 15)
    let calendar = fixed(preset("Calendar Icon"), #"{"text":"","symbol":"calendar:24:Thu:black"}"#)
    // Kept for the menu slide: a text item next to the icons.
    let btc = fixed(preset("BTC 3 digits"), "805")

    let state = AppState.shared
    state.items = [claude, codex, battery, calendar, btc]
    for i in state.items { state.refresh(i) }
    RunLoop.current.run(until: Date().addingTimeInterval(2.0))

    for i in state.items { print("\(i.name): \(state.output(for: i)?.symbol ?? state.output(for: i)?.text ?? "nil")") }
    // Put the real commands back (outputs are keyed by item id, so they survive), so the
    // Preferences capture shows the presets as users see them.
    for i in state.items {
        guard var real = Recipes.all().first(where: { $0.name == i.name }) else { continue }
        real.id = i.id
        real.dots = i.dots.enumerated().map { k, d in
            var d = d; if k < real.dots.count { d.source = real.dots[k].source }; return d
        }
        state.update(real)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    for d in battery.dots { print("dot \(d.label): \(state.output(for: d, in: battery)?.text ?? "nil")") }

    // App Store screenshots: only the presets the sandboxed build offers.
    try? Recipes.all().map(\.name).filter { !Recipes.sandboxUnavailable.contains($0) }.joined(separator: "\n")
        .write(to: out("recipes.txt"), atomically: true, encoding: .utf8)

    // MARK: Status item strips

    func dotColors(_ item: Item) -> [NSColor] {
        item.dots.map { dot in
            RuleEngine.color(for: dot.color, output: state.output(for: dot, in: item)) ?? .secondaryLabelColor
        }
    }

    func renderStrip(_ item: Item, name: String, scale: CGFloat = 4) {
        dark.performAsCurrentDrawingAppearance {
            MainActor.assumeIsolated {
                let v = DotBarView(frame: .zero)
                v.configure(item: item, output: state.output(for: item), dotColors: dotColors(item))
                let h: CGFloat = 24
                let w = ceil(v.intrinsicContentSize.width)
                v.frame = NSRect(x: 0, y: 0, width: w, height: h)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                rep.size = NSSize(width: w, height: h)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                v.displayIgnoringOpacity(v.bounds, in: NSGraphicsContext.current!)
                NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])!.write(to: out(name))
                print("\(name): \(w)x\(h) pt")
            }
        }
    }

    renderStrip(claude, name: "strip-claude.png")
    renderStrip(codex, name: "strip-codex.png")
    renderStrip(claude, name: "strip-claude-16x.png", scale: 16)     // sharp close-up
    renderStrip(codex, name: "strip-codex-16x.png", scale: 16)
    renderStrip(battery, name: "strip-battery.png")
    renderStrip(calendar, name: "strip-calendar.png")
    renderStrip(btc, name: "strip-btc.png")

    // MARK: Preferences window (offscreen, never ordered in)

    let selection = PreferencesWindowController.SelectionModel()
    selection.itemID = claude.id

    // Same construction as the real app: NSHostingController in the window, so SwiftUI
    // gets the usual safe-area insets under the title bar.
    let controller = NSHostingController(rootView: PreferencesView(state: state, selection: selection))
    let window = NSWindow(contentViewController: controller)
    window.title = "DotBar Preferences"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.appearance = dark
    window.setContentSize(NSSize(width: 960, height: 700))
    window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
    window.isReleasedWhenClosed = false
    // Far offscreen (no display there), but ordered in so vibrancy/controls render properly.
    window.orderFrontRegardless()
    window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
    window.makeKey()
    window.displayIfNeeded()

    for _ in 0..<8 { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }

    func renderWindow(_ w: NSWindow, name: String, scale: CGFloat = 2) {
        guard let frameView = w.contentView?.superview else { return }
        let b = frameView.bounds
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b.width * scale), pixelsHigh: Int(b.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = b.size
        frameView.cacheDisplay(in: b, to: rep)
        try? rep.representation(using: .png, properties: [:])!.write(to: out(name))
        print("\(name): \(rep.pixelsWide)x\(rep.pixelsHigh) px")
    }

    renderWindow(window, name: "prefs.png")

    print("done")
}

MainActor.assumeIsolated { run() }
exit(0)
