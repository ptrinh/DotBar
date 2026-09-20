import SwiftUI

struct ItemEditorView: View {
    @ObservedObject var state: AppState
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
                TextField("Name", text: $item.name)
                Picker("Type", selection: sourceKind) {
                    Text("Static text").tag(0)
                    Text("Script").tag(1)
                }.pickerStyle(.segmented)
                switch item.source {
                case .static(let text):
                    TextField("Text", text: Binding(get: { text }, set: { item.source = .static(text: $0) }))
                case .script(let cmd, let secs):
                    TextField("Command", text: Binding(get: { cmd }, set: { item.source = .script(command: $0, refreshSeconds: secs) }),
                              prompt: Text("e.g. curl -s https://… | jq -r .price"), axis: .vertical)
                        .lineLimit(2...5).font(.system(.body, design: .monospaced))
                    HStack {
                        TextField("Refresh every", value: Binding(get: { secs }, set: { item.source = .script(command: cmd, refreshSeconds: max(0, $0)) }),
                                  format: .number).frame(width: 80)
                        Text("seconds (0 = manual)").foregroundStyle(.secondary)
                    }
                    Text("Tip: extra output lines become menu items (a line of `----` is a separator). ANSI colors (`\\e[31m`, `\\e[1;32m`, `\\e[38;5;N m`) are rendered.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Or output JSON: `{\"text\":\"…\",\"color\":\"#hex\",\"dots\":[\"#hex\",…],\"menu\":[\"line\",\"----\",\"line\"],\"symbol\":\"bolt.fill\",\"refresh\":30,\"action\":\"copy\" | {\"url\":\"…\"} | {\"script\":\"…\"}}`")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Text style") {
                FontPicker(spec: $item.font)
                TextField("SF Symbol", text: Binding(get: { item.symbol ?? "" }, set: { item.symbol = $0.isEmpty ? nil : $0 }),
                          prompt: Text("e.g. bolt.fill (empty = none)"))
                HStack {
                    TextField("Max width", value: $item.maxWidth, format: .number).frame(width: 80)
                    Text("points (0 = unlimited)").foregroundStyle(.secondary)
                }
                ColorSpecEditor(title: "Text color", spec: $item.textColor, allowSystem: true)
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

            Section("Left click") {
                Picker("Action", selection: actionKind) {
                    Text("Show menu").tag(0)
                    Text("Copy text").tag(1)
                    Text("Run script").tag(2)
                    Text("Open URL").tag(3)
                }
                switch item.action {
                case .script(let cmd):
                    TextField("Command", text: Binding(get: { cmd }, set: { item.action = .script(command: $0) })).font(.system(.body, design: .monospaced))
                case .openURL(let u):
                    TextField("URL", text: Binding(get: { u }, set: { item.action = .openURL(url: $0) }))
                default: EmptyView()
                }
                Text("Right click always shows the menu.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var previewBox: some View {
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

    private var sourceKind: Binding<Int> {
        Binding(get: { item.source.isScript ? 1 : 0 }, set: { v in
            switch (v, item.source) {
            case (0, .script): item.source = .static(text: state.output(for: item)?.text ?? "")
            case (1, .static(let t)): item.source = .script(command: "echo \"\(t)\"", refreshSeconds: 60)
            default: break
            }
        })
    }

    private var actionKind: Binding<Int> {
        Binding(get: {
            switch item.action { case .menu: 0; case .copy: 1; case .script: 2; case .openURL: 3 }
        }, set: { v in
            switch v { case 1: item.action = .copy; case 2: item.action = .script(command: ""); case 3: item.action = .openURL(url: "https://"); default: item.action = .menu }
        })
    }
}

// MARK: - Font

struct FontPicker: View {
    @Binding var spec: FontSpec
    private let families = ["System"] + NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        Picker("Font", selection: Binding(get: { spec.family ?? "System" }, set: { spec.family = $0 == "System" ? nil : $0 })) {
            ForEach(families, id: \.self) { Text($0).tag($0) }
        }
        HStack {
            Picker("Weight", selection: $spec.weight) {
                ForEach(FontSpec.Weight.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Stepper(value: $spec.size, in: 8...20, step: 1) { Text("Size \(Int(spec.size))") }.frame(width: 120)
            Toggle("Monospaced digits", isOn: $spec.monospacedDigits)
        }
    }
}

// MARK: - Dots

struct DotsEditor: View {
    @Binding var dots: [Dot]

    var body: some View {
        ForEach($dots) { $dot in
            DisclosureGroup {
                Picker("Value from", selection: Binding(get: { dot.source.isScript ? 1 : 0 }, set: { v in
                    dot.source = v == 0 ? .mainValue : .script(command: "", refreshSeconds: 60)
                })) {
                    Text("Item's text").tag(0)
                    Text("Own script").tag(1)
                }
                if case .script(let cmd, let secs) = dot.source {
                    TextField("Command", text: Binding(get: { cmd }, set: { dot.source = .script(command: $0, refreshSeconds: secs) }))
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        TextField("Refresh every", value: Binding(get: { secs }, set: { dot.source = .script(command: cmd, refreshSeconds: max(0, $0)) }), format: .number).frame(width: 80)
                        Text("seconds").foregroundStyle(.secondary)
                    }
                }
                ColorSpecEditor(title: "Color", spec: $dot.color, allowSystem: false)
            } label: {
                HStack {
                    Circle().fill(Color(nsColor: RuleEngine.color(for: dot.color, output: nil) ?? .gray)).frame(width: 8, height: 8)
                    Text("Dot \((dots.firstIndex(where: { $0.id == dot.id }) ?? 0) + 1)")
                    Spacer()
                    Button(role: .destructive) { dots.removeAll { $0.id == dot.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
        }
        if dots.count < 3 {
            Button { dots.append(Dot()) } label: { Label("Add dot", systemImage: "plus.circle") }
        }
    }
}

extension DotSource { var isScript: Bool { if case .script = self { return true } else { return false } } }

// MARK: - Color spec

struct ColorSpecEditor: View {
    let title: String
    @Binding var spec: ColorSpec
    let allowSystem: Bool

    var body: some View {
        Picker(title, selection: Binding(get: { isRules ? 1 : 0 }, set: { v in
            if v == 0 { spec = .fixed(fixedHex ?? (allowSystem ? nil : "#8E8E93")) }
            else { spec = .rules([], fallback: fixedHex ?? (allowSystem ? nil : "#8E8E93")) }
        })) {
            Text("Fixed").tag(0)
            Text("By condition").tag(1)
        }.pickerStyle(.segmented)

        switch spec {
        case .fixed(let hex):
            HexColorField(label: allowSystem ? "Color (empty = system)" : "Color", hex: Binding(get: { hex }, set: { spec = .fixed($0) }), allowNil: allowSystem)
        case .rules(let rules, let fallback):
            RulesEditor(rules: Binding(get: { rules }, set: { spec = .rules($0, fallback: fallback) }))
            HexColorField(label: allowSystem ? "Otherwise (empty = system)" : "Otherwise", hex: Binding(get: { fallback }, set: { spec = .rules(rules, fallback: $0) }), allowNil: allowSystem)
        }
    }

    private var isRules: Bool { if case .rules = spec { return true } else { return false } }
    private var fixedHex: HexColor? {
        switch spec { case .fixed(let h): h; case .rules(_, let f): f }
    }
}

struct HexColorField: View {
    let label: String
    @Binding var hex: HexColor?
    let allowNil: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor(hex: hex) ?? .labelColor) },
                set: { hex = NSColor($0).hexString }
            ), supportsOpacity: false).labelsHidden()
            TextField("#RRGGBB", text: Binding(get: { hex ?? "" }, set: { hex = $0.isEmpty && allowNil ? nil : $0 }))
                .font(.system(.body, design: .monospaced)).frame(width: 90)
            if allowNil && hex != nil { Button("Reset") { hex = nil }.buttonStyle(.link) }
        }
    }
}

// MARK: - Rules

struct RulesEditor: View {
    @Binding var rules: [Rule]

