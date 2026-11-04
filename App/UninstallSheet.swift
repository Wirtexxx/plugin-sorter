import SwiftUI
import AppKit

/// What removing a plugin takes with it: its files always, leftovers only when ticked, and the installer
/// receipts nothing else needs. The search for leftovers runs while the window is open.
struct UninstallSheet: View {
    let plugin: ManagedPlugin
    @ObservedObject var model: AppModel
    let t: L10n

    @State private var loading = true
    @State private var leftovers: [Leftover] = []
    @State private var sizes: [String: Int64] = [:]
    @State private var selected: Set<String> = []
    @State private var receipts: [Receipt] = []
    @State private var forgettable: [Receipt] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("uninstall.title", plugin.name)).font(.system(size: 18, weight: .semibold)).foregroundColor(.text)
            Text(t("uninstall.subtitle")).font(.system(size: 13)).foregroundColor(.label)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    filesSection
                    leftoversSection
                    if !loading && !receipts.isEmpty {
                        Text(t("uninstall.receipts", forgettable.count, receipts.count - forgettable.count))
                            .font(.system(size: 12)).foregroundColor(.label)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.inset))
            HStack {
                Spacer()
                Button(t("mgr.cancel")) { model.uninstallTarget = nil }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(t("mgr.trash")) { confirm() }
                    .buttonStyle(PillButtonStyle(destructive: true))
                    .disabled(loading || model.manager.busy)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .background(Color.panel)
        .onAppear(perform: search)
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("uninstall.files")).font(.system(size: 13, weight: .semibold)).foregroundColor(.text)
            ForEach(plugin.bundles) { bundle in
                HStack(spacing: 10) {
                    FormatPill(text: bundle.format.rawValue, level: nil)
                    Text(bundle.displayPath).font(.system(size: 11, design: .monospaced)).foregroundColor(.text).lineLimit(1)
                    Spacer(minLength: 8)
                    if let size = model.manager.size(of: bundle) {
                        Text(formatBytes(size)).font(.system(size: 11)).foregroundColor(.label)
                    }
                }
            }
        }
    }

    @ViewBuilder private var leftoversSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("uninstall.leftovers")).font(.system(size: 13, weight: .semibold)).foregroundColor(.text)
            if loading {
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle()).scaleEffect(0.6).frame(width: 16, height: 16)
                    Text(t("uninstall.searching")).font(.system(size: 12)).foregroundColor(.label)
                }
            } else if leftovers.isEmpty {
                Text(t("uninstall.none")).font(.system(size: 12)).foregroundColor(.label)
            }
            ForEach(leftovers) { item in row(item) }
        }
    }

    private func row(_ item: Leftover) -> some View {
        let on = selected.contains(item.id)
        return Button {
            if on { selected.remove(item.id) } else { selected.insert(item.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundColor(on ? .accent : .label)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t(label(item.kind))).font(.system(size: 12)).foregroundColor(.text)
                    Text(item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.label).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(sizes[item.id].map(formatBytes) ?? "…").font(.system(size: 11)).foregroundColor(.label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PointerButtonStyle())
    }

    private func label(_ kind: Leftover.Kind) -> String {
        switch kind {
        case .preferences: return "left.preferences"
        case .cache:       return "left.cache"
        case .presets:     return "left.presets"
        case .vendorData:  return "left.vendorData"
        }
    }

    /// Reads the receipts and looks for leftovers away from the main thread.
    private func search() {
        let plugin = self.plugin
        let others = model.manager.plugins.filter { $0.key != plugin.key }
        DispatchQueue.global(qos: .userInitiated).async {
            let mine = Uninstall.receipts(in: Uninstall.loadReceipts(), for: plugin)
            let found = Uninstall.leftovers(for: plugin, others: others, home: FileManager.default.homeDirectoryForCurrentUser,
                                            dataFolders: DiskUsage.dataFolders(),
                                            fileExists: { FileManager.default.fileExists(atPath: $0.path) })
            var measured: [String: Int64] = [:]
            for item in found { measured[item.id] = DiskUsage.size(of: item.url) }
            let forget = Uninstall.forgettable(mine, removing: plugin, others: others)
            DispatchQueue.main.async {
                receipts = mine
                forgettable = forget
                leftovers = found
                sizes = measured
                selected = Set(found.filter(\.preselected).map(\.id))
                loading = false
            }
        }
    }

    private func confirm() {
        let chosen = leftovers.filter { selected.contains($0.id) }
        let target = plugin
        let forget = forgettable
        model.uninstallTarget = nil
        model.whenFLClosed { model.manager.uninstall(target, leftovers: chosen, receipts: forget) }
    }
}
