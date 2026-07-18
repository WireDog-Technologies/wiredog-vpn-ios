import SwiftUI

struct ChangeLogEntry: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let changes: [String]
}

private let changeLog: [ChangeLogEntry] = [
    ChangeLogEntry(
        version: "1.5.0",
        date: "July 2026",
        changes: [
            "Togglable DNS filters — Block Ads and Block Malware can now be switched on or off independently in Settings.",
            "Clearer VPN conflict errors — Connecting while another VPN configuration is active now shows a specific message telling you to select WireDog VPN in Settings, instead of a generic system error.",
        ]
    ),
    ChangeLogEntry(
        version: "1.4.0",
        date: "June 2026",
        changes: [
            "Real latency measurement — Live TCP probes with triple sampling replace server-reported latency values, improving recommendation accuracy.",
            "Protocol upgraded from WireGuard to AmneziaWG — Operates on port 443 with packet obfuscation for improved compatibility on restricted and censored networks.",
        ]
    ),
    ChangeLogEntry(
        version: "1.3.0",
        date: "May 2026",
        changes: [
            "Initial release",
            "WireGuard protocol support only",
            "Kill Switch protection",
            "Auto-Connect on startup",
            "Interactive world map for server selection",
            "Server stats — load, speed, and latency per server",
            "Server Selector sheet with Favorites, Recommended, and All Servers sections",
            "Active connection stats sheet",
            "DNS leak protection",
            "IPv6 leak protection",
        ]
    )
]

struct ChangeLogView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
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
                    Text("Change Log")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.vpnTextPrimary)

                    Text("Release history and updates")
                        .font(.system(size: 14))
                        .foregroundColor(.vpnTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(changeLog) { entry in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text("v\(entry.version)")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.vpnTextPrimary)
                                    Spacer()
                                    Text(entry.date)
                                        .font(.system(size: 13))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                                .padding(16)
                                .background(Color.vpnSecondaryBackground)

                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(entry.changes, id: \.self) { change in
                                        HStack(alignment: .top, spacing: 10) {
                                            Circle()
                                                .fill(Color.vpnPrimary)
                                                .frame(width: 6, height: 6)
                                                .padding(.top, 5)
                                            Text(change)
                                                .font(.system(size: 14))
                                                .foregroundColor(.vpnTextPrimary)
                                        }
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.vpnCardBackground)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

#Preview {
    ChangeLogView()
}
