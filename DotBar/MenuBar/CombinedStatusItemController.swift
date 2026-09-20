import AppKit

/// Combined mode: every bar-visible item drawn inside ONE NSStatusItem.
///
/// macOS forces ~8–10pt of its own spacing between separate status items, so several DotBar
/// items look scattered even with zero padding. Here the whole row lives in a single slot and
/// the spacing between items is `state.combinedGap`, which may be zero or negative (overlap).
@MainActor
final class CombinedStatusItemController: NSObject {
    private unowned let state: AppState
    private let statusItem: NSStatusItem
    private let container = NSView()

    /// One DotBarView per item, kept across updates so layout is just a frame change.
    private var views: [UUID: DotBarView] = [:]
    /// One ItemActions per item: the target of that item's menu items.
    private var actions: [UUID: ItemActions] = [:]
    /// Items currently on the bar, in order, with the x-range their view occupies.
    private var placed: [(id: UUID, minX: CGFloat, maxX: CGFloat)] = []

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "DotBar.combined"
        super.init()
        guard let button = statusItem.button else { return }
        container.translatesAutoresizingMaskIntoConstraints = true
        container.autoresizingMask = [.width, .height]
        container.frame = button.bounds
        button.addSubview(container)
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
        update()
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
        views.removeAll()
        actions.removeAll()
        placed.removeAll()
    }

    /// Re-render every sub-view and lay the row out again. Cheap enough to call on any change.
    func update() { layout() }

    /// Items that belong on the bar right now, in model order.
    private func barItems() -> [Item] {
        state.items.filter { $0.enabled && $0.showInBar && !state.shouldHideWhenEmpty($0) }
    }

    // MARK: Layout

    /// Manual frames: x starts at 0; each item takes paddingLeft, its intrinsic width and
    /// paddingRight, then the gap (not after the last one). Total width = final x.
    private func layout() {
        let items = barItems()
        let live = Set(items.map(\.id))
        for (id, v) in views where !live.contains(id) {
            v.removeFromSuperview()
            views[id] = nil
        }
        for id in actions.keys where !live.contains(id) { actions[id] = nil }

        let gap = CGFloat(state.combinedGap)
        let height = container.bounds.height > 0 ? container.bounds.height : NSStatusBar.system.thickness
        var x: CGFloat = 0
        placed.removeAll(keepingCapacity: true)

        for (idx, item) in items.enumerated() {
            let v = view(for: item.id)
            v.configure(item: item, output: state.output(for: item),
                        dotColors: state.resolvedDotColors(for: item))
            let w = v.intrinsicContentSize.width
            x += CGFloat(max(0, item.paddingLeft))
            v.frame = NSRect(x: x, y: 0, width: w, height: height)
            v.needsDisplay = true
            placed.append((item.id, x, x + w))
            x += w + CGFloat(max(0, item.paddingRight))
            if idx < items.count - 1 { x += gap }
        }

        statusItem.length = max(1, x)
        statusItem.isVisible = !items.isEmpty
    }

    private func view(for id: UUID) -> DotBarView {
        if let v = views[id] { return v }
        let v = DotBarView()
        v.translatesAutoresizingMaskIntoConstraints = true
        views[id] = v
        container.addSubview(v)
        return v
    }

    private func actions(for id: UUID) -> ItemActions {
        if let a = actions[id] { return a }
        let a = ItemActions(state: state, itemID: id, statusItem: statusItem)
        a.combinedItemIDs = { [weak self] in self?.barItems().map(\.id) ?? [] }
        actions[id] = a
        return a
    }

    // MARK: Click

    /// Map the click x onto a sub-view: the one containing it, otherwise the nearest one
    /// (a click in a gap belongs to whichever neighbour is closer).
    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        guard let id = itemID(atX: clickX(sender, event)) else { return }
        actions(for: id).handleClick(event)
    }

    private func clickX(_ button: NSStatusBarButton, _ event: NSEvent?) -> CGFloat {
        guard let event else { return 0 }
        return button.convert(event.locationInWindow, from: nil).x
    }

    private func itemID(atX x: CGFloat) -> UUID? {
        guard !placed.isEmpty else {
            // Nothing laid out (everything hidden): fall back to the first item.
            return state.items.first(where: { $0.enabled && $0.showInBar })?.id
        }
        if let hit = placed.first(where: { x >= $0.minX && x <= $0.maxX }) { return hit.id }
        // In a gap, or past either end: nearest by distance to the sub-view's x-range.
        return placed.min(by: { distance(x, $0) < distance(x, $1) })?.id
    }

    private func distance(_ x: CGFloat, _ p: (id: UUID, minX: CGFloat, maxX: CGFloat)) -> CGFloat {
        x < p.minX ? p.minX - x : (x > p.maxX ? x - p.maxX : 0)
    }
}
