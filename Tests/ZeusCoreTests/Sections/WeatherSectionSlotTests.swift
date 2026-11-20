import Testing
import ZeusCore

@Suite struct WeatherSectionSlotTests {
    @Test func weatherSlotStartsEmpty() {
        let slot = WeatherSectionSlot.descriptor
        #expect(slot.id == "glass.weather")
        #expect(slot.title == "Weather")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
