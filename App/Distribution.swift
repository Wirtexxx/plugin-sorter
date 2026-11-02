import SwiftUI

/// Mirrored waveform display: one hump per developer, height = number of plugins to move.
struct Distribution: View {
    let groups: [VendorGroup]
    var barWidth: CGFloat = 5

    /// The wave breathes and a playhead sweeps across it, like a plugin's live display.
    @State private var breathe = false
    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            let perGroup = groups.isEmpty ? 0 : max(3, Int(geo.size.width / barWidth) / groups.count)
            let levels = Self.levels(groups, perGroup: perGroup, idle: Int(geo.size.width / barWidth))
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    VStack(spacing: 0) {
                        WaveBars(levels: levels, mirrored: false)
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.accentHot, Color.accent.opacity(0.55)]),
                                                 startPoint: .top, endPoint: .bottom))
                            .scaleEffect(x: 1, y: breathe ? 1 : 0.86, anchor: .bottom)
                        Rectangle().fill(Color.text.opacity(0.12)).frame(height: 1)
                        WaveBars(levels: levels.map { $0 * 0.8 }, mirrored: true)
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.wave, Color.wave.opacity(0.15)]),
                                                 startPoint: .top, endPoint: .bottom))
                            .scaleEffect(x: 1, y: breathe ? 1 : 0.86, anchor: .top)
                    }
                    if !groups.isEmpty && !Motion.reduced {
                        Rectangle()
                            .fill(LinearGradient(gradient: Gradient(colors: [Color.accentHot.opacity(0), Color.accentHot,
                                                                             Color.accentHot.opacity(0)]),
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 1.5)
                            .shadow(color: Color.accentHot.opacity(0.9), radius: 4)
                            .offset(x: sweep ? geo.size.width : 0)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(groups) { group in
                        Text(group.vendor.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(1)
                            .foregroundColor(.label)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 18)
            }
        }
        .onAppear {
            guard !Motion.reduced else { breathe = true; return }
            withAnimation(Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(Animation.linear(duration: 6).repeatForever(autoreverses: false)) { sweep = true }
        }
    }

    static func levels(_ groups: [VendorGroup], perGroup: Int, idle: Int) -> [CGFloat] {
        guard let maxCount = groups.map({ $0.items.count }).max(), perGroup > 0 else {
            return Array(repeating: 0.02, count: max(idle, 1))
        }
        var out: [CGFloat] = []
        for (g, group) in groups.enumerated() {
            let base = CGFloat(group.items.count) / CGFloat(maxCount)
            for j in 0..<perGroup {
                let t = CGFloat(j) / CGFloat(max(perGroup - 1, 1))
                let envelope = sin(t * .pi)
                let jitter = 0.6 + 0.4 * noise(g * 131 + j)
                out.append(max(0.03, base * (0.15 + 0.85 * envelope) * jitter))
            }
        }
        return out
    }

    /// Deterministic pseudo-random value in 0..<1 so the wave doesn't flicker between renders.
    private static func noise(_ i: Int) -> CGFloat {
        let v = sin(Double(i + 1) * 12.9898) * 43758.5453
        return CGFloat(v - v.rounded(.down))
    }
}

struct WaveBars: Shape {
    let levels: [CGFloat]
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !levels.isEmpty else { return path }
        let step = rect.width / CGFloat(levels.count)
        for (i, level) in levels.enumerated() {
            let h = max(1, level * rect.height)
            let y = mirrored ? rect.minY : rect.maxY - h
            path.addRect(CGRect(x: rect.minX + CGFloat(i) * step + step * 0.15, y: y, width: step * 0.7, height: h))
        }
        return path
    }
}
