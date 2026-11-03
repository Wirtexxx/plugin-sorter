import SwiftUI
import AppKit

/// The whole window: header with search and filters, every plugin, and the tasks below.
struct MainView: View {
    @ObservedObject var model: AppModel
    let t: L10n

    var body: some View {
        VStack(spacing: 10) {
            header
            if let banner = model.banner { bannerView(banner) }
            list
            TasksView(model: model, t: t)
        }
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.2), value: model.banner?.id)
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.2), value: model.tasksAllDone)
        .sheet(isPresented: $model.showFolderSheet) {
            FolderSortSheet(model: model, t: t)
        }
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
            .buttonStyle(PlainButtonStyle())
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
                GradientTitle(text: "PLUGIN SORTER")
                    .padding(.trailing, 4)
                    .help(t("subtitle"))
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
                .frame(height: 32)
                .background(Capsule().fill(Color.inset))
                filters
                gearMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if let checking = model.manager.checking {
                checkingLine(checking)
            }
        }
        .card()
    }

    private var filters: some View {
        HStack(spacing: 6) {
            filterPill(.all, "filter.all")
            filterPill(.problems, "filter.problems")
            filterPill(.notInFL, "filter.notInFL")
            // Places for later features: shown only once they find something
            if model.count(.new) > 0 { filterPill(.new, "filter.new") }
            if model.count(.duplicates) > 0 { filterPill(.duplicates, "filter.duplicates") }
        }
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
            Button(t("gear.restore")) { model.whenFLClosed { model.favorites.restore() } }
                .disabled(!model.favorites.canRestore)
            Divider()
            Button(t("gear.settings")) { openSettings() }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.label)
        }
        .menuStyle(BorderlessButtonMenuStyle(showsMenuIndicator: false))
        .frame(width: 32, height: 32)
        .background(Circle().fill(Color.raised))
    }

    private func openSettings() {
        // The Settings scene's window; the selector was renamed in macOS 13
        if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func checkingLine(_ checking: CheckProgress) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(t("main.checking", checking.done + 1, checking.total, checking.current))
                    .font(.system(size: 12))
                    .foregroundColor(.label)
                    .lineLimit(1)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.inset)
                    Capsule()
                        .fill(accentGradient)
                        .frame(width: max(4, geo.size.width * CGFloat(checking.done) / CGFloat(max(checking.total, 1))))
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
            columnHeaders
            if rows.isEmpty {
                Text(t("main.empty"))
                    .font(.system(size: 13))
                    .foregroundColor(.label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { row in
                            PluginRowView(row: row, model: model, t: t)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .background(SmoothScroll())
                }
                .overlay(edgeFade(.top), alignment: .top)
                .overlay(edgeFade(.bottom), alignment: .bottom)
                // The fades would otherwise paint over the card's rounded corners
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxHeight: .infinity)
        .card()
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
        .buttonStyle(PlainButtonStyle())
    }
}
