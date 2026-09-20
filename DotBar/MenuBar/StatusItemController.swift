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
        let out = state.output(for: item)
        // JSON `"action"` wins, then inline `href=` / `bash=` on the bar line, then the configured action.
        if let override = out?.actionOverride { perform(override); return }
        if let p = out?.barParams, p.hasAction { run(p, fallbackCopy: nil); return }
        perform(item.action)
    }

    private func perform(_ action: ClickAction) {
        switch action {
        case .menu: showMenu()
        case .copy: copyOutput()
        case .script(let cmd): Task.detached(priority: .utility) { _ = await ScriptRunner.run(cmd) }
        case .openURL(let s): if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        }
    }

    /// xbar line action: `href=` opens a URL, `bash=` runs a command (optionally in Terminal),
    /// neither copies the text. `refresh=true` refreshes the item afterwards.
    private func run(_ p: LineParams, fallbackCopy text: String?) {
        let wantsRefresh = p.refresh
        if let href = p.href, let u = URL(string: href) {
            NSWorkspace.shared.open(u)
        } else if let cmd = p.shellCommand {
            if p.terminal {
                Self.runInTerminal(cmd)
            } else {
                Task { [weak self] in
                    _ = await ScriptRunner.run(cmd)
                    guard wantsRefresh, let self, let item = self.state.binding(for: self.itemID) else { return }
                    self.state.refresh(item)
                }
                return
            }
        } else if let text {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        if wantsRefresh, let item = state.binding(for: itemID) { state.refresh(item) }
    }

    /// Run a command in Terminal.app through a throwaway `.command` script.
    private static func runInTerminal(_ command: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotbar-\(UUID().uuidString).command")
        let body = "#!/bin/zsh\n\(command)\n"
        guard (try? body.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let path = url.path
        Task.detached(priority: .utility) {
            _ = await ScriptRunner.run("open -a Terminal \(LineParams.shellQuote(path))")
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
        menu.autoenablesItems = false
        guard let item = state.binding(for: itemID) else { return menu }
        if let out = state.output(for: item) {
            // Extra output lines first, TextBar style: click one to copy it.
            if !out.menuLines.isEmpty {
                appendLines(out.menuLines, to: menu)
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

    /// Output lines, xbar style: `--` nesting builds submenus, `| key=value` params style them.
    private func appendLines(_ lines: [String], to menu: NSMenu) {
        var stack: [NSMenu] = [menu]
        var lastItems: [NSMenuItem?] = [nil]
        for raw in lines {
            let pl = LineParser.parse(raw)
            guard pl.params.dropdown else { continue }              // dropdown=false: bar only
            var d = pl.depth
            if d < stack.count - 1 {                                // back out to a shallower level
                stack.removeLast(stack.count - 1 - d)
                lastItems.removeLast(lastItems.count - 1 - d)
            }
            while d > stack.count - 1 {                             // nest under the previous line
                guard let parent = lastItems[stack.count - 1] else { break }
                let sub = parent.submenu ?? NSMenu()
                sub.autoenablesItems = false
                parent.submenu = sub
                stack.append(sub)
                lastItems.append(nil)
            }
            d = min(d, stack.count - 1)
            if pl.isSeparator { stack[d].addItem(.separator()); continue }
            let mi = menuLineItem(pl)
            stack[d].addItem(mi)
            lastItems[d] = mi
        }
    }

    /// One output line: ANSI colours + inline params preserved, plain text copied on click.
    private func menuLineItem(_ pl: ParsedLine) -> NSMenuItem {
        let p = pl.params
        let m = NSMenuItem(title: pl.text, action: #selector(lineClicked(_:)), keyEquivalent: "")
        m.target = self
        m.representedObject = pl

        let base = lineFont(p)
        let styled = p.color != nil || p.fontName != nil || p.size != nil
        if styled || pl.runs.contains(where: { $0.color != nil || $0.bold }) {
            let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
            let s = NSMutableAttributedString()
            for r in pl.runs {
                // ANSI colour wins per run over the line's `color=` param.
                s.append(NSAttributedString(string: r.text, attributes: [
                    .font: r.bold ? bold : base,
                    .foregroundColor: r.color ?? p.color ?? NSColor.labelColor,
                ]))
            }
            if s.length > 0 { m.attributedTitle = s }
        }
        if let name = p.sfimage, !name.isEmpty,
           let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            img.isTemplate = true
            m.image = img
        }
        if let t = p.tooltip { m.toolTip = t }
        if p.checked { m.state = .on }
        if p.disabled { m.isEnabled = false }
        if p.alternate {
            m.isAlternate = true
            m.keyEquivalentModifierMask = .option
        }
        return m
    }

    private func lineFont(_ p: LineParams) -> NSFont {
        let size = p.size.map { CGFloat($0) } ?? NSFont.systemFontSize
        if let name = p.fontName, !name.isEmpty, let f = NSFont(name: name, size: size) { return f }
        return p.size != nil ? NSFont.menuFont(ofSize: size) : NSFont.menuFont(ofSize: 0)
    }

    @objc private func lineClicked(_ sender: NSMenuItem) {
        guard let pl = sender.representedObject as? ParsedLine else { return }
        run(pl.params, fallbackCopy: pl.text)
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
