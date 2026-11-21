import Foundation
import Observation
import ZeusCore

/// Settings model for the companion persona. Classic is the stored default.
@MainActor
@Observable
final class PersonaSetting {
    static let shared = PersonaSetting()
    static let choices = [MascotPersona.displayName, OrbPersona.displayName]

    var displayName: String

    var showsOrb: Bool { displayName == OrbPersona.displayName }

    private init() {
        displayName = PersonaCatalog.current().displayName
    }

    func select(displayName: String) {
        let persona: any Persona = displayName == OrbPersona.displayName ? OrbPersona() : MascotPersona()
        self.displayName = persona.displayName
        UserDefaults.standard.set(persona.id, forKey: PersonaCatalog.defaultsKey)
    }
}
