import Foundation
import Testing
@testable import PluginSorterCore

/// A script that waits until told to go on, so a test can start something while it runs.
private final class HeldScript {
    private let lock = NSLock()
    private var gates: [DispatchSemaphore] = []
    private(set) var calls: [[String]] = []
    let answers: ([String]) -> Shell.Result

    init(answers: @escaping ([String]) -> Shell.Result = { _ in Shell.Result(status: 0, output: "Would move: 0\n", error: "") }) {
        self.answers = answers
    }

    func run(_ args: [String], _ admin: Bool, _ env: [String: String]) -> Shell.Result {
        let gate = DispatchSemaphore(value: 0)
        lock.lock()
        calls.append(args)
        gates.append(gate)
        lock.unlock()
        gate.wait()
        return answers(args)
    }

    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls.count }

    func release(_ index: Int) {
        lock.lock()
        let gate = gates[index]
        lock.unlock()
        gate.signal()
    }
}

/// Lets the main queue run until `condition` holds.
@MainActor private func wait(until condition: @escaping () -> Bool) async {
    for _ in 0..<500 where !condition() { try? await Task.sleep(nanoseconds: 2_000_000) }
}

@Suite("Runs of the script don't step on each other")
@MainActor struct SorterRunTests {
    @Test func aPreviewDoesNotStartWhilePluginsAreMoving() async {
        let script = HeldScript()
        let sorter = Sorter(runner: script.run)
        sorter.apply()
        await wait { script.callCount == 1 }
        sorter.preview()
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(script.callCount == 1)
        #expect(sorter.running)
        script.release(0)
        await wait { !sorter.running }
    }

    @Test func aSecondApplyIsRefused() async {
        let script = HeldScript()
        let sorter = Sorter(runner: script.run)
        sorter.apply()
        await wait { script.callCount == 1 }
        sorter.apply()
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(script.callCount == 1)
        script.release(0)
        await wait { !sorter.running }
    }

    @Test func aPreviewFinishingEarlyLeavesTheMoveRunning() async {
        let script = HeldScript()
        let sorter = Sorter(runner: script.run)
        sorter.preview()
        await wait { script.callCount == 1 }
        sorter.apply()
        await wait { script.callCount == 2 }
        script.release(0)
        try? await Task.sleep(nanoseconds: 30_000_000)
        #expect(sorter.running)
        script.release(1)
        await wait { !sorter.running }
    }

    @Test func anOlderPreviewCannotOverwriteANewerOne() async {
        var answer = 0
        let lock = NSLock()
        let script = HeldScript { _ in
            lock.lock(); defer { lock.unlock() }
            answer += 1
            return Shell.Result(status: 0, output: answer == 1 ? "== VST3\n  New.vst3 -> Vendor/\nWould move: 1\n"
                                                               : "== VST3\n  Old.vst3 -> Vendor/\nWould move: 1\n", error: "")
        }
        let sorter = Sorter(runner: script.run)
        sorter.preview()
        await wait { script.callCount == 1 }
        sorter.preview()
        await wait { script.callCount == 2 }
        script.release(1)   // the newer one finishes first
        await wait { !sorter.moves.isEmpty }
        script.release(0)
        await wait { !sorter.running }
        #expect(sorter.moves.map(\.plugin) == ["New"])
    }
}

@Suite("Scans wait in line once")
struct ScanGateTests {
    @Test func onlyOneScanWaits() {
        let gate = ScanGate()
        #expect(gate.request())
        #expect(!gate.request())
        #expect(!gate.request())
    }

    @Test func aScanRunningDoesNotCoverWhatChangesAfterItStarted() {
        let gate = ScanGate()
        #expect(gate.request())
        gate.started()
        #expect(gate.request())
    }
}

@Suite("Refreshes come together")
struct DebouncerTests {
    @Test func burstsBecomeOneCall() async {
        let debouncer = Debouncer(delay: 0.02)
        let calls = Counter()
        await MainActor.run {
            for _ in 0..<5 { debouncer.schedule { calls.add() } }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(calls.value == 1)
    }

    private final class Counter {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func add() { lock.lock(); count += 1; lock.unlock() }
    }
}
