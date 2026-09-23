import SwiftUI

struct ItemEditorView: View {
    let state: AppState          // not observed: the editor edits `item`; live output is shown by PreviewBox only
    @Binding var item: Item

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top) {
                    previewBox
                    Spacer()
                    Button("Refresh Now") { state.refresh(item) }.disabled(!item.source.isScript)
                }
            }

            Section("Source") {
                LabeledContent("Name") {
                    TextField("", text: $item.name).labelsHidden()
                }
                Picker("Type", selection: sourceKind) {
                    Text("Static text").tag(0)
                    Text("Script").tag(1)
                }.pickerStyle(.segmented)
                switch item.source {
                case .static(let text):
                    LabeledContent("Text") {
                        TextField("", text: Binding(get: { text }, set: { item.source = .static(text: $0) }))
                            .labelsHidden()
                    }
                case .script(let cmd, let secs):
                    commandField(cmd) { item.source = .script(command: $0, refreshSeconds: secs) }
                    Toggle("Streaming", isOn: streaming)
                    LabeledContent("Refresh every") {
                        HStack(spacing: 6) {
                            TextField("", value: Binding(get: { secs },
                                                         set: { item.source = .script(command: cmd, refreshSeconds: max(0, $0)) }),
                                      format: .number)
                                .labelsHidden()
                                .frame(width: 72)
                                .multilineTextAlignment(.trailing)
                            Text("seconds (0 = manual)").foregroundStyle(.secondary).fixedSize()
                        }
                    }
                    scriptHints
                case .stream(let cmd):
                    commandField(cmd) { item.source = .stream(command: $0) }
                    Toggle("Streaming", isOn: streaming)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Print a `~~~` line to end each update block.")
                        Text("The command runs once and keeps running; DotBar updates the item on every block (or every line, if the script never prints `~~~`). Refresh restarts it.")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    scriptHints
                }
            }

            Section("Text style") {
                FontPicker(spec: $item.font)
                LabeledContent("SF Symbol") {
                    TextField("", text: Binding(get: { item.symbol ?? "" }, set: { item.symbol = $0.isEmpty ? nil : $0 }),
                              prompt: Text("e.g. bolt.fill (empty = none)"))
                        .labelsHidden()
                }
                LabeledContent("Max width") {
                    HStack(spacing: 6) {
                        TextField("", value: $item.maxWidth, format: .number)
                            .labelsHidden()
                            .frame(width: 72)
                            .multilineTextAlignment(.trailing)
                        Text("points (0 = unlimited)").foregroundStyle(.secondary).fixedSize()
                    }
                }
                ColorSpecEditor(title: "Text color", spec: $item.textColor, allowSystem: true)
            }

            Section("Display") {
                Toggle("Show in menu bar", isOn: $item.showInBar)
                if !item.showInBar {
                    Text("Hidden from the bar. Its text and dots appear inside the menu of every other DotBar item.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent("Padding") {
                    HStack(spacing: 6) {
                        Text("L").foregroundStyle(.secondary)
                        TextField("", value: $item.paddingLeft, format: .number).labelsHidden().frame(width: 44).multilineTextAlignment(.trailing)
                        Stepper("", value: $item.paddingLeft, in: 0...20, step: 1).labelsHidden()
                        Text("R").foregroundStyle(.secondary).padding(.leading, 8)
                        TextField("", value: $item.paddingRight, format: .number).labelsHidden().frame(width: 44).multilineTextAlignment(.trailing)
                        Stepper("", value: $item.paddingRight, in: 0...20, step: 1).labelsHidden()
                        Text("pt").foregroundStyle(.secondary)
                    }
                }
                Picker("Show", selection: $item.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Dot style", selection: $item.dotStyle) {
                    ForEach(DotStyle.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Dot size") {
                    HStack(spacing: 6) {
                        Text("\(Int(item.dotSize)) pt").monospacedDigit().fixedSize()
                        Stepper("", value: $item.dotSize, in: 3...14, step: 1).labelsHidden()
                    }
                }
                ClickActionPicker(title: "Left click", action: $item.action)
                ClickActionPicker(title: "⌥ + click", action: $item.altAction)
                ClickActionPicker(title: "Middle click", action: $item.middleAction)
                Text("Right click always shows the menu.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                DotsEditor(dots: $item.dots)
                if !item.dots.isEmpty {
                    Picker("Position", selection: $item.dotsPosition) {
                        Text("Left of text").tag(DotsPosition.leading)
                        Text("Right of text").tag(DotsPosition.trailing)
                    }
                }
            } header: { Text("Dots (0–3)") }

            Section("Behavior") {
                Picker("Notify", selection: $item.notify) {
                    ForEach(NotifySpec.allCases) { Text($0.label).tag($0) }
                }
                Text("Notifications start from the second result, so launching the app is quiet.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HotkeyRecorder(label: "Refresh hotkey", hotkey: $item.hotkey)
                Text("Global shortcut that refreshes this item. At least one modifier is required.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Hide when empty", isOn: $item.hideWhenEmpty)
                Text("Removes the status item from the menu bar while the output is empty.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private var previewBox: some View { PreviewBox(state: state, item: item) }
}

/// The only part of the editor that re-renders on script output.
private struct PreviewBox: View {
    let state: AppState
    @ObservedObject var live: AppState.LiveOutputs
    let item: Item
    init(state: AppState, item: Item) { self.state = state; self.live = state.live; self.item = item }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preview").font(.caption).foregroundStyle(.secondary)
            DotBarPreview(state: state, item: item)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            if let o = state.output(for: item), o.failed, let e = o.errorMessage {
                Text(e).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
        }
    }
}

extension ItemEditorView {

    /// Command text field + the "…" file picker, shared by scripts and streams.
    private func commandField(_ cmd: String, set: @escaping (String) -> Void) -> some View {
        LabeledContent {
            HStack(alignment: .top, spacing: 8) {
                TextField("", text: Binding(get: { cmd }, set: set),
                          prompt: Text("e.g. curl -s https://… | jq -r .price"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...6)
                    .font(.system(.body, design: .monospaced))
                Button("…") { if let c = FilePicker.chooseScriptCommand() { set(c) } }
                    .help("Choose a script file")
            }
        } label: {
            Text("Command").fixedSize()
        }
    }

    /// Collapsed cheat-sheet for what a script can print.
    private var scriptHints: some View {
        DisclosureGroup("Output syntax help") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Extra output lines become menu items — a line of \(Text("----").monospaced()) is a separator.")
                Text("ANSI colors are rendered: \(Text("\\e[31m").monospaced()), \(Text("\\e[1;32m").monospaced()), \(Text("\\e[38;5;Nm").monospaced()).")
                Text("xbar-style params after a \(Text("|").monospaced()): \(Text("color= href= bash= refresh= sfimage= length=").monospaced()).")
                Text("A \(Text("--").monospaced()) prefix nests the line into a submenu.")
                Text("Or print JSON with any of \(Text("text, color, dots, menu, symbol, refresh, action, mode, badge, badgeColor").monospaced()).")
                Link("Full reference (Recipes.md)",
                     destination: URL(string: "https://github.com/ptrinh/DotBar/blob/main/Recipes.md")!)
                    .padding(.top, 2)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 12)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceKind: Binding<Int> {
        Binding(get: { item.source.isScript ? 1 : 0 }, set: { v in
            switch (v, item.source) {
            case (0, .script), (0, .stream): item.source = .static(text: state.output(for: item)?.text ?? "")
            case (1, .static(let t)): item.source = .script(command: "echo \"\(t)\"", refreshSeconds: 60)
            default: break
            }
        })
    }

    /// Converts `.script(cmd, s)` ↔ `.stream(cmd)`, keeping the command.
    private var streaming: Binding<Bool> {
        Binding(get: { item.source.isStream }, set: { on in
            switch (on, item.source) {
            case (true, .script(let cmd, _)): item.source = .stream(command: cmd)
            case (false, .stream(let cmd)): item.source = .script(command: cmd, refreshSeconds: 60)
            default: break
            }
        })
    }
}

// MARK: - Click action

/// Action kind + its argument field. Reused for left click, ⌥ + click and middle click.
struct ClickActionPicker: View {
    let title: String
    @Binding var action: ClickAction

    var body: some View {
        Picker(title, selection: kind) {
            Text("Show menu").tag(0)
            Text("Copy text").tag(1)
            Text("Run script").tag(2)
            Text("Open URL").tag(3)
            Text("Show calendar").tag(4)
        }
        switch action {
        case .script(let cmd):
            LabeledContent("Command") {
                TextField("", text: Binding(get: { cmd }, set: { action = .script(command: $0) }))
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
            }
        case .openURL(let u):
            LabeledContent("URL") {
                TextField("", text: Binding(get: { u }, set: { action = .openURL(url: $0) })).labelsHidden()
            }
        default: EmptyView()
        }
    }

    private var kind: Binding<Int> {
        Binding(get: {
            switch action { case .menu: 0; case .copy: 1; case .script: 2; case .openURL: 3; case .calendar: 4 }
        }, set: { v in
            switch v {
            case 1: action = .copy
            case 2: action = .script(command: "")
            case 3: action = .openURL(url: "https://")
            case 4: action = .calendar
            default: action = .menu
            }
        })
    }
}

// MARK: - Font

struct FontPicker: View {
    @Binding var spec: FontSpec
    var body: some View {
        LabeledContent("Font") {
            FontFamilyPopUp(family: Binding(get: { spec.family ?? "System" }, set: { spec.family = $0 == "System" ? nil : $0 }))
                .frame(width: 220)
        }
        Picker("Weight", selection: $spec.weight) {
            ForEach(FontSpec.Weight.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        LabeledContent("Size") {
            HStack(spacing: 6) {
                Text("\(Int(spec.size)) pt").monospacedDigit().fixedSize()
                Stepper("", value: $spec.size, in: 8...20, step: 1).labelsHidden()
            }
        }
        Toggle("Monospaced digits", isOn: $spec.monospacedDigits)
    }
}

// MARK: - Dots

struct DotsEditor: View {
    @Binding var dots: [Dot]

    var body: some View {
        ForEach($dots) { $dot in
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Label") {
                        HStack(spacing: 8) {
                            TextField("", text: Binding(get: { dot.label }, set: { dot.label = String($0.prefix(1)) }), prompt: Text("C"))
                                .labelsHidden().frame(width: 40).multilineTextAlignment(.center)
                            Text("one character left of the dot").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    LabeledContent("Value from") {
                        Picker("", selection: Binding(get: { dot.source.isScript ? 1 : 0 }, set: { v in
                            dot.source = v == 0 ? .mainValue : .script(command: "", refreshSeconds: 60)
                        })) {
                            Text("Item's text").tag(0)
                            Text("Own script").tag(1)
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    if case .script(let cmd, let secs) = dot.source {
                        LabeledContent("Command") {
                            TextField("", text: Binding(get: { cmd }, set: { dot.source = .script(command: $0, refreshSeconds: secs) }),
                                      prompt: Text("e.g. curl -s https://… | jq -r .status"))
                                .labelsHidden()
                                .font(.system(.body, design: .monospaced))
                        }
                        LabeledContent("Refresh every") {
                            HStack(spacing: 6) {
                                TextField("", value: Binding(get: { secs },
                                                             set: { dot.source = .script(command: cmd, refreshSeconds: max(0, $0)) }),
                                          format: .number)
                                    .labelsHidden()
                                    .frame(width: 72)
                                    .multilineTextAlignment(.trailing)
                                Text("seconds").foregroundStyle(.secondary).fixedSize()
                            }
                        }
                    }
                    ColorSpecEditor(title: "Color", spec: $dot.color, allowSystem: false)
                }
                .padding(.leading, 12)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                HStack {
                    Circle().fill(Color(nsColor: swatchColor(dot.color))).frame(width: 8, height: 8)
                    Text("Dot \((dots.firstIndex(where: { $0.id == dot.id }) ?? 0) + 1)").fixedSize()
                    Spacer()
                    Button(role: .destructive) { dots.removeAll { $0.id == dot.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
        }
        if dots.count < 3 {
            Button { dots.append(Dot()) } label: { Label("Add dot", systemImage: "plus.circle") }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Editor swatch: for gradients show the end color so the dot is visible before any data arrives.
private func swatchColor(_ spec: ColorSpec) -> NSColor {
    if case .gradient(_, _, _, let to) = spec { return NSColor(hex: to) ?? .gray }
    return RuleEngine.color(for: spec, output: nil) ?? .gray
}

extension DotSource { var isScript: Bool { if case .script = self { return true } else { return false } } }

// MARK: - Color spec

struct ColorSpecEditor: View {
    let title: String
    @Binding var spec: ColorSpec
    let allowSystem: Bool

    var body: some View {
        Picker(title, selection: Binding(get: { kind }, set: { v in
            let base = fixedHex ?? (allowSystem ? nil : "#8E8E93")
            switch v {
            case 1: spec = .rules([], fallback: base)
            case 2: spec = .gradient(min: 0, max: 100, from: (base ?? "#FF453A") + "00", to: base ?? "#FF453A")
            default: spec = .fixed(base)
            }
        })) {
            Text("Fixed").tag(0)
            Text("By condition").tag(1)
            Text("Gradient").tag(2)
        }.pickerStyle(.segmented)

        switch spec {
        case .fixed(let hex):
            HexColorField(label: allowSystem ? "Color (empty = system)" : "Color", hex: Binding(get: { hex }, set: { spec = .fixed($0) }), allowNil: allowSystem)
        case .rules(let rules, let fallback):
            RulesEditor(rules: Binding(get: { rules }, set: { spec = .rules($0, fallback: fallback) }))
            HexColorField(label: allowSystem ? "Otherwise (empty = system)" : "Otherwise", hex: Binding(get: { fallback }, set: { spec = .rules(rules, fallback: $0) }), allowNil: allowSystem)
        case .gradient(let lo, let hi, let from, let to):
            LabeledContent("Value range") {
                HStack(spacing: 6) {
                    TextField("", value: Binding(get: { lo }, set: { spec = .gradient(min: $0, max: hi, from: from, to: to) }), format: .number)
                        .labelsHidden().frame(width: 64).multilineTextAlignment(.trailing)
                    Text("→").foregroundStyle(.secondary)
                    TextField("", value: Binding(get: { hi }, set: { spec = .gradient(min: lo, max: $0, from: from, to: to) }), format: .number)
                        .labelsHidden().frame(width: 64).multilineTextAlignment(.trailing)
                }
            }
            HexColorField(label: "Color at min", hex: Binding(get: { from }, set: { spec = .gradient(min: lo, max: hi, from: $0 ?? from, to: to) }), allowNil: false)
            HexColorField(label: "Color at max", hex: Binding(get: { to }, set: { spec = .gradient(min: lo, max: hi, from: from, to: $0 ?? to) }), allowNil: false)
            Text("The first number in the value is mapped linearly between the two colors. Alpha is interpolated too, so a transparent start fades in.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var kind: Int {
        switch spec { case .fixed: 0; case .rules: 1; case .gradient: 2 }
    }
    private var fixedHex: HexColor? {
        switch spec { case .fixed(let h): h; case .rules(_, let f): f; case .gradient(_, _, _, let t): String(t.prefix(7)) }
    }
}

struct HexColorField: View {
    let label: String
    @Binding var hex: HexColor?
    let allowNil: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: NSColor(hex: hex) ?? .labelColor) },
                    set: { hex = NSColor($0).hexString }
                ), supportsOpacity: true).labelsHidden()
                TextField("", text: Binding(get: { hex ?? "" }, set: { hex = $0.isEmpty && allowNil ? nil : $0 }),
                          prompt: Text("#RRGGBB"))
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: 96)
                if allowNil && hex != nil {
                    Button("Reset") { hex = nil }.buttonStyle(.link)
                }
            }
            .fixedSize()
        } label: {
            Text(label).fixedSize()
        }
    }
}

// MARK: - Rules

struct RulesEditor: View {
    @Binding var rules: [Rule]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($rules) { $rule in
                HStack(spacing: 8) {
                    Picker("", selection: Binding(get: { rule.condition.kind }, set: { rule.condition = $0.makeDefault() })) {
                        ForEach(Condition.Kind.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 150)
                    conditionFields($rule)
                    Spacer(minLength: 8)
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: NSColor(hex: rule.color) ?? .gray) },
                        set: { rule.color = NSColor($0).hexString }), supportsOpacity: false).labelsHidden()
                    TextField("", text: $rule.color, prompt: Text("#hex"))
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                    Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
            Button { rules.append(Rule()) } label: { Label("Add rule", systemImage: "plus.circle").font(.callout) }
                .buttonStyle(.borderless)
            if !rules.isEmpty {
                Text("First matching rule wins, top to bottom.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func conditionFields(_ rule: Binding<Rule>) -> some View {
        switch rule.wrappedValue.condition {
        case .numberInRange(let min, let max):
            TextField("", value: Binding(get: { min }, set: { rule.wrappedValue.condition = .numberInRange(min: $0, max: max) }),
                      format: .number, prompt: Text("min"))
                .labelsHidden().frame(width: 64).multilineTextAlignment(.trailing)
            Text("≤ n ≤").foregroundStyle(.secondary).fixedSize()
            TextField("", value: Binding(get: { max }, set: { rule.wrappedValue.condition = .numberInRange(min: min, max: $0) }),
                      format: .number, prompt: Text("max"))
                .labelsHidden().frame(width: 64).multilineTextAlignment(.trailing)
        case .regex(let p):
            TextField("", text: Binding(get: { p }, set: { rule.wrappedValue.condition = .regex(pattern: $0) }), prompt: Text("pattern"))
                .labelsHidden().font(.system(.body, design: .monospaced))
        case .contains(let t):
            TextField("", text: Binding(get: { t }, set: { rule.wrappedValue.condition = .contains(text: $0) }), prompt: Text("text"))
                .labelsHidden()
        case .equals(let t):
            TextField("", text: Binding(get: { t }, set: { rule.wrappedValue.condition = .equals(text: $0) }), prompt: Text("text"))
                .labelsHidden()
        case .isEmpty, .scriptFailed:
            EmptyView()
        }
    }
}

// MARK: - Hotkey recorder

struct HotkeyRecorder: View {
    var label: String = "Hotkey"
    @Binding var hotkey: Hotkey?
    @State private var recording = false

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(recording ? "Press keys…" : (hotkey?.display ?? "None"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(recording ? Color.accentColor : (hotkey == nil ? Color.secondary : Color.primary))
                    .fixedSize()
                Button(recording ? "Cancel" : "Record") { recording.toggle() }
                Button("Clear") { hotkey = nil; recording = false }.disabled(hotkey == nil)
                KeyCaptureView(recording: $recording) { hotkey = $0; recording = false }
                    .frame(width: 1, height: 1)
            }
            .fixedSize()
        } label: {
            Text(label).fixedSize()
        }
    }
}

/// Invisible NSView that grabs the next keyDown while recording.
private struct KeyCaptureView: NSViewRepresentable {
    @Binding var recording: Bool
    var onCapture: (Hotkey) -> Void

    func makeNSView(context: Context) -> Capture { Capture() }

    func updateNSView(_ view: Capture, context: Context) {
        view.onCapture = onCapture
        view.onCancel = { recording = false }
        let wantsFocus = recording
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if wantsFocus, window.firstResponder !== view { window.makeFirstResponder(view) }
            else if !wantsFocus, window.firstResponder === view { window.makeFirstResponder(nil) }
        }
    }

    final class Capture: NSView {
        var onCapture: ((Hotkey) -> Void)?
        var onCancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { finish(); onCancel?(); return }          // esc cancels
            let mods = Hotkey.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { NSSound.beep(); return }                    // plain keys ignored
            onCapture?(Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods))
            finish()
        }

        /// Command-based combos arrive here instead of keyDown.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            keyDown(with: event)
            return true
        }

        private func finish() { window?.makeFirstResponder(nil) }
    }
}

/// NSPopUpButton with all font families: one AppKit control instead of ~300 SwiftUI rows.
struct FontFamilyPopUp: NSViewRepresentable {
    @Binding var family: String
    private static let families = ["System"] + NSFontManager.shared.availableFontFamilies.sorted()

    func makeNSView(context: Context) -> NSPopUpButton {
        let b = NSPopUpButton(frame: .zero, pullsDown: false)
        b.addItems(withTitles: Self.families)
        b.target = context.coordinator
        b.action = #selector(Coordinator.changed(_:))
        b.controlSize = .regular
        return b
    }
    func updateNSView(_ b: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if b.titleOfSelectedItem != family { b.selectItem(withTitle: family) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: FontFamilyPopUp
        init(_ p: FontFamilyPopUp) { parent = p }
        @objc func changed(_ sender: NSPopUpButton) { parent.family = sender.titleOfSelectedItem ?? "System" }
    }
}
