import AppKit
import EventKit

/// Month calendar + the selected day's events, shown from a status item (click action `.calendar`).
///
/// Everything is created on open and dropped on close — popover, view and `EKEventStore` —
/// so the idle app pays nothing for it. One custom-drawn view, no SwiftUI, one event query
/// per visible month, reloads only on `EKEventStoreChanged` while open.
@MainActor
final class CalendarPopover: NSObject, NSPopoverDelegate {
    private static var current: CalendarPopover?

    static func toggle(relativeTo button: NSView) {
        if let c = current { c.popover.performClose(nil); return }
        let c = CalendarPopover()
        current = c
        c.show(relativeTo: button)
    }

    private let popover = NSPopover()
    private let view = CalendarView()
    private var store: EKEventStore?
    private var observer: NSObjectProtocol?

    private func show(relativeTo button: NSView) {
        let vc = NSViewController()
        vc.view = view
        view.onChange = { [weak self] in self?.reload() }
        view.onResize = { [weak self] size in self?.popover.contentSize = size }
        view.onClose = { [weak self] in self?.popover.performClose(nil) }
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        reload()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        requestAccessIfNeeded()
    }

    func popoverDidClose(_ notification: Notification) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        store = nil
        popover.contentViewController = nil
        Self.current = nil
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
        for e in s.events(matching: s.predicateForEvents(withStart: start, end: end, calendars: nil)) {
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
        for (k, name) in ["chevron.left", "calendar", "chevron.right"].enumerated() {
            drawSymbol(name, in: buttonRect(k), color: .white)
        }
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        for c in 0..<7 {
            let s = str(symbols[(cal.firstWeekday - 1 + c) % 7], Self.small, .white)
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
            let color: NSColor = isToday ? .white
                : (cal.component(.month, from: d) == thisMonth ? .labelColor : .tertiaryLabelColor)
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

    private func drawSymbol(_ name: String, in r: NSRect, color: NSColor) {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)
                .applying(.init(paletteColors: [color]))) else { return }
        let s = img.size
        img.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height),
                 from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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
