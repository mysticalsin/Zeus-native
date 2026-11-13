import Foundation
import Testing
@testable import ZeusCore

@Suite("Live diagnostics")
struct LiveDiagnosticsTests {
    private static let mb: UInt64 = 1_048_576

    private func fixture(cpu: Double? = 0.4, memoryMB: UInt64? = 96, thermal: KeepAwakeRules.Thermal = .nominal,
                         audio: LiveDiagnostics.AudioCapture = .off, player: String? = nil, playing: Bool = false) -> LiveDiagnostics {
        LiveDiagnostics(cpuPercent: cpu, memoryBytes: memoryMB.map { $0 * Self.mb }, thermal: thermal, audio: audio,
                        playerName: player, isPlaying: playing, appVersion: "1.4.2", build: "317", osVersion: "15.1.0")
    }

    // MARK: Rows

    @Test func rowsComeInDisplayOrder() {
        let labels = fixture().rows.map(\.label)
        #expect(labels == ["CPU", "Memory", "Heat", "System audio capture", "Now playing"])
        #expect(fixture().rows.map(\.field) == [.cpu, .memory, .heat, .audio, .nowPlaying])
    }

    @Test func cpuShowsOneDecimalAndMemoryWholeMegabytes() {
        let rows = fixture(cpu: 0.46, memoryMB: 96).rows
        #expect(rows[0].value == "0.5%")
        #expect(rows[1].value == "96 MB")
        #expect(fixture(cpu: 12, memoryMB: 1024).rows[0].value == "12.0%")
        #expect(fixture(cpu: 0, memoryMB: 1024).rows[1].value == "1024 MB")
    }

    @Test func roundingUsesTheValueTheReaderSees() {
        #expect(fixture(cpu: 0.04).rows[0].value == "0.0%")
        #expect(fixture(cpu: 0.05).rows[0].value == "0.1%")
        #expect(fixture(cpu: 0.94).rows[0].value == "0.9%")
        // 96.4 MB and 96.5 MB, in bytes.
        let low = LiveDiagnostics(cpuPercent: 0, memoryBytes: UInt64(96.4 * 1_048_576), thermal: .nominal, audio: .off,
                                  playerName: nil, isPlaying: false, appVersion: "1", build: "1", osVersion: "1")
        let high = LiveDiagnostics(cpuPercent: 0, memoryBytes: UInt64(96.5 * 1_048_576), thermal: .nominal, audio: .off,
                                   playerName: nil, isPlaying: false, appVersion: "1", build: "1", osVersion: "1")
        #expect(low.rows[1].value == "96 MB")
        #expect(high.rows[1].value == "97 MB")
    }

    @Test func missingValuesReadUnknown() {
        let rows = fixture(cpu: nil, memoryMB: nil).rows
        #expect(rows[0].value == "Unknown")
        #expect(rows[1].value == "Unknown")
        #expect(rows[0].isHigh == false)
        #expect(rows[1].isHigh == false)
    }

    @Test func aValueThatIsNotANumberReadsUnknown() {
        #expect(fixture(cpu: .nan).rows[0].value == "Unknown")
        #expect(fixture(cpu: .infinity).rows[0].value == "Unknown")
        #expect(fixture(cpu: -3).rows[0].value == "0.0%")
    }

    @Test func aHugeFiniteCpuValueNeitherTrapsNorReadsAsSmall() {
        // A bad sample can be finite and enormous; converting it to a whole number once trapped.
        for huge in [1e300, Double.greatestFiniteMagnitude, 9.3e17, 1e9] {
            let row = fixture(cpu: huge).rows[0]
            #expect(row.isHigh)
            #expect(row.value.hasSuffix("%"))
            #expect(row.value != "Unknown")
        }
        #expect(LiveDiagnostics.isHigh(cpu: 1e300))
        #expect(fixture(cpu: 1e300).summaryText.contains("CPU: "))
    }

    // MARK: Heat

