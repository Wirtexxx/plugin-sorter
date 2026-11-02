import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// FL Studio tab: adds pictures to favourites in FL's plugin database.
struct FLView: View {
    @ObservedObject var library: FLLibrary
    let t: L10n

    var body: some View {
        VStack(spacing: 6) {
            if FLDatabase.exists {
                overview
                tiles
                bottomBar
            } else {
                Text(t("fl.notFound"))
                    .font(.system(size: 13))
                    .foregroundColor(.label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .panel()
            }
        }
        .onAppear { library.scan() }
    }

    // MARK: - Sections

    private var overview: some View {
        let total = max(library.plugins.count, 1)
        let withPicture = library.plugins.count - library.missing.count
        return HStack(spacing: 6) {
            HStack(spacing: 22) {
                Knob(value: withPicture, fraction: Double(withPicture) / Double(total), label: t("fl.withPicture").uppercased())
                Knob(value: library.missing.count, fraction: Double(library.missing.count) / Double(total),
                     label: t("fl.missing").uppercased())
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
            .panel()

            VStack(alignment: .leading, spacing: 10) {
                Text(t("fl.title").uppercased()).caption()
                if library.busy {
                    HStack {
                        Text("\(t("fl.capturing").uppercased()) · \(library.current)").caption(.text).lineLimit(1)
                        Spacer()
                        Text("\(Int(library.progress * 100))%").caption()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.inset)
                            Capsule()
                                .fill(LinearGradient(gradient: Gradient(colors: [Color.accent, Color.accentHot]),
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, geo.size.width * CGFloat(library.progress)))
                                .shadow(color: Color.accent.opacity(0.6), radius: 4)
                        }
                    }
                    .frame(height: 6)
                } else {
                    Text(t("fl.hint"))
                        .font(.system(size: 12))
                        .foregroundColor(.label)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .done = library.status {
                        HStack(spacing: 8) {
                            StatusDot()
                            Text(t("fl.restart"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.text)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .panel()
        }
        .frame(height: 130)
    }

    private var tiles: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6, alignment: .top)], spacing: 6) {
                ForEach(library.visible) { plugin in
                    FLTile(plugin: plugin, t: t, library: library)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .panel()
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            PowerToggle(title: t("fl.showStock").uppercased(), isOn: library.showStock) { library.showStock.toggle() }
            Rectangle().fill(Color.edge).frame(width: 1, height: 16)
            Text(t.flStatus(library.status).uppercased()).caption().lineLimit(1)
            Spacer()
            if library.busy { ProgressView().controlSize(.small) }
            Button(t("fl.removeMine").uppercased()) { library.remove(library.mine) }
                .buttonStyle(PluginButtonStyle())
                .disabled(library.busy || library.mine.isEmpty)
            Button(t("button.refresh").uppercased()) { library.scan() }
                .buttonStyle(PluginButtonStyle())
                .disabled(library.busy)
            Button(t("fl.generate").uppercased()) { library.generateMissing() }
                .buttonStyle(PluginButtonStyle(primary: true))
                .disabled(library.busy || library.missing.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .panel()
    }
}

struct FLTile: View {
    let plugin: FLPlugin
    let t: L10n
    @ObservedObject var library: FLLibrary
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.chassis)
                if plugin.hasPicture, let image = NSImage(contentsOf: plugin.picture) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundColor(.edge)
                        Text(t("fl.noPicture").uppercased()).caption()
                    }
                }
            }
            .frame(height: 104)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(targeted ? Color.accent : .clear, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plugin.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.text)
                        .lineLimit(1)
                    Text(plugin.info.vendor.uppercased()).caption().lineLimit(1)
                }
                Spacer(minLength: 4)
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(plugin.source == nil ? .label : .accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .panel(.raised, radius: 3)
                }
            }
        }
        .padding(10)
        .panel(.inset, radius: 5)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            guard !plugin.isStock, let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                library.setCustom(plugin, image: url)
            }
            return true
        }
        .contextMenu {
            if !plugin.isStock {
                Button(t("fl.retake")) { library.generate([plugin], screenshots: true) }
                Button(t("fl.useCard")) { library.generate([plugin], screenshots: false) }
                Button(t("fl.choose")) { chooseImage() }
                if plugin.source != nil {
                    Divider()
                    Button(t("fl.remove")) { library.remove([plugin]) }
                }
            }
        }
    }

    private var badge: String? {
        switch plugin.source {
        case .screenshot?: return t("badge.screenshot").uppercased()
        case .card?:       return t("badge.card").uppercased()
        case .custom?:     return t("badge.custom").uppercased()
        case nil:          return plugin.hasPicture ? "FL" : nil
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            library.setCustom(plugin, image: url)
        }
    }
}
