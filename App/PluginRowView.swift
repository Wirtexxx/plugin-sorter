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
                PluginDetailsView(row: row, model: model, t: t)
                    .padding(.leading, Self.ledWidth + Self.spacing + 14)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(isExpanded || hovered ? Color.inset : Color.clear))
        .overlay(LabelStripe(color: model.labelColor(of: row)).padding(.vertical, 8), alignment: .leading)
        .onHover { hovered = $0 && !SmoothScrollView.isScrolling }
    }

    // MARK: - Summary line

    private var summary: some View {
        HStack(spacing: Self.spacing) {
            LED(level: model.level(of: row), running: isRunning).frame(width: Self.ledWidth)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(row.isStale ? .label : .text)
                        .lineLimit(1)
                    if model.isNew(row) { NewBadge(t: t) }
                }
                Text(row.vendor)
                    .font(.system(size: 12))
                    .foregroundColor(.label)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            formats.frame(width: Self.formatsWidth, alignment: .trailing)
            PluginStar(row: row, model: model, t: t).frame(width: Self.starWidth)
            PluginCategoryMenu(row: row, model: model, t: t).frame(width: Self.categoryWidth, alignment: .leading)
            Text(size)
                .font(.system(size: 12))
                .foregroundColor(.label)
                .frame(width: Self.sizeWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(row.plugin?.isDisabled == true ? 0.45 : 1)
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

}

extension LabelColor {
    var swatch: Color {
        switch self {
        case .accent: return .accent
        case .mint:   return .mint
        case .amber:  return .amber
        case .danger: return .danger
        }
    }
}

/// The colour label: a strip at the edge, apart from the status lamp.
struct LabelStripe: View {
    let color: LabelColor?

    var body: some View {
        Capsule().fill(color?.swatch ?? .clear).frame(width: 3).opacity(color == nil ? 0 : 1)
    }
}

/// A text field that hands over its text on Return and empties itself.
struct NewTagField: View {
    let placeholder: String
    let onAdd: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text, onCommit: {
            onAdd(text)
            text = ""
        })
        .textFieldStyle(PlainTextFieldStyle())
        .font(.system(size: 12))
        .foregroundColor(.text)
        .padding(.horizontal, 10)
        .frame(width: 120, height: 24)
        .background(Capsule().fill(Color.raised))
    }
}

/// Marks a plugin installed since the last "all seen".
struct NewBadge: View {
    let t: L10n

    var body: some View {
        Text(t("new.badge"))
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .frame(height: 15)
            .background(Capsule().fill(Color.accent))
    }
}

/// The FL star: adds the plugin to FL's favourites or takes it out.
struct PluginStar: View {
    let row: CatalogRow
    @ObservedObject var model: AppModel
    let t: L10n
    var size: CGFloat = 14

    var body: some View {
        Button { model.toggleFavorite(row) } label: {
            Image(systemName: row.isFavorite ? "star.fill" : "star")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(row.isFavorite ? .accent : row.isKnownToFL ? .label : .edge)
                .shadow(color: row.isFavorite ? Color.accent.opacity(0.5) : .clear, radius: 4)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!row.isKnownToFL || model.favorites.busy)
        .help(row.isKnownToFL ? t(row.isFavorite ? "row.removeFavorite" : "row.addFavorite") : t("row.notSeen"))
    }
}

/// The FL category of a favourite, as a menu of FL's folders.
struct PluginCategoryMenu: View {
    let row: CatalogRow
    @ObservedObject var model: AppModel
    let t: L10n

    @ViewBuilder var body: some View {
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
}

/// What's known about one plugin and what can be done with it: in place in the list, or narrow
/// (`compact`) in the panel beside the cards.
struct PluginDetailsView: View {
    let row: CatalogRow
    @ObservedObject var model: AppModel
    let t: L10n
    var compact = false

    /// A license form is open: switching tabs would throw away what's typed in it.
    @State private var editingLicense = false

