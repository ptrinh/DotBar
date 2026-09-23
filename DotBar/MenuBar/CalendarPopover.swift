import AppKit
import EventKit

/// Month calendar + the selected day's events, shown from a status item (click action `.calendar`).
///
/// Shown in a borderless panel, not an `NSPopover`: measured on macOS 27, an empty popover
/// peaks at ~72 MB and keeps ~10 MB after closing; this panel peaks at ~16 MB and keeps ~2 MB.
/// Everything is created on open and dropped on close — panel, view and `EKEventStore` —
/// so the idle app pays nothing for it. One custom-drawn view, no SwiftUI, one event query
/// per visible month, reloads only on `EKEventStoreChanged` while open.
@MainActor
final class CalendarPopover: NSObject {
    private static var current: CalendarPopover?
    /// A click on the status item while open can first reach the outside-click monitor (mouse
    /// down — e.g. on the copy of the item macOS draws on another display) and only then
    /// `toggle` (mouse up). A close that recent means this click was the closing one.
    private static var closedAt = Date.distantPast

    static func toggle(relativeTo button: NSView) {
        if let c = current { c.close(); return }
        guard Date().timeIntervalSince(closedAt) > 0.35 else { return }
        let c = CalendarPopover()
        current = c
        c.show(relativeTo: button)
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        var onCancel: () -> Void = {}
        override func cancelOperation(_ sender: Any?) { onCancel() }     // Esc
    }

    private var panel: Panel?
    private let view = CalendarView()
    private var store: EKEventStore?
    private var observer: NSObjectProtocol?
    private var monitors: [Any] = []
    private weak var anchor: NSView?

