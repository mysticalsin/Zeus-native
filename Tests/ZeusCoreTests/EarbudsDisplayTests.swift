import Testing
@testable import ZeusCore

@Suite("Earbuds display")
struct EarbudsDisplayTests {
    @Test func plainNameStays() {
        #expect(EarbudsName.display("Pro Max Buds", hideDetails: false) == "Pro Max Buds")
        #expect(EarbudsName.display("  Pro Max Buds  ", hideDetails: false) == "Pro Max Buds")
        #expect(EarbudsName.display("Pro   Max", hideDetails: false) == "Pro Max")
    }

    @Test func noBreakSpaceFoldsToOneSpace() {
        #expect(EarbudsName.display("Pro\u{00A0}Max\u{00A0}Buds", hideDetails: false) == "Pro Max Buds")
    }

    @Test func newlineAndLineSeparatorFoldToOneSpace() {
        #expect(EarbudsName.display("Pro\nMax", hideDetails: false) == "Pro Max")
        #expect(EarbudsName.display("Pro\n\nMax", hideDetails: false) == "Pro Max")
        #expect(EarbudsName.display("Pro\u{2028}Max", hideDetails: false) == "Pro Max")
        #expect(EarbudsName.display("Pro\u{2029}Max", hideDetails: false) == "Pro Max")
    }

    @Test func directionOverridePrivateUseAndUnassignedDrop() {
        #expect(EarbudsName.display("Pro\u{202E}Max", hideDetails: false) == "ProMax")
        #expect(EarbudsName.display("Pro\u{200B}Max", hideDetails: false) == "ProMax")
        #expect(EarbudsName.display("Pro\u{E000}Max", hideDetails: false) == "ProMax")
        #expect(EarbudsName.display("Pro\u{0378}Max", hideDetails: false) == "ProMax")
    }

    @Test func zeroWidthJoinerRunDrops() {
        #expect(EarbudsName.display("Pro\u{200D}\u{200D}\u{200D}Max", hideDetails: false) == "ProMax")
        #expect(EarbudsName.display("\u{200D}\u{200D}\u{200D}", hideDetails: false) == "Earbuds")
        #expect(EarbudsName.display("A\u{200D}B", hideDetails: false) == "A\u{200D}B")
        #expect(EarbudsName.display("A\u{FE0F}B", hideDetails: false) == "A\u{FE0F}B")
        #expect(EarbudsName.display("A \u{200D}\u{200D} B", hideDetails: false) == "A B")
    }

    @Test func longNameEndsWithAnEllipsis() {
        let twoHundred = String(repeating: "B", count: 200)
        let cut = EarbudsName.display(twoHundred, hideDetails: false)
        #expect(cut.count == 32)
        #expect(cut.last == "\u{2026}")
        #expect(cut == String(repeating: "B", count: 31) + "\u{2026}")
        let exact = String(repeating: "C", count: 32)
        #expect(EarbudsName.display(exact, hideDetails: false) == exact)
        let over = String(repeating: "C", count: 33)
        #expect(EarbudsName.display(over, hideDetails: false) == String(repeating: "C", count: 31) + "\u{2026}")
    }

    @Test func onlyWhitespaceBecomesEarbuds() {
        #expect(EarbudsName.display("   ", hideDetails: false) == "Earbuds")
        #expect(EarbudsName.display(" \n\t\u{00A0} ", hideDetails: false) == "Earbuds")
        #expect(EarbudsName.display("", hideDetails: false) == "Earbuds")
    }

    @Test func hiddenDetailsSayEarbuds() {
        #expect(EarbudsName.display("Secret Buds", hideDetails: true) == "Earbuds")
        let cue = EarbudsCueFacts(name: "Secret Buds", connected: true, parts: [
            EarbudsPartReading(part: .left, level: .fresh(80)),
        ])
        let spoken = EarbudsWords.spoken(cue, hideDetails: true)
        #expect(spoken == "Earbuds connected. Left 80 percent.")
        #expect(!spoken.contains("Secret"))
        let panel = EarbudsPanelModel.make(presence: shown(), mode: nil, hideDetails: true)
        #expect(panel?.name == "Earbuds")
        #expect(panel?.name.contains("Pro") == false)
    }

