import SwiftUI

// tvOS-only. Mirrors MainTabView's role for iOS — a standard SwiftUI TabView renders as
// tvOS's top tab bar with no extra code. Two tabs only: Home (status + server picking, all in
// one consolidated screen) and Settings — there's no separate Servers tab anymore.
struct TVMainTabView: View {
    @ObservedObject var vpnManager: VPNManager

    var body: some View {
        TabView {
            TVHomeView(vpnManager: vpnManager)
                .tabItem { Label("Home", systemImage: "house.fill") }

            TVSettingsView(vpnManager: vpnManager)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
