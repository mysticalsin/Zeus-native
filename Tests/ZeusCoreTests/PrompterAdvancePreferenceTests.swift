import Foundation
import Testing
@testable import ZeusCore

@Suite("Prompter advance preference")
struct PrompterAdvancePreferenceTests {
    private func fresh() throws -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.prompter-advance.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aMissingPairStaysOffAndDoesNotWrite() throws {
        let defaults = try fresh()
        #expect(!PrompterAdvancePreference.isOn(defaults))
        #expect(!PrompterAdvancePreference.migrate(defaults))
        #expect(defaults.object(forKey: PrompterAdvancePreference.key) == nil)
        #expect(defaults.object(forKey: PrompterAdvancePreference.legacyKey) == nil)
    }

    @Test func aLegacyBooleanIsCopiedAndKept() throws {
        let defaults = try fresh()
        defaults.set(true, forKey: PrompterAdvancePreference.legacyKey)
        #expect(PrompterAdvancePreference.isOn(defaults))
        #expect(PrompterAdvancePreference.migrate(defaults))
        #expect(defaults.object(forKey: PrompterAdvancePreference.key) as? Bool == true)
        #expect(defaults.object(forKey: PrompterAdvancePreference.legacyKey) as? Bool == true)
    }

    @Test func theSettingsKeyWinsOverTheLegacyBoolean() throws {
        let defaults = try fresh()
        defaults.set(false, forKey: PrompterAdvancePreference.key)
        defaults.set(true, forKey: PrompterAdvancePreference.legacyKey)
        #expect(!PrompterAdvancePreference.migrate(defaults))
        #expect(!PrompterAdvancePreference.isOn(defaults))
        #expect(defaults.object(forKey: PrompterAdvancePreference.legacyKey) as? Bool == true)
    }
}
