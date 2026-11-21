import Foundation

@main
struct BandScheduleMain {
    static func main() {
        let steps = OrbBandWork.steps(personaIsOrb: true)
        if steps != [.queuePlayback, .analyseBands] {
            fputs("FAIL orb steps \(steps.map(\.rawValue))\n", stderr)
            exit(1)
        }
        if OrbBandWork.steps(personaIsOrb: false) != [.queuePlayback] {
            fputs("FAIL classic still analyses\n", stderr)
            exit(1)
        }
        fputs("band schedule ok\n", stderr)
    }
}
