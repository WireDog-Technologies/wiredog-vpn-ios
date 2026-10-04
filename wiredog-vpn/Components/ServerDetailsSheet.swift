import SwiftUI

struct ServerDetailsSheet: View {
    let server: Server
    let connectionDuration: TimeInterval
    let originalIP: String?
    let vpnIP: String?
    let isConnected: Bool
    @State private var revealIP = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.vpnBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Drag Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.vpnTextSecondary.opacity(0.5))
                        .frame(width: 40, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    VStack(spacing: 20) {
                        // Server Header Section
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                Text(server.countryFlag())
                                    .font(.system(size: 40))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(server.countryName)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.vpnTextPrimary)

                                    Text(server.id)
                                        .font(.custom("Iosevka Term Extended", size: 14))
                                        .fontWeight(.semibold)
                                        .foregroundColor(.vpnPrimary)
                                }

                                Spacer()
                            }
                        }
                        .padding(16)
                        .background(Color.vpnCardBackground)
                        .cornerRadius(12)

                        // Connection Details Section
                        VStack(spacing: 0) {
                            HStack {
                                Text("Connection details")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.vpnTextSecondary)
                                Spacer()
                            }
                            .padding(16)

                            VStack(spacing: 1) {
                                // My IP with eye icon
                                HStack {
                                    HStack(spacing: 4) {
                                        Text("My IP")
                                            .font(.system(size: 14))
                                            .foregroundColor(.vpnTextSecondary)

                                        Button(action: { revealIP.toggle() }) {
                                            Image(systemName: revealIP ? "eye.slash" : "eye")
                                                .font(.system(size: 12))
                                                .foregroundColor(.vpnTextTertiary)
                                        }
                                    }

                                    Spacer()

                                    Text(revealIP ? (originalIP ?? "Unknown") : "••••••••••••")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.vpnTextPrimary)
                                        .animation(.easeInOut(duration: 0.2), value: revealIP)
                                }
                                .padding(16)

                                Divider().overlay(Color.vpnBorderColor)
                                DetailRow(label: "VPN IP", value: isConnected ? (vpnIP ?? "Unknown") : "Not Connected")
                                Divider().overlay(Color.vpnBorderColor)
                                DetailRow(label: "Connected for", value: connectionDuration.formattedHMS)
                                Divider().overlay(Color.vpnBorderColor)
                                DetailRow(label: "State", value: server.countryName)
                                Divider().overlay(Color.vpnBorderColor)
                                DetailRow(label: "City", value: server.city ?? "Unknown")
                                Divider().overlay(Color.vpnBorderColor)
                                DetailRow(label: server.isDedicated ? "Gateway" : "Server", value: server.gatewayName ?? server.id)
                                Divider().overlay(Color.vpnBorderColor)

                                HStack {
                                    Text("Server load")
                                        .font(.system(size: 14))
                                        .foregroundColor(.vpnTextSecondary)

                                    Spacer()

                                    LoadIndicatorView(load: server.load, size: .small)
                                }
                                .padding(16)

                                Divider().overlay(Color.vpnBorderColor)
                                DetailRow(label: "Protocol", value: "AmneziaWG")
                            }
                        }
                        .background(Color.vpnCardBackground)
                        .cornerRadius(12)
                    }
                    .padding(14)
                }
            }
        }
    }

}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.vpnTextSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.vpnTextPrimary)
        }
        .padding(16)
    }
}

#Preview {
    ServerDetailsSheet(
        server: MockData.servers[0],
        connectionDuration: 5149,
        originalIP: "192.0.2.1",
        vpnIP: "203.0.113.42",
        isConnected: true
    )
}
