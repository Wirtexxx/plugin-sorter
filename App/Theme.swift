import SwiftUI
import AppKit

extension Color {
    static let space = Color(red: 0.03, green: 0.02, blue: 0.06)
    static let deepSpace = Color(red: 0.08, green: 0.03, blue: 0.15)
    static let nebula = Color(red: 0.48, green: 0.20, blue: 0.97)
    static let plasma = Color(red: 0.80, green: 0.30, blue: 1.00)
    static let ion = Color(red: 0.45, green: 0.78, blue: 1.00)
}

// MARK: - Window

/// Behind-window blur, the base of the translucent look.
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

// MARK: - Cosmic background

struct Orb: View {
    let color: Color
    let size: CGFloat
    var glow: Double = 0.35

    var body: some View {
        ZStack {
            // Halo as a gradient instead of .blur: cheaper and renders offscreen too
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [color.opacity(glow), color.opacity(glow * 0.35), color.opacity(0)]),
                    center: .center,
                    startRadius: size * 0.35,
                    endRadius: size * 0.95))
                .frame(width: size * 1.9, height: size * 1.9)
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.9), color, color.opacity(0.4), Color.space]),
                    center: UnitPoint(x: 0.32, y: 0.28),
                    startRadius: 0,
                    endRadius: size * 0.78))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(color.opacity(0.45), lineWidth: 1))
        }
        .allowsHitTesting(false)
    }
}

struct Starfield: View {
    var count = 80

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<count, id: \.self) { i in
                let x = Self.noise(i, 12.9898) * geo.size.width
                let y = Self.noise(i, 78.233) * geo.size.height
                let s = 0.6 + Self.noise(i, 39.346) * 1.8
                Circle()
                    .fill(Color.white)
                    .frame(width: s, height: s)
                    .opacity(0.15 + Self.noise(i, 93.989) * 0.6)
                    .position(x: x, y: y)
            }
        }
        .allowsHitTesting(false)
    }

    /// Deterministic pseudo-random value in 0..<1 so stars don't jump between renders.
    private static func noise(_ i: Int, _ seed: Double) -> CGFloat {
        let v = sin(Double(i + 1) * seed) * 43758.5453
        return CGFloat(v - v.rounded(.down))
    }
}

struct CosmicBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            VisualEffect()
            LinearGradient(
                gradient: Gradient(colors: [Color.space.opacity(0.80), Color.deepSpace.opacity(0.70)]),
                startPoint: .top, endPoint: .bottom)
            Starfield()
            Orb(color: .nebula, size: 340, glow: 0.4)
                .opacity(0.55)
                .offset(x: drift ? -250 : -290, y: drift ? -190 : -160)
            Orb(color: .plasma, size: 220)
                .opacity(0.45)
                .offset(x: drift ? 300 : 270, y: drift ? 230 : 260)
            Orb(color: .ion, size: 90, glow: 0.5)
                .opacity(0.5)
                .offset(x: drift ? 230 : 250, y: drift ? -230 : -210)
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

// MARK: - Controls

struct Glass: ViewModifier {
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(Color.white.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: radius).stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.white.opacity(0.20), Color.nebula.opacity(0.25)]),
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1))
    }
}

struct GlowButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        GlowButton(configuration: configuration, primary: primary)
    }

    private struct GlowButton: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        if primary {
                            Capsule().fill(LinearGradient(
                                gradient: Gradient(colors: [Color.nebula, Color.plasma]),
                                startPoint: .leading, endPoint: .trailing))
                        } else {
                            Capsule().fill(Color.white.opacity(0.07))
                        }
                    })
                .overlay(Capsule().stroke(Color.white.opacity(primary ? 0.30 : 0.15), lineWidth: 1))
                .shadow(color: primary && isEnabled ? Color.plasma.opacity(0.6) : .clear, radius: 12)
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
        }
    }
}

struct Chip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(isOn ? Color.plasma : Color.white.opacity(0.2))
                    .frame(width: 7, height: 7)
                    .shadow(color: isOn ? Color.plasma : .clear, radius: 4)
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kerning(1.2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(isOn ? .white : Color.white.opacity(0.5))
            .background(Capsule().fill(isOn ? Color.nebula.opacity(0.30) : Color.white.opacity(0.04)))
            .overlay(Capsule().stroke(isOn ? Color.plasma.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct Meter: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .foregroundColor(.white)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.5)
                .foregroundColor(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(Glass())
    }
}
