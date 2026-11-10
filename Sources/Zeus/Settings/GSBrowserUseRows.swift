import Observation
import SwiftUI
import ZeusCore

/// What the "Separate browser (browser-use)" option needs, and the button that fetches it.
@MainActor
@Observable
final class BrowserUseSetupModel {
    static let shared = BrowserUseSetupModel()

    private(set) var status: BrowserUseSetup.Status?
    private(set) var working = false
    private(set) var progress = ""
    private(set) var failure: String?

    func refresh() async {
        status = await BrowserUseSetup.status()
    }

    /// Fetches browser-use (and a Chromium if there is none) with progress lines. Only ever runs from the button.
    func setUp() {
        guard !working else { return }
        working = true
        failure = nil
        progress = "Starting..."
        Task { @MainActor in
            do {
                try await BrowserUseSetup.setUp { line in
                    Task { @MainActor in BrowserUseSetupModel.shared.progress = line }
                }
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            working = false
            await refresh()
        }
    }
}

/// The rows under the browser choice: status, Set up, allowed sites, telemetry note.
struct GSBrowserUseRows: View {
    private var store: SettingsStore { .shared }
    private var model: BrowserUseSetupModel { .shared }

    var body: some View {
        let status = model.status
        GSRow(symbol: "checklist", title: "Separate browser setup",
              text: "Zeus runs browser-use from uv, in its own browser profile (Zeus/browser-use-profile). Nothing is downloaded until you press Set up.") {
            HStack(spacing: 8) {
                if model.working { ProgressView().controlSize(.small) }
                Button(status?.ready == true ? "Check again" : "Set up") {
                    if status?.ready == true { Task { await model.refresh() } } else { model.setUp() }
                }
                .buttonStyle(GSButtonStyle(prominent: status?.ready != true)).disabled(model.working)
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            GSStatus(ok: status?.uvPath != nil, text: status?.uvText ?? "Checking uv...")
            GSStatus(ok: status?.packageCached == true, text: status?.packageText ?? "Checking browser-use...")
            GSStatus(ok: status?.browserPath != nil, text: status?.browserText ?? "Checking Chromium...")
            if model.working { Text(model.progress).font(OB.font(12.5)).foregroundStyle(GS.secondary).lineLimit(1) }
            if let failure = model.failure { Text(failure).font(OB.font(12.5)).foregroundStyle(Color(rgb: 255, 120, 110)).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.leading, 42).padding(.bottom, 8)
        .task { await model.refresh() }
        GSDivider()
        GSRow(symbol: "network", title: "Allowed sites", text: "The separate browser opens only these sites (and their subdomains), separated by commas. Empty means any site.") {
            GSTextInput(text: store.stringBinding("browserAgent.allowedDomains"), placeholder: "e.g. example.com, wikipedia.org", label: "Allowed sites")
        }
        GSInfo(text: "Telemetry: off. Zeus starts browser-use with ANONYMIZED_TELEMETRY=False, no cloud sync, no version check and no AI keys: your own AI decides every step, browser-use only drives the page.")
    }
}