    var body: some View {
        ForEach($rules) { $rule in
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { rule.condition.kind }, set: { rule.condition = $0.makeDefault() })) {
                    ForEach(Condition.Kind.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 150)
                conditionFields($rule)
                Spacer(minLength: 0)
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: NSColor(hex: rule.color) ?? .gray) },
                    set: { rule.color = NSColor($0).hexString }), supportsOpacity: false).labelsHidden()
                TextField("#hex", text: $rule.color).font(.system(.caption, design: .monospaced)).frame(width: 76)
                Button { rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
            }
        }
        .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
        Button { rules.append(Rule()) } label: { Label("Add rule", systemImage: "plus.circle") }
        if !rules.isEmpty { Text("First matching rule wins, top to bottom.").font(.caption).foregroundStyle(.secondary) }
    }

    @ViewBuilder
    private func conditionFields(_ rule: Binding<Rule>) -> some View {
        switch rule.wrappedValue.condition {
        case .numberInRange(let min, let max):
            TextField("min", value: Binding(get: { min }, set: { rule.wrappedValue.condition = .numberInRange(min: $0, max: max) }), format: .number).frame(width: 60)
            Text("≤ n ≤").foregroundStyle(.secondary)
            TextField("max", value: Binding(get: { max }, set: { rule.wrappedValue.condition = .numberInRange(min: min, max: $0) }), format: .number).frame(width: 60)
        case .regex(let p):
            TextField("pattern", text: Binding(get: { p }, set: { rule.wrappedValue.condition = .regex(pattern: $0) })).font(.system(.body, design: .monospaced))
        case .contains(let t):
            TextField("text", text: Binding(get: { t }, set: { rule.wrappedValue.condition = .contains(text: $0) }))
        case .equals(let t):
            TextField("text", text: Binding(get: { t }, set: { rule.wrappedValue.condition = .equals(text: $0) }))
        case .isEmpty, .scriptFailed:
            EmptyView()
        }
    }
}
