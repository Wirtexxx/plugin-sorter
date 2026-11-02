import SwiftUI
import AppKit

/// Manager tab: every installed plugin, checks that they load, and moving them to the Trash.
struct ManagerView: View {
    @ObservedObject var library: ManagerLibrary
    let t: L10n

    var body: some View {
        VStack(spacing: 6) {
            overview
            list
            bottomBar
        }
        .onAppear { if library.plugins.isEmpty { library.scan() } }
    }

    // MARK: - Sections

    private var overview: some View {
        let total = max(library.plugins.count, 1)
        let ok = library.count(.ok)
        let problems = library.count(.warning) + library.count(.failed)
        return HStack(spacing: 6) {
            HStack(spacing: 22) {
                Knob(value: library.plugins.count, fraction: 1, label: t("meter.plugins").uppercased())
                Knob(value: ok, fraction: Double(ok) / Double(total), label: t("mgr.ok").uppercased())
                Knob(value: problems, fraction: Double(problems) / Double(total), label: t("mgr.problems").uppercased())
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
            .panel()

            VStack(alignment: .leading, spacing: 10) {
                Text(t("mgr.title").uppercased()).caption()
                if library.busy && !library.current.isEmpty {
                    HStack {
                        Text("\(t("mgr.checking").uppercased()) · \(library.current)").caption(.text).lineLimit(1)
                        Spacer()
                        Text("\(Int(library.progress * 100))%").caption()
                    }
                    ProgressBar(value: library.progress)
                } else {
                    Text(t("mgr.hint"))
                        .font(.system(size: 12))
                        .foregroundColor(.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .panel()
        }
        .frame(height: 130)
    }

    private var list: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.label)
                    TextField(t("mgr.search"), text: $library.query)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12))
                        .foregroundColor(.text)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .panel(.inset, radius: 4)
                PowerToggle(title: t("mgr.onlyProblems").uppercased(), isOn: library.onlyProblems) {
                    library.onlyProblems.toggle()
                }
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(library.visible) { plugin in
                        ManagerRow(plugin: plugin, library: library, t: t)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .panel()
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text(t.managerStatus(library.status).uppercased()).caption().lineLimit(1)
            Spacer()
            if library.busy { ProgressView().controlSize(.small) }
            Button(t("button.refresh").uppercased()) { library.scan() }
                .buttonStyle(PluginButtonStyle())
                .disabled(library.busy)
            Button(t("mgr.checkAll").uppercased()) { library.check(library.visible) }
                .buttonStyle(PluginButtonStyle(primary: true))
                .disabled(library.busy || library.visible.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .panel()
    }
}

struct ManagerRow: View {
    let plugin: ManagedPlugin
    @ObservedObject var library: ManagerLibrary
    let t: L10n

    private var isExpanded: Bool { library.expanded.contains(plugin.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                LevelDot(level: library.level(of: plugin), running: plugin.bundles.contains { library.state(of: $0) == .running })
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.text)
                        .lineLimit(1)
                    Text(plugin.vendor.uppercased()).caption().lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(plugin.bundles) { bundle in
                        FormatChip(format: bundle.format, level: library.state(of: bundle).level)
                    }
                }
                Text(plugin.version).caption().frame(width: 64, alignment: .trailing).lineLimit(1)
                Button { library.check([plugin]) } label: {
                    Image(systemName: "stethoscope").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(IconButtonStyle())
                .disabled(library.busy)
                .help(t("mgr.check"))
                Button { confirmTrash() } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(IconButtonStyle(destructive: true))
                .disabled(library.busy)
                .help(t("mgr.trash"))
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plugin.bundles) { bundle in
                        HStack(alignment: .top, spacing: 8) {
                            FormatChip(format: bundle.format, level: library.state(of: bundle).level)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bundle.displayPath)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.text)
                                    .lineLimit(1)
                                ForEach(details(bundle), id: \.self) { line in
                                    Text(line).font(.system(size: 11)).foregroundColor(.label)
                                }
                            }
                            Spacer()
                            Text(bundle.archs.joined(separator: " · ")).caption()
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .panel(.inset, radius: 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if isExpanded { library.expanded.remove(plugin.id) } else { library.expanded.insert(plugin.id) }
        }
        .contextMenu {
            Button(t("mgr.check")) { library.check([plugin]) }
            Button(t("mgr.reveal")) { NSWorkspace.shared.activateFileViewerSelecting(plugin.bundles.map(\.url)) }
            Divider()
            Button(t("mgr.trash")) { confirmTrash() }
        }
    }

    private func details(_ bundle: PluginBundle) -> [String] {
        switch library.state(of: bundle) {
        case .unchecked:         return [t("mgr.unchecked")]
        case .running:           return [t("mgr.checking") + "…"]
        case .done(let issues):  return issues.isEmpty ? [t("mgr.works")] : issues.map(t.issue)
        }
    }

    private func confirmTrash() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("mgr.confirm", plugin.name)
        alert.informativeText = t("mgr.confirmInfo") + "\n\n" + plugin.bundles.map(\.displayPath).joined(separator: "\n")
        alert.addButton(withTitle: t("mgr.trash"))
        alert.addButton(withTitle: t("mgr.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            library.trash(plugin.bundles)
        }
    }
}

private extension CheckState.Level {
    var color: Color {
        switch self {
        case .ok:      return .mint
        case .warning: return .amber
        case .failed:  return .danger
        }
    }
}

struct LevelDot: View {
    let level: CheckState.Level?
    var running = false

    var body: some View {
        Group {
            if running {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            } else {
                StatusDot(color: level?.color ?? .edge, on: level != nil)
            }
        }
        .frame(width: 12, height: 12)
    }
}

struct FormatChip: View {
    let format: PluginFormat
    let level: CheckState.Level?

    var body: some View {
        Text(format.rawValue)
            .font(.system(size: 9, weight: .bold))
            .kerning(0.8)
            .foregroundColor(level?.color ?? .accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .panel(.raised, radius: 3)
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.inset)
                Capsule()
                    .fill(LinearGradient(gradient: Gradient(colors: [Color.accent, Color.accentHot]),
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * CGFloat(value)))
                    .shadow(color: Color.accent.opacity(0.6), radius: 4)
            }
        }
        .frame(height: 6)
    }
}

struct IconButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(destructive ? .danger : .text)
            .frame(width: 26, height: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.raised).brightness(configuration.isPressed ? -0.08 : 0))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.edge, lineWidth: 1))
    }
}
