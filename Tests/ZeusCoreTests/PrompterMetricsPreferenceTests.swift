import Foundation
import Testing
@testable import ZeusCore

@Suite("Prompter metrics preference")
struct PrompterMetricsPreferenceTests {
    private func fresh() throws -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.prompter-metrics.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aWindowOnlySpeedBecomesTheCanonicalSpeedAndTheWindowKeyStays() throws {
        let defaults = try fresh()
        defaults.set(80.0, forKey: PrompterMetricsPreference.legacySpeedKey)
        defaults.set(48.0, forKey: PrompterMetricsPreference.legacySizeKey)
        #expect(PrompterMetricsPreference.speed(defaults) == 80)
        #expect(PrompterMetricsPreference.size(defaults) == 48)
        PrompterMetricsPreference.migrate(defaults)
        #expect(defaults.object(forKey: PrompterMetricsPreference.speedKey) as? Double == 80)
        #expect(defaults.object(forKey: PrompterMetricsPreference.sizeKey) as? Double == 48)
        #expect(defaults.object(forKey: PrompterMetricsPreference.legacySpeedKey) as? Double == 80)
        #expect(defaults.object(forKey: PrompterMetricsPreference.legacySizeKey) as? Double == 48)
    }

    @Test func anExistingCanonicalSpeedIsNotReplaced() throws {
        let defaults = try fresh()
        defaults.set(10.0, forKey: PrompterMetricsPreference.speedKey)
        defaults.set(80.0, forKey: PrompterMetricsPreference.legacySpeedKey)
        PrompterMetricsPreference.migrate(defaults)
        #expect(PrompterMetricsPreference.speed(defaults) == 10)
        #expect(defaults.object(forKey: PrompterMetricsPreference.legacySpeedKey) as? Double == 80)
    }

    @Test func settingSpeedWritesBothKeys() throws {
        let defaults = try fresh()
        PrompterMetricsPreference.setSpeed(18, defaults: defaults)
        #expect(defaults.object(forKey: PrompterMetricsPreference.speedKey) as? Double == 18)
        #expect(defaults.object(forKey: PrompterMetricsPreference.legacySpeedKey) as? Double == 18)
    }
}
