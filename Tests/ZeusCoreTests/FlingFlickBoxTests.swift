import Testing
@testable import ZeusCore

@Suite("Fling flick box")
struct FlingFlickBoxTests {
    /// Samples along a straight line at `speed` points per second, 10 ms apart, for `ms` milliseconds.
    private func line(dx: Double, dy: Double, speed: Double, ms: Int = 120) -> [FlickPointBox] {
        let length = (dx * dx + dy * dy).squareRoot()
        let ux = dx / length
        let uy = dy / length
        return stride(from: 0, through: ms, by: 10).map { t in
            let seconds = Double(t) / 1000
            return FlickPointBox(time: seconds, x: 100 + ux * speed * seconds, y: 100 + uy * speed * seconds)
        }
    }

    @Test func theSensitivityThresholdsAreExact() {
        #expect(FlingFlickBox.lowThreshold == 1800)
        #expect(FlingFlickBox.normalThreshold == 1200)
        #expect(FlingFlickBox.highThreshold == 800)
        #expect(FlingFlickBox.window == 0.08)
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: 0, speed: 1100), threshold: FlingFlickBox.normalThreshold, peers: 2) == .drop)
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: 0, speed: 1300), threshold: FlingFlickBox.normalThreshold, peers: 2) == .send(peerIndex: 0))
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: 0, speed: 1300), threshold: FlingFlickBox.lowThreshold, peers: 2) == .drop)
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: 0, speed: 900), threshold: FlingFlickBox.highThreshold, peers: 2) == .send(peerIndex: 0))
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: 0, speed: 700), threshold: FlingFlickBox.highThreshold, peers: 2) == .drop)
        let exact = [
            FlickPointBox(time: 0, x: 0, y: 0),
            FlickPointBox(time: 0.08, x: -96, y: 0),
        ]
        #expect(FlingFlickBox.classify(samples: exact, threshold: 1200, peers: 2) == .send(peerIndex: 0))
    }

    @Test func aSlowDropAndTooFewSamplesAreAPlainDrop() {
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: 0, speed: 100), threshold: FlingFlickBox.normalThreshold, peers: 1) == .drop)
        #expect(FlingFlickBox.classify(samples: [], threshold: FlingFlickBox.normalThreshold, peers: 1) == .drop)
        #expect(FlingFlickBox.classify(samples: [FlickPointBox(time: 0, x: 0, y: 0)], threshold: FlingFlickBox.highThreshold, peers: 1) == .drop)
        let sameInstant = [
            FlickPointBox(time: 1, x: 0, y: 0),
            FlickPointBox(time: 1, x: 500, y: 0),
        ]
        #expect(FlingFlickBox.classify(samples: sameInstant, threshold: FlingFlickBox.highThreshold, peers: 1) == .drop)
    }

    @Test func onlyTheLastEightyMillisecondsCount() {
        var samples = line(dx: -1, dy: 0, speed: 3000, ms: 100)
        let last = samples.last!
        for k in 1...10 {
            samples.append(FlickPointBox(time: last.time + Double(k) * 0.01, x: last.x - Double(k), y: last.y))
        }
        #expect(FlingFlickBox.classify(samples: samples, threshold: FlingFlickBox.normalThreshold, peers: 2) == .drop)
    }

    @Test func oneFastDirectionPicksThePeerTheOtherPicksThePicker() {
        let fast = 2500.0
        #expect(FlingFlickBox.classify(samples: line(dx: 0, dy: 1, speed: fast), threshold: FlingFlickBox.normalThreshold, peers: 1) == .send(peerIndex: 0))
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: 0, speed: fast), threshold: FlingFlickBox.normalThreshold, peers: 3) == .send(peerIndex: 0))
        #expect(FlingFlickBox.classify(samples: line(dx: 1, dy: 0, speed: fast), threshold: FlingFlickBox.normalThreshold, peers: 3) == .send(peerIndex: 2))
        #expect(FlingFlickBox.classify(samples: line(dx: 0, dy: -1, speed: fast), threshold: FlingFlickBox.normalThreshold, peers: 2) == .picker)
        #expect(FlingFlickBox.classify(samples: line(dx: 0, dy: 1, speed: fast), threshold: FlingFlickBox.normalThreshold, peers: 2) == .drop)
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: 0, speed: fast), threshold: FlingFlickBox.normalThreshold, peers: 0) == .picker)
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: 0, speed: fast), threshold: FlingFlickBox.normalThreshold, peers: -1) == .picker)
        #expect(FlingFlickBox.classify(samples: line(dx: 1, dy: 1, speed: fast), threshold: FlingFlickBox.normalThreshold, peers: 3) == .send(peerIndex: 2))
        #expect(FlingFlickBox.classify(samples: line(dx: -1, dy: -1, speed: fast), threshold: FlingFlickBox.normalThreshold, peers: 4) == .send(peerIndex: 0))
    }
}
