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

// MARK: - One-screen components

/// The accent gradient, from the skin's colour to its bright partner.
var accentGradient: LinearGradient {
    LinearGradient(gradient: Gradient(colors: [Color.accent, Color.accentHot]), startPoint: .leading, endPoint: .trailing)
}

extension View {
    /// A large rounded panel, the main building block of the window.
    func card() -> some View { panel(.panel, radius: 16) }
}

/// Capsule button. The primary one carries the accent gradient and glows; destructive text is red.
struct PillButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false
    /// Smaller, for tight spots like the task cards.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, primary: primary, destructive: destructive, compact: compact)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let destructive: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            let lit = hovered && isEnabled
            let text: Color = primary ? .white : destructive ? .danger : .text
            return configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundColor(text)
                .padding(.horizontal, compact ? 13 : 16)
                .frame(height: compact ? 26 : 32)
                .background(background.brightness(configuration.isPressed ? -0.08 : lit ? 0.05 : 0))
                .clipShape(Capsule())
                .shadow(color: primary && isEnabled ? Color.accent.opacity(lit ? 0.55 : 0.35) : .clear, radius: 10)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.15), value: lit)
        }

        @ViewBuilder private var background: some View {
            if primary { accentGradient } else { Color.raised }
        }
    }
}

/// A filter in the header: title, count, gradient when selected.
struct FilterPill: View {
    let title: String
    let count: Int?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isOn ? Color.white.opacity(0.8) : .label)
                }
            }
            .foregroundColor(isOn ? .white : .text)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Group { if isOn { accentGradient } else { Color.raised } })
            .clipShape(Capsule())
            .shadow(color: isOn ? Color.accent.opacity(0.35) : .clear, radius: 10)
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// How much of a task is done: the ring fills as the remaining number drops, or shows progress while working.
struct TaskRing: View {
    let remaining: Int
    let total: Int
    var progress: Double?

    var body: some View {
        let done = total > 0 ? Double(total - remaining) / Double(total) : 1
        let fraction = max(0, min(1, progress ?? done))
        return ZStack {
            Circle().stroke(Color.raised, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(accentGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.accent.opacity(0.45), radius: 4)
                .animation(Motion.reduced ? nil : .easeOut(duration: 0.6), value: fraction)
            if remaining == 0 && progress == nil {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.mint)
            } else {
                Text("\(remaining)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.text)
            }
        }
        .frame(width: 44, height: 44)
    }
}

/// A plugin's state: green works, amber warning, red problem, grey not checked yet.
struct LED: View {
    let level: CheckState.Level?
    var running = false

    var body: some View {
        let color: Color = {
            switch level {
            case .ok?:      return .mint
            case .warning?: return .amber
            case .failed?:  return .danger
            case nil:       return .edge
            }
        }()
        return Group {
            if running {
                PulseDot()
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: level == nil ? .clear : color.opacity(0.8), radius: 4)
            }
        }
        .frame(width: 10, height: 10)
    }
}

/// The app's mark and name, top left in the header. The mark takes its colours from the skin.
struct AppLogo: View {
    /// Three bars in rising order: mixer levels, sorted.
    private let bars: [CGFloat] = [13, 20, 28]

    var body: some View {
        HStack(spacing: 9) {
            accentGradient
                .mask(HStack(alignment: .bottom, spacing: 4) {
                    ForEach(bars, id: \.self) { Capsule().frame(width: 7, height: $0) }
                })
                .frame(width: 29, height: 28)
                .shadow(color: Color.accent.opacity(0.35), radius: 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("PLUGIN").font(.system(size: 12, weight: .heavy)).kerning(1.6).foregroundColor(.text)
                Text("SORTER").font(.system(size: 12, weight: .regular)).kerning(1.6).foregroundColor(.label)
            }
            .fixedSize()
        }
    }
}
