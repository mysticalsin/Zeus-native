import Foundation
import ZeusCore

enum ScreenShareMigration {
    static let origin = SettingsStore.ChangeOrigin.migration

    static func run(defaults: UserDefaults) {
        _ = ZeusScreenSharePolicy.commit(value: "true", origin: .migration, defaults: defaults)
        ZeusScreenSharePolicy.migrate(defaults)
    }
}
