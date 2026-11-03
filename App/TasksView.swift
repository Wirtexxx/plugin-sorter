import SwiftUI

/// The jobs that act on every plugin at once, each with how much is left and one button.
/// Once all of them are done they fold into a small strip that opens them again.
struct TasksView: View {
    @ObservedObject var model: AppModel
    let t: L10n

    @State private var expanded = false

    var body: some View {
        let allDone = model.tasksAllDone
        return VStack(spacing: 10) {
            if !allDone || expanded {
                HStack(spacing: 10) {
                    folders
                    categories
                    pictures
                }
                .frame(height: 100)
            }
            if allDone { strip }
        }
        .onChange(of: allDone) { _ in expanded = false }
    }

    private var strip: some View {
        Button {
            if Motion.reduced {
                expanded.toggle()
            } else {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.mint)
                Text(t("task.allDone")).font(.system(size: 12)).foregroundColor(.label)
                Spacer()
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.label)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .card()
        .help(t(expanded ? "task.collapse" : "task.expand"))
    }

    private var folders: some View {
        let sorter = model.sorter
        let remaining = sorter.applied ? 0 : sorter.moves.count
        return TaskCard(title: t("task.folders"),
                        detail: sorter.running ? t("mgr.checking") + "…" : t("task.folders.left", remaining),
                        remaining: remaining, total: max(model.manager.plugins.count, remaining),
                        progress: nil, busy: sorter.running,
                        action: t("task.sort"), run: { model.showFolderSheet = true },
                        canUndo: sorter.latestLog != nil, undo: { sorter.undo() }, t: t)
    }

    private var categories: some View {
        let favorites = model.favorites
        let remaining = favorites.unsorted.count
        let working = favorites.busy && !favorites.current.isEmpty
        return TaskCard(title: t("task.categories"),
                        detail: working ? "\(t("fav.reading")) · \(favorites.current)" : t("task.categories.left", remaining),
                        remaining: remaining, total: max(model.categoryTotal, remaining),
                        progress: nil, busy: favorites.busy,
                        action: t("task.sort"), run: { model.whenFLClosed { favorites.sortByCategory() } },
                        canUndo: favorites.canUnsort, undo: { model.whenFLClosed { favorites.unsort() } }, t: t)
    }

    private var pictures: some View {
        let library = model.pictures
        let remaining = model.missingPictures.count
        return TaskCard(title: t("task.pictures"),
                        detail: library.busy ? "\(t("fl.capturing")) · \(library.current)" : t("task.pictures.left", remaining),
                        remaining: remaining, total: max(model.pictureTargets.count, remaining),
                        progress: library.busy ? library.progress : nil, busy: library.busy,
                        action: t("task.add"), run: { model.whenFLClosed { library.generate(model.missingPictures, screenshots: true) } },
                        canUndo: !library.mine.isEmpty, undo: { model.whenFLClosed { library.remove(library.mine) } }, t: t)
    }
}

private struct TaskCard: View {
    let title: String
    let detail: String
    let remaining: Int
    let total: Int
    let progress: Double?
    let busy: Bool
    let action: String
    let run: () -> Void
    let canUndo: Bool
    let undo: () -> Void
    let t: L10n

    var body: some View {
        HStack(spacing: 12) {
            TaskRing(remaining: remaining, total: total, progress: progress)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.text).lineLimit(1)
                Text(remaining == 0 && !busy ? t("task.done") : detail)
                    .font(.system(size: 12))
                    .foregroundColor(remaining == 0 && !busy ? .mint : .label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Group {
                    if remaining > 0 || busy {
                        Button(action, action: run)
                            .buttonStyle(PillButtonStyle(primary: true, compact: true))
                            .disabled(busy)
                    } else {
                        Button(t("task.undo"), action: undo)
                            .buttonStyle(PillButtonStyle(compact: true))
                            .disabled(!canUndo)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }
}

/// Preview of the folder sort: what moves where, which formats, and the script's notes.
struct FolderSortSheet: View {
    @ObservedObject var model: AppModel
    let t: L10n

    var body: some View {
        let sorter = model.sorter
        return VStack(alignment: .leading, spacing: 14) {
            Text(t("sheet.title")).font(.system(size: 18, weight: .semibold)).foregroundColor(.text)
            Text(t("sheet.subtitle")).font(.system(size: 13)).foregroundColor(.label)
            HStack(spacing: 6) {
                FilterPill(title: "VST3", count: nil, isOn: sorter.vst3) { sorter.vst3.toggle(); sorter.preview() }
                FilterPill(title: "VST", count: nil, isOn: sorter.vst) { sorter.vst.toggle(); sorter.preview() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if sorter.moves.isEmpty {
                        Text(t("sheet.empty")).font(.system(size: 13)).foregroundColor(.label)
                    }
                    ForEach(sorter.groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.vendor).font(.system(size: 13, weight: .semibold)).foregroundColor(.text)
                            ForEach(group.items) { move in
                                HStack {
                                    Text(move.plugin).font(.system(size: 13)).foregroundColor(.text)
                                    Spacer()
                                    FormatPill(text: move.format, level: nil)
                                }
                            }
                        }
                    }
                    ForEach(sorter.notes) { note in
                        Text(t.note(note)).font(.system(size: 12)).foregroundColor(.label)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.inset))
            HStack {
                Spacer()
                Button(t("mgr.cancel")) { model.showFolderSheet = false }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(t("task.sort")) {
                    model.showFolderSheet = false
                    sorter.apply()
                }
                .buttonStyle(PillButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(sorter.moves.isEmpty || sorter.running)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .background(Color.panel)
    }
}