    private func show(relativeTo button: NSView) {
        anchor = button
        let p = Panel(contentRect: NSRect(origin: .zero, size: view.frame.size),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.isReleasedWhenClosed = false
        p.onCancel = { [weak self] in self?.close() }
        let bg = NSVisualEffectView()
        bg.material = .popover
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true
        bg.addSubview(view)
        p.contentView = bg
        panel = p

        view.onChange = { [weak self] in self?.reload() }
        view.onResize = { [weak self] _ in self?.place() }
        view.onClose = { [weak self] in self?.close() }
        reload()
        place()
        p.makeKeyAndOrderFront(nil)

        // Close on any click outside: other apps (global) or other DotBar windows (local).
        // A click on the anchor itself is left to `toggle`, which closes on mouse up.
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated {
                if let self, e.window !== self.panel, e.window !== self.anchor?.window { self.close() }
            }
            return e
        }) { monitors.append(l) }
        requestAccessIfNeeded()
    }

    /// Centred under the status item, kept on screen, top edge just below the menu bar.
    private func place() {
        guard let p = panel, let button = anchor, let bw = button.window else { return }
        let size = view.frame.size
        p.contentView?.frame.size = size
        view.frame.origin = .zero
        let r = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (bw.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = r.midX - size.width / 2
        x = min(max(x, screen.minX + 6), screen.maxX - size.width - 6)
        p.setFrame(NSRect(x: x, y: r.minY - 6 - size.height, width: size.width, height: size.height), display: true)
    }

    private func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        store = nil
        panel?.orderOut(nil)
        panel = nil
        Self.current = nil
        Self.closedAt = Date()
    }

    // MARK: Events

    private var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    private func requestAccessIfNeeded() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        let s = EKEventStore()
        store = s
        s.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload() }
        }
    }

    private func reload() {
        view.access = authorized ? .granted
            : (EKEventStore.authorizationStatus(for: .event) == .notDetermined ? .pending : .denied)
        guard authorized else { view.events = [:]; return }
        let s = store ?? EKEventStore()
        if store == nil {
            store = s
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: s, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        let (start, end) = view.gridRange
        let cal = Calendar.current
        var byDay: [Int: [EKEvent]] = [:]
        let all = s.events(matching: s.predicateForEvents(withStart: start, end: end, calendars: nil))
        for e in all {
            // Multi-day events appear on every day they touch within the grid.
            guard let s0 = e.startDate else { continue }
            let e0: Date = e.endDate ?? s0
            var d = max(cal.startOfDay(for: s0), start)
            let last = e0 > s0 ? e0.addingTimeInterval(-1) : e0
            while d <= last && d < end {
                byDay[cal.dateComponents([.day], from: start, to: d).day ?? 0, default: []].append(e)
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
        }
        for k in byDay.keys {
            byDay[k]!.sort { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
        }
        view.events = byDay
    }
}

// MARK: - View

@MainActor
private final class CalendarView: NSView {
    enum Access { case granted, pending, denied }

    var onChange: () -> Void = {}
    var onResize: (NSSize) -> Void = { _ in }
    var onClose: () -> Void = {}
    var access: Access = .pending { didSet { relayout() } }
    /// Events keyed by day offset from the grid's first day.
    var events: [Int: [EKEvent]] = [:] { didSet { relayout() } }

    private let cal = Calendar.current
    private var month: Date                      // first day of the displayed month
    private var selected: Date                   // start of the selected day

    static let width: CGFloat = 280, headerH: CGFloat = 40, weekdayH: CGFloat = 20
    static let rowH: CGFloat = 36, sectionH: CGFloat = 28, eventH: CGFloat = 22, maxEvents = 8

    override init(frame: NSRect) {
        let today = Calendar.current.startOfDay(for: Date())
        selected = today
        month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today))!
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        relayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    var gridStart: Date {
        let wd = cal.component(.weekday, from: month)
        return cal.date(byAdding: .day, value: -((wd - cal.firstWeekday + 7) % 7), to: month)!
    }
    var gridRange: (Date, Date) { (gridStart, cal.date(byAdding: .day, value: 42, to: gridStart)!) }
    private var selectedIndex: Int? {
        let i = cal.dateComponents([.day], from: gridStart, to: selected).day ?? -1
        return (0..<42).contains(i) ? i : nil
    }
    private var dayEvents: [EKEvent] { selectedIndex.flatMap { events[$0] } ?? [] }

    private var colW: CGFloat { Self.width / 7 }
    private var gridTop: CGFloat { Self.headerH + Self.weekdayH }
    private var listTop: CGFloat { gridTop + Self.rowH * 6 + 6 }
    private func cellRect(_ i: Int) -> NSRect {
        NSRect(x: CGFloat(i % 7) * colW, y: gridTop + CGFloat(i / 7) * Self.rowH, width: colW, height: Self.rowH)
    }
    private func buttonRect(_ k: Int) -> NSRect {       // 0 = prev, 1 = today, 2 = next
        NSRect(x: Self.width - 8 - CGFloat(3 - k) * 28, y: 8, width: 28, height: 24)
    }
    private var listRows: Int {
        guard access == .granted else { return 1 }
        let n = dayEvents.count
        return n == 0 ? 1 : min(n, Self.maxEvents) + (n > Self.maxEvents ? 1 : 0)
    }

    private func relayout() {
        let h = listTop + Self.sectionH + CGFloat(listRows) * Self.eventH + 10
        if frame.height != h { setFrameSize(NSSize(width: Self.width, height: h)); onResize(frame.size) }
        needsDisplay = true
    }

    // MARK: Drawing

    private static let title = NSFont.systemFont(ofSize: 18, weight: .semibold)
    private static let small = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let day = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
    private static let dayBold = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
    private static let body = NSFont.systemFont(ofSize: 13)
    /// Weekend day numbers; which weekdays count as weekend follows the user's locale.
    private static let weekend = NSColor.systemRed
    private static let weekendWeekdays: Set<Int> = {
        let cal = Calendar.current
        let sunday = cal.date(from: DateComponents(year: 2023, month: 1, day: 1))!   // a Sunday
        return Set((0..<7).filter { cal.isDateInWeekend(cal.date(byAdding: .day, value: $0, to: sunday)!) }.map { $0 + 1 })
    }()
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("LLLL yyyy"); return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEE d MMMM"); return f
    }()
    private static let interval: DateIntervalFormatter = {
        let f = DateIntervalFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        // Header band: month title, buttons, weekday letters.
        accent.setFill()
        NSRect(x: 0, y: 0, width: Self.width, height: gridTop).fill()
        str(Self.monthFormatter.string(from: month), Self.title, .white)
            .draw(at: NSPoint(x: 12, y: (Self.headerH - Self.title.pointSize * 1.25) / 2 + 2))
        for k in 0..<3 { drawButton(k, in: buttonRect(k)) }
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        for c in 0..<7 {
            let wd = (cal.firstWeekday - 1 + c) % 7                 // 0 = Sunday
            let s = str(symbols[wd], Self.small, Self.weekendWeekdays.contains(wd + 1) ? .white.withAlphaComponent(0.65) : .white)
            s.draw(at: NSPoint(x: CGFloat(c) * colW + (colW - s.size().width) / 2, y: Self.headerH + 2))
        }

        // Month grid.
        let today = cal.startOfDay(for: Date())
        let thisMonth = cal.component(.month, from: month)
        for i in 0..<42 {
            let d = cal.date(byAdding: .day, value: i, to: gridStart)!
            let r = cellRect(i)
            let isToday = d == today, isSel = i == selectedIndex
            let pill = NSRect(x: r.midX - 19, y: r.minY + 3, width: 38, height: r.height - 6)
            if isToday {
                accent.setFill(); NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            } else if isSel {
                NSColor.quaternaryLabelColor.setFill(); NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            }
            let inMonth = cal.component(.month, from: d) == thisMonth
            let color: NSColor = isToday ? .white
                : cal.isDateInWeekend(d) ? Self.weekend.withAlphaComponent(inMonth ? 1 : 0.4)
                : (inMonth ? .labelColor : .tertiaryLabelColor)
            let s = str("\(cal.component(.day, from: d))", isToday ? Self.dayBold : Self.day, color)
            let ss = s.size()
            s.draw(at: NSPoint(x: r.midX - ss.width / 2, y: r.minY + 5))
            // Up to three dots, one per distinct calendar colour.
            if let evs = events[i], !evs.isEmpty {
                var colors: [NSColor] = []
                for e in evs where colors.count < 3 {
                    let c = e.calendar?.color ?? .systemGray
                    if !colors.contains(where: { $0.isEqual(c) }) { colors.append(c) }
                }
                let dot: CGFloat = 5, gap: CGFloat = 3
                var x = r.midX - (CGFloat(colors.count) * dot + CGFloat(colors.count - 1) * gap) / 2
                for c in colors {
                    (isToday ? NSColor.white.withAlphaComponent(0.85) : c).setFill()
                    NSBezierPath(ovalIn: NSRect(x: x, y: r.maxY - 10, width: dot, height: dot)).fill()
                    x += dot + gap
                }
            }
        }

        // Selected day's events.
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: listTop - 3, width: Self.width, height: 1).fill()
        let head = selected == today ? "TODAY" : Self.dayFormatter.string(from: selected).uppercased()
        let hs = str(head, Self.small, accent)
        hs.draw(at: NSPoint(x: (Self.width - hs.size().width) / 2, y: listTop + 7))
        var y = listTop + Self.sectionH
        switch access {
        case .pending: row(y, text: "Waiting for Calendar access…", color: .secondaryLabelColor)
        case .denied: row(y, text: "Calendar access is off — click to open Settings", color: .secondaryLabelColor)
        case .granted:
            let evs = dayEvents
            if evs.isEmpty { row(y, text: "No events", color: .secondaryLabelColor) }
            for e in evs.prefix(Self.maxEvents) {
                let time = e.isAllDay ? "All Day" : Self.interval.string(from: e.startDate, to: e.endDate)
                row(y, text: e.title ?? "", color: .labelColor, dot: e.calendar?.color ?? .systemGray, trailing: time)
                y += Self.eventH
            }
            if evs.count > Self.maxEvents {
                row(y, text: "+\(evs.count - Self.maxEvents) more", color: .secondaryLabelColor)
            }
        }
    }

    private func row(_ y: CGFloat, text: String, color: NSColor, dot: NSColor? = nil, trailing: String? = nil) {
        var x: CGFloat = 12
        if let dot {
            dot.setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: y + 6, width: 10, height: 10)).fill()
            x += 18
        }
        var right = Self.width - 12
        if let trailing {
            let t = str(trailing, Self.body, .secondaryLabelColor)
            right -= t.size().width
            t.draw(at: NSPoint(x: right, y: y + 2))
            right -= 10
        }
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text, attributes: [.font: Self.body, .foregroundColor: color, .paragraphStyle: ps])
            .draw(with: NSRect(x: x, y: y + 2, width: max(0, right - x), height: Self.eventH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func str(_ s: String, _ f: NSFont, _ c: NSColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c])
    }

    /// Header buttons drawn as paths: SF Symbols would pull the whole symbol catalog
    /// (~50 MB of CoreSVG data) into memory for three glyphs.
    private func drawButton(_ k: Int, in r: NSRect) {
        NSColor.white.set()
        let c = NSPoint(x: r.midX, y: r.midY)
        if k == 1 {                                         // today: small calendar page
            let page = NSRect(x: c.x - 8, y: c.y - 7, width: 16, height: 14)
            let outline = NSBezierPath(roundedRect: page, xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1.5; outline.stroke()
            NSRect(x: page.minX, y: page.minY, width: page.width, height: 4).fill()
            for i in 0..<6 {
                NSRect(x: page.minX + 3 + CGFloat(i % 3) * 4, y: page.minY + 6 + CGFloat(i / 3) * 3.5, width: 2, height: 2).fill()
            }
            return
        }
        let dx: CGFloat = k == 0 ? 3 : -3                   // chevron pointing left / right
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x + dx, y: c.y - 7))
        p.line(to: NSPoint(x: c.x - dx, y: c.y))
        p.line(to: NSPoint(x: c.x + dx, y: c.y + 7))
        p.lineWidth = 2; p.lineCapStyle = .round; p.lineJoinStyle = .round
        p.stroke()
    }

    // MARK: Input

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.y < Self.headerH {
            if buttonRect(0).contains(p) { shiftMonth(-1) }
            else if buttonRect(1).contains(p) { goToday() }
            else if buttonRect(2).contains(p) { shiftMonth(1) }
            return
        }
        if p.y >= gridTop, p.y < gridTop + Self.rowH * 6 {
            let i = Int((p.y - gridTop) / Self.rowH) * 7 + min(6, Int(p.x / colW))
            let d = cal.date(byAdding: .day, value: i, to: gridStart)!
            selected = d
            if cal.component(.month, from: d) != cal.component(.month, from: month) {
                month = cal.date(from: cal.dateComponents([.year, .month], from: d))!
                onChange()
            }
            relayout()
            return
        }
        if p.y >= listTop + Self.sectionH {
            if access == .denied, let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(u); onClose(); return
            }
            let i = Int((p.y - listTop - Self.sectionH) / Self.eventH)
            let evs = dayEvents
            if access == .granted, i < min(evs.count, Self.maxEvents) { open(evs[i]) }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // One month per deliberate swipe/notch; ignore momentum and tiny deltas.
        guard event.momentumPhase.isEmpty, abs(event.scrollingDeltaY) > 3 else { return }
        if event.phase == .began || event.phase.isEmpty { shiftMonth(event.scrollingDeltaY > 0 ? -1 : 1) }
    }

    private func shiftMonth(_ n: Int) {
        month = cal.date(byAdding: .month, value: n, to: month)!
        onChange(); relayout()
    }

    private func goToday() {
        let today = cal.startOfDay(for: Date())
        selected = today
        month = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        onChange(); relayout()
    }

    private func open(_ e: EKEvent) {
        let id = e.calendarItemIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if let u = URL(string: "ical://ekevent/\(id)?method=show&options=more"), NSWorkspace.shared.open(u) {
            onClose(); return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        onClose()
    }
}
