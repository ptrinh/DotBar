import AppKit

/// One NSStatusItem per item — the default (non-combined) mode.
/// Click handling and menu building live in `ItemActions`, shared with the combined controller.
@MainActor
final class StatusItemController: NSObject {
    let itemID: UUID
    private unowned let state: AppState
    private let statusItem: NSStatusItem
    private let view = DotBarView()
    private let actions: ItemActions
    private var leading: NSLayoutConstraint!, trailing: NSLayoutConstraint!

    init(state: AppState, itemID: UUID) {
        self.state = state
        self.itemID = itemID
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "DotBar.\(itemID.uuidString)"
        actions = ItemActions(state: state, itemID: itemID, statusItem: statusItem)
        super.init()
        guard let button = statusItem.button else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)
        leading = view.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2)
        trailing = view.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2)
        NSLayoutConstraint.activate([
            leading, trailing,
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
        update()
    }

    /// Re-render from current model/output. Called by AppState only when something relevant changed.
    func update() {
        guard let item = state.binding(for: itemID) else { return }
        let out = state.output(for: item)
        let colors = state.resolvedDotColors(for: item)
        view.configure(item: item, output: out, dotColors: colors)
        let padL = CGFloat(max(0, item.paddingLeft)), padR = CGFloat(max(0, item.paddingRight))
        leading.constant = padL; trailing.constant = -padR
        statusItem.length = view.intrinsicContentSize.width + padL + padR
    }

    /// Used by `hideWhenEmpty`: keeps the status item alive but off the bar.
    func setVisible(_ visible: Bool) { statusItem.isVisible = visible }

    func remove() { NSStatusBar.system.removeStatusItem(statusItem) }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        actions.handleClick(NSApp.currentEvent)
    }
}
