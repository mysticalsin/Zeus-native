import Foundation
import Testing
@testable import Zeus

struct SpeakerRouteTextTests {
    @Test func theRouteLineNamesTheUltronEffectOnlyWhenItIsOn() {
        #expect(Speaker.describe(engine: "ElevenLabs", effectOn: false) == "ElevenLabs")
        #expect(Speaker.describe(engine: "ElevenLabs", effectOn: true) == "ElevenLabs with the Ultron effect")
    }
}
