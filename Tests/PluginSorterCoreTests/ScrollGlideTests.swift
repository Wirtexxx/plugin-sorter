import Testing
@testable import PluginSorterCore

@Suite("Wheel scroll glide")
struct ScrollGlideTests {
    private let range: ClosedRange<Double> = 0...1000

    @Test func slowsDownAndArrivesExactly() {
        var glide = ScrollGlide(position: 100)
        glide.add(200, range: range)
        var last = 100.0, lastStep = Double.infinity, frames = 0
        var moving = true
        while moving && frames < 300 {
            moving = glide.step(dt: 1.0 / 60, range: range)
            let moved = glide.position - last
            #expect(moved >= 0)
            #expect(moved <= lastStep || moved <= 0.25)
            last = glide.position
            lastStep = moved
            frames += 1
        }
        #expect(glide.position == 300)
        #expect(frames > 5 && frames < 60)
    }

    @Test func notchesAddUp() {
        var glide = ScrollGlide(position: 0)
        glide.add(100, range: range)
        _ = glide.step(dt: 1.0 / 60, range: range)
        glide.add(100, range: range)
        #expect(glide.target == 200)
    }

    @Test func reversingStartsFromWhereItIs() {
        var glide = ScrollGlide(position: 500)
        glide.add(300, range: range)
        _ = glide.step(dt: 0.05, range: range)
        let position = glide.position
        glide.add(-100, range: range)
        #expect(glide.target == position - 100)
    }

    @Test func staysInsideTheList() {
        var glide = ScrollGlide(position: 950)
        glide.add(500, range: range)
        #expect(glide.target == 1000)
        glide.add(-5000, range: range)
        #expect(glide.target == 0)
    }

    @Test func aListThatShrankPullsItBack() {
        var glide = ScrollGlide(position: 900)
        glide.add(50, range: range)
        while glide.step(dt: 1.0 / 60, range: 0...400) {}
        #expect(glide.position == 400)
    }

    @Test func sameSpeedAtAnyFrameRate() {
        func after(_ fps: Double) -> Double {
            var glide = ScrollGlide(position: 0)
            glide.add(1000, range: range)
            for _ in 0..<Int(fps / 10) { _ = glide.step(dt: 1 / fps, range: range) }
            return glide.position
        }
        #expect(abs(after(60) - after(120)) < 0.5)
    }
}
