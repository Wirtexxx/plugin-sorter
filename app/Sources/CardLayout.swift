import CoreGraphics

/// How a screenshot goes into the picture area of an FL card, so every card in FL's plugin picker looks alike.
enum CardLayout: Equatable {
    /// Close enough to the area's shape: fills it, trimming a little from the edges.
    case fill
    /// Anything else sits whole in the middle, on the halftone background.
    case fit

    /// The area under the card's header, in points.
    static let pictureArea = CGSize(width: 104, height: 47)
    /// Width-to-height ratios that fill the area: Ozone 11 (2.04) does, Serum 2 (1.61) doesn't.
    static let fillRange: ClosedRange<CGFloat> = 1.8...2.7

    static func mode(for size: CGSize) -> CardLayout {
        guard size.width > 0, size.height > 0 else { return .fit }
        return fillRange.contains(size.width / size.height) ? .fill : .fit
    }
}
