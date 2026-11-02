import SwiftUI

struct ContentView: View {
    @StateObject private var sorter: Sorter
    @AppStorage("language") private var language = Lang.system.rawValue
    @State private var showNotes = false

    init(sorter: Sorter = Sorter()) {
        _sorter = StateObject(wrappedValue: sorter)
    }

    private var t: L10n { L10n(lang: Lang(rawValue: language) ?? .en) }

    var body: some View {
        ZStack {
            CosmicBackground()
            VStack(alignment: .leading, spacing: 16) {
                header
                controls
                content
                if !sorter.notes.isEmpty { notes }
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 20)
        }
        .background(WindowStyler())
        .onAppear { sorter.refreshLatestLog(); sorter.preview() }
        .onChange(of: sorter.formats) { _ in sorter.preview() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Orb(color: .plasma, size: 42, glow: 0.6)
                Image(systemName: "folder.fill.badge.gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("PLUGIN SORTER")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .kerning(3)
                    .foregroundColor(.white)
                Text(t("subtitle"))
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(Lang.allCases) { lang in
                    Button(lang.rawValue.uppercased()) { language = lang.rawValue }
                        .buttonStyle(PlainButtonStyle())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(language == lang.rawValue ? .white : Color.white.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(language == lang.rawValue ? Color.nebula.opacity(0.45) : .clear))
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Chip(title: "VST3", isOn: sorter.vst3) { sorter.vst3.toggle() }
                Chip(title: "VST", isOn: sorter.vst) { sorter.vst.toggle() }
                Chip(title: "AU", isOn: sorter.au) { sorter.au.toggle() }
            }
            .disabled(sorter.running)
            HStack(spacing: 10) {
                Meter(value: sorter.moves.count, label: t("meter.plugins"))
                Meter(value: sorter.groups.count, label: t("meter.vendors"))
                Meter(value: Set(sorter.moves.map(\.format)).count, label: t("meter.formats"))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if sorter.moves.isEmpty && !sorter.running {
            VStack(spacing: 14) {
                ZStack {
                    Orb(color: .nebula, size: 90, glow: 0.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(t("empty.title"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(t("empty.hint"))
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(sorter.groups) { VendorCard(group: $0) }
                }
                .padding(1)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showNotes.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showNotes ? 90 : 0))
                    Text(t("notes", sorter.notes.count))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
            if showNotes {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(sorter.notes) { note in
                            Text(t.note(note))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(maxHeight: 90)
                .modifier(Glass(radius: 10))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(t("button.undo")) { sorter.undo() }
                .buttonStyle(GlowButtonStyle())
                .disabled(sorter.running || sorter.latestLog == nil)
            Text(t.status(sorter.status))
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.6))
                .lineLimit(1)
            Spacer()
            if sorter.running {
                ProgressView().controlSize(.small)
            }
            Button(t("button.refresh")) { sorter.preview() }
                .buttonStyle(GlowButtonStyle())
                .disabled(sorter.running)
            Button(sorter.applied ? t("button.done") : t("button.sort")) { sorter.apply() }
                .buttonStyle(GlowButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(sorter.running || sorter.applied || sorter.moves.isEmpty)
        }
    }
}

struct VendorCard: View {
    let group: VendorGroup

    /// One row per plugin with all of its formats, in script order.
    private var rows: [(name: String, formats: [String])] {
        var order: [String] = []
        var formats: [String: [String]] = [:]
        for move in group.items {
            if formats[move.plugin] == nil { order.append(move.plugin) }
            formats[move.plugin, default: []].append(move.format)
        }
        return order.map { ($0, formats[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [Color.white, Color.plasma, Color.nebula]),
                        center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: 7))
                    .frame(width: 10, height: 10)
                    .shadow(color: Color.plasma, radius: 4)
                Text(group.vendor)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Text("\(group.items.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.nebula.opacity(0.45)))
            }
            ForEach(rows, id: \.name) { row in
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    ForEach(row.formats, id: \.self) { format in
                        Text(format)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.ion)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(Capsule().stroke(Color.ion.opacity(0.4), lineWidth: 1))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(Glass())
    }
}
