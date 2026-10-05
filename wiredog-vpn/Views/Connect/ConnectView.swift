import SwiftUI
import UIKit

struct ConnectView: View {
    @ObservedObject var vpnManager: VPNManager
    @ObservedObject private var broadcastService = BroadcastService.shared
    @State private var showServerDetails = false
    @State private var showServerSelector = false
    @State private var showAnnouncements = false
    @State private var isPulsing = false
    @State private var envelopePulse = false

    private var activeAnnouncements: [BroadcastMessage] {
        broadcastService.activeMessages()
    }

    private var unreadAnnouncementCount: Int {
        broadcastService.unreadCount()
    }

    var statusText: String { vpnManager.statusText }

    var statusColor: Color { vpnManager.statusColor }

    var isTransitioning: Bool {
        if vpnManager.isFetchingNetworkInfo {
            return true
        }
        switch vpnManager.connectionState {
        case .connecting, .disconnecting, .reconnecting:
            return true
        case .connected, .disconnected:
            return false
        }
    }

    var locationText: String {
        if isTransitioning {
            return "Loading..."
        }
        if vpnManager.connectionState == .connected, let server = vpnManager.selectedServer {
            return server.gatewayName ?? "\(server.city ?? server.countryName), \(server.countryCode)"
        }
        return vpnManager.currentLocation ?? "Unknown"
    }

    var protectionLabel: String {
        vpnManager.connectionState == .connected ? "Protected" : "Unprotected"
    }

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Logo
                HStack(spacing: 8) {
                    Image("WireDog Head Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 38)

                    Image("WireDog Text Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 52)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .overlay(alignment: .trailing) {
                    // Announcements — envelope icon, vertically centered on the logo row.
                    // Hidden entirely when there's nothing relevant to show.
                    if !activeAnnouncements.isEmpty {
                        Button(action: { showAnnouncements = true }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.vpnTextPrimary)
                                    .scaleEffect(envelopePulse ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true), value: envelopePulse)

                                if unreadAnnouncementCount > 0 {
                                    Text(unreadAnnouncementCount > 9 ? "9+" : "\(unreadAnnouncementCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Circle().fill(Color.vpnRed))
                                        .offset(x: 10, y: -8)
                                }
                            }
                        }
                        .padding(.trailing, 32)
                        .offset(y: -1)
                        .onChange(of: unreadAnnouncementCount) { count in
                            guard count > 0 else { return }
                            envelopePulse = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                envelopePulse = false
                            }
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 20)

                // Location & IP Info — tappable when connected to show connection stats
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Location")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)

                            Text(locationText)
                                .font(.custom("Iosevka Term Extended", size: 16))
                                .fontWeight(.semibold)
                                .foregroundColor(vpnManager.connectionState == .connected ? statusColor : .vpnRed)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("IP Address")
                                .font(.system(size: 12))
                                .foregroundColor(.vpnTextSecondary)

                            Text(isTransitioning ? "Loading..." : (vpnManager.publicIP ?? (vpnManager.connectionState == .connected ? "Unknown" : "Loading...")))
                                .font(.custom("Iosevka Term Extended", size: 16))
                                .foregroundColor(vpnManager.connectionState == .connected ? statusColor : .vpnRed)
                        }
                    }
                }
                .padding(16)
                .background(Color.vpnCardBackground)
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .onTapGesture {
                    if vpnManager.connectionState == .connected,
                       vpnManager.selectedServer != nil {
                        showServerDetails = true
                    }
                }

                Spacer()

                // Large Shield Power Button
                VStack(spacing: 24) {
                    ZStack {
                        if vpnManager.connectionState == .connecting || vpnManager.connectionState == .reconnecting {
                            Circle()
                                .fill(statusColor.opacity(0.2))
                                .frame(width: 200, height: 200)
                                .scaleEffect(isPulsing ? 1.2 : 1.0)
                                .opacity(isPulsing ? 0 : 0.5)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isPulsing)
                                .onAppear { isPulsing = true }
                                .onDisappear { isPulsing = false }
                        }

                        Circle()
                            .stroke(statusColor, lineWidth: 4)
                            .frame(width: 180, height: 180)

                        Circle()
                            .fill(statusColor)
                            .frame(width: 140, height: 140)

                        Image(systemName: vpnManager.statusIconName)
                            .font(.system(size: 56, weight: .regular))
                            .foregroundColor(.vpnBackground)
                    }
                    .onTapGesture {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        vpnManager.toggleConnection()
                    }

                    Text(statusText)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(statusColor)
                        .tracking(0.5)
                }

                Spacer()

                // Connection Time Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection Time")
                        .font(.system(size: 14))
                        .foregroundColor(.vpnTextSecondary)

                    HStack(spacing: 8) {
                        if vpnManager.connectionState == .connected {
                            Text(vpnManager.connectionDuration.formattedHMS)
                                .font(.custom("Iosevka Term Extended", size: 22))
                                .fontWeight(.semibold)
                                .foregroundColor(statusColor)
                        } else {
                            Text("00:00:00")
                                .font(.custom("Iosevka Term Extended", size: 22))
                                .fontWeight(.semibold)
                                .foregroundColor(.vpnTextTertiary)
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.vpnCardBackground)
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                // Server Info Card — always tappable to open server selector
                if let server = vpnManager.selectedServer {
                    Button(action: { showServerSelector = true }) {
                        ServerInfoCard(server: server)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showAnnouncements) {
            BroadcastListView(broadcastService: broadcastService)
        }
        .sheet(isPresented: $showServerDetails) {
            if let server = vpnManager.selectedServer {
                ServerDetailsSheet(
                    server: server,
                    connectionDuration: vpnManager.connectionDuration,
                    originalIP: vpnManager.originalIP,
                    vpnIP: vpnManager.publicIP,
                    isConnected: vpnManager.connectionState == .connected
                )
            }
        }
        .sheet(isPresented: $showServerSelector) {
            if #available(iOS 16, *) {
                ServerSelectorSheet(vpnManager: vpnManager)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
            } else {
                ServerSelectorSheet(vpnManager: vpnManager)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { vpnManager.errorMessage != nil },
            set: { if !$0 { vpnManager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vpnManager.errorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { vpnManager.needsSubscription },
            set: { if !$0 { vpnManager.needsSubscription = false } }
        )) {
            SubscriptionSheet {
                vpnManager.needsSubscription = false
                if let server = vpnManager.pendingServer {
                    vpnManager.connect(to: server)
                }
            }
        }
    }
}

#Preview {
    ConnectView(vpnManager: VPNManager())
}
