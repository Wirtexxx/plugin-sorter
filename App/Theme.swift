import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    static let chassis = Color(hex: 0x17171A)
    static let panel = Color(hex: 0x27272C)
    static let inset = Color(hex: 0x1E1E22)
    static let raised = Color(hex: 0x323238)
    static let edge = Color(hex: 0x3A3A41)
    static let label = Color(hex: 0x8C8C97)
    static let text = Color(hex: 0xDCDCE2)
    // Accent colours follow the skin chosen in Settings
    static var accent: Color { Color(hex: Skin.current.accent) }
    static var accentHot: Color { Color(hex: Skin.current.accentHot) }
    static var wave: Color { Color(hex: Skin.current.wave) }
    static let mint = Color(hex: 0x3EE28A)
    static let amber = Color(hex: 0xFFB547)
    static let danger = Color(hex: 0xFF5C6C)
}

/// Colour skins, like the ones many plugins offer. Stored under "skin" in UserDefaults.
enum Skin: String, CaseIterable, Identifiable {
    case violet, mint, amber, ice

    static let key = "skin"
    static var current: Skin { Skin(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .violet }

    var id: String { rawValue }

    var accent: UInt32 {
        switch self {
        case .violet: return 0xA76BFF
        case .mint:   return 0x35D8A6
        case .amber:  return 0xFF9F43
        case .ice:    return 0x5CB8FF
        }
    }

    var accentHot: UInt32 {
        switch self {
        case .violet: return 0xE073FF
        case .mint:   return 0x9BFFD9
        case .amber:  return 0xFFD166
        case .ice:    return 0xB4E6FF
        }
    }

    /// The lower, mirrored half of the waveform.
    var wave: UInt32 {
        switch self {
        case .violet: return 0x3D6BFF
        case .mint:   return 0x1F8FFF
        case .amber:  return 0xFF4F6D
        case .ice:    return 0x5468FF
        }
    }
}

extension Text {
    /// Small uppercase caption used for every label, plugin-UI style.
    func caption(_ color: Color = .label) -> some View {
        self.font(.system(size: 10, weight: .semibold))
            .kerning(1.4)
            .foregroundColor(color)
    }
}

// MARK: - Window

/// Behind-window blur that shows through the gaps between panels.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Makes the hosting window transparent, dark and draggable by its background.
struct WindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .darkAqua)
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

struct Chassis: View {
    var body: some View {
        ZStack {
            VisualEffect()
            Color.chassis.opacity(0.88)
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Building blocks

struct Panel: ViewModifier {
    var fill: Color = .panel
    var radius: CGFloat = 6

    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius).fill(fill))
    }
}

extension View {
    func panel(_ fill: Color = .panel, radius: CGFloat = 6) -> some View {
        modifier(Panel(fill: fill, radius: radius))
    }
}

struct StatusDot: View {
    var color: Color = .mint
    var on = true

    var body: some View {
        Circle()
            .fill(on ? color : Color.edge)
            .frame(width: 6, height: 6)
            .shadow(color: on ? color.opacity(0.8) : .clear, radius: 3)
    }
}

struct PluginButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        PluginButton(configuration: configuration, primary: primary)
    }

    private struct PluginButton: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            let lit = hovered && isEnabled
            return configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(primary ? .white : .text)
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(primary ? Color.accent : Color.raised)
                        .brightness(configuration.isPressed ? -0.08 : 0))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(primary ? Color.accentHot.opacity(lit ? 0.9 : 0.5) : lit ? Color.accent.opacity(0.7) : Color.edge,
                            lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.15), value: lit)
        }
    }
}

/// Toggle that looks like a plugin's module power button.
struct PowerToggle: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(isOn ? Color.accent : Color.inset)
                    Image(systemName: "power")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(isOn ? .white : .label)
                }
                .frame(width: 15, height: 15)
                Text(title).caption(isOn ? .text : .label)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.raised))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.edge, lineWidth: 1))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Read-only knob: an arc shows the share, the cap shows the number.
struct Knob: View {
    let value: Int
    let fraction: Double
    let label: String
    var size: CGFloat = 62

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                arc(to: 1).stroke(Color.inset, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                arc(to: max(0, min(1, fraction)))
                    .stroke(Color.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .shadow(color: Color.accent.opacity(0.5), radius: 3)
                    // Turn to the new value like a real knob instead of jumping
                    .animation(Motion.reduced ? nil : .easeOut(duration: 0.6), value: fraction)
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [Color(hex: 0x3B3B42), Color(hex: 0x24242A)]),
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                    .padding(9)
                    .shadow(color: Color.black.opacity(0.5), radius: 4, y: 2)
                Text("\(value)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.text)
            }
            .frame(width: size, height: size)
            Text(label).caption()
        }
    }

    /// 270° arc that opens at the bottom, like a real knob scale.
    private func arc(to fraction: Double) -> some Shape {
        Circle()
            .trim(from: 0, to: CGFloat(0.75 * fraction))
            .rotation(.degrees(135))
    }
}