    @Test func thermalWords() {
        #expect(LiveDiagnostics.thermalWord(.nominal) == "Normal")
        #expect(LiveDiagnostics.thermalWord(.fair) == "Warm")
        #expect(LiveDiagnostics.thermalWord(.serious) == "Hot")
        #expect(LiveDiagnostics.thermalWord(.critical) == "Very hot")
        #expect(fixture(thermal: .serious).rows[2].value == "Hot")
    }

    /// One mapping for the whole app: Keep Awake and Diagnostics both read it.
    @Test func thermalStateMapsOneToOne() {
        #expect(KeepAwakeRules.Thermal(.nominal) == .nominal)
        #expect(KeepAwakeRules.Thermal(.fair) == .fair)
        #expect(KeepAwakeRules.Thermal(.serious) == .serious)
        #expect(KeepAwakeRules.Thermal(.critical) == .critical)
    }

    // MARK: Audio and player

    @Test func audioCaptureWords() {
        #expect(fixture(audio: .running).rows[3].value == "Running")
        #expect(fixture(audio: .off).rows[3].value == "Off")
        #expect(fixture(audio: .notAllowed).rows[3].value == "Not allowed")
    }

    @Test func audioStateFollowsRunningThenPermission() {
        #expect(LiveDiagnostics.AudioCapture(running: true, permission: .allowed) == .running)
        #expect(LiveDiagnostics.AudioCapture(running: false, permission: .allowed) == .off)
        #expect(LiveDiagnostics.AudioCapture(running: false, permission: .notAsked) == .off)
        #expect(LiveDiagnostics.AudioCapture(running: false, permission: .refused) == .notAllowed)
    }

    @Test func nowPlayingNamesThePlayerAndItsState() {
        #expect(fixture(player: "Music", playing: true).rows[4].value == "Music, Playing")
        #expect(fixture(player: "Spotify", playing: false).rows[4].value == "Spotify, Paused")
        #expect(fixture(player: nil).rows[4].value == "None")
        #expect(fixture(player: nil, playing: true).rows[4].value == "None")
    }

    // MARK: High marks

    @Test func cpuIsHighOnlyOverTheIdleBudget() {
        let budget = PerformanceBudget.idleCPUPercent
        #expect(LiveDiagnostics.isHigh(cpu: budget - 0.5) == false)
        #expect(LiveDiagnostics.isHigh(cpu: budget) == false)
        #expect(LiveDiagnostics.isHigh(cpu: budget + 0.04) == false)
        #expect(LiveDiagnostics.isHigh(cpu: budget + 0.05) == true)
        #expect(LiveDiagnostics.isHigh(cpu: budget + 5) == true)
        #expect(LiveDiagnostics.isHigh(cpu: nil) == false)
        #expect(LiveDiagnostics.isHigh(cpu: .nan) == false)
    }

    @Test func memoryIsHighOnlyOverTheIdleBudget() {
        let budget = UInt64(PerformanceBudget.idleMemoryMB)
        #expect(LiveDiagnostics.isHigh(memoryBytes: (budget - 1) * Self.mb) == false)
        #expect(LiveDiagnostics.isHigh(memoryBytes: budget * Self.mb) == false)
        #expect(LiveDiagnostics.isHigh(memoryBytes: budget * Self.mb + Self.mb / 4) == false)
        #expect(LiveDiagnostics.isHigh(memoryBytes: (budget + 1) * Self.mb) == true)
        #expect(LiveDiagnostics.isHigh(memoryBytes: nil) == false)
    }

    @Test func aHighRowCarriesTheMarkAndAttentionTone() {
        let rows = fixture(cpu: 3.2, memoryMB: 400).rows
        #expect(rows[0].isHigh && rows[1].isHigh)
        #expect(rows[0].tone == .attention && rows[1].tone == .attention)
        let calm = fixture(cpu: 0.2, memoryMB: 80).rows
        #expect(!calm[0].isHigh && !calm[1].isHigh)
        #expect(calm[0].tone == .neutral && calm[1].tone == .neutral)
    }

