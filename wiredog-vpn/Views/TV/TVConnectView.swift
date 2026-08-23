import SwiftUI

// tvOS-only. Built for the focus engine/remote rather than ported from the iOS ConnectView —
// binds to the same VPNManager, so connect/disconnect/server-switch behavior matches iOS exactly.
struct TVConnectView: View {
    @ObservedObject var vpnManager: VPNManager

    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: vpnManager.statusIconName)
                .font(.system(size: 100))
                .foregroundColor(vpnManager.statusColor)

            VStack(spacing: 8) {
                Text(vpnManager.statusText)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)

                if let server = vpnManager.selectedServer {
                    Text(server.city ?? server.countryName)
                        .font(.title3)
                        .foregroundColor(.vpnTextSecondary)
                }
            }

            if vpnManager.connectionState == .connected {
                HStack(spacing: 48) {
                    statTile(title: "Download", value: String(format: "%.1f Mbps", vpnManager.connectionStats.downloadSpeed))
                    statTile(title: "Upload", value: String(format: "%.1f Mbps", vpnManager.connectionStats.uploadSpeed))
                    statTile(title: "Duration", value: formattedDuration(vpnManager.connectionDuration))
                }
            }

            Button(action: { vpnManager.toggleConnection() }) {
                Text(connectButtonTitle)
                    .font(.title2.weight(.semibold))
                    .frame(width: 360, height: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(vpnManager.statusColor)

            if let error = vpnManager.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.vpnRed)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vpnBackground)
    }

    private var connectButtonTitle: String {
        switch vpnManager.connectionState {
        case .connected: return "Disconnect"
        case .connecting, .reconnecting: return "Cancel"
        case .disconnecting: return "Disconnecting…"
        case .disconnected: return "Connect"
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(.vpnTextPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(.vpnTextSecondary)
        }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
