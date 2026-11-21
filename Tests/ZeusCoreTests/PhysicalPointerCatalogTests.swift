import Foundation
import Testing
@testable import ZeusCore

@Suite struct PhysicalPointerCatalogTests {
    /// S04-04. Settings stores the string `true`/`false` at `opt.present.physicalPointer`.
    /// The drive gate used to read a Bool at `present.physicalPointer`, so the catalog value never counted.
    @Test func catalogStringWinsOverTheLegacyBool() {
        #expect(PhysicalPointerSettings.catalogKey == "opt.present.physicalPointer")
        #expect(PhysicalPointerSettings.enabled(boolValue: true, catalogText: "false") == false)
        #expect(PhysicalPointerSettings.enabled(boolValue: false, catalogText: "true"))
        #expect(PhysicalPointerSettings.enabled(boolValue: nil, catalogText: nil) == false)
        #expect(PhysicalPointerSettings.enabled(boolValue: true, catalogText: nil))
        #expect(PhysicalPointerSettings.enabled(boolValue: nil, catalogText: " true ") )
    }
}
