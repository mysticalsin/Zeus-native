import SwiftUI
import ZeusCore

/// Hosted speech is off until the person turns it on. The token is written only to the Keychain.
struct HostedSpeechCard: View {
    @State private var enabled = HostedSpeechPreference.isEnabled()
    @State private var address = ""
    @State private var token = ""
    @State private var note = "Off until you turn it on. The token stays in the Keychain."

    var body: some View {
        GSCard("Hosted speech") {
            GSToggleRow(symbol: "network", title: "Use a hosted speech route",
                        text: "Off by default. Zeus does not call the network until this is on.",
                        isOn: Binding(get: { enabled }, set: { value in
                            enabled = value
                            HostedSpeechPreference.setEnabled(value)
                            refreshNote()
                        }))
            GSDivider()
            GSRow(symbol: "link", title: "Address", text: "https only.") {
                TextField("https://", text: $address)
                    .textFieldStyle(.plain)
                    .font(OB.font(13.5))
                    .foregroundStyle(GS.text)
                    .frame(width: 220, height: 30)
                    .accessibilityLabel("Hosted speech address")
            }
            GSDivider()
            GSRow(symbol: "key", title: "Token", text: "Stored in the Keychain. It is not saved in settings or logs.") {
                SecureField("Token", text: $token)
                    .textFieldStyle(.plain)
                    .snapshotSafeText(token, placeholder: "Token", secure: true)
                    .font(OB.font(13.5))
                    .foregroundStyle(GS.text)
                    .frame(width: 180, height: 30)
                    .accessibilityLabel("Hosted speech token")
                Button("Save") { save() }
                    .buttonStyle(GSButtonStyle())
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            GSInfo(text: note)
        }
        .onAppear {
            address = Keychain.get(HostedSpeechAccounts.url) ?? ""
            refreshNote()
        }
    }

    private func save() {
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanAddress.isEmpty { _ = Keychain.set(cleanAddress, for: HostedSpeechAccounts.url) }
        if !cleanToken.isEmpty {
            _ = Keychain.set(cleanToken, for: HostedSpeechAccounts.token)
            token = ""
        }
        refreshNote()
    }

    private func refreshNote() {
        let storedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Keychain.get(HostedSpeechAccounts.url) : address
        let storedToken = Keychain.get(HostedSpeechAccounts.token)
        switch HostedSpeechGate.phase(enabled: enabled, rawURL: storedAddress, token: storedToken) {
        case .off:
            note = "Off. No network call will be made."
        case .ready:
            note = "Ready. The token is in the Keychain."
        case .refused(.notHTTPS), .refused(.missingURL):
            note = "The address must be https."
        case .refused(.missingToken):
            note = "Add a token. It is stored in the Keychain."
        case .refused(.tokenEmbeddedInURL):
            note = "The address cannot contain the token."
        }
    }
}