    private var manager: ManagerLibrary { model.manager }
    private var isRunning: Bool {
        row.plugin?.bundles.contains { manager.state(of: $0) == .running } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if row.isStale {
                problem(t("row.stale")) {
                    Button(t("row.removeFromFL")) { model.whenFLClosed { model.favorites.remove(row.favorites) } }
                        .buttonStyle(PillButtonStyle(primary: true))
                }
            } else {
                // Never behind a tab: whatever tab is open, a problem stays in sight
                if let plugin = row.plugin { notices(plugin) }
                if DetailsTab.available(for: row).count > 1 { tabBar }
                tabContent
                if let plugin = row.plugin { actionBar(plugin) }
            }
        }
    }

    @ViewBuilder private func notices(_ plugin: ManagedPlugin) -> some View {
        if plugin.isDisabled {
            Text(t("row.disabledNote")).font(.system(size: 12)).foregroundColor(.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let text = problemText(plugin) {
            problem(text) {
                ForEach(plugin.activeBundles.flatMap(manager.fixes)) { fix in
                    Button(t.fix(fix)) { manager.apply(fix, for: plugin) }
                        .buttonStyle(PillButtonStyle(primary: true))
                        .disabled(manager.busy)
                }
                supportButtons(plugin)
            }
        }
    }

    // MARK: Tabs

    private var selectedTab: DetailsTab? { DetailsTab.resolved(model.detailsTab, for: row) }

    private var tabBar: some View {
        HStack(spacing: compact ? 12 : 18) {
            ForEach(DetailsTab.available(for: row)) { tab in
                Button { model.detailsTab = tab } label: { tabLabel(tab) }
                    .buttonStyle(PlainButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .overlay(Rectangle().fill(Color.raised).frame(height: 1), alignment: .bottom)
        .disabled(editingLicense)
        .opacity(editingLicense ? 0.5 : 1)
    }

    private func tabLabel(_ tab: DetailsTab) -> some View {
        let selected = tab == selectedTab
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(t("tab.\(tab.rawValue)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .text : .label)
                    .fixedSize()
                tabHint(tab)
            }
            Rectangle().fill(selected ? Color.accent : Color.clear).frame(height: 2)
        }
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
    }

    /// What a closed tab holds, so a tag or a license isn't out of mind just because it's out of sight.
    @ViewBuilder private func tabHint(_ tab: DetailsTab) -> some View {
        if let plugin = row.plugin {
            if tab == .tags, case let count = model.labels.labels(of: plugin.key).tags.count, count > 0 {
                Text("\(count)").font(.system(size: 11)).foregroundColor(.label)
            } else if tab == .license, model.vault.hasLicense(plugin.key) {
                Circle().fill(Color.accent).frame(width: 5, height: 5)
            }
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .files:
            if let plugin = row.plugin {
                VStack(alignment: .leading, spacing: 14) {
                    bundles(plugin)
                    vendorData(plugin)
                }
            }
        case .fl:
            flSection
        case .tags:
            if let plugin = row.plugin { tagsSection(plugin) }
        case .license:
            if let plugin = row.plugin {
                LicenseSection(plugin: plugin, model: model, t: t, compact: compact, editing: $editingLicense)
            }
        case nil:
            EmptyView()
        }
    }

    /// Buttons side by side, or one under another where they wouldn't fit.
    @ViewBuilder private func flow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 6) { content() }
        } else {
            HStack(spacing: 8) { content() }
        }
    }

    private func problem<Actions: View>(_ text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0xFFB3BB))
                .fixedSize(horizontal: false, vertical: true)
            flow { actions() }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.danger.opacity(0.1)))
    }

    /// The problems of the plugin's formats in plain words, nil when there are none.
    private func problemText(_ plugin: ManagedPlugin) -> String? {
        let lines = plugin.activeBundles.flatMap { bundle -> [String] in
            guard case .done(let issues) = manager.state(of: bundle) else { return [] }
            return issues.map { "\(bundle.format.rawValue): \(t.issue($0))" }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// What can be done with the plugin, the same on every tab.
    private func actionBar(_ plugin: ManagedPlugin) -> some View {
        flow {
            actions(plugin)
            if !compact { Spacer(minLength: 0) }
            moreMenu(plugin)
        }
    }

    @ViewBuilder private func actions(_ plugin: ManagedPlugin) -> some View {
        Button(t("mgr.reveal")) { NSWorkspace.shared.activateFileViewerSelecting(plugin.bundles.map(\.url)) }
            .buttonStyle(PillButtonStyle())
        Button(t("row.recheck")) { manager.recheck([plugin]) }
            .buttonStyle(PillButtonStyle())
            .disabled(isRunning)
        Button(t(plugin.isDisabled ? "row.enable" : "row.disable")) { toggleDisabled(plugin) }
            .buttonStyle(PillButtonStyle())
            .disabled(manager.busy)
    }

    /// Removing a plugin, a step away from the everyday buttons.
    private func moreMenu(_ plugin: ManagedPlugin) -> some View {
        Menu {
            Button(t("mgr.uninstall")) { model.uninstallTarget = plugin }
            Button(t("mgr.trash")) { confirmTrash(plugin) }
        } label: {
            // Invisible, like the gear's: the system menu ignores the label's colour
            Image(nsImage: NSImage(size: NSSize(width: 36, height: 26)))
        }
        .menuStyle(BorderlessButtonMenuStyle(showsMenuIndicator: false))
        .frame(width: 36, height: 26)
        .background(ZStack {
            Capsule().fill(Color.raised)
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundColor(.text)
        })
        .contentShape(Capsule())
        .disabled(manager.busy)
        .help(t("row.more"))
    }

    /// A draft for the developer's support: written in a mail, or copied for where mail isn't set up.
    @ViewBuilder private func supportButtons(_ plugin: ManagedPlugin) -> some View {
        Button(t("row.writeSupport")) { NSWorkspace.shared.open(supportDraft(plugin).mailto) }
            .buttonStyle(PillButtonStyle())
        Button(t("row.copyDraft")) {
            let draft = supportDraft(plugin)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(draft.subject + "\n\n" + draft.body, forType: .string)
        }
        .buttonStyle(PillButtonStyle())
    }

    private func supportDraft(_ plugin: ManagedPlugin) -> SupportDraft {
        var issues: [String: [Issue]] = [:]
        for bundle in plugin.activeBundles {
            if case .done(let found) = manager.state(of: bundle) { issues[bundle.id] = found }
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let context = SupportContext(macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                                     cpu: PluginInventory.hostArch, appVersion: app)
        return SupportDraft.make(plugin: plugin, issues: issues, context: context)
    }

    // MARK: Tags

    private func tagsSection(_ plugin: ManagedPlugin) -> some View {
        let current = model.labels.labels(of: plugin.key)
        let unused = model.labels.allTags.map(\.tag).filter { tag in
            !current.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
        return VStack(alignment: .leading, spacing: 8) {
            if !current.tags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6, alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(current.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag).font(.system(size: 11, weight: .semibold)).foregroundColor(.text).lineLimit(1)
                            Button { model.labels.removeTag(tag, from: plugin.key) } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.label)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help(t("tags.remove"))
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.raised))
                        .fixedSize()
                    }
                }
            }
            flow {
                NewTagField(placeholder: t("tags.add")) { model.labels.addTag($0, to: plugin.key) }
                if !unused.isEmpty {
                    Menu(t("tags.existing")) {
                        ForEach(unused, id: \.self) { tag in
                            Button(tag) { model.labels.addTag(tag, to: plugin.key) }
                        }
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .fixedSize()
                }
            }
            HStack(spacing: 8) {
                ForEach(LabelColor.allCases, id: \.self) { color in
                    Button { model.labels.setColor(current.color == color ? nil : color, for: plugin.key) } label: {
                        Circle().fill(color.swatch).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.text, lineWidth: current.color == color ? 2 : 0).padding(-3))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(current.color == color ? t("tags.noColor") : "")
                }
            }
        }
    }

    private func bundles(_ plugin: ManagedPlugin) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(plugin.bundles) { bundle in
                if compact {
                    compactBundle(bundle)
                } else {
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
    }

    private func compactBundle(_ bundle: PluginBundle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                FormatPill(text: bundle.format.rawValue, level: manager.state(of: bundle).level)
                Text(state(bundle)).font(.system(size: 12)).foregroundColor(.label).lineLimit(1)
                Spacer(minLength: 0)
                if let size = manager.size(of: bundle) {
                    Text(formatBytes(size)).font(.system(size: 11)).foregroundColor(.label)
                }
            }
            Text(bundle.displayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.text)
                .lineLimit(2)
            Text(bundle.archs.joined(separator: " · ")).font(.system(size: 11)).foregroundColor(.label)
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

    @ViewBuilder private var flSection: some View {
        if compact {
            VStack(alignment: .leading, spacing: 14) {
                flFormats
                if let picture = model.picture(of: row) {
                    PictureWell(plugin: picture, model: model, t: t, compact: true)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 18) {
                flFormats
                if let picture = model.picture(of: row) {
                    PictureWell(plugin: picture, model: model, t: t)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var flFormats: some View {
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
    }

    @ViewBuilder private func vendorData(_ plugin: ManagedPlugin) -> some View {
        if let folders = manager.vendorData[plugin.vendor], !folders.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("mgr.vendorData")).font(.system(size: 12, weight: .semibold)).foregroundColor(.label)
                ForEach(folders, id: \.self) { folder in
                    if compact {
                        VStack(alignment: .leading, spacing: 4) {
                            folderPath(folder).lineLimit(2)
                            HStack(spacing: 10) {
                                folderSize(folder)
                                Spacer()
                                revealButton(folder)
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            folderPath(folder).lineLimit(1)
                            Spacer()
                            folderSize(folder)
                            revealButton(folder)
                        }
                    }
                }
            }
            .onAppear { manager.measure(folders) }
        }
    }

    private func folderPath(_ folder: URL) -> some View {
        Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.text)
    }

    private func folderSize(_ folder: URL) -> some View {
        Text(manager.folderSizes[folder].map(formatBytes) ?? "…").font(.system(size: 11)).foregroundColor(.label)
    }

    private func revealButton(_ folder: URL) -> some View {
        Button(t("mgr.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
            .buttonStyle(PillButtonStyle())
    }

    /// Turning off asks first: open projects lose the plugin. Both ways wait for FL to be closed.
    private func toggleDisabled(_ plugin: ManagedPlugin) {
        if plugin.isDisabled {
            model.whenFLClosed { manager.setDisabled(plugin, false) }
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("row.disable") + ": " + plugin.name
        alert.informativeText = t("row.disableInfo")
        alert.addButton(withTitle: t("row.disable"))
        alert.addButton(withTitle: t("mgr.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.whenFLClosed { manager.setDisabled(plugin, true) }
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
    /// Only the buttons: the panel shows the picture above them and takes the drop there.
    var compact = false
    @State private var targeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !compact { well }
            VStack(alignment: .leading, spacing: 6) {
                Text(t("row.picture")).font(.system(size: 12, weight: .semibold)).foregroundColor(.label)
                pictureButtons
            }
            .disabled(model.pictures.busy)
        }
    }

    private var well: some View {
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
    }

    @ViewBuilder private var pictureButtons: some View {
        let retake = Button(t("fl.retake")) { model.whenFLClosed { model.pictures.generate([plugin], screenshots: true) } }
        let card = Button(t("fl.useCard")) { model.whenFLClosed { model.pictures.generate([plugin], screenshots: false) } }
        let pick = Button(t("fl.choose")) { choose() }
        let remove = Button(t("fl.remove")) { model.whenFLClosed { model.pictures.remove([plugin]) } }
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                retake.buttonStyle(PillButtonStyle())
                card.buttonStyle(PillButtonStyle())
                pick.buttonStyle(PillButtonStyle())
                if plugin.source != nil { remove.buttonStyle(PillButtonStyle(destructive: true)) }
            }
        } else {
            HStack(spacing: 6) {
                retake.buttonStyle(PillButtonStyle())
                card.buttonStyle(PillButtonStyle())
            }
            HStack(spacing: 6) {
                pick.buttonStyle(PillButtonStyle())
                if plugin.source != nil { remove.buttonStyle(PillButtonStyle(destructive: true)) }
            }
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

/// The plugin's license: nothing is read from the Keychain until the user asks to see or copy it.
struct LicenseSection: View {
    let plugin: ManagedPlugin
    @ObservedObject var model: AppModel
    let t: L10n
    var compact = false
    /// Set while the form is open.
    @Binding var editing: Bool

    /// The license on screen after "Show".
    @State private var revealed: License?
    /// The form, while adding or editing.
    @State private var draft: License?
    /// Redraws after a change: the vault isn't observable.
    @State private var version = 0

    private var vault: LicenseVault { model.vault }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft != nil {
                form
            } else if vault.hasLicense(plugin.key) {
                saved
            } else {
                Button(t("license.add")) { draft = License() }.buttonStyle(PillButtonStyle())
            }
        }
        .id(version)
        .onChange(of: draft != nil) { editing = $0 }
    }

    private var saved: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let license = revealed {
                VStack(alignment: .leading, spacing: 4) {
                    Text(license.serial).font(.system(size: 12, design: .monospaced)).foregroundColor(.text)
                    if !license.email.isEmpty { Text(license.email).font(.system(size: 12)).foregroundColor(.label) }
                    if !license.note.isEmpty { Text(license.note).font(.system(size: 12)).foregroundColor(.label) }
                }
            } else {
                Text("••••••••••").font(.system(size: 13)).foregroundColor(.label)
            }
            buttons
        }
    }

    @ViewBuilder private var buttons: some View {
        let show = Button(revealed == nil ? t("license.show") : t("license.hide")) { toggleReveal() }
        let copy = Button(t("license.copy")) { copySerial() }
        let edit = Button(t("license.edit")) { startEditing() }
        let delete = Button(t("license.delete")) { confirmDelete() }.buttonStyle(PillButtonStyle(destructive: true))
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                show.buttonStyle(PillButtonStyle())
                copy.buttonStyle(PillButtonStyle())
                edit.buttonStyle(PillButtonStyle())
                delete
            }
        } else {
            HStack(spacing: 8) {
                show.buttonStyle(PillButtonStyle())
                copy.buttonStyle(PillButtonStyle())
                edit.buttonStyle(PillButtonStyle())
                delete
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            field("license.serial", \.serial)
            field("license.email", \.email)
            field("license.note", \.note)
            Text(t("license.hint")).font(.system(size: 11)).foregroundColor(.label)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(t("license.save")) { save() }.buttonStyle(PillButtonStyle(primary: true))
                Button(t("mgr.cancel")) { draft = nil }.buttonStyle(PillButtonStyle())
            }
        }
    }

    private func field(_ title: String, _ path: WritableKeyPath<License, String>) -> some View {
        TextField(t(title), text: Binding(get: { draft?[keyPath: path] ?? "" }, set: { draft?[keyPath: path] = $0 }))
            .textFieldStyle(PlainTextFieldStyle())
            .font(.system(size: 12))
            .foregroundColor(.text)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(Color.raised))
    }

    // MARK: Actions

    private func toggleReveal() {
        if revealed != nil { revealed = nil; return }
        do { revealed = try vault.license(plugin.key) } catch { model.report(error) }
    }

    private func copySerial() {
        do {
            if let license = try vault.license(plugin.key) { model.copySecret(license.serial) }
        } catch { model.report(error) }
    }

    private func startEditing() {
        do { draft = try vault.license(plugin.key) ?? License() } catch { model.report(error) }
    }

    private func save() {
        guard let license = draft else { return }
        do {
            try vault.save(license, for: plugin.key)
            draft = nil
            revealed = nil
            version += 1
            model.objectWillChange.send()  // the dot on the tab
        } catch { model.report(error) }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t("license.confirm", plugin.name)
        alert.addButton(withTitle: t("license.delete"))
        alert.addButton(withTitle: t("mgr.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try vault.remove(plugin.key)
            revealed = nil
            version += 1
            model.objectWillChange.send()  // the dot on the tab
        } catch { model.report(error) }
    }
}
