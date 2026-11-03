import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One plugin in the list. A click opens its details right in place: what's wrong, what can be done,
/// its formats, its picture in FL and the developer's data.
struct PluginRowView: View {
    let row: CatalogRow
    @ObservedObject var model: AppModel
    let t: L10n

    static let spacing: CGFloat = 14
    static let ledWidth: CGFloat = 10
    static let formatsWidth: CGFloat = 220
    static let starWidth: CGFloat = 28
    static let categoryWidth: CGFloat = 120
    static let sizeWidth: CGFloat = 70

    @State private var hovered = false
    private var isExpanded: Bool { model.expanded == row.id }
    private var manager: ManagerLibrary { model.manager }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if isExpanded {
                details
                    .padding(.leading, Self.ledWidth + Self.spacing + 14)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(isExpanded || hovered ? Color.inset : Color.clear))
        .onHover { hovered = $0 && !SmoothScrollView.isScrolling }
    }

    // MARK: - Summary line

    private var summary: some View {
        HStack(spacing: Self.spacing) {
            LED(level: model.level(of: row), running: isRunning).frame(width: Self.ledWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(row.isStale ? .label : .text)
                    .lineLimit(1)
                Text(row.vendor)
                    .font(.system(size: 12))
                    .foregroundColor(.label)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            formats.frame(width: Self.formatsWidth, alignment: .trailing)
            star.frame(width: Self.starWidth)
            category.frame(width: Self.categoryWidth, alignment: .leading)
            Text(size)
                .font(.system(size: 12))
                .foregroundColor(.label)
                .frame(width: Self.sizeWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Motion.reduced ? nil : .easeOut(duration: 0.2)) {
                model.expanded = isExpanded ? nil : row.id
            }
        }
    }

    private var isRunning: Bool {
        row.plugin?.bundles.contains { manager.state(of: $0) == .running } ?? false
    }

    private var size: String {
        let bytes = model.size(of: row)
        return bytes > 0 ? formatBytes(bytes) : ""
    }

    private var formats: some View {
        HStack(spacing: 4) {
            if let plugin = row.plugin {
                ForEach(plugin.bundles) { bundle in
                    FormatPill(text: bundle.format.rawValue, level: manager.state(of: bundle).level)
                }
            } else if !row.isStale {
                // Installed outside /Library/Audio/Plug-Ins: the formats FL found
                ForEach(row.entries) { entry in FormatPill(text: entry.shortFormat, level: nil) }
            }
        }
    }

    private var star: some View {
        Button { model.toggleFavorite(row) } label: {
            Image(systemName: row.isFavorite ? "star.fill" : "star")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(row.isFavorite ? .accent : row.isKnownToFL ? .label : .edge)
                .shadow(color: row.isFavorite ? Color.accent.opacity(0.5) : .clear, radius: 4)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!row.isKnownToFL || model.favorites.busy)
        .help(row.isKnownToFL ? t(row.isFavorite ? "row.removeFavorite" : "row.addFavorite") : t("row.notSeen"))
    }

    @ViewBuilder private var category: some View {
        if row.isFavorite && !row.isStale {
            Menu {
                ForEach(FLCategories.folders(model.section(of: row)), id: \.self) { folder in
                    Button(folder) { model.setCategory(row, to: folder) }
                }
                Divider()
                Button(t("fav.noCategory")) { model.setCategory(row, to: nil) }
            } label: {
                Text(model.category(of: row) ?? t("fav.noCategory"))
                    .font(.system(size: 13))
                    .foregroundColor(model.category(of: row) == nil ? .label : .text)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .fixedSize()
            .disabled(model.favorites.busy)
        } else {
            Text("—").font(.system(size: 13)).foregroundColor(.edge)
        }
    }

    // MARK: - Details

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            if row.isStale {
                problem(t("row.stale")) {
                    Button(t("row.removeFromFL")) { model.whenFLClosed { model.favorites.remove(row.favorites) } }
                        .buttonStyle(PillButtonStyle(primary: true))
                }
            } else if let plugin = row.plugin {
                if let text = problemText(plugin) {
                    problem(text) { actions(plugin) }
                } else {
                    HStack(spacing: 8) { actions(plugin) }
                }
                bundles(plugin)
                if row.isKnownToFL { flSection }
                vendorData(plugin)
            } else {
                flSection
            }
        }
    }

    private func problem<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0xFFB3BB))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) { actions() }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.danger.opacity(0.1)))
    }

    /// The problems of the plugin's formats in plain words, nil when there are none.
    private func problemText(_ plugin: ManagedPlugin) -> String? {
        let lines = plugin.bundles.flatMap { bundle -> [String] in
            guard case .done(let issues) = manager.state(of: bundle) else { return [] }
            return issues.map { "\(bundle.format.rawValue): \(t.issue($0))" }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    @ViewBuilder private func actions(_ plugin: ManagedPlugin) -> some View {
        let fixes = plugin.bundles.flatMap(manager.fixes)
        ForEach(fixes) { fix in
            Button(t.fix(fix)) { manager.apply(fix, for: plugin) }
                .buttonStyle(PillButtonStyle(primary: true))
                .disabled(manager.busy)
        }
        Button(t("mgr.reveal")) { NSWorkspace.shared.activateFileViewerSelecting(plugin.bundles.map(\.url)) }
            .buttonStyle(PillButtonStyle())
        Button(t("row.recheck")) { manager.recheck([plugin]) }
            .buttonStyle(PillButtonStyle())
            .disabled(isRunning)
        Button(t("mgr.trash")) { confirmTrash(plugin) }
            .buttonStyle(PillButtonStyle(destructive: true))
            .disabled(manager.busy)
    }

    private func bundles(_ plugin: ManagedPlugin) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(plugin.bundles) { bundle in
                HStack(spacing: 10) {
                    FormatPill(text: bundle.format.rawValue, level: manager.state(of: bundle).level)
                    Text(bundle.displayPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.text)
                        .lineLimit(1)
                    Text(state(bundle)).font(.system(size: 12)).foregroundColor(.label).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(bundle.archs.joined(separator: " · ")).font(.system(size: 11)).foregroundColor(.label)
                    if let size = manager.size(of: bundle) {
                        Text(formatBytes(size)).font(.system(size: 11)).foregroundColor(.label)
                    }
                }
            }
        }
    }

    private func state(_ bundle: PluginBundle) -> String {
        switch manager.state(of: bundle) {
        case .unchecked:         return t("mgr.unchecked")
        case .running:           return t("mgr.checking") + "…"
        case .done(let issues):  return issues.isEmpty ? t("mgr.works") : t("filter.problems")
        }
    }

    // MARK: FL

    private var flSection: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("row.inFL")).font(.system(size: 12, weight: .semibold)).foregroundColor(.label)
                HStack(spacing: 4) {
                    ForEach(row.entries) { entry in
                        let on = model.isFavorite(entry)
                        Button { model.toggle(entry) } label: {
                            FormatPill(text: entry.shortFormat, level: nil, filled: on)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(model.favorites.busy)
                    }
                }
                .help(t("row.formatsHint"))
            }
            if let picture = model.picture(of: row) {
                PictureWell(plugin: picture, model: model, t: t)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func vendorData(_ plugin: ManagedPlugin) -> some View {
        if let folders = manager.vendorData[plugin.vendor], !folders.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("mgr.vendorData")).font(.system(size: 12, weight: .semibold)).foregroundColor(.label)
                ForEach(folders, id: \.self) { folder in
                    HStack(spacing: 10) {
                        Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.text)
                            .lineLimit(1)
                        Spacer()
                        Text(manager.folderSizes[folder].map(formatBytes) ?? "…").font(.system(size: 11)).foregroundColor(.label)
                        Button(t("mgr.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                            .buttonStyle(PillButtonStyle())
                    }
                }
            }
            .onAppear { manager.measure(folders) }
        }
    }

    private func confirmTrash(_ plugin: ManagedPlugin) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("mgr.confirm", plugin.name)
        alert.informativeText = t("mgr.confirmInfo") + "\n\n" + plugin.bundles.map(\.displayPath).joined(separator: "\n")
        alert.addButton(withTitle: t("mgr.trash"))
        alert.addButton(withTitle: t("mgr.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            manager.trash(plugin.bundles)
        }
    }
}

