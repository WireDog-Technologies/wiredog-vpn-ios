import SwiftUI

// tvOS-only. List-based server picker — tvOS's focus engine handles row navigation natively.
struct TVServersView: View {
    @ObservedObject var vpnManager: VPNManager

    var body: some View {
        List {
            if !vpnManager.recommendedServers.isEmpty {
                Section("Recommended") {
                    ForEach(vpnManager.recommendedServers) { server in
                        row(for: server)
                    }
                }
            }

            Section("All Servers") {
                ForEach(vpnManager.availableServers) { server in
                    row(for: server)
                }
            }
        }
        .task {
            await vpnManager.loadServers()
        }
    }

    private func row(for server: Server) -> some View {
        Button(action: { vpnManager.selectServer(server) }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.city ?? server.countryName)
                        .font(.headline)
                    Text(server.countryName)
                        .font(.subheadline)
                        .foregroundColor(.vpnTextSecondary)
                }

                Spacer()

                if server.latencyMs > 0 {
                    Text("\(server.latencyMs) ms")
                        .font(.subheadline)
                        .foregroundColor(.vpnTextSecondary)
                }

                if vpnManager.selectedServer?.id == server.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.vpnGreen)
                }
            }
        }
    }
}
