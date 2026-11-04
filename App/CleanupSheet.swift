import SwiftUI
import AppKit

/// Old versions and duplicate files the app found. Nothing is ticked at first: the user decides.
struct CleanupSheet: View {
    @ObservedObject var model: AppModel
    let t: L10n

    @State private var selected: Set<String> = []

    private var findings: [CleanupFinding] { model.findings }
    private var chosen: [CleanupFinding] { findings.filter { selected.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("cleanup.title")).font(.system(size: 18, weight: .semibold)).foregroundColor(.text)
            Text(t("cleanup.subtitle")).font(.system(size: 13)).foregroundColor(.label)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if findings.isEmpty {
                        Text(t("cleanup.empty")).font(.system(size: 13)).foregroundColor(.label)
                    }
                    group("cleanup.older") { if case .olderVersion = $0 { return true } else { return false } }
                    group("cleanup.copies") { $0 == .extraCopy }
                    group("cleanup.vst2") { $0 == .legacyVST2 }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.inset))
            HStack {
                Text(t("cleanup.selected", chosen.count, formatBytes(chosen.reduce(0) { $0 + model.size(of: $1) })))
                    .font(.system(size: 12)).foregroundColor(.label)
                Spacer()
                Button(t("mgr.cancel")) { model.showCleanupSheet = false }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(t("mgr.trash")) { confirm() }
                    .buttonStyle(PillButtonStyle(destructive: true))
                    .disabled(chosen.isEmpty || model.manager.busy)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(Color.panel)
    }

    @ViewBuilder private func group(_ title: String, _ matches: (CleanupKind) -> Bool) -> some View {
        let items = findings.filter { matches($0.kind) }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(t(title)).font(.system(size: 13, weight: .semibold)).foregroundColor(.text)
                ForEach(items) { finding in row(finding) }
            }
        }
    }

    private func row(_ finding: CleanupFinding) -> some View {
        let on = selected.contains(finding.id)
        return Button {
            if on { selected.remove(finding.id) } else { selected.insert(finding.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundColor(on ? .accent : .label)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(finding.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.text)
                        if isFavorite(finding) {
                            Text(t("cleanup.inFL")).font(.system(size: 11)).foregroundColor(.amber)
                        }
                    }
                    if case .olderVersion(let newest) = finding.kind {
                        Text(t("cleanup.newer", newest)).font(.system(size: 12)).foregroundColor(.label)
                    }
                    ForEach(finding.bundles, id: \.self) { url in
                        Text(path(url)).font(.system(size: 11, design: .monospaced)).foregroundColor(.label).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(formatBytes(model.size(of: finding))).font(.system(size: 12)).foregroundColor(.label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PointerButtonStyle())
    }

    private func isFavorite(_ finding: CleanupFinding) -> Bool {
        model.allRows.first { $0.id == finding.pluginKey }?.isFavorite ?? false
    }

    /// "VST3/Vendor/X.vst3": from the format folder on, as the details show it.
    private func path(_ url: URL) -> String {
        let parts = url.pathComponents
        guard let start = parts.firstIndex(where: { ["VST3", "VST", "Components", "CLAP"].contains($0) }) else { return url.path }
        return parts[start...].joined(separator: "/")
    }

    private func confirm() {
        let targets = chosen
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("cleanup.confirm", targets.count)
        alert.informativeText = t("cleanup.confirmInfo") + "\n\n" + targets.flatMap(\.bundles).map(path).joined(separator: "\n")
        alert.addButton(withTitle: t("mgr.trash"))
        alert.addButton(withTitle: t("mgr.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let urls = Set(targets.flatMap(\.bundles))
        let bundles = model.manager.plugins.flatMap(\.bundles).filter { urls.contains($0.url) }
        model.showCleanupSheet = false
        model.whenHostsClosed { model.manager.trash(bundles) }
    }
}
