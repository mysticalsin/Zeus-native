import Foundation
import ZeusCore

enum ScreenShareMigration {
    static func run(defaults: UserDefaults) {
        ZeusScreenSharePolicy.migrate(defaults)
    }
}