/// A format as a small capsule, coloured by its check result; filled when it's an FL favourite.
struct FormatPill: View {
    let text: String
    let level: CheckState.Level?
    var filled = false

    var body: some View {
        let color: Color = {
            switch level {
            case .warning?: return .amber
            case .failed?:  return .danger
            default:        return .label
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(filled ? .white : color)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Group { if filled { accentGradient } else { Color.raised } })
            .clipShape(Capsule())
    }
}

/// The plugin's picture in FL's browser: drop an image on it, or retake, make a card, remove ours.
struct PictureWell: View {
    let plugin: FLPlugin
    @ObservedObject var model: AppModel
    let t: L10n
    @State private var targeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.chassis)
                if plugin.hasPicture, let image = NSImage(contentsOf: plugin.picture) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(4)
                } else {
                    Text(t("row.dropHint")).font(.system(size: 11)).foregroundColor(.label).multilineTextAlignment(.center)
                        .padding(8)
                }
            }
            .frame(width: 150, height: 76)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(targeted ? Color.accent : .clear, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { model.whenFLClosed { model.pictures.setCustom(plugin, image: url) } }
                }
                return true
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(t("row.picture")).font(.system(size: 12, weight: .semibold)).foregroundColor(.label)
                HStack(spacing: 6) {
                    Button(t("fl.retake")) { model.whenFLClosed { model.pictures.generate([plugin], screenshots: true) } }
                    Button(t("fl.useCard")) { model.whenFLClosed { model.pictures.generate([plugin], screenshots: false) } }
                }
                .buttonStyle(PillButtonStyle())
                HStack(spacing: 6) {
                    Button(t("fl.choose")) { choose() }
                    if plugin.source != nil {
                        Button(t("fl.remove")) { model.whenFLClosed { model.pictures.remove([plugin]) } }
                            .buttonStyle(PillButtonStyle(destructive: true))
                    }
                }
                .buttonStyle(PillButtonStyle())
            }
            .disabled(model.pictures.busy)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            model.whenFLClosed { model.pictures.setCustom(plugin, image: url) }
        }
    }
}
