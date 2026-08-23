import SwiftUI

// tvOS-only. Mirrors MainTabView's role for iOS — a standard SwiftUI TabView renders as
// tvOS's top tab bar with no extra code.
struct TVMainTabView: View {
    @ObservedObject var vpnManager: VPNManager

    var body: some View {
        TabView {
            TVConnectView(vpnManager: vpnManager)
                .tabItem { Label("Connect", systemImage: "shield.fill") }

            TVServersView(vpnManager: vpnManager)
                .tabItem { Label("Servers", systemImage: "globe") }

            TVSettingsView(vpnManager: vpnManager)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
