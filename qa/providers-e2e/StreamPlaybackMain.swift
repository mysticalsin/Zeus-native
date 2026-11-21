import Foundation

@main
struct StreamPlaybackMain {
    static func main() {
        var played: [Data] = []
        let first = Data([1, 2, 3])
        let second = Data([4, 5])
        let all = ProviderStreamPlayback.deliver([first, second]) { played.append($0) }
        if played != [first, second] {
            fputs("FAIL played \(played.count) buffers, wanted one call per chunk\n", stderr)
            exit(1)
        }
        if all != first + second {
            fputs("FAIL joined audio\n", stderr)
            exit(1)
        }
        fputs("stream playback ok\n", stderr)
    }
}
