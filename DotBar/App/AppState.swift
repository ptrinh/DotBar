import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var items: [Item] = [] { didSet { persistAndSync() } }
    @Published private(set) var outputs: [UUID: ScriptOutput] = [:]
    @Published private(set) var dotOutputs: [UUID: ScriptOutput] = [:]

    private var timers: [UUID: Timer] = [:]
    /// Per-item refresh interval coming from JSON `"refresh"`, until an output without it.
    private var refreshOverrides: [UUID: Int] = [:]
    private var controllers: [UUID: StatusItemController] = [:]
    private var suppressPersist = false

    private init() {}

    func start() {
        suppressPersist = true
        items = Store.load()
        suppressPersist = false
        syncControllers()
        refreshAll()
    }

    // MARK: Items CRUD

    @discardableResult
    func addItem() -> Item { let item = Item(); items.append(item); return item }
    func removeItem(_ id: UUID) { items.removeAll { $0.id == id } }
    func binding(for id: UUID) -> Item? { items.first { $0.id == id } }
    func update(_ item: Item) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), items[idx] != item else { return }
        items[idx] = item
    }

    // MARK: Refresh

    func refreshAll() { for item in items where item.enabled { refresh(item) } }

    func refresh(_ item: Item) {
        let id = item.id
        switch item.source {
        case .static(let text):
            setOutput(.parse(text), for: id)
        case .script(let command, _):
            Task.detached(priority: .utility) { [weak self] in
                let out = await ScriptRunner.run(command)
                await MainActor.run { self?.setOutput(out, for: id) }
            }
        }
        for dot in item.dots {
            if case .script(let command, _) = dot.source {
                let dotID = dot.id
                Task.detached(priority: .utility) { [weak self] in
                    let out = await ScriptRunner.run(command)
                    await MainActor.run { self?.dotOutputs[dotID] = out; self?.controllers[id]?.update() }
                }
            }
        }
    }

    private func setOutput(_ out: ScriptOutput, for id: UUID) {
        outputs[id] = out
        controllers[id]?.update()
        if refreshOverrides[id] != out.refreshOverride {
            refreshOverrides[id] = out.refreshOverride
            if let item = binding(for: id), item.enabled { scheduleTimer(for: item) }
        }
    }

    func output(for item: Item) -> ScriptOutput? { outputs[item.id] }
    func output(for dot: Dot, in item: Item) -> ScriptOutput? {
        switch dot.source {
        case .mainValue: outputs[item.id]
        case .script: dotOutputs[dot.id]
        }
    }

    // MARK: Internal sync

    private func persistAndSync() {
        guard !suppressPersist else { return }
        Store.save(items)
        syncControllers()
    }

    private func syncControllers() {
        let ids = Set(items.map(\.id))
        for (id, c) in controllers where !ids.contains(id) {
            c.remove(); controllers[id] = nil; timers[id]?.invalidate(); timers[id] = nil
            refreshOverrides[id] = nil
        }
        for item in items {
            if item.enabled {
                if let c = controllers[item.id] { c.update() }
                else { controllers[item.id] = StatusItemController(state: self, itemID: item.id); refresh(item) }
                scheduleTimer(for: item)
            } else {
                controllers[item.id]?.remove(); controllers[item.id] = nil
                timers[item.id]?.invalidate(); timers[item.id] = nil
            }
        }
    }

    private func scheduleTimer(for item: Item) {
        var interval = refreshOverrides[item.id] ?? item.refreshSeconds
        for d in item.dots { if case .script(_, let s) = d.source, s > 0 { interval = interval == 0 ? s : min(interval, s) } }
        if let t = timers[item.id], Int(t.timeInterval) == interval { return }   // unchanged
        timers[item.id]?.invalidate()
        guard interval > 0 else { timers[item.id] = nil; return }
        let id = item.id
        let t = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let item = self.binding(for: id) else { return }
                self.refresh(item)
            }
        }
        t.tolerance = max(1, TimeInterval(interval) * 0.1)   // lets the OS coalesce wakeups
        RunLoop.main.add(t, forMode: .common)
        timers[id] = t
    }
}
