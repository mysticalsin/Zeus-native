import Testing
@testable import ZeusCore

@Suite("Fling layout box")
struct FlingLayoutBoxTests {
    @Test func aFarFlickStopsAt240AndKeepsItsSlope() {
        let far = FlingLayoutBox.flyOff(width: 600, height: -80, reduceMotion: false)
        #expect(!far.fadeOnly)
        let length = (far.width * far.width + far.height * far.height).squareRoot()
        #expect(abs(length - 240) < 0.001)
        #expect(far.width > 0 && far.height < 0)
        #expect(abs(far.height / far.width - (-80.0 / 600.0)) < 0.001)

        let near = FlingLayoutBox.flyOff(width: 30, height: 40, reduceMotion: false)
        #expect(near == FlingFlyOffBox(width: 30, height: 40, fadeOnly: false))

        let still = FlingLayoutBox.flyOff(width: 0, height: 0, reduceMotion: false)
        #expect(still == FlingFlyOffBox(width: 0, height: 0, fadeOnly: false))

        let edge = FlingLayoutBox.flyOff(width: 240, height: 0, reduceMotion: false)
        #expect(edge == FlingFlyOffBox(width: 240, height: 0, fadeOnly: false))

        let reduced = FlingLayoutBox.flyOff(width: 600, height: -80, reduceMotion: true)
        #expect(reduced == FlingFlyOffBox(width: 0, height: 0, fadeOnly: true))
    }

    @Test func papersStepDownLeftAndAHugePaperStaysAtTheCorner() {
        let first = FlingLayoutBox.paperOrigin(index: 0, paperWidth: 180, paperHeight: 120, minX: 0, minY: 0, maxX: 1000, maxY: 700)
        let second = FlingLayoutBox.paperOrigin(index: 1, paperWidth: 180, paperHeight: 120, minX: 0, minY: 0, maxX: 1000, maxY: 700)
        #expect(first.x == 796 && first.y == 556)
        #expect(second.x == 768 && second.y == 528)
        for index in 0..<200 {
            let origin = FlingLayoutBox.paperOrigin(index: index, paperWidth: 180, paperHeight: 120, minX: 0, minY: 0, maxX: 1000, maxY: 700)
            #expect(origin.x >= 0 && origin.y >= 0)
            #expect(origin.x + 180 <= 1000 && origin.y + 120 <= 700)
        }
        let huge = FlingLayoutBox.paperOrigin(index: 3, paperWidth: 2000, paperHeight: 2000, minX: 0, minY: 0, maxX: 1000, maxY: 700)
        #expect(huge.x == 0 && huge.y == 0)
    }

    @Test func onePaperIsNotAStackAndTheFanStopsAtFive() {
        #expect(FlingLayoutBox.stackFan(count: 0).isEmpty)
        #expect(FlingLayoutBox.stackFan(count: 1).isEmpty)
        let three = FlingLayoutBox.stackFan(count: 3)
        #expect(three.count == 3)
        #expect(three[0].x == 0 && three[0].y == 0)
        #expect(three[1].x == 6 && three[1].y == -4)
        #expect(three[2].x == 12 && three[2].y == -8)
        #expect(FlingLayoutBox.stackFan(count: 40).count == 5)
        #expect(FlingLayoutBox.maxFlyOffDistance == 240)
    }
}
