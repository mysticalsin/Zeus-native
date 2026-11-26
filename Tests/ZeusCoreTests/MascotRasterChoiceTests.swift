import Testing
@testable import ZeusCore

@Suite("Mascot raster choice")
struct MascotRasterChoiceTests {
    @Test func zeroAndANegativeScaleUseTheNotchDefault() {
        #expect(MascotRasterChoice.resolve(0) == 2)
        #expect(MascotRasterChoice.resolve(-1) == 2)
        #expect(MascotRasterChoice.notchDefault == 2)
    }

    @Test func aPositiveExportScaleIsKept() {
        #expect(MascotRasterChoice.resolve(1) == 1)
        #expect(MascotRasterChoice.resolve(3) == 3)
    }
}
