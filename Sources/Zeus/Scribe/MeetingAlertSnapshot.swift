import SwiftUI

/// One meeting notice, for snapshots. Synthetic title and time only.
struct MeetingAlertSnapshot: View {
    var title: String
    var when: String
    var appName: String
    var symbol: String
    var scheme: ColorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(TopBarStyle.label(12, .semibold)).lineLimit(1)
                Text("\(when) · \(appName)").font(TopBarStyle.label(10.5)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("Start").font(TopBarStyle.label(11, .semibold))
            Text("Not now").font(TopBarStyle.label(11))
        }
        .padding(.horizontal, 10)
        .frame(width: MeetingAlert.width, height: MeetingAlert.height)
        .background(scheme == .dark ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, scheme)
    }
}
