import Foundation

/// How a wheel-scrolled list moves: quickly towards where the wheel points, slowing down on arrival.
/// Further notches push the target along, so the motion never restarts.
struct ScrollGlide {
    /// How fast the gap closes, per second. Higher is snappier.
    private static let rate = 12.0
    /// Under half a device pixel on Retina, so the last small step can't be seen.
    private static let arrival = 0.25

    private(set) var position: Double
    private(set) var target: Double

    init(position: Double) {
        self.position = position
        target = position
    }

    mutating func add(_ delta: Double, range: ClosedRange<Double>) {
        // Turning the wheel back answers at once instead of first using up the old target
        let reversing = (target - position) * delta < 0
        let base = reversing ? position : target
        target = min(max(base + delta, range.lowerBound), range.upperBound)
    }

    /// Moves one frame on; false once it has arrived. Takes the range anew as the list can change size.
    mutating func step(dt: Double, range: ClosedRange<Double>) -> Bool {
        target = min(max(target, range.lowerBound), range.upperBound)
        let gap = target - position
        guard abs(gap) > Self.arrival else {
            position = target
            return false
        }
        position += gap * (1 - exp(-dt * Self.rate))
        return true
    }
}
