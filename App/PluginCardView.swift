import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The picture of a plugin, or a generated card when it has none. The card is only drawn here:
/// nothing is written to FL's database. Our cards' header is cut off: the name is shown next to the
/// picture anyway, and the header's green dot would contradict the plugin's real state.
struct CardArtwork: View {
    let title: String
    let vendor: String
    let url: URL?
    /// The picture is one of ours, with the header on top. FL's own pictures have none.
    let hasHeader: Bool
    /// False to true means the picture may have been rewritten in place.
    let busy: Bool

    @State private var image: NSImage?
    @State private var loaded = false

    /// One at a time: cards come and go by the dozen while scrolling, and each would take a thread.
    private static let queue = DispatchQueue(label: "plugin-sorter.pictures", qos: .userInitiated)

    var body: some View {
        Color.chassis
            .aspectRatio(FLCard.size.width / (FLCard.size.height - FLCard.header), contentMode: .fit)
            .overlay(GeometryReader { geo in
                let scale = geo.size.width / FLCard.size.width
                if let image = image {
                    if hasHeader {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: geo.size.width, height: FLCard.size.height * scale)
                            .offset(y: -FLCard.header * scale)
                    } else {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                } else if loaded {
                    FLCard(title: title, vendor: vendor)
                        .scaleEffect(scale, anchor: .topLeading)
                        .offset(y: -FLCard.header * scale)
                }
            })
            .clipped()
            .onAppear {
                // A card scrolled back into view shows its picture at once, then checks the file
                if let url = url, let cached = CardPictures.shared.cached(at: url) {
                    image = cached
                    loaded = true
                }
                load()
            }
            .onChange(of: busy) { if !$0 { load() } }
    }

    private func load() {
        guard let url = url else { loaded = true; return }
        Self.queue.async {
            let image = CardPictures.shared.image(at: url)
            DispatchQueue.main.async {
                self.image = image
                self.loaded = true
            }
        }
    }
}

/// One plugin as a tile: its picture, state, star and name. A click opens the panel on the right.
struct PluginCardView: View {
    let row: CatalogRow
    @ObservedObject var model: AppModel
    let t: L10n

    @State private var hovered = false
    private var isSelected: Bool { model.expanded == row.id }
    private var isRunning: Bool {
        row.plugin?.bundles.contains { model.manager.state(of: $0) == .running } ?? false
    }

    var body: some View {
        let art = model.artwork(of: row)
        return VStack(alignment: .leading, spacing: 0) {
            CardArtwork(title: row.name, vendor: row.vendor, url: art?.url,
                        hasHeader: art?.hasHeader ?? false, busy: model.pictures.busy)
                .id(art?.url)
                .overlay(LED(level: model.level(of: row), running: isRunning)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.chassis.opacity(0.75)))
                    .padding(4), alignment: .topLeading)
                .overlay(Group { if model.isNew(row) { NewBadge(t: t).padding(6) } }, alignment: .bottomLeading)
            Text(row.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(row.isStale ? .label : .text)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(row.plugin?.isDisabled == true ? 0.45 : 1)
        .background(hovered || isSelected ? Color.raised : Color.inset)
        .overlay(LabelStripe(color: model.labelColor(of: row)), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // One layer per card: dozens of them are on screen, and scrolling moves each of their parts
        .drawingGroup()
        .overlay(Group {
            if model.usesFL {
                PluginStar(row: row, model: model, t: t, size: 12)
                    .background(Circle().fill(Color.chassis.opacity(0.75)))
                    .opacity(row.plugin?.isDisabled == true ? 0.45 : 1)
                    .padding(2)
            }
        }, alignment: .topTrailing)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accent : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .help(row.vendor.isEmpty ? row.name : "\(row.name) · \(row.vendor)")
        .onHover { hovered = $0 && !SmoothScrollView.isScrolling }
        .onTapGesture {
            withAnimation(Motion.reduced ? nil : .easeOut(duration: 0.2)) {
                model.expanded = isSelected ? nil : row.id
            }
        }
    }
}

/// One plugin's details beside the cards, like the preview pane in Finder.
struct PluginDetailPanel: View {
    let row: CatalogRow
    @ObservedObject var model: AppModel
    let t: L10n

    static let width: CGFloat = 300

    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(row.isStale ? .label : .text)
                        .lineLimit(2)
                    Text(row.vendor).font(.system(size: 12)).foregroundColor(.label).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(Motion.reduced ? nil : .easeOut(duration: 0.2)) { model.expanded = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.label)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PointerButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help(t("banner.close"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    artwork
                    HStack(spacing: 8) {
                        if model.usesFL {
                            PluginStar(row: row, model: model, t: t)
                            PluginCategoryMenu(row: row, model: model, t: t)
                        }
                        Spacer(minLength: 0)
                        Text(size).font(.system(size: 12)).foregroundColor(.label)
                    }
                    PluginDetailsView(row: row, model: model, t: t, compact: true)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .background(SmoothScroll())
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private var size: String {
        let bytes = model.size(of: row)
        return bytes > 0 ? formatBytes(bytes) : ""
    }

    /// Takes a dropped image, as the picture in the list's details does, when the plugin has a picture in FL.
    private var artwork: some View {
        let picture = model.picture(of: row)
        let art = model.artwork(of: row)
        return CardArtwork(title: row.name, vendor: row.vendor, url: art?.url,
                           hasHeader: art?.hasHeader ?? false, busy: model.pictures.busy)
            .id(art?.url)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(targeted ? Color.accent : .clear, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                guard let picture = picture, let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { model.whenFLClosed { model.pictures.setCustom(picture, image: url) } }
                }
                return true
            }
    }
}
