import SwiftUI

struct LogsView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                        }
                        .foregroundColor(.vpnPrimary)
                    }
                    Spacer()
                }
                .padding(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Logs")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.vpnTextPrimary)

                    Text("View application and VPN service logs")
                        .font(.system(size: 14))
                        .foregroundColor(.vpnTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

                VStack(spacing: 0) {
                    NavigationLink(destination: LogViewerView(logType: .application)) {
                        logRow(
                            icon: "doc.text.fill",
                            title: "Application Logs",
                            subtitle: "General app events and errors",
                            color: .vpnPrimary
                        )
                    }

                    Divider()
                        .overlay(Color.vpnBorderColor)

                    NavigationLink(destination: LogViewerView(logType: .service)) {
                        logRow(
                            icon: "network",
                            title: "Service Logs",
                            subtitle: "VPN tunnel and connection logs",
                            color: .vpnGreen
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.vpnPrimary)

                        Text("Logs are never sent to our servers. These logs are local to your device for troubleshooting.")
                            .font(.system(size: 13))
                            .foregroundColor(.vpnTextSecondary)
                    }
                    .padding(12)
                    .background(Color.vpnCardBackground)
                    .cornerRadius(8)
                }
                .padding(16)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }

    private func logRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.vpnTextPrimary)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.vpnTextSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.vpnTextSecondary)
        }
        .padding(16)
        .background(Color.vpnCardBackground)
    }
}
