import SwiftUI

/// Plugin Sorter → Settings… (⌘,): language and colour skin.
struct SettingsView: View {
    @AppStorage("language") private var language = Lang.system.rawValue
    @AppStorage(Skin.key) private var skin = Skin.violet.rawValue

    private var t: L10n { L10n(lang: Lang(rawValue: language) ?? .en) }

    var body: some View {
        ZStack {
            Chassis()
            VStack(spacing: 6) {
                section(t("settings.language")) {
                    HStack(spacing: 6) {
                        ForEach(Lang.allCases) { lang in
                            Choice(selected: language == lang.rawValue) { language = lang.rawValue } label: {
                                VStack(spacing: 3) {
                                    Text(lang.rawValue.uppercased()).caption(language == lang.rawValue ? .text : .label)
                                    Text(lang.nativeName)
                                        .font(.system(size: 11))
                                        .foregroundColor(language == lang.rawValue ? .text : .label)
                                }
                            }
                        }
                    }
                }
                section(t("settings.skin")) {
                    HStack(spacing: 6) {
                        ForEach(Skin.allCases) { option in
                            Choice(selected: skin == option.rawValue) { skin = option.rawValue } label: {
                                VStack(spacing: 6) {
                                    Swatch(skin: option)
                                    Text(t("skin.\(option.rawValue)"))
                                        .font(.system(size: 11))
                                        .foregroundColor(skin == option.rawValue ? .text : .label)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 30)
            .padding(.bottom, 8)
            .id(skin)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowStyler())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).caption()
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

/// A selectable tile: raised and outlined in the accent colour when chosen.
private struct Choice<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.raised : Color.inset))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(selected ? Color.accent : Color.edge, lineWidth: selected ? 1.5 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PointerButtonStyle())
    }
}

/// A skin preview: its accent arc over a tiny mirrored wave.
private struct Swatch: View {
    let skin: Skin

    var body: some View {
        ZStack {
            Circle().fill(Color.inset)
            Circle()
                .trim(from: 0, to: 0.75)
                .rotation(.degrees(135))
                .stroke(Color(hex: skin.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .shadow(color: Color(hex: skin.accent).opacity(0.6), radius: 3)
                .padding(3)
            VStack(spacing: 1) {
                Capsule().fill(Color(hex: skin.accentHot)).frame(width: 14, height: 3)
                Capsule().fill(Color(hex: skin.wave)).frame(width: 10, height: 3)
            }
        }
        .frame(width: 34, height: 34)
    }
}