    @Test func statusRowTones() {
        #expect(fixture(thermal: .nominal).rows[2].tone == .ok)
        #expect(fixture(thermal: .fair).rows[2].tone == .neutral)
        #expect(fixture(thermal: .serious).rows[2].tone == .attention)
        #expect(fixture(thermal: .critical).rows[2].tone == .attention)
        #expect(fixture(audio: .running).rows[3].tone == .ok)
        #expect(fixture(audio: .off).rows[3].tone == .neutral)
        #expect(fixture(audio: .notAllowed).rows[3].tone == .attention)
        #expect(fixture(player: "Music", playing: true).rows[4].tone == .ok)
        #expect(fixture(player: nil).rows[4].tone == .neutral)
    }

    // MARK: Summary

    @Test func summaryHoldsVersionBuildAndOS() {
        let text = fixture().summaryText
        #expect(text.contains("Zeus 1.4.2 (build 317)"))
        #expect(text.contains("macOS 15.1.0"))
    }

    @Test func summaryListsEveryRowAndMarksHighValues() {
        let text = fixture(cpu: 3.2, memoryMB: 96, thermal: .fair, audio: .running, player: "Music", playing: true).summaryText
        #expect(text.contains("CPU: 3.2% (High)"))
        #expect(text.contains("Memory: 96 MB"))
        #expect(!text.contains("Memory: 96 MB (High)"))
        #expect(text.contains("Heat: Warm"))
        #expect(text.contains("System audio capture: Running"))
        #expect(text.contains("Now playing: Music, Playing"))
    }

    @Test func summaryIsDeterministic() {
        #expect(fixture().summaryText == fixture().summaryText)
        #expect(fixture().summaryText == """
        Zeus diagnostics
        Zeus 1.4.2 (build 317)
        macOS 15.1.0
        CPU: 0.4%
        Memory: 96 MB
        Heat: Normal
        System audio capture: Off
        Now playing: None
        """)
    }

    @Test func summaryNeverHoldsWhatIsPlaying() {
        let track = NowPlaying(player: .spotify, title: "Secret Song Title", artist: "Hidden Artist", album: "Private Album",
                               isPlaying: true, duration: 200, position: 10, trackID: "spotify:track:abc123")
        let live = LiveDiagnostics(cpuPercent: 0.3, memoryBytes: 90 * Self.mb, thermal: .nominal, audio: .running,
                                   nowPlaying: track, appVersion: "1.4.2", build: "317", osVersion: "15.1.0")
        let text = live.summaryText
        #expect(text.contains("Now playing: Spotify, Playing"))
        for secret in ["Secret Song Title", "Hidden Artist", "Private Album", "abc123"] {
            #expect(!text.contains(secret))
            #expect(!live.rows.contains { $0.value.contains(secret) })
        }
    }

    @Test func noPlayerReadsNone() {
        let live = LiveDiagnostics(cpuPercent: 0.3, memoryBytes: 90 * Self.mb, thermal: .nominal, audio: .off,
                                   nowPlaying: nil, appVersion: "1", build: "1", osVersion: "1")
        #expect(live.rows[4].value == "None")
    }

    @Test func versionFieldsStayOnOneLine() {
        let live = LiveDiagnostics(cpuPercent: 0, memoryBytes: Self.mb, thermal: .nominal, audio: .off, playerName: nil, isPlaying: false,
                                   appVersion: "1.0\nInjected: line", build: "9\r\n8", osVersion: "15.1")
        #expect(!live.summaryText.contains("\nInjected"))
        #expect(live.summaryText.contains("Zeus 1.0 Injected: line (build 9 8)"))
    }

    @Test func summaryUsesNoDashes() {
        let text = fixture(cpu: 3, memoryMB: 400, thermal: .critical, audio: .notAllowed, player: "Music", playing: true).summaryText
        #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
    }
}
