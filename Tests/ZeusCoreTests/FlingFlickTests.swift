import CoreGraphics
import Foundation
import Testing
@testable import ZeusCore

@Suite("Fling flick")
struct FlingFlickTests {
    /// Samples along a straight line at `speed` points per second, 10 ms apart, for `ms` milliseconds.
    private func line(dx: CGFloat, dy: CGFloat, speed: CGFloat, ms: Int = 120) -> [FlickSample] {
        let length = hypot(dx, dy)
        let ux = dx / length, uy = dy / length
        return stride(from: 0, through: ms, by: 10).map { t in
            let seconds = TimeInterval(t) / 1000
            return FlickSample(time: seconds, point: CGPoint(x: 100 + ux * speed * CGFloat(seconds), y: 100 + uy * speed * CGFloat(seconds)))
        }
    }

    /// REG-677: the thresholds are 1800, 1200 and 800 points per second, measured over the last 80 ms.
    @Test func theSensitivityThresholdsAreExact() {
        #expect(FlickSensitivity.low.threshold == 1800)
        #expect(FlickSensitivity.normal.threshold == 1200)
        #expect(FlickSensitivity.high.threshold == 800)
        #expect(FlingFlick.classify(samples: line(dx: -1, dy: 0, speed: 1100), sensitivity: .normal, peers: 2) == .drop)
        #expect(FlingFlick.classify(samples: line(dx: -1, dy: 0, speed: 1300), sensitivity: .normal, peers: 2) == .send(peerIndex: 0))
        #expect(FlingFlick.classify(samples: line(dx: -1, dy: 0, speed: 1300), sensitivity: .low, peers: 2) == .drop)
        #expect(FlingFlick.classify(samples: line(dx: -1, dy: 0, speed: 900), sensitivity: .high, peers: 2) == .send(peerIndex: 0))
        #expect(FlingFlick.classify(samples: line(dx: -1, dy: 0, speed: 700), sensitivity: .high, peers: 2) == .drop)
    }

    @Test func aSlowDropAndTooFewSamplesAreAPlainDrop() {
        #expect(FlingFlick.classify(samples: line(dx: -1, dy: 0, speed: 100), sensitivity: .normal, peers: 1) == .drop)
        #expect(FlingFlick.classify(samples: [], sensitivity: .normal, peers: 1) == .drop)
        #expect(FlingFlick.classify(samples: [FlickSample(time: 0, point: .zero)], sensitivity: .high, peers: 1) == .drop)
        // Two samples at the same instant carry no speed.
        #expect(FlingFlick.classify(samples: [FlickSample(time: 1, point: .zero), FlickSample(time: 1, point: CGPoint(x: 500, y: 0))], sensitivity: .high, peers: 1) == .drop)
    }

    @Test func onlyTheLastEightyMillisecondsCount() {
        // Fast for the first 100 ms, then nearly still: the end of the drag is what matters.
        var samples = line(dx: -1, dy: 0, speed: 3000, ms: 100)
        let last = samples.last!
        for k in 1...10 { samples.append(FlickSample(time: last.time + Double(k) * 0.01, point: CGPoint(x: last.point.x - CGFloat(k), y: last.point.y))) }
        #expect(FlingFlick.classify(samples: samples, sensitivity: .normal, peers: 2) == .drop)
    }

    @Test func oneFastDirectionPicksTheAvatarTheOtherPicksThePicker() {
        let fast: CGFloat = 2500
        // Screen space: y grows downward, so up is negative y.
        #expect(FlingFlick.classify(samples: line(dx: 0, dy: 1, speed: fast), sensitivity: .normal, peers: 1) == .send(peerIndex: 0))
        #expect(FlingFlick.classify(samples: line(dx: -1, dy: 0, speed: fast), sensitivity: .normal, peers: 3) == .send(peerIndex: 0))
        #expect(FlingFlick.classify(samples: line(dx: 1, dy: 0, speed: fast), sensitivity: .normal, peers: 3) == .send(peerIndex: 2))
        #expect(FlingFlick.classify(samples: line(dx: 0, dy: -1, speed: fast), sensitivity: .normal, peers: 2) == .picker)
        #expect(FlingFlick.classify(samples: line(dx: 0, dy: 1, speed: fast), sensitivity: .normal, peers: 2) == .drop)
        // With nobody to send to, a fast flick still offers the picker, which lists AirDrop.
        #expect(FlingFlick.classify(samples: line(dx: -1, dy: 0, speed: fast), sensitivity: .normal, peers: 0) == .picker)
    }
}
