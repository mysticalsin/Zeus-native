import Foundation
import ZeusCore

enum ScreenShareMigration {
    static func run(defaults: UserDefaults) {
        let key = "opt." + ZeusScreenSharePolicy.showInSharingKey
        guard defaults.string(forKey: key) == nil else { return }
        let show = ZeusScreenSharePolicy.showInScreenSharing(from: defaults)
        defaults.set(show ? "true" : "false", forKey: key)
    }
}
