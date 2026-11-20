import AVFoundation
import SwiftUI
import ZeusCore

/// Privacy card for face verification. The camera prompt runs only after the switch is turned on.
/// A capture session is not opened here.
struct FaceVerificationSettingsPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var machine = FaceVerificationMachine()
    @State private var confirmingDelete = false

    private var store: SettingsStore { SettingsStore.shared }

    var body: some View {
        let model = FaceVerificationSectionModel.make(
            machine: machine,
            presenceEnabled: store.bool(FacePresenceLink.enabledKey),
            reduceMotion: reduceMotion,
            vaultReadable: true
        )
        VStack(alignment: .leading, spacing: model.layout.cardSpacing) {
            header(model)
            preview(model)
            stateBanner(model)
            controls(model)
        }
        .padding(model.layout.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: model.animationDuration), value: machine.phase)
    }

    private func header(_ model: FaceVerificationSectionModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.title)
                .font(GS.cardTitle)
                .foregroundStyle(GS.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(model.title)
            Text(model.onboarding)
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(model.onboarding)
        }
    }

    private func preview(_ model: FaceVerificationSectionModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.preview.title)
                .font(GS.rowTitle)
                .foregroundStyle(GS.text)
            Text(model.preview.status)
                .font(GS.rowText.monospacedDigit())
                .foregroundStyle(GS.text)
                .accessibilityLabel(model.preview.accessibilityLabel)
            Text("Status only. The camera picture is not shown.")
                .font(GS.rowText)
                .foregroundStyle(GS.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: model.layout.rowHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func stateBanner(_ model: FaceVerificationSectionModel) -> some View {
        switch model.screen {
        case .loading:
            labeled("Loading", "Reading the saved face.")
        case .empty:
            labeled("No face saved", "Turn the check on, then save a face. Nothing is kept until you do.")
        case .error(let message):
            labeled("Could not read the saved face", message)
        case .ready:
            EmptyView()
        }
    }

    private func controls(_ model: FaceVerificationSectionModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: approvalBinding) {
                controlLabel(model, id: "face.approval")
            }
            .toggleStyle(.switch)
            .accessibilityLabel(label(model, id: "face.approval"))
            helper(model, id: "face.approval")
            Button("Save a face") { send(.beginEnrollment) }
                .buttonStyle(GSButtonStyle())
                .accessibilityLabel(label(model, id: "face.enroll"))
            helper(model, id: "face.enroll")
            Button(confirmingDelete ? "Delete saved face now" : "Delete saved face") {
                if confirmingDelete {
                    send(.deleteTemplate)
                    confirmingDelete = false
                } else {
                    confirmingDelete = true
                }
            }
            .buttonStyle(GSButtonStyle())
            .accessibilityLabel(confirmingDelete ? "Delete saved face now" : label(model, id: "face.delete"))
            helper(model, id: "face.delete")
            if confirmingDelete {
                Button("Keep the saved face") { confirmingDelete = false }
                    .buttonStyle(GSButtonStyle())
                    .accessibilityLabel("Keep the saved face")
                Text("The template stays until you confirm.")
                    .font(GS.rowText)
                    .foregroundStyle(GS.secondary)
            }
            helper(model, id: "face.fallback")
            Toggle(isOn: store.boolBinding(FacePresenceLink.enabledKey)) {
                controlLabel(model, id: FacePresenceLink.enabledKey)
            }
            .toggleStyle(.switch)
            .accessibilityLabel(label(model, id: FacePresenceLink.enabledKey))
            helper(model, id: FacePresenceLink.enabledKey)
            helper(model, id: FacePresenceLink.lockAfterKey)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).fill(GS.card))
        .overlay(RoundedRectangle(cornerRadius: GS.cardRadius, style: .continuous).strokeBorder(GS.cardStroke, lineWidth: 1))
    }

    private var approvalBinding: Binding<Bool> {
        Binding(get: { machine.approvalEnabled }, set: { on in
            if on {
                let access = currentCamera()
                send(.enable(enrolled: machine.enrolled, camera: access, uptime: ProcessInfo.processInfo.systemUptime))
            } else {
                send(.disable)
            }
        })
    }

    private func currentCamera() -> FaceCameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .unavailable
        }
    }

    private func send(_ event: FaceVerificationEvent) {
        let effects = machine.handle(event)
        for effect in effects {
            if case .askCameraConsent = effect { requestPermission() }
        }
    }

    private func requestPermission() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                _ = machine.handle(.cameraAnswered(granted: granted))
            }
        }
    }

    private func controlLabel(_ model: FaceVerificationSectionModel, id: String) -> some View {
        Text(model.controls.first { $0.id == id }?.title ?? id)
            .font(GS.rowTitle)
            .foregroundStyle(GS.text)
            .frame(minHeight: model.layout.rowHeight, alignment: .leading)
    }

    private func helper(_ model: FaceVerificationSectionModel, id: String) -> some View {
        Text(model.controls.first { $0.id == id }?.helper ?? "")
            .font(GS.rowText)
            .foregroundStyle(GS.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: GlassSettingsMetrics.helperLine, alignment: .leading)
            .padding(.bottom, 8)
    }

    private func label(_ model: FaceVerificationSectionModel, id: String) -> String {
        model.controls.first { $0.id == id }?.accessibilityLabel ?? id
    }

    private func labeled(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(GS.rowTitle).foregroundStyle(GS.text)
            Text(text).font(GS.rowText).foregroundStyle(GS.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
