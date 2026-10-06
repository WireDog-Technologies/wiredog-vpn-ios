import SwiftUI

// tvOS-only. Replaces the old separate TVConnectView/TVServersView split with one consolidated
// screen: connection status + a Recommended row + an All Servers row, both tap-to-connect.
struct TVHomeView: View {
    @ObservedObject var vpnManager: VPNManager

    // Without this, the tvOS focus engine has no established initial target the first time
    // this tab's content is entered from the top tab bar, so pressing Down falls back to raw
    // geometry — which favors whichever tile is horizontally closest to the (centered) tab bar
    // over the (left-aligned) Connect button, since row 1 lands here (confirmed by a real bug:
    // Down from the tab bar skipped the button entirely).
    @Namespace private var focusNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                statusSection

                if !vpnManager.recommendedServers.isEmpty {
                    serverRow(title: "Recommended", servers: vpnManager.recommendedServers, includeFastestTile: true)
                }

                serverRow(title: "All Servers", servers: vpnManager.availableServers, includeFastestTile: false)
            }
            .padding(80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vpnBackground)
        .tvFocusScope(focusNamespace)
        .task {
            await vpnManager.loadServers()
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: vpnManager.connectionState == .connected ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 30, weight: .semibold))
                Text(statusTitle)
                    .font(.system(size: 34, weight: .bold))
            }
            .foregroundColor(vpnManager.statusColor)

            if let server = vpnManager.selectedServer {
                HStack(spacing: 10) {
                    Text(server.city ?? server.countryName)
                        .fontWeight(.semibold)

                    if vpnManager.connectionState == .connected, let ip = vpnManager.publicIP {
                        Text("•")
                            .foregroundColor(.vpnTextSecondary)
                        Text(ip)
                            .foregroundColor(.vpnTextSecondary)
                    }
                }
                .font(.title3)
                .foregroundColor(.vpnTextPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.vpnCardBackground)
                .cornerRadius(12)
            }

            Button(action: {
                // Cleared on each press so the message below goes away once the account has been
                // subscribed on the web; a still-unpaid account sets it again inside toggleConnection.
                vpnManager.needsSubscription = false
                vpnManager.toggleConnection()
            }) {
                Text(connectButtonTitle)
                    .font(.title3.weight(.semibold))
                    .frame(width: 260, height: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(vpnManager.statusColor)
            .padding(.top, 4)
            .tvPrefersDefaultFocus(in: focusNamespace)

            // iOS answers needsSubscription with the IAP sheet; the TV app has no purchase flow, so it
            // just says why Connect did nothing (deliberately no pricing or purchase link).
            if vpnManager.needsSubscription {
                Text("Your account doesn't have an active subscription.")
                    .font(.callout)
                    .foregroundColor(.vpnRed)
                    .frame(maxWidth: 600, alignment: .leading)
            }

            if let error = vpnManager.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.vpnRed)
                    .frame(maxWidth: 600, alignment: .leading)
            }
        }
    }

    private var statusTitle: String {
        switch vpnManager.connectionState {
        case .connected:
            return vpnManager.statusText == "PROTECTED" ? "Protected" : "Connection Issue"
        case .connecting:
            return "Connecting…"
        case .reconnecting:
            return "Reconnecting…"
        case .disconnecting:
            return "Disconnecting…"
        case .disconnected:
            return "Unprotected"
        }
    }

    private var connectButtonTitle: String {
        switch vpnManager.connectionState {
        case .connected: return "Disconnect"
        case .connecting, .reconnecting: return "Cancel"
        case .disconnecting: return "Disconnecting…"
        case .disconnected: return "Connect"
        }
    }

    // MARK: - Server rows

    private func serverRow(title: String, servers: [Server], includeFastestTile: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundColor(.vpnTextPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 48) {
                    if includeFastestTile, let fastest = vpnManager.recommendedServers.first {
                        fastestTile(for: fastest)
                    }

                    ForEach(servers) { server in
                        serverTile(for: server)
                    }
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 8)
            }
            // Without this, the ScrollView clips its content to its own bounds, which sliced
            // the leftmost tile's focus-scale growth (confirmed by a real bug — only the first
            // tile clipped, since every other tile has a neighbor's spacing to grow into).
            .tvScrollClipDisabled()
        }
        // The focus section has to wrap the *row* (title + scroll view), not just the
        // ScrollView on its own — that was the actual bug: with it only on the ScrollView, the
        // engine still treated every tile as if it were at the same level as the row above/
        // below, so Up/Down still resolved by raw geometry (jumping to whatever tile happened
        // to be closest, and dead-ending when the destination row had fewer tiles).
        .tvFocusSection()
    }

    private func fastestTile(for server: Server) -> some View {
        tile(
            label: "Fastest",
            isSelected: vpnManager.selectedServer?.id == server.id,
            action: { select(server) }
        ) {
            ZStack {
                Color.vpnGreen
                Image(systemName: "bolt.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    private func serverTile(for server: Server) -> some View {
        tile(
            label: server.city ?? server.countryName,
            isSelected: vpnManager.selectedServer?.id == server.id,
            action: { select(server) }
        ) {
            Image(USStateFlag.assetName(for: server.countryCode))
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    // The card button style wraps only the flag/icon square, so its focus scale + default
    // background chrome never touches the label — that's what was causing the label to sit on
    // a gray card background and the whole tile (label included) to blow past its neighbors
    // when focused.
    private func tile<Content: View>(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 12) {
            Button(action: action) {
                content()
                    .frame(width: 180, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.vpnGreen : .clear, lineWidth: 4)
                    )
            }
            .tvCardButtonStyle()

            Text(label)
                .font(.callout.weight(.medium))
                .foregroundColor(.vpnTextPrimary)
                .lineLimit(1)
                .frame(width: 180)
        }
    }

    // MARK: - Actions

    // One-tap tile behavior without changing VPNManager's own rules: select (which live-switches
    // if already connected, per VPNManager.selectServer) and, if idle, immediately connect too
    // instead of requiring a second tap on the status button.
    private func select(_ server: Server) {
        vpnManager.needsSubscription = false
        vpnManager.selectServer(server)
        if vpnManager.connectionState == .disconnected {
            vpnManager.toggleConnection()
        }
    }
}

private extension View {
    // `.buttonStyle(.card)` is tvOS-only (gives tiles the native focus lift/shadow); this file
    // also compiles into the iOS target today (Views/TV/ isn't excluded from it — pre-existing,
    // matches every other file in this folder), so the non-tvOS branch just needs to compile,
    // never run.
    @ViewBuilder
    func tvCardButtonStyle() -> some View {
        #if os(tvOS)
        self.buttonStyle(.card)
        #else
        self.buttonStyle(.plain)
        #endif
    }

    // `.scrollClipDisabled()` needs iOS 17/tvOS 17, but the iOS target here deploys back to
    // 15.0 — gate on platform (not just #available) so the iOS compile never sees the call.
    @ViewBuilder
    func tvScrollClipDisabled() -> some View {
        #if os(tvOS)
        self.scrollClipDisabled()
        #else
        self
        #endif
    }

    // `.focusSection()` is tvOS's directional-focus grouping API; same reasoning as the other
    // helpers here for gating it out of the (unused) iOS compile of this file.
    @ViewBuilder
    func tvFocusSection() -> some View {
        #if os(tvOS)
        self.focusSection()
        #else
        self
        #endif
    }

    // `.focusScope(_:)` and `.prefersDefaultFocus(_:in:)` are tvOS-only focus-engine APIs; same
    // reasoning as the other helpers here for gating them out of the (unused) iOS compile.
    @ViewBuilder
    func tvFocusScope(_ namespace: Namespace.ID) -> some View {
        #if os(tvOS)
        self.focusScope(namespace)
        #else
        self
        #endif
    }

    @ViewBuilder
    func tvPrefersDefaultFocus(in namespace: Namespace.ID) -> some View {
        #if os(tvOS)
        self.prefersDefaultFocus(in: namespace)
        #else
        self
        #endif
    }
}
