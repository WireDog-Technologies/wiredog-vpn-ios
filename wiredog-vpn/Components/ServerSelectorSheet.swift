import SwiftUI

struct ServerSelectorSheet: View {
    @ObservedObject var vpnManager: VPNManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.vpnBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.vpnTextSecondary.opacity(0.5))
                        .frame(width: 40, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    VStack(spacing: 20) {
                        if !vpnManager.favoriteServers.isEmpty {
                            SelectorSection(title: "FAVORITES") {
                                ForEach(vpnManager.favoriteServers) { server in
                                    ServerRowView(
                                        server: server,
                                        isSelected: vpnManager.selectedServer?.id == server.id,
                                        action: {
                                            vpnManager.selectServer(server)
                                            dismiss()
                                        },
                                        onToggleFavorite: { vpnManager.toggleFavorite(server) }
                                    )
                                }
                            }
                        }

                        if !vpnManager.recommendedServers.isEmpty {
                            SelectorSection(title: "RECOMMENDED") {
                                ForEach(vpnManager.recommendedServers) { server in
                                    ServerRowView(
                                        server: server,
                                        isSelected: vpnManager.selectedServer?.id == server.id,
                                        action: {
                                            vpnManager.selectServer(server)
                                            dismiss()
                                        },
                                        onToggleFavorite: { vpnManager.toggleFavorite(server) }
                                    )
                                }
                            }
                        }

                        SelectorSection(title: "ALL SERVERS") {
                            ForEach(vpnManager.availableServers) { server in
                                ServerRowView(
                                    server: server,
                                    isSelected: vpnManager.selectedServer?.id == server.id,
                                    action: {
                                        vpnManager.selectServer(server)
                                        dismiss()
                                    },
                                    onToggleFavorite: { vpnManager.toggleFavorite(server) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .task {
            await vpnManager.measureLatencies()
        }
    }
}

private struct SelectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.vpnTextSecondary)
                .tracking(0.5)
                .padding(.horizontal, 4)

            content()
        }
    }
}

#Preview {
    ServerSelectorSheet(vpnManager: VPNManager())
}
