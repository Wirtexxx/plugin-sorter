import SwiftUI

/// FL Studio tab → Favourites: choose what FL's browser shows and drop entries of deleted plugins.
struct FavoritesView: View {
    @ObservedObject var library: FavoritesLibrary
    let t: L10n

    var body: some View {
        VStack(spacing: 6) {
            overview
            list
            bottomBar
        }
        .onAppear { library.scan() }
    }

    private var overview: some View {
        let total = max(library.entries.count, 1)
        let stale = library.stale.count
        return HStack(spacing: 6) {
            HStack(spacing: 22) {
                Knob(value: library.favorites.count, fraction: Double(library.favorites.count) / Double(total),
                     label: t("fav.favorites").uppercased())
                Knob(value: library.entries.count, fraction: 1, label: t("fav.installed").uppercased())
                Knob(value: stale, fraction: stale > 0 ? 1 : 0, label: t("fav.removedCount").uppercased())
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
            .panel()

            VStack(alignment: .leading, spacing: 10) {
                Text(t("fav.title").uppercased()).caption()
                if stale > 0 {
                    HStack(spacing: 10) {
                        StatusDot(color: .danger)
                        Text(t("fav.stale", stale))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.text)
                        Spacer()
                        Button(t("fav.removeStale").uppercased()) { library.removeStale() }
                            .buttonStyle(PluginButtonStyle(primary: true))
                            .disabled(library.busy)
                    }
                    Text(library.stale.map(\.title).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundColor(.label)
                        .lineLimit(2)
                } else {
                    Text(t("fav.hint"))
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
                PowerToggle(title: t("fav.onlyFavorites").uppercased(), isOn: library.onlyFavorites) {
                    library.onlyFavorites.toggle()
                }
                PowerToggle(title: t("fl.showStock").uppercased(), isOn: library.showStock) {
                    library.showStock.toggle()
                }
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(library.rows) { row in
                        FavoriteRowView(row: row, library: library, t: t)
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
            Text(t.favoritesStatus(library.status).uppercased()).caption().lineLimit(1)
            Spacer()
            if library.busy { ProgressView().controlSize(.small) }
            Button(t("fav.restore").uppercased()) { library.restore() }
                .buttonStyle(PluginButtonStyle())
                .disabled(library.busy || !library.canRestore)
            Button(t("button.refresh").uppercased()) { library.scan() }
                .buttonStyle(PluginButtonStyle())
                .disabled(library.busy)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .panel()
    }
}

struct FavoriteRowView: View {
    let row: FavoriteRow
    @ObservedObject var library: FavoritesLibrary
    let t: L10n

    var body: some View {
        let starred = row.entries.contains(where: library.isFavorite)
        let state = library.availability(of: row)
        HStack(spacing: 10) {
            Button { library.toggle(row) } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(starred ? .accent : .label)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(library.busy)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(state == .removed ? .label : .text)
                    .lineLimit(1)
                Text("\(row.vendor.uppercased()) · \(t(row.section == "Generators" ? "fav.generator" : "fav.effect").uppercased())")
                    .caption()
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if state == .removed || state == .moved {
                Text(t(state == .removed ? "badge.removed" : "badge.moved").uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(state == .removed ? .danger : .amber)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .panel(.raised, radius: 3)
            }
            HStack(spacing: 4) {
                ForEach(row.entries) { entry in
                    let on = library.isFavorite(entry)
                    Button { library.toggle(entry) } label: {
                        Text(entry.shortFormat)
                            .font(.system(size: 9, weight: .bold))
                            .kerning(0.8)
                            .foregroundColor(on ? .white : .label)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 3).fill(on ? Color.accent : Color.raised))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? Color.clear : Color.edge, lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(library.busy)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panel(.inset, radius: 5)
    }
}
