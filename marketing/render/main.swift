// Offscreen renderer for App Store screenshots.
//
// Compiled together with every app source EXCEPT DotBar/App/DotBarApp.swift (which owns @main).
// Renders, without ever showing anything on screen:
//   - prefs.png      the real SwiftUI Preferences window (900x640 @2x)
//   - strip-*.png    the real AppKit DotBarView for two items (4x, transparent background)
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

    // Screenshot item: BTC text with the CPU/RAM dots of the "Battery + CPU/RAM dots" recipe.
    var btc = Recipes.all().first { $0.name == "BTC 3 digits" }!
    let loadDots = Recipes.all().first { $0.name == "Battery + CPU/RAM dots" }!
    btc.name = "BTC 3 digits + CPU/RAM dots"
    btc.dots = loadDots.dots
    btc.dotSize = loadDots.dotSize
    // Deterministic dot inputs (the real recipe shells out to top / vm_stat).
    btc.dots[0].source = .script(command: "echo 86", refreshSeconds: 10)
    btc.dots[1].source = .script(command: "echo 91", refreshSeconds: 15)
    let clock = Recipes.all().first { $0.name == "Clock" }!

    let state = AppState.shared

    // Add the items with a static source first so nothing hits the network, then restore
    // the real commands (outputs are keyed by item id, so they survive the edit).
    var btcStatic = btc; btcStatic.source = .static(text: "805")
    var clockStatic = clock; clockStatic.source = .static(text: "Sat 20 14:05")
    state.items = [btcStatic, clockStatic]
    state.refresh(btcStatic)
    state.refresh(clockStatic)
    RunLoop.current.run(until: Date().addingTimeInterval(2.0))
    state.update(btc)
    state.update(clock)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))

    print("btc output: \(state.output(for: btc)?.text ?? "nil")")
    for d in btc.dots { print("dot \(d.label): \(state.output(for: d, in: btc)?.text ?? "nil")") }

    try? Recipes.all().map(\.name).joined(separator: "\n")
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

    renderStrip(btc, name: "strip-btc.png")
    renderStrip(clock, name: "strip-clock.png")

    // MARK: Preferences window (offscreen, never ordered in)

    let selection = PreferencesWindowController.SelectionModel()
    selection.itemID = btc.id

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
