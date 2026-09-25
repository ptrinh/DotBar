import AppKit
import SwiftUI

/// First-launch tour: offers the compact calendar, battery + CPU/RAM dots and AI usage icons,
/// helps hide the macOS items they replace, and shows how to rearrange the menu bar.
/// Choices apply to the real menu bar at once. Built on open, dropped on close.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = OnboardingView(close: { [weak self] in self?.window?.close() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Welcome to DotBar"
            w.styleMask = [.titled, .closable]
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window?.contentViewController = nil
        window = nil
    }
}

private struct OnboardingView: View {
    let close: () -> Void
    @State private var step = 0
    private let steps: [Step]

    init(close: @escaping () -> Void) {
        self.close = close
        var s: [Step] = [.calendar, .battery]
        if !AIChoice.available.isEmpty { s.append(.ai) }
        s.append(.done)
        steps = s
    }

    enum Step { case calendar, battery, ai, done }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch steps[step] {
                case .calendar: CalendarStep()
                case .battery: BatteryStep()
                case .ai: AIStep()
                case .done: DoneStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(28)
            Divider()
            HStack {
                Text("\(step + 1) of \(steps.count)").foregroundStyle(.secondary).font(.caption)
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                if step < steps.count - 1 {
                    Button("Next") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Open Preferences") { close(); PreferencesWindowController.shared.show() }
                    Button("Done") { close() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 560, height: 470)
    }
}

// MARK: - Steps

private struct CalendarStep: View {
    @State private var on = Onboarding.has("Calendar Icon")
    @State private var hidden = MenuBarTweaks.clockDateHidden

    var body: some View {
        StepLayout(title: "A compact calendar",
                   text: "Today's weekday and date in one small icon. Click it for a month calendar with your events.",
                   preview: Recipes.calendarIcon, output: #"{"text":"","symbol":"calendar:24:Thu:black"}"#,
                   on: $on, onChange: { Onboarding.set("Calendar Icon", $0) }) {
            TweakRow(done: hidden, doneText: "The clock no longer shows the date.",
                     askText: "Save space by hiding the date from the macOS clock.",
                     manual: "System Settings → Menu Bar → Clock → Clock Options: turn off Show date and Show the day of the week.",
                     apply: { hidden = MenuBarTweaks.hideClockDate() }, applyTitle: "Hide the date for me")
        }
    }
}

private struct BatteryStep: View {
    @State private var on = Onboarding.has("Battery + CPU/RAM dots")
    @State private var hidden = MenuBarTweaks.systemBatteryHidden

