import SwiftUI

enum Tab: String {
    case sorter, fl, manager
}

struct ContentView: View {
    @StateObject private var sorter: Sorter
    @StateObject private var library: FLLibrary
    @StateObject private var manager: ManagerLibrary
    @AppStorage("language") private var language = Lang.system.rawValue
    @State private var tab: Tab
    @State private var showNotes = false

    init(sorter: Sorter = Sorter(), library: FLLibrary = FLLibrary(), manager: ManagerLibrary = ManagerLibrary(),
         tab: Tab = .sorter) {
        _sorter = StateObject(wrappedValue: sorter)
        _library = StateObject(wrappedValue: library)
        _manager = StateObject(wrappedValue: manager)
        _tab = State(initialValue: tab)
    }

    private var t: L10n { L10n(lang: Lang(rawValue: language) ?? .en) }

    var body: some View {
        ZStack {
            Chassis()
            VStack(spacing: 6) {
                topBar
                if tab == .fl {
                    FLView(library: library, t: t)
                } else if tab == .manager {
                    ManagerView(library: manager, t: t)
                } else {
                    if sorter.nestedAU > 0 { auWarning }
                    HStack(spacing: 6) {
                        distributionPanel
                        formatsPanel.frame(width: 280)
                    }
                    .frame(height: 200)
                    developersPanel
                    if showNotes && !sorter.notes.isEmpty { notesPanel }
                    bottomBar
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 30)
            .padding(.bottom, 8)
        }
        .background(WindowStyler())
        .onAppear { sorter.refreshLatestLog(); sorter.preview() }
        .onChange(of: sorter.formats) { _ in sorter.preview() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: -2) {
                Text("PLUGIN")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(2.5)
                    .foregroundColor(.label)
                Text("SORTER")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .kerning(2)
                    .foregroundColor(.text)
            }
            .padding(.horizontal, 8)
            .help(t("subtitle"))

            HStack(spacing: 2) {
                tabButton(.sorter, title: t("tab.sorter"))
                tabButton(.fl, title: t("tab.fl"))
                tabButton(.manager, title: t("tab.manager"))
            }
            .padding(3)
            .panel(.inset, radius: 4)

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.label)
                Text(tab == .fl ? "~/DOCUMENTS/IMAGE-LINE/…/PLUGIN DATABASE" : "/LIBRARY/AUDIO/PLUG-INS")
                    .caption(.text)
                    .lineLimit(1)
                Spacer()
                StatusDot(on: statusLit)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .panel(.inset, radius: 4)

            if tab == .sorter {
                PowerToggle(title: "VST3", isOn: sorter.vst3) { sorter.vst3.toggle() }
                PowerToggle(title: "VST", isOn: sorter.vst) { sorter.vst.toggle() }
            }

            HStack(spacing: 2) {
                ForEach(Lang.allCases) { lang in
                    let active = language == lang.rawValue
                    Button { language = lang.rawValue } label: {
                        Text(lang.rawValue.uppercased())
                            .caption(active ? .text : .label)
                            .frame(width: 30, height: 24)
                            .background(RoundedRectangle(cornerRadius: 3).fill(active ? Color.raised : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(3)
            .panel(.inset, radius: 4)
        }
        .disabled(sorter.running || library.busy || manager.busy)
        .padding(6)
        .panel()
    }

    private var statusLit: Bool {
        switch tab {
        case .sorter:  return !sorter.moves.isEmpty || sorter.running
        case .fl:      return library.busy || !library.missing.isEmpty
        case .manager: return manager.busy
        }
    }

    private func tabButton(_ value: Tab, title: String) -> some View {
        let active = tab == value
        return Button { tab = value } label: {
            Text(title.uppercased())
                .caption(active ? .text : .label)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 3).fill(active ? Color.raised : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var auWarning: some View {
        HStack(spacing: 10) {
            StatusDot(color: .accentHot)
            Text(t("au.nested", sorter.nestedAU))
                .font(.system(size: 12))
                .foregroundColor(.text)
                .lineLimit(2)
            Spacer()
            Button(t("button.restoreAU").uppercased()) { sorter.restoreAU() }
                .buttonStyle(PluginButtonStyle(primary: true))
                .disabled(sorter.running)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .panel()
    }

    // MARK: - Displays

    private var distributionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("panel.distribution").uppercased()).caption()
                Spacer()
                Text("\(sorter.groups.count) · \(t("meter.vendors").uppercased())").caption()
            }
            ZStack {
                Distribution(groups: sorter.groups)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                if sorter.moves.isEmpty && !sorter.running {
                    HStack(spacing: 8) {
                        StatusDot()
                        Text(t("empty.title").uppercased()).caption(.text)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .panel(.panel, radius: 4)
                }
            }
            .panel(.inset, radius: 4)
        }
        .padding(12)
        .panel()
    }

    private var formatsPanel: some View {
        let total = max(sorter.moves.count, 1)
        let count = { (format: String) in sorter.moves.filter { $0.format == format }.count }
        return VStack(spacing: 14) {
            HStack {
                Text(t("meter.formats").uppercased()).caption()
                Spacer()
            }
            HStack(spacing: 18) {
                ForEach(["VST3", "VST"], id: \.self) { format in
                    Knob(value: count(format), fraction: Double(count(format)) / Double(total), label: format)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text(t("meter.plugins").uppercased()).caption()
                Spacer()
                Text("\(sorter.moves.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.text)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .panel(.inset, radius: 4)
        }
        .padding(12)
        .panel()
    }

    // MARK: - Developers

    private var developersPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("meter.vendors").uppercased()).caption()
            if sorter.moves.isEmpty && !sorter.running {
                VStack(spacing: 6) {
                    Text(t("empty.title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.text)
                    Text(t("empty.hint"))
                        .font(.system(size: 11))
                        .foregroundColor(.label)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 6, alignment: .top)], spacing: 6) {
                        ForEach(sorter.groups) { VendorCard(group: $0) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .panel()
    }

    private var notesPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sorter.notes) { note in
                    Text(t.note(note))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.label)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(height: 80)
        .panel()
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { showNotes.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 10, weight: .semibold))
                    Text(t("notes", sorter.notes.count).uppercased()).caption(showNotes ? .text : .label)
                }
                .foregroundColor(showNotes ? .text : .label)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(sorter.notes.isEmpty)
            .opacity(sorter.notes.isEmpty ? 0.4 : 1)

            Rectangle().fill(Color.edge).frame(width: 1, height: 16)

            Text(t.status(sorter.status).uppercased())
                .caption()
                .lineLimit(1)

            Spacer()

            if sorter.running {
                ProgressView().controlSize(.small)
            }
            Button(t("button.undo").uppercased()) { sorter.undo() }
                .buttonStyle(PluginButtonStyle())
                .disabled(sorter.running || sorter.latestLog == nil)
            Button(t("button.refresh").uppercased()) { sorter.preview() }
                .buttonStyle(PluginButtonStyle())
                .disabled(sorter.running)
            Button((sorter.applied ? t("button.done") : t("button.sort")).uppercased()) { sorter.apply() }
                .buttonStyle(PluginButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(sorter.running || sorter.applied || sorter.moves.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .panel()
    }
}

struct VendorCard: View {
    let group: VendorGroup

    /// One row per plugin with all of its formats, in script order.
    private var rows: [(name: String, formats: [String])] {
        var order: [String] = []
        var formats: [String: [String]] = [:]
        for move in group.items {
            if formats[move.plugin] == nil { order.append(move.plugin) }
            formats[move.plugin, default: []].append(move.format)
        }
        return order.map { ($0, formats[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot()
                Text(group.vendor.uppercased()).caption(.text).lineLimit(1)
                Spacer()
                Text("\(group.items.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.text)
                    .frame(minWidth: 20, minHeight: 18)
                    .panel(.raised, radius: 3)
            }
            Rectangle().fill(Color.edge.opacity(0.6)).frame(height: 1)
            ForEach(rows, id: \.name) { row in
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 12))
                        .foregroundColor(.text)
                        .lineLimit(1)
                    Spacer()
                    ForEach(row.formats, id: \.self) { format in
                        Text(format)
                            .font(.system(size: 9, weight: .bold))
                            .kerning(0.8)
                            .foregroundColor(.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .panel(.raised, radius: 3)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .panel(.inset, radius: 5)
    }
}
