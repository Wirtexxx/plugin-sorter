import SwiftUI
import AppKit

/// "48,2 MB": file sizes the way Finder shows them.
func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// Honour System Settings → Accessibility → Display → Reduce motion.
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// An LED that pulses while something is being worked on.
struct PulseDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.accent)
            .frame(width: 7, height: 7)
            .opacity(on ? 1 : 0.25)
            .shadow(color: Color.accent.opacity(on ? 0.9 : 0), radius: 4)
            .onAppear {
                guard !Motion.reduced else { on = true; return }
                withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