    @Test func cueStatusMixesKnownLevelsAndNeverDrawsZero() {
        #expect(EarbudsWords.cueStatus(EarbudsCueFacts(name: "Pro Max Buds", connected: false)) == [
            EarbudsCueLine(text: "Disconnected"),
        ])
        #expect(EarbudsWords.cueStatus(EarbudsCueFacts(name: "Pro Max Buds", connected: true)) == [
            EarbudsCueLine(text: "Connected"),
        ])
        let mixed = EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: [
            EarbudsPartReading(part: .case, level: .lastKnown(60)),
            EarbudsPartReading(part: .right, level: .unknown),
            EarbudsPartReading(part: .left, level: .fresh(80)),
        ])
        #expect(EarbudsWords.cueStatus(mixed) == [
            EarbudsCueLine(text: "L 80%"),
            EarbudsCueLine(text: "Case 60%", symbol: "clock"),
        ])
        let single = EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: [
            EarbudsPartReading(part: .single, level: .fresh(80)),
        ])
        #expect(EarbudsWords.cueStatus(single) == [EarbudsCueLine(text: "80%")])
        let lastSingle = EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: [
            EarbudsPartReading(part: .single, level: .lastKnown(80)),
        ])
        #expect(EarbudsWords.cueStatus(lastSingle) == [EarbudsCueLine(text: "80%", symbol: "clock")])
        let zeros = EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: [
            EarbudsPartReading(part: .left, level: .fresh(0)),
            EarbudsPartReading(part: .right, level: .lastKnown(0)),
            EarbudsPartReading(part: .case, level: .fresh(101)),
            EarbudsPartReading(part: .single, level: .fresh(-1)),
        ])
        #expect(EarbudsWords.cueStatus(zeros) == [EarbudsCueLine(text: "Connected")])
        let full = EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: [
            EarbudsPartReading(part: .left, level: .fresh(100)),
        ])
        #expect(EarbudsWords.cueStatus(full) == [EarbudsCueLine(text: "L 100%")])
        for line in EarbudsWords.cueStatus(zeros) + EarbudsWords.cueStatus(mixed) {
            #expect(!drawsZeroPercent(line.text))
        }
    }

    @Test func panelPartsListEveryPart() {
        let parts = EarbudsWords.panelParts([
            EarbudsPartReading(part: .case, level: .lastKnown(60)),
            EarbudsPartReading(part: .right, level: .fresh(75)),
            EarbudsPartReading(part: .left, level: .fresh(80)),
        ])
        #expect(parts == [
            EarbudsPanelPart(text: "Left 80%"),
            EarbudsPanelPart(text: "Right 75%"),
            EarbudsPanelPart(text: "Case 60%", symbol: "clock"),
        ])
        let unknown = EarbudsWords.panelParts([
            EarbudsPartReading(part: .left, level: .unknown),
            EarbudsPartReading(part: .right, level: .fresh(0)),
            EarbudsPartReading(part: .case, level: .lastKnown(101)),
        ])
        #expect(unknown == [
            EarbudsPanelPart(text: "Left unknown", symbol: "questionmark.circle"),
            EarbudsPanelPart(text: "Right unknown", symbol: "questionmark.circle"),
            EarbudsPanelPart(text: "Case unknown", symbol: "questionmark.circle"),
        ])
        #expect(EarbudsWords.panelParts([
            EarbudsPartReading(part: .single, level: .fresh(80)),
        ]) == [EarbudsPanelPart(text: "80%")])
        for part in parts + unknown {
            #expect(!drawsZeroPercent(part.text))
        }
    }

    @Test func spokenCueNamesEveryPart() {
        let cue = EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: [
            EarbudsPartReading(part: .left, level: .fresh(80)),
            EarbudsPartReading(part: .right, level: .fresh(75)),
            EarbudsPartReading(part: .case, level: .lastKnown(60)),
        ])
        #expect(EarbudsWords.spoken(cue, hideDetails: false) ==
            "Pro Max Buds connected. Left 80 percent, right 75 percent, case 60 percent last known.")
        let unknown = EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: [
            EarbudsPartReading(part: .left, level: .fresh(0)),
            EarbudsPartReading(part: .single, level: .unknown),
        ])
        #expect(EarbudsWords.spoken(unknown, hideDetails: false) ==
            "Pro Max Buds connected. Left unknown, unknown.")
        let gone = EarbudsCueFacts(name: "Pro\nMax", connected: false, parts: [
            EarbudsPartReading(part: .left, level: .fresh(80)),
        ])
        #expect(EarbudsWords.spoken(gone, hideDetails: false) == "Pro Max disconnected.")
        #expect(!EarbudsWords.spoken(gone, hideDetails: false).contains("%"))
        #expect(!drawsZeroPercent(EarbudsWords.spoken(unknown, hideDetails: false)))
    }

    @Test func capsulesCoverEachKindAndAdaptive() {
        let choices = [
            EarbudsModeChoice(mode: .off, available: true),
            EarbudsModeChoice(mode: .noiseCancelling, available: true),
            EarbudsModeChoice(mode: .transparency, available: false),
        ]
        let ready = EarbudsModeStatus(current: .noiseCancelling, choices: choices)
        #expect(EarbudsWords.modeCapsules(ready) == [
            EarbudsCapsule(title: "Off", symbol: "speaker.slash", spoken: "Off", kind: .available),
            EarbudsCapsule(title: "Noise cancelling", symbol: "waveform.slash", spoken: "Noise cancelling, selected", kind: .selected),
            EarbudsCapsule(title: "Transparency", symbol: "exclamationmark.circle", spoken: "Transparency, not available", kind: .refused),
        ])
        let setting = EarbudsModeStatus(current: .noiseCancelling, choices: choices, pending: .off)
        #expect(EarbudsWords.modeCapsules(setting)[0].kind == .pending)
        #expect(EarbudsWords.modeCapsules(setting)[0].spoken == "Off, pending")
        #expect(EarbudsWords.modeCapsules(setting)[1].kind == .selected)
        let same = EarbudsModeStatus(current: .noiseCancelling, choices: choices, pending: .noiseCancelling)
        #expect(EarbudsWords.modeCapsules(same)[1].kind == .selected)
        let adaptive = EarbudsModeStatus(current: .adaptive, choices: choices + [
            EarbudsModeChoice(mode: .adaptive, available: true),
        ])
        let capsules = EarbudsWords.modeCapsules(adaptive)
        #expect(capsules.map(\.kind) == [.available, .available, .refused, .fixed])
        #expect(capsules.last == EarbudsCapsule(
            title: "Adaptive", symbol: "waveform", spoken: "Adaptive, selected", kind: .fixed
        ))
        #expect(!capsules.dropLast().contains { $0.title == "Adaptive" })
    }

    @Test func modeTitlesAndOutcomes() {
        #expect(EarbudsWords.modeTitle(.off) == "Off")
        #expect(EarbudsWords.modeTitle(.noiseCancelling) == "Noise cancelling")
        #expect(EarbudsWords.modeTitle(.transparency) == "Transparency")
        #expect(EarbudsWords.modeTitle(.adaptive) == "Adaptive")
        #expect(EarbudsWords.spoken(.changed(.noiseCancelling)) == "Noise cancelling on.")
        #expect(EarbudsWords.spoken(.stayed(.transparency)) == "Listening mode stayed on Transparency.")
        #expect(EarbudsWords.spoken(.changed(.off)) == "Off on.")
        #expect(EarbudsWords.spoken(.stayed(.adaptive)) == "Listening mode stayed on Adaptive.")
    }

    @Test func matchUsesAddressOrCleanedName() {
        #expect(EarbudsMatch.same(
            id: "AA:BB:CC:DD:EE:FF", name: "Left", outputUID: "aa-bb-cc-dd-ee-ff", outputName: "Right"
        ))
        #expect(EarbudsMatch.same(
            id: "00:11:22:33:44:55", name: "Pro\u{00A0}Max", outputUID: "BuiltInSpeaker", outputName: "Pro Max"
        ))
        #expect(!EarbudsMatch.same(
            id: "00:11:22:33:44:55", name: "Pro Max Buds", outputUID: "BuiltInSpeaker", outputName: "MacBook Speakers"
        ))
        #expect(!EarbudsMatch.same(
            id: "ab", name: "Left", outputUID: "ab", outputName: "Right"
        ))
        #expect(!EarbudsMatch.same(
            id: "", name: "   ", outputUID: "", outputName: "\n"
        ))
    }

    @Test func panelModelIsOneGroup() {
        let presence = shown()
        let mode = EarbudsModeShown(outputUID: "BuiltInSpeaker", outputName: "MacBook Speakers", status: sampleStatus())
        let earbudsOnly = EarbudsPanelModel.make(presence: presence, mode: nil, hideDetails: false)
        #expect(earbudsOnly?.name == "Pro Max Buds")
        #expect(earbudsOnly?.parts.count == 3)
        #expect(earbudsOnly?.capsules.isEmpty == true)

        let modeOnly = EarbudsPanelModel.make(
            presence: nil,
            mode: EarbudsModeShown(outputUID: "display", outputName: "Studio Display", status: sampleStatus()),
            hideDetails: false
        )
        #expect(modeOnly?.name == "Studio Display")
        #expect(modeOnly?.parts.isEmpty == true)
        #expect(modeOnly?.capsules.isEmpty == false)

        let matched = EarbudsPanelModel.make(
            presence: presence,
            mode: EarbudsModeShown(outputUID: "AA:BB:CC:DD:EE:FF", outputName: "MacBook Speakers", status: sampleStatus()),
            hideDetails: false
        )
        #expect(matched?.name == "Pro Max Buds")
        #expect(matched?.parts.isEmpty == false)
        #expect(matched?.capsules.isEmpty == false)
        #expect(matched?.name.contains("\n") == false)

        let split = EarbudsPanelModel.make(presence: presence, mode: mode, hideDetails: false)
        #expect(split?.name == "Pro Max Buds")
        #expect(split?.parts.isEmpty == false)
        #expect(split?.capsules.isEmpty == true)

        #expect(EarbudsPanelModel.make(presence: nil, mode: nil, hideDetails: false) == nil)
        let blank = EarbudsShown(id: "00:11:22:33:44:55", name: "Pro Max Buds", parts: [])
        #expect(EarbudsPanelModel.make(presence: blank, mode: nil, hideDetails: false) == nil)
    }

    @Test func settingsWordsAreTheFiveStates() {
        #expect(EarbudsSettingsWords.state(.allowed) == "Allowed")
        #expect(EarbudsSettingsWords.state(.notAsked) == "Not asked")
        #expect(EarbudsSettingsWords.state(.notAllowed) == "Not allowed")
        #expect(EarbudsSettingsWords.state(.batteryUnavailable) == "Battery not available")
        #expect(EarbudsSettingsWords.state(.unavailable) == "Not available")
    }

    @Test func drawnStringsHaveNoEmDashOrEnDash() {
        var strings = [
            EarbudsName.display("Pro Max Buds", hideDetails: false),
            EarbudsName.display(String(repeating: "B", count: 200), hideDetails: false),
            EarbudsName.display("Secret", hideDetails: true),
        ]
        let cue = EarbudsCueFacts(name: "Pro Max Buds", connected: true, parts: shown().parts)
        strings += EarbudsWords.cueStatus(cue).map(\.text)
        strings += EarbudsWords.panelParts(shown().parts).map(\.text)
        strings.append(EarbudsWords.spoken(cue, hideDetails: false))
        strings.append(EarbudsWords.spoken(.changed(.noiseCancelling)))
        strings.append(EarbudsWords.spoken(.stayed(.transparency)))
        for mode in [EarbudsMode.off, .noiseCancelling, .transparency, .adaptive] {
            strings.append(EarbudsWords.modeTitle(mode))
            strings.append(EarbudsWords.modeSymbol(mode))
        }
        for capsule in EarbudsWords.modeCapsules(sampleStatus()) {
            strings.append(capsule.title)
            strings.append(capsule.symbol)
            strings.append(capsule.spoken)
        }
        for face in [EarbudsSettingsFace.allowed, .notAsked, .notAllowed, .batteryUnavailable, .unavailable] {
            strings.append(EarbudsSettingsWords.state(face))
        }
        if let group = EarbudsPanelModel.make(presence: shown(), mode: nil, hideDetails: false) {
            strings.append(group.name)
        }
        #expect(!strings.isEmpty)
        for text in strings {
            #expect(!text.unicodeScalars.contains { $0 == "\u{2014}" || $0 == "\u{2013}" })
        }
    }

    private func shown() -> EarbudsShown {
        EarbudsShown(id: "aa:bb:cc:dd:ee:ff", name: "Pro Max Buds", parts: [
            EarbudsPartReading(part: .left, level: .fresh(80)),
            EarbudsPartReading(part: .right, level: .fresh(75)),
            EarbudsPartReading(part: .case, level: .lastKnown(60)),
        ])
    }

    private func sampleStatus() -> EarbudsModeStatus {
        EarbudsModeStatus(current: .noiseCancelling, choices: [
            EarbudsModeChoice(mode: .off, available: true),
            EarbudsModeChoice(mode: .noiseCancelling, available: true),
            EarbudsModeChoice(mode: .transparency, available: true),
        ])
    }

    private func drawsZeroPercent(_ text: String) -> Bool {
        text.split { $0 == " " || $0 == "," || $0 == "." }.contains("0%")
    }
}
