import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var items: [Item] = [] { didSet { persistAndSync() } }
    @Published private(set) var outputs: [UUID: ScriptOutput] = [:]
    @Published private(set) var dotOutputs: [UUID: ScriptOutput] = [:]

    private var timers: [UUID: Timer] = [:]
    private var controllers: [UUID: StatusItemController] = [:]
    private var suppressPersist = false

    /// Last state we compared against for notifications. Absent = no output yet,
    /// so the first output after launch never notifies.
    private struct NotifySnapshot: Equatable { var text: String; var dots: [String] }
    private var notifyBaseline: [UUID: NotifySnapshot] = [:]

    /// Currently registered per-item hotkeys, so we only touch the ones that changed.
    private var registeredHotkeys: [UUID: Hotkey] = [:]
    private static let refreshAllOwner = UUID(uuidString: "00000000-0000-0000-0000-00000000DA1F")!

    private init() {}

    func start() {
        suppressPersist = true
        items = Store.load()
        suppressPersist = false
        syncControllers()
        syncHotkeys()
        registerRefreshAllHotkey()
        observeWake()
        refreshAll()
    }

    // MARK: Wake

    private func observeWake() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    // Give the network / VPN a moment to come back before re-running scripts.
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.refreshAll()
                }
            }
        }
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
                    await MainActor.run {
                        self?.dotOutputs[dotID] = out
                        self?.controllers[id]?.update()
                        self?.checkNotify(id)
                    }
                }
            }
        }
    }

    private func setOutput(_ out: ScriptOutput, for id: UUID) {
        outputs[id] = out
        controllers[id]?.update()
        checkNotify(id)
    }

    // MARK: Rendering helper

    /// The dot colors actually drawn for an item (script `dots` override wins over rules).
    func resolvedDotColors(for item: Item) -> [NSColor] {
        let out = output(for: item)
        var colors: [NSColor] = []
        for (idx, dot) in item.dots.enumerated() {
            if let ov = out?.overrideDots, idx < ov.count, let c = NSColor(hex: ov[idx]) { colors.append(c) }
            else { colors.append(RuleEngine.color(for: dot.color, output: output(for: dot, in: item)) ?? .secondaryLabelColor) }
        }
        return colors
    }

    // MARK: Notifications

    private func checkNotify(_ id: UUID) {
        guard let item = binding(for: id) else { return }
        guard item.notify != .off else { notifyBaseline[id] = nil; return }
        Notifier.requestAuthorizationIfNeeded()

        let snapshot = NotifySnapshot(text: outputs[id]?.text ?? "",
                                      dots: resolvedDotColors(for: item).map(\.hexString))
        guard let previous = notifyBaseline[id] else { notifyBaseline[id] = snapshot; return }
        notifyBaseline[id] = snapshot
        guard previous != snapshot else { return }

        let textChanged = previous.text != snapshot.text
        var dotLines: [String] = []
        for (idx, hex) in snapshot.dots.enumerated() where idx < previous.dots.count && previous.dots[idx] != hex {
            let from = Notifier.name(for: NSColor(hex: previous.dots[idx]) ?? .secondaryLabelColor)
            let to = Notifier.name(for: NSColor(hex: hex) ?? .secondaryLabelColor)
            dotLines.append("Dot \(idx + 1): \(from) → \(to)")
        }

        let wantsText = item.notify == .onTextChange || item.notify == .onAnyChange
        let wantsDots = item.notify == .onDotColorChange || item.notify == .onAnyChange
        guard (wantsText && textChanged) || (wantsDots && !dotLines.isEmpty) else { return }

        var body = snapshot.text
        if wantsDots, !dotLines.isEmpty {
            body += (body.isEmpty ? "" : "\n") + dotLines.joined(separator: "\n")
        }
        Notifier.post(title: item.name, body: body)
    }

    // MARK: Hotkeys

    /// Global "Refresh All" hotkey, persisted in UserDefaults.
    var refreshAllHotkey: Hotkey? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "refreshAllHotkey") else { return nil }
            return try? JSONDecoder().decode(Hotkey.self, from: data)
        }
        set {
            objectWillChange.send()
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "refreshAllHotkey")
            } else {
                UserDefaults.standard.removeObject(forKey: "refreshAllHotkey")
            }
            registerRefreshAllHotkey()
        }
    }

    private func registerRefreshAllHotkey() {
        HotkeyManager.shared.set(refreshAllHotkey, for: Self.refreshAllOwner) { [weak self] in
            self?.refreshAll()
        }
    }

    /// Register/unregister only the item hotkeys that actually changed.
    private func syncHotkeys() {
        var live = Set<UUID>()
        for item in items {
            live.insert(item.id)
            let wanted = item.enabled ? item.hotkey : nil
            guard registeredHotkeys[item.id] != wanted else { continue }
            let id = item.id
            if let wanted {
                HotkeyManager.shared.set(wanted, for: id) { [weak self] in
                    guard let self, let item = self.binding(for: id) else { return }
                    self.refresh(item)
                }
                registeredHotkeys[id] = wanted
            } else {
                HotkeyManager.shared.unregister(owner: id)
                registeredHotkeys[id] = nil
            }
        }
        for id in registeredHotkeys.keys where !live.contains(id) {
            HotkeyManager.shared.unregister(owner: id)
            registeredHotkeys[id] = nil
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
        syncHotkeys()
    }

    private func syncControllers() {
        let ids = Set(items.map(\.id))
        for (id, c) in controllers where !ids.contains(id) {
            c.remove(); controllers[id] = nil; timers[id]?.invalidate(); timers[id] = nil
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
        var interval = item.refreshSeconds
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
