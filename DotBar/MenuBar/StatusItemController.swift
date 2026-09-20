import AppKit

@MainActor
final class StatusItemController: NSObject {
    let itemID: UUID
    private unowned let state: AppState
    private let statusItem: NSStatusItem
    private let view = DotBarView()

    init(state: AppState, itemID: UUID) {
        self.state = state
        self.itemID = itemID
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "DotBar.\(itemID.uuidString)"
        super.init()
        guard let button = statusItem.button else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 6),
            view.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -6),
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        update()
    }

    /// Re-render from current model/output. Called by AppState only when something relevant changed.
    func update() {
        guard let item = state.binding(for: itemID) else { return }
        let out = state.output(for: item)
        let colors = state.resolvedDotColors(for: item)
        view.configure(item: item, output: out, dotColors: colors)
        statusItem.length = view.intrinsicContentSize.width + 12
    }

    /// Used by `hideWhenEmpty`: keeps the status item alive but off the bar.
    func setVisible(_ visible: Bool) { statusItem.isVisible = visible }

    func remove() { NSStatusBar.system.removeStatusItem(statusItem) }

    // MARK: Click

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let item = state.binding(for: itemID) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        // JSON `"action"` in the latest output wins over the configured action.
        switch state.output(for: item)?.actionOverride ?? item.action {
        case .menu: showMenu()
        case .copy: copyOutput()
        case .script(let cmd): Task.detached(priority: .utility) { _ = await ScriptRunner.run(cmd) }
        case .openURL(let s): if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        }
    }

    private func showMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func copyOutput() {
        guard let item = state.binding(for: itemID) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.output(for: item)?.text ?? "", forType: .string)
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        guard let item = state.binding(for: itemID) else { return menu }
        if let out = state.output(for: item) {
            // Extra output lines first, TextBar style: click one to copy it.
            if !out.menuLines.isEmpty {
                for line in out.menuLines {
                    if ScriptOutput.isSeparator(line) { menu.addItem(.separator()); continue }
                    menu.addItem(menuLineItem(line))
                }
                menu.addItem(.separator())
            }
            let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .medium
            menu.addItem(withTitle: "Updated: \(out.updatedAt.map(df.string(from:)) ?? "—")", action: nil, keyEquivalent: "").isEnabled = false
            if out.failed, let err = out.errorMessage {
                menu.addItem(withTitle: "Error: \(err.prefix(120))", action: nil, keyEquivalent: "").isEnabled = false
            }
            menu.addItem(.separator())
        }
        menu.addItem(mk("Copy", #selector(menuCopy)))
        menu.addItem(mk("Refresh", #selector(menuRefresh), "r"))
        menu.addItem(.separator())
        menu.addItem(mk("Refresh All", #selector(menuRefreshAll), "R"))
        menu.addItem(.separator())
        menu.addItem(mk("Edit \"\(item.name)\"…", #selector(menuEdit), "e"))
        menu.addItem(mk("Preferences…", #selector(menuPrefs), ","))
        menu.addItem(mk(LaunchAtLogin.isEnabled ? "Launch at Login ✓" : "Launch at Login", #selector(menuLogin)))
        menu.addItem(.separator())
        menu.addItem(mk("Quit DotBar", #selector(menuQuit), "q"))
        return menu
    }

    /// One output line: ANSI colours preserved, plain text copied on click.
    private func menuLineItem(_ line: String) -> NSMenuItem {
        let runs = ANSIParser.parse(line)
        let plain = runs.map(\.text).joined()
        let m = NSMenuItem(title: plain, action: #selector(copyLine(_:)), keyEquivalent: "")
        m.target = self
        m.representedObject = plain
        if runs.contains(where: { $0.color != nil || $0.bold }) {
            let base = NSFont.menuFont(ofSize: 0)
            let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
            let s = NSMutableAttributedString()
            for r in runs {
                s.append(NSAttributedString(string: r.text, attributes: [
                    .font: r.bold ? bold : base,
                    .foregroundColor: r.color ?? NSColor.labelColor,
                ]))
            }
            m.attributedTitle = s
        }
        return m
    }

    @objc private func copyLine(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func mk(_ title: String, _ sel: Selector, _ key: String = "") -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: key); m.target = self; return m
    }

    @objc private func menuCopy() { copyOutput() }
    @objc private func menuRefresh() { if let i = state.binding(for: itemID) { state.refresh(i) } }
    @objc private func menuRefreshAll() { state.refreshAll() }
    @objc private func menuEdit() { PreferencesWindowController.shared.show(selecting: itemID) }
    @objc private func menuPrefs() { PreferencesWindowController.shared.show() }
    @objc private func menuLogin() { LaunchAtLogin.toggle() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
