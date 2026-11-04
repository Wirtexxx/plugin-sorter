import Foundation

/// Keeps scans from piling up behind a long job on a serial queue: one waiting is enough, since it will
/// see everything the others would. A scan already running doesn't count, it may have read too early.
final class ScanGate {
    private let lock = NSLock()
    private var waiting = false

    /// True when the caller should queue a scan.
    func request() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !waiting else { return false }
        waiting = true
        return true
    }

    /// Called first thing by the queued scan.
    func started() {
        lock.lock()
        waiting = false
        lock.unlock()
    }
}

/// Runs the last of a burst of calls, once things are quiet. Main thread only.
final class Debouncer {
    private let delay: TimeInterval
    private var pending: DispatchWorkItem?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func schedule(_ work: @escaping () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem(block: work)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