    var body: some View {
        StepLayout(title: "Battery, CPU and RAM",
                   text: "A slim battery with two dots that light up when CPU (C) or memory (M) gets busy. Click it for health, cycle count and top processes.",
                   preview: Recipes.batteryWithLoadDots, output: ##"{"text":"","symbol":"battery:82","dots":["#FF453A","#FFD60A"]}"##,
                   on: $on, onChange: { Onboarding.set("Battery + CPU/RAM dots", $0) }) {
            TweakRow(done: hidden, doneText: "The macOS battery icon is hidden.",
                     askText: "Hide the macOS battery icon so it isn't shown twice.",
                     manual: "System Settings → Menu Bar → Battery: turn off Show in Menu Bar.",
                     apply: { hidden = MenuBarTweaks.hideSystemBattery() }, applyTitle: "Hide it for me")
        }
    }
}

private struct AIStep: View {
    @State private var choice: AIChoice = AIChoice.current

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your AI limits, always in sight").font(.title2.bold())
            Text("Two bars: the top one is your current 5-hour session, the bottom one your week. They turn red from 90%, and a click shows exact numbers and reset times.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 28) {
                IconPreview(item: Recipes.aiUsage, output: #"{"text":"","symbol":"usage:38:64:Claude"}"#)
                if AIChoice.available.contains(.codex) {
                    IconPreview(item: Recipes.codexUsage, output: #"{"text":"","symbol":"usage:12:47:Codex"}"#)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            Picker(AIChoice.detected.isEmpty ? "Which do you use?" : "Show AI usage for", selection: $choice) {
                ForEach(AIChoice.options) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: choice) { _, c in c.apply() }
            if !AIChoice.detected.isEmpty {
                Label("Found your \(AIChoice.detected.map(\.label).joined(separator: " and ")) sign-in on this Mac.",
                      systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.callout)
            } else if Recipes.isSandboxed {
                Text("The icon asks once for access the first time you click it.").foregroundStyle(.secondary).font(.callout)
            }
        }
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Arrange your menu bar").font(.title2.bold())
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "command").font(.system(size: 28, weight: .medium)).frame(width: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hold ⌘ Command and drag any icon").font(.headline)
                    Text("Move DotBar's icons, or macOS's, to where you want them. Drag an icon off the menu bar while holding ⌘ to remove it.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "cursorarrow.click.2").font(.system(size: 26, weight: .medium)).frame(width: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Click an icon for details, right-click for its menu").font(.headline)
                    Text("Add more from Preferences → +: 30+ presets for prices, network, weather, Pomodoro, or your own shell scripts.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct StepLayout<Extra: View>: View {
    let title: String, text: String
    let preview: Item, output: String
    @Binding var on: Bool
    let onChange: (Bool) -> Void
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            IconPreview(item: preview, output: output).frame(maxWidth: .infinity).padding(.vertical, 8)
            Toggle("Show it in my menu bar", isOn: $on)
                .toggleStyle(.switch)
                .onChange(of: on) { _, v in onChange(v) }
            if on { extra() }
        }
    }
}

private struct TweakRow: View {
    let done: Bool, doneText: String, askText: String, manual: String
    let apply: () -> Void, applyTitle: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if done {
                    Label(doneText, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text(askText)
                    if MenuBarTweaks.canApply {
                        Button(applyTitle, action: apply)
                        Text("Or by hand: \(manual)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(manual).font(.callout).foregroundStyle(.secondary)
                        Button("Open Menu Bar Settings") { MenuBarTweaks.openMenuBarSettings() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

/// A menu bar icon drawn by the real DotBarView from fixed output, on a menu-bar-like strip.
private struct IconPreview: View {
    let item: Item, output: String
    var body: some View {
        StaticIcon(item: item, output: output)
            .scaleEffect(2.4)
            .frame(height: 70)
            .padding(.horizontal, 40)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.16)))
            .environment(\.colorScheme, .dark)
    }
}

private struct StaticIcon: NSViewRepresentable {
    let item: Item, output: String
    func makeNSView(context: Context) -> DotBarView {
        let v = DotBarView()
        v.appearance = NSAppearance(named: .vibrantDark)                 // live menu bar look, never dimmed
        return v
    }
    func updateNSView(_ v: DotBarView, context: Context) {
        let out = ScriptOutput.parse(output)
        let colors = (out.overrideDots ?? []).compactMap { NSColor(hex: $0) }
        v.configure(item: item, output: out, dotColors: colors)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DotBarView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

// MARK: - Model

/// Onboarding edits the live item list by preset name.
@MainActor
enum Onboarding {
    static func has(_ name: String) -> Bool { AppState.shared.items.contains { $0.name == name } }

    static func set(_ name: String, _ on: Bool) {
        let state = AppState.shared
        if on {
            guard !has(name), let recipe = Recipes.all().first(where: { $0.name == name }) else { return }
            state.items.append(recipe)
        } else {
            state.items.removeAll { $0.name == name }
        }
    }
}

private enum AIChoice: String, Identifiable, CaseIterable {
    case claude, codex, both, none
    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .both: "Both"
        case .none: "Neither"
        }
    }

    static let claudeName = "AI Usage Icon (Claude)", codexName = "AI Usage Icon (Codex)"

    /// Providers offered here (Codex is off on the China mainland storefront).
    static var available: [AIChoice] { Recipes.isChinaStorefront ? [.claude] : [.claude, .codex] }

    /// Sign-ins found on this Mac (never in the sandbox, which cannot see them).
    static var detected: [AIChoice] {
        guard !Recipes.isSandboxed else { return [] }
        return available.filter { $0 == .claude ? Store.hasClaudeCodeSignIn : Store.hasCodexSignIn }
    }

    static var options: [AIChoice] {
        available.count > 1 ? [.claude, .codex, .both, .none] : [.claude, .none]
    }

    /// What the menu bar shows now.
    @MainActor static var current: AIChoice {
        switch (Onboarding.has(claudeName), Onboarding.has(codexName)) {
        case (true, true): .both
        case (true, false): .claude
        case (false, true): .codex
        default: detected.isEmpty ? .none : (detected.count > 1 ? .both : detected[0])
        }
    }

    @MainActor func apply() {
        Onboarding.set(Self.claudeName, self == .claude || self == .both)
        Onboarding.set(Self.codexName, self == .codex || self == .both)
    }
}
