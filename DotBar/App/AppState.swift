import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var items: [Item] = [] { didSet { persistAndSync() } }
    /// Script results. Kept OFF AppState's publisher so the Preferences form does not re-render
    /// on every script tick; only views that show live output observe `live`.
    private(set) var outputs: [UUID: ScriptOutput] = [:] { didSet { live.objectWillChange.send() } }
    /// Sparkline samples per item, in memory only.
    private var history: [UUID: [Double]] = [:]
    private(set) var dotOutputs: [UUID: ScriptOutput] = [:] { didSet { live.objectWillChange.send() } }
    let live = LiveOutputs()
    final class LiveOutputs: ObservableObject {}

    private var timers: [UUID: Timer] = [:]
    /// Per-item refresh interval coming from JSON `"refresh"`, until an output without it.
    private var refreshOverrides: [UUID: Int] = [:]
    private var controllers: [UUID: StatusItemController] = [:]
    /// Combined mode: the single status item holding every bar-visible item.
    private var combined: CombinedStatusItemController?
    private var suppressPersist = false

    /// Last state we compared against for notifications. Absent = no output yet,
    /// so the first output after launch never notifies.
    private struct NotifySnapshot: Equatable { var text: String; var dots: [String] }
    private var notifyBaseline: [UUID: NotifySnapshot] = [:]

    /// Currently registered per-item hotkeys, so we only touch the ones that changed.
    private var registeredHotkeys: [UUID: Hotkey] = [:]
    private static let refreshAllOwner = UUID(uuidString: "00000000-0000-0000-0000-00000000DA1F")!

    /// Runs currently in flight, keyed by item id (main script) or dot id. Guards against pile-ups.
    private var inFlight: Set<UUID> = []
    /// When each item's script last started, exported as DOTBAR_LAST_RUN.
    private var lastRun: [UUID: Date] = [:]
    /// Last system wake, exported as DOTBAR_LAST_WAKE.
    private var lastWake: Date?
    /// True between willSleep and didWake: no timers are scheduled.
    private var timersPaused = false
    /// Set during start() so the first refresh of every item is staggered instead of immediate.
    private var isStarting = false
    private var appearanceObserver: NSKeyValueObservation?

    /// Long-lived processes of `.stream` items, one per item.
    private var streams: [UUID: StreamRunner] = [:]
    /// True between willSleep and didWake: no stream is running.
    private var streamsPaused = false
    private var itemsWatcher: FileWatcher?
    private var scriptsWatcher: FileWatcher?

    /// Spacing between the first run of consecutive items at launch.
    private static let staggerStep: TimeInterval = 0.7
    private static let staggerCap: TimeInterval = 5

    private init() {}

    func start() {
        isStarting = true
        LaunchAtLogin.enableOnFirstLaunch()
        suppressPersist = true
        items = Store.load()
        suppressPersist = false
        syncControllers()
        syncHotkeys()
        syncStreams()
        registerRefreshAllHotkey()
        observeWake()
        observePower()
        observeAppearance()
        startWatchingFiles()
        isStarting = false
        staggeredRefreshAll()
    }

    /// Launch-time refresh: item N starts N * 0.7s in (capped at 5s) so we don't fork every script at once.
    private func staggeredRefreshAll() {
        // Streams are launched by syncStreams() instead, so they are skipped here.
        for (idx, item) in items.enumerated() where item.enabled && !item.isStream {
            let delay = staggerDelay(forIndex: idx)
            let id = item.id
            Task { @MainActor [weak self] in
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard let self, let item = self.binding(for: id), item.enabled else { return }
                self.refresh(item)
            }
        }
    }

    private func staggerDelay(forIndex idx: Int) -> TimeInterval {
        min(Double(idx) * Self.staggerStep, Self.staggerCap)
    }

    // MARK: Wake / power

    private func observeWake() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.lastWake = Date()
                    // Timers were invalidated on sleep; bring them back before the catch-up refresh.
                    self.timersPaused = false
                    for item in self.items where item.enabled { self.scheduleTimer(for: item) }
                    // Give the network / VPN a moment to come back before re-running scripts.
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.streamsPaused = false
                    self.syncStreams()
                    self.refreshAll()
                }
            }
        }
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pauseTimers()
                self?.pauseStreams()
            }
        }
    }

    private func pauseTimers() {
        timersPaused = true
        for (id, t) in timers { t.invalidate(); timers[id] = nil }
    }

    /// Sleep: kill every streaming process. They come back in syncStreams() after wake.
    private func pauseStreams() {
        streamsPaused = true
        for (id, s) in streams { s.stop(); streams[id] = nil }
    }

    /// Quit: stop the streams so no child process outlives the app (and none restarts).
    func shutdownStreams() { pauseStreams() }

    /// Low Power Mode stretches short intervals; the user can opt out.
    var respectLowPowerMode: Bool {
        get { UserDefaults.standard.object(forKey: "respectLowPowerMode") as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "respectLowPowerMode")
            rescheduleAllTimers()
        }
    }

    /// Combined mode: render every bar-visible item inside one NSStatusItem, so macOS
    /// cannot insert its own ~8–10pt spacing between them.
    var combineItems: Bool {
        get { UserDefaults.standard.object(forKey: "combineItems") as? Bool ?? false }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "combineItems")
            syncControllers()
        }
    }

    /// Spacing between items in combined mode, in points. Negative overlaps them.
    var combinedGap: Double {
        get { UserDefaults.standard.object(forKey: "combinedGap") as? Double ?? 4 }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(min(max(newValue, -6), 24), forKey: "combinedGap")
            combined?.update()
        }
    }

    private func observePower() {
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rescheduleAllTimers() }
        }
    }

    private func rescheduleAllTimers() {
        for (id, t) in timers { t.invalidate(); timers[id] = nil }
        for item in items where item.enabled { scheduleTimer(for: item) }
    }

    /// Appearance flips (dark <-> light) change what scripts should print, so re-run everything once.
    private func observeAppearance() {
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshAll() }
        }
    }

    // MARK: Script environment

    private var appearanceName: String {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light"
    }

    private func scriptEnv(for item: Item) -> [String: String] {
        [
            "DOTBAR_ITEM_NAME": item.name,
            "DOTBAR_ITEM_ID": item.id.uuidString,
            "DOTBAR_APPEARANCE": appearanceName,
            "DOTBAR_REFRESH_SECONDS": String(refreshOverrides[item.id] ?? item.refreshSeconds),
            "DOTBAR_LAST_RUN": lastRun[item.id].map { String(Int($0.timeIntervalSince1970)) } ?? "",
            "DOTBAR_LAST_WAKE": lastWake.map { String(Int($0.timeIntervalSince1970)) } ?? "",
            "DOTBAR_VERSION": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "DOTBAR_PREVIOUS_TEXT": String((outputs[item.id]?.text ?? "").prefix(512)),
        ]
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
            // Never stack a second run on a script that is still going.
            if !inFlight.contains(id) {
                inFlight.insert(id)
                lastRun[id] = Date()
                let env = scriptEnv(for: item)
                Task.detached(priority: .utility) { [weak self] in
                    let out = await ScriptRunner.run(command, extra: env)
                    await MainActor.run {
                        self?.inFlight.remove(id)
                        self?.setOutput(out, for: id)
                    }
                }
            }
        case .stream:
            // "Refresh" on a stream means: start the process over.
            if let runner = streams[id] { runner.restart() } else { syncStreams() }
        }
        for dot in item.dots {
            if case .script(let command, _) = dot.source {
                let dotID = dot.id
                guard !inFlight.contains(dotID) else { continue }
                inFlight.insert(dotID)
                let env = scriptEnv(for: item)
                Task.detached(priority: .utility) { [weak self] in
                    let out = await ScriptRunner.run(command, extra: env)
                    await MainActor.run {
                        guard let self else { return }
                        self.inFlight.remove(dotID)
                        self.dotOutputs[dotID] = out
                        self.refreshBarItem(id)
                        self.applyVisibility(id)
                        self.checkNotify(id)
                    }
                }
            }
        }
    }

    /// Output pushed in from outside (dotbar://set), handled exactly like script output.
    func applyExternalOutput(_ text: String, for id: UUID) {
        setOutput(.parse(text), for: id)
    }

    private func setOutput(_ out: ScriptOutput, for id: UUID) {
        outputs[id] = out
        if let n = binding(for: id)?.sparkline, n > 0, let v = out.number {
            var h = history[id] ?? []
            h.append(v)
            if h.count > n { h.removeFirst(h.count - n) }
            history[id] = h
        } else if history[id] != nil, (binding(for: id)?.sparkline ?? 0) == 0 {
            history[id] = nil
        }
        refreshBarItem(id)
        applyVisibility(id)
        if refreshOverrides[id] != out.refreshOverride {
            refreshOverrides[id] = out.refreshOverride
            if let item = binding(for: id), item.enabled { scheduleTimer(for: item) }
        }
        checkNotify(id)
    }

    /// `hideWhenEmpty`: drop the status item off the bar while there is nothing to show.
    private func applyVisibility(_ id: UUID) {
        // Combined mode: nothing to hide individually, the layout just omits the item.
        if let combined { combined.update(); return }
        guard let item = binding(for: id), let controller = controllers[id] else { return }
        controller.setVisible(!shouldHideWhenEmpty(item))
    }

    /// True when `hideWhenEmpty` is on and the item currently has nothing to draw.
    func shouldHideWhenEmpty(_ item: Item) -> Bool {
        guard item.hideWhenEmpty else { return false }
        let out = outputs[item.id]
        let empty = (out?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDotsOverride = !(out?.overrideDots ?? []).isEmpty
        // A symbol alone (e.g. `"symbol":"battery:80"` with empty text) still draws something.
        let hasSymbol = !(out?.symbol ?? out?.barParams.sfimage ?? "").isEmpty
        return empty && !hasDotsOverride && !hasSymbol
    }

    /// Re-render one item on the bar, whichever controller owns it.
    func refreshBarItem(_ id: UUID) {
        if let combined { combined.update() } else { controllers[id]?.update() }
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
    /// Recent numbers for the item's sparkline (empty when off).
    func history(for item: Item) -> [Double] { item.sparkline > 0 ? Array((history[item.id] ?? []).suffix(item.sparkline)) : [] }
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
        syncStreams()
    }

    // MARK: Streaming items

    /// One StreamRunner per enabled `.stream` item. Runners whose item disappeared, got
    /// disabled or had its command edited are stopped (and so never restart themselves).
    private func syncStreams() {
        var wanted: [UUID: String] = [:]
        for item in items where item.enabled {
            if case .stream(let cmd) = item.source, !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                wanted[item.id] = cmd
            }
        }
        for (id, runner) in streams where runner.command != wanted[id] {
            runner.stop()
            streams[id] = nil
        }
        guard !streamsPaused else { return }
        for (id, cmd) in wanted where streams[id] == nil {
            guard let item = binding(for: id) else { continue }
            let runner = StreamRunner(command: cmd, env: scriptEnv(for: item)) { [weak self] out in
                Task { @MainActor [weak self] in self?.setOutput(out, for: id) }
            }
            streams[id] = runner
            runner.start()
        }
    }

    // MARK: File watching

    /// Reload items.json when something else edits it, and re-run items that use a script
    /// from ~/Library/Application Support/DotBar/scripts when that folder changes.
    private func startWatchingFiles() {
        Store.ensureScriptsDirectory()
        // The directory, not the file: an atomic replace swaps the inode out from under us.
        itemsWatcher = FileWatcher(directory: Store.directory, debounce: 0.3) { [weak self] in
            Task { @MainActor [weak self] in self?.reloadItemsIfChangedExternally() }
        }
        scriptsWatcher = FileWatcher(directory: Store.scriptsDirectory, debounce: 0.5) { [weak self] in
            Task { @MainActor [weak self] in self?.refreshItemsUsingScriptsFolder() }
        }
    }

    private func reloadItemsIfChangedExternally() {
        guard let loaded = Store.loadIfChangedExternally(), loaded != items else { return }
        suppressPersist = true          // the file is already the source of truth; don't write it back
        items = loaded
        suppressPersist = false
        syncControllers()
        syncHotkeys()
        syncStreams()
    }

    private func refreshItemsUsingScriptsFolder() {
        let dir = Store.scriptsDirectory.path
        let variants = [dir, (dir as NSString).abbreviatingWithTildeInPath,
                        "$HOME/Library/Application Support/DotBar/scripts",
                        "${HOME}/Library/Application Support/DotBar/scripts"]
        for item in items where item.enabled {
            guard let cmd = item.source.command else { continue }
            guard variants.contains(where: { cmd.contains($0) }) else { continue }
            refresh(item)
        }
    }

    private func syncControllers() {
        let ids = Set(items.map(\.id))
        for (id, c) in controllers where !ids.contains(id) { c.remove(); controllers[id] = nil }
        for id in timers.keys where !ids.contains(id) {
            timers[id]?.invalidate(); timers[id] = nil
            refreshOverrides[id] = nil
        }
        let combining = combineItems
        if combining {
            // One slot for everything: the per-item status items go away.
            for (id, c) in controllers { c.remove(); controllers[id] = nil }
            if combined == nil { combined = CombinedStatusItemController(state: self) }
        } else if combined != nil {
            combined?.remove(); combined = nil
        }
        for (idx, item) in items.enumerated() {
            if item.enabled {
                if item.showInBar && !combining {
                    if let c = controllers[item.id] { c.update() }
                    else {
                        controllers[item.id] = StatusItemController(state: self, itemID: item.id)
                        // At launch staggeredRefreshAll() does the first run instead, spread out over time.
                        if !isStarting { refresh(item) }
                    }
                    applyVisibility(item.id)
                } else {
                    // Menu-only, or combined mode (the combined controller draws it): no status item
                    // of its own, but keep producing output.
                    controllers[item.id]?.remove(); controllers[item.id] = nil
                    if !isStarting, outputs[item.id] == nil { refresh(item) }
                }
                scheduleTimer(for: item, firstFireDelay: isStarting ? staggerDelay(forIndex: idx) : 0)
            } else {
                controllers[item.id]?.remove(); controllers[item.id] = nil
                timers[item.id]?.invalidate(); timers[item.id] = nil
            }
        }
        combined?.update()
    }

    /// Low Power Mode: stretch anything faster than a minute to 3x (never below 30s).
    private func effectiveInterval(_ interval: Int) -> Int {
        guard interval > 0, interval < 60, respectLowPowerMode,
              ProcessInfo.processInfo.isLowPowerModeEnabled else { return interval }
        return max(30, interval * 3)
    }

    private func scheduleTimer(for item: Item, firstFireDelay: TimeInterval = 0) {
        var interval = refreshOverrides[item.id] ?? item.refreshSeconds
        for d in item.dots { if case .script(_, let s) = d.source, s > 0 { interval = interval == 0 ? s : min(interval, s) } }
        interval = effectiveInterval(interval)
        guard !timersPaused else { timers[item.id]?.invalidate(); timers[item.id] = nil; return }
        if let t = timers[item.id], Int(t.timeInterval) == interval { return }   // unchanged
        timers[item.id]?.invalidate()
        guard interval > 0 else { timers[item.id] = nil; return }
        let id = item.id
        let t = Timer(fire: Date().addingTimeInterval(firstFireDelay + TimeInterval(interval)),
                      interval: TimeInterval(interval), repeats: true) { [weak self] _ in
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
