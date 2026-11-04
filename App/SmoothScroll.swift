import SwiftUI
import AppKit

/// Put behind a ScrollView's content: makes a notched mouse wheel glide. A trackpad or Magic Mouse
/// already has the system's own inertia, so its events are left alone.
struct SmoothScroll: NSViewRepresentable {
    func makeNSView(context: Context) -> SmoothScrollView { SmoothScrollView() }
    func updateNSView(_ view: SmoothScrollView, context: Context) {}
}

final class SmoothScrollView: NSView {
    /// The list is moving under the pointer, so rows passing by shouldn't light up.
    private(set) static var isScrolling = false

    /// Points per wheel line. The system already speeds lines up when the wheel spins fast.
    private static let lineHeight: CGFloat = 14

    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var glide: ScrollGlide?
    private var lastFrame: CFTimeInterval = 0
    private var lastOrigin: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tearDown()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
        if let scroll = enclosingScrollView {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main) { _ in
                    Self.isScrolling = true
                },
                center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: scroll, queue: .main) { _ in
                    Self.isScrolling = false
                },
            ]
        }
    }

    deinit { tearDown() }

    private func tearDown() {
        stop()
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, let scroll = enclosingScrollView,
              scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)) else { return event }
        if event.hasPreciseScrollingDeltas {
            stop()
            return event
        }
        guard !Motion.reduced, event.scrollingDeltaY != 0 else { return event }
        wheel(lines: event.scrollingDeltaY)
        return nil
    }

    /// Positive lines scroll towards the top of the list, as `scrollingDeltaY` does.
    func wheel(lines: CGFloat) {
        guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
        let start = Double(scroll.contentView.bounds.origin.y)
        var current = glide ?? ScrollGlide(position: start)
        let towardsTop = document.isFlipped ? -lines : lines
        current.add(Double(towardsTop * Self.lineHeight), range: range(of: scroll))
        glide = current
        guard timer == nil else { return }
        lastFrame = CACurrentMediaTime()
        lastOrigin = scroll.contentView.bounds.origin.y
        Self.isScrolling = true
        let timer = Timer(timeInterval: 1.0 / frameRate, repeats: true) { [weak self] _ in self?.tick() }
        // .common: keep moving while a menu or other tracking loop is up
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The screen's own rate: faster would lay the list out for frames nobody sees.
    private var frameRate: Double {
        if #available(macOS 12.0, *), let rate = window?.screen?.maximumFramesPerSecond, rate > 0 { return Double(rate) }
        return 60
    }

    private func tick() {
        guard var current = glide, let scroll = enclosingScrollView else { return stop() }
        let clip = scroll.contentView
        // Something else moved the list, like the scroller being dragged: it wins
        guard abs(clip.bounds.origin.y - lastOrigin) < 1 else { return stop() }

        let now = CACurrentMediaTime()
        let moving = current.step(dt: now - lastFrame, range: range(of: scroll))
        lastFrame = now
        glide = current

        // Whole device pixels keep the text sharp on the way
        let scale = window?.backingScaleFactor ?? 2
        let origin = (CGFloat(current.position) * scale).rounded() / scale
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: origin))
        scroll.reflectScrolledClipView(clip)
        lastOrigin = origin
        if !moving { stop() }
    }

    private func range(of scroll: NSScrollView) -> ClosedRange<Double> {
        let height = scroll.documentView?.frame.height ?? 0
        return 0...max(0, Double(height - scroll.contentView.bounds.height))
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        glide = nil
        Self.isScrolling = false
    }
}
