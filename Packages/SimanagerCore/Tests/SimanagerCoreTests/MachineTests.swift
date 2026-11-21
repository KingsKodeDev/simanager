import Testing
import SimanagerCore

private let gb: UInt64 = 1_073_741_824

@Test func memorySplitsIntoSimulatorsEverythingElseAndFree() {
    let split = MemorySplit(total: 36 * gb, used: 31 * gb, simulators: 11 * gb)
    #expect(split.simulators == 11 * gb)
    #expect(split.other == 20 * gb)
    #expect(split.free == 5 * gb)
}

// The three figures are read a moment apart, so they can disagree; the parts must still add up to the total.
@Test func memorySplitNeverAddsUpToMoreThanTheMac() {
    let split = MemorySplit(total: 8 * gb, used: 9 * gb, simulators: 10 * gb)
    #expect(split.simulators == 8 * gb)
    #expect(split.other == 0)
    #expect(split.free == 0)
}

@Test func temperatureReadsInEitherUnit() {
    #expect(TemperatureUnit.celsius.text(71.4) == "71 °C")
    #expect(TemperatureUnit.fahrenheit.text(71.4) == "161 °F")
    #expect(TemperatureUnit.fahrenheit.text(0) == "32 °F")
}

@Test func fanPercentIsTheBusiestFanAgainstItsTopSpeed() {
    #expect(fanPercent([Fan(rpm: 1361, max: 5349), Fan(rpm: 2840, max: 5800)]) == 49)
    #expect(fanPercent([Fan(rpm: 6000, max: 5800)]) == 100)
}

@Test func fanPercentIsUnknownWithoutAFan() {
    #expect(fanPercent([]) == nil)
    #expect(fanPercent([Fan(rpm: 1200, max: 0)]) == nil)     // a fan that reports no top speed
}
