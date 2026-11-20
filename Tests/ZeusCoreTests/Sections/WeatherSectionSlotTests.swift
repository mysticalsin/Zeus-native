import Testing

@Suite struct WeatherSectionSlotTests {
    @Test func weatherSlotStartsEmpty() {
        let slot = WeatherSectionSlot.slot
        #expect(slot.id == "glass.weather")
        #expect(slot.title == "Weather")
        #expect(slot.filled == false)
        #expect(slot.keys.isEmpty)
    }
}
