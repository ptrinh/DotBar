import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    static let shared = PreferencesWindowController()
    private var window: NSWindow?
    let selection = SelectionModel()

    final class SelectionModel: ObservableObject { @Published var itemID: UUID? }

    func show(selecting id: UUID? = nil) {
        if let id { selection.itemID = id }
        if window == nil {
            let root = PreferencesView(state: AppState.shared, selection: selection)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "DotBar Preferences"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 900, height: 640))
            w.minSize = NSSize(width: 760, height: 520)
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Drop the whole SwiftUI hierarchy when closed so idle memory stays minimal.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window?.contentViewController = nil
        window = nil
    }
}

/// Preview of the real menu bar view, reused inside Preferences.
struct DotBarPreview: NSViewRepresentable {
    let state: AppState
    @ObservedObject var live: AppState.LiveOutputs
    let item: Item
    init(state: AppState, item: Item) { self.state = state; self.live = state.live; self.item = item }

    func makeNSView(context: Context) -> DotBarView { DotBarView() }
    func updateNSView(_ v: DotBarView, context: Context) {
        let out = state.output(for: item)
        let colors = item.dots.enumerated().map { idx, dot -> NSColor in
            if let ov = out?.overrideDots, idx < ov.count, let c = NSColor(hex: ov[idx]) { return c }
            return RuleEngine.color(for: dot.color, output: state.output(for: dot, in: item)) ?? .secondaryLabelColor
        }
        v.configure(item: item, output: out, dotColors: colors)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DotBarView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
