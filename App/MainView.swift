import SwiftUI
import AppKit

/// How the window shows the plugins. The raw value is what's remembered between launches.
enum PluginViewMode: String {
    case list, cards
}

/// The whole window: header with search and filters, every plugin, and the tasks below.
struct MainView: View {
    @ObservedObject var model: AppModel
    let t: L10n

    @State private var gearHovered = false
    @AppStorage("viewMode") private var viewMode: PluginViewMode = .list

    var body: some View {
        VStack(spacing: 10) {
            header
            if let banner = model.banner { bannerView(banner) }
            HStack(spacing: 10) {
                list
                if let row = panelRow {
                    PluginDetailPanel(row: row, model: model, t: t)
                        .id(row.id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            TasksView(model: model, t: t)
        }
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.2), value: model.banner?.id)
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.2), value: panelRow == nil)
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.2), value: model.tasksAllDone)
        .sheet(isPresented: $model.showFolderSheet) {
            FolderSortSheet(model: model, t: t)
        }
        .sheet(isPresented: $model.showCleanupSheet) {
            CleanupSheet(model: model, t: t)
        }
        .sheet(item: $model.uninstallTarget) { plugin in
            UninstallSheet(plugin: plugin, model: model, t: t)
        }
    }

    /// The plugin open in the panel. Only the cards have one; the list opens plugins in place. Gone when
    /// a filter or the Trash takes the plugin away.
    private var panelRow: CatalogRow? {
        guard viewMode == .cards, let id = model.expanded else { return nil }
        return model.rows.first { $0.id == id }
    }

    // MARK: - Result banner

    private func bannerView(_ banner: Banner) -> some View {
        HStack(spacing: 12) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(banner.isError ? .danger : .mint)
            Text(text(of: banner))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.text)
                .lineLimit(2)
            Spacer()
            if let undo = banner.undo {
                Button(t("task.undo")) {
                    model.banner = nil
                    undo()
                }
                .buttonStyle(PillButtonStyle())
            }
            Button { model.banner = nil } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(.label)
            }
            .buttonStyle(PointerButtonStyle())
            .help(t("banner.close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16)
            .fill(banner.isError ? Color.danger.opacity(0.14) : Color.mint.opacity(0.1)))
        .transition(.opacity)
    }

    private func text(of banner: Banner) -> String {
        switch banner.source {
        case .sorter(let status):    return t.status(status)
        case .pictures(let status):  return t.flStatus(status) + (isDone(status) ? " · " + t("fl.restart") : "")
        case .manager(let status):   return t.managerStatus(status)
        case .favorites(let status): return t.favoritesStatus(status)
        }
    }

    private func isDone(_ status: FLStatus) -> Bool {
        if case .done = status { return true }
        return false
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AppLogo()
                    .padding(.trailing, 4)
                    .help(t("subtitle"))
                searchField
                viewToggle
                gearMenu
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // On a line of their own: beside the search they squeezed it down to nothing
            filters
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            if let checking = model.manager.checking {
                progressLine(t("main.checking", checking.done + 1, checking.total, checking.current), checking)
            }
            if let capture = model.pictures.capture {
                progressLine(t("main.capturing", capture.done + 1, capture.total, capture.current), capture) {
                    let stopping = model.pictures.stopRequested
                    Button(t(stopping ? "main.stopping" : "gear.stopPictures")) { model.pictures.stopCapture() }
                        .buttonStyle(PillButtonStyle(compact: true))
                        .disabled(stopping)
                }
            }
        }
        .card()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.label)
            TextField(t("main.search"), text: $model.query)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13))
                .foregroundColor(.text)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(Capsule().fill(Color.inset))
    }

    private var viewToggle: some View {
        HStack(spacing: 2) {
            viewButton(.list, icon: "list.bullet", help: "view.list")
            viewButton(.cards, icon: "square.grid.2x2", help: "view.cards")
        }
        .padding(2)
        .background(Capsule().fill(Color.inset))
    }

    private func viewButton(_ mode: PluginViewMode, icon: String, help: String) -> some View {
        Button {
            withAnimation(Motion.reduced ? nil : .easeOut(duration: 0.2)) { viewMode = mode }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(viewMode == mode ? .text : .label)
                .frame(width: 28, height: 28)
                .background(Circle().fill(viewMode == mode ? Color.raised : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PointerButtonStyle())
        .help(t(help))
    }

    private var filters: some View {
        HStack(spacing: 6) {
            filterPill(.all, "filter.all")
            // Stays while it's the filter, or the list would be empty with nothing lit to say why
            if model.count(.problems) > 0 || model.filter == .problems { filterPill(.problems, "filter.problems") }
            filterPill(.notInFL, "filter.notInFL")
            // Shown only once they find something
            if model.count(.new) > 0 { filterPill(.new, "filter.new") }
            if model.count(.duplicates) > 0 { filterPill(.duplicates, "filter.duplicates") }
            if model.count(.disabled) > 0 { filterPill(.disabled, "filter.disabled") }
            if !model.labels.allTags.isEmpty { tagsMenu }
        }
    }


    /// The user's tags as a pill that opens a menu; it shows the tag while one is the filter.
    private var tagsMenu: some View {
        var active: String?
        if case .tag(let tag) = model.filter { active = tag }
        return Menu {
            ForEach(model.labels.allTags, id: \.tag) { item in
                Button(item.tag + "  (\(item.count))") { model.filter = active == item.tag ? .all : .tag(item.tag) }
            }
        } label: {
            Text(active ?? t("filter.tags"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(active == nil ? .text : .white)
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .pointerCursor()
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Group { if active != nil { accentGradient } else { Color.raised } })
        .clipShape(Capsule())
    }

    private func filterPill(_ filter: CatalogFilter, _ key: String) -> some View {
        FilterPill(title: t(key), count: model.count(filter), isOn: model.filter == filter) {
            model.filter = filter
        }
    }

    /// Things needed now and then: a full recheck, the AU cache, removed favourites, settings.
    private var gearMenu: some View {
        Menu {
            Button(t("gear.recheck")) { model.manager.recheckAll() }
            Button(t("fix.resetAU")) { model.manager.apply(.resetAUCache, for: nil) }
                .disabled(model.manager.busy)
            if model.pictures.capturingAll {
                Button(t("gear.stopPictures")) { model.pictures.stopCapture() }
            } else {
                Button(t("gear.allPictures")) { model.captureAllPictures() }
                    .disabled(model.pictures.busy || model.shotTargets.isEmpty)
            }
            Button(t("gear.restore")) { model.whenFLClosed { model.favorites.restore() } }
                .disabled(!model.favorites.canRestore)
            Menu(t("gear.export")) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button(t("export." + format.rawValue)) { model.export(as: format) }
                }
            }
            Divider()
            Button(t("gear.settings")) { openSettings() }
        } label: {
            // Invisible: the system menu keeps room for an arrow, which would push a visible
            // label off-centre, and it ignores the label's colour
            Image(nsImage: NSImage(size: NSSize(width: 32, height: 32)))
        }
        .menuStyle(BorderlessButtonMenuStyle(showsMenuIndicator: false))
        .pointerCursor()
        .frame(width: 32, height: 32)
        .background(ZStack {
            Circle().fill(gearHovered ? Color.inset : Color.raised)
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(gearHovered ? .text : .label)
        })
        .contentShape(Circle())
        .onHover { gearHovered = $0 }
    }

    private func openSettings() {
        // The app menu's own Settings… item (⌘,). macOS 14 made the showSettingsWindow: selector
        // do nothing, and SettingsLink doesn't exist before it; this item works on every version
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let item = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) else { return }
        menu.performActionForItem(at: item)
    }

    private func progressLine<Accessory: View>(_ text: String, _ progress: CheckProgress,
                                               @ViewBuilder accessory: () -> Accessory = { EmptyView() }) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.label)
                    .lineLimit(1)
                Spacer()
                accessory()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.inset)
                    Capsule()
                        .fill(accentGradient)
                        .frame(width: max(4, geo.size.width * CGFloat(progress.done) / CGFloat(max(progress.total, 1))))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - List

    private var list: some View {
        let rows = model.rows
        return VStack(spacing: 0) {
            if model.filter == .duplicates { cleanupBar }
            if model.filter == .new { newBar }
            if viewMode == .list { columnHeaders } else { cardHeaders }
            if rows.isEmpty {
                Text(t("main.empty"))
                    .font(.system(size: 13))
                    .foregroundColor(.label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Group {
                        if viewMode == .list {
                            LazyVStack(spacing: 2) {
                                ForEach(rows) { row in
                                    PluginRowView(row: row, model: model, t: t)
                                }
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                                ForEach(rows) { row in
                                    PluginCardView(row: row, model: model, t: t)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .background(SmoothScroll())
                }
                // Only the fades are clipped, or they'd paint over the card's rounded corners.
                // A clip on the list itself would mask all of it in every frame of the scroll.
                .overlay(VStack(spacing: 0) {
                    edgeFade(.top)
                    Spacer(minLength: 0)
                    edgeFade(.bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .allowsHitTesting(false))
            }
        }
        .frame(maxHeight: .infinity)
        .card()
    }

    /// Above the list while the duplicates filter is on: how much there is to clean and a way to do it.
    private var cleanupBar: some View {
        let findings = model.findings
        let bytes = findings.reduce(0) { $0 + model.size(of: $1) }
        return HStack(spacing: 12) {
            Text(t("cleanup.found", findings.count, formatBytes(bytes)))
                .font(.system(size: 13)).foregroundColor(.text)
            Spacer()
            Button(t("cleanup.review")) { model.showCleanupSheet = true }
                .buttonStyle(PillButtonStyle(primary: true))
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    /// Above the list while the new filter is on: the marks stay until they are cleared here.
    private var newBar: some View {
        HStack {
            Spacer()
            Button(t("new.markSeen")) { model.markAllSeen() }
                .buttonStyle(PillButtonStyle(primary: true))
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    /// Rows melt into the card's edge instead of being cut off by it.
    private func edgeFade(_ edge: UnitPoint) -> some View {
        LinearGradient(gradient: Gradient(colors: [Color.panel, Color.panel.opacity(0)]),
                       startPoint: edge, endPoint: edge == .top ? .bottom : .top)
            .frame(height: 12)
            .allowsHitTesting(false)
    }

    private var columnHeaders: some View {
        HStack(spacing: PluginRowView.spacing) {
            Color.clear.frame(width: PluginRowView.ledWidth, height: 1)
            sortHeader(t("col.plugin"), .name).frame(maxWidth: .infinity, alignment: .leading)
            header(t("col.formats")).frame(width: PluginRowView.formatsWidth, alignment: .trailing)
            header("FL").frame(width: PluginRowView.starWidth)
            header(t("col.category")).frame(width: PluginRowView.categoryWidth, alignment: .leading)
            sortHeader(t("col.size"), .size).frame(width: PluginRowView.sizeWidth, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// The list's column titles sort it; the cards have no columns, so only the sorting stays.
    private var cardHeaders: some View {
        HStack(spacing: PluginRowView.spacing) {
            sortHeader(t("col.plugin"), .name)
            sortHeader(t("col.size"), .size)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).caption()
    }

    private func sortHeader(_ text: String, _ sort: CatalogSort) -> some View {
        Button { model.sort = sort } label: {
            HStack(spacing: 4) {
                Text(text.uppercased()).caption(model.sort == sort ? .text : .label)
                if model.sort == sort {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.text)
                }
            }
        }
        .buttonStyle(PointerButtonStyle())
    }
}
