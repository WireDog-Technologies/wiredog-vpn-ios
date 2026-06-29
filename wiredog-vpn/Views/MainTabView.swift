import SwiftUI

struct MainTabView: View {
    @ObservedObject var vpnManager: VPNManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 1

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                ServersView(vpnManager: vpnManager)
                    .tabItem {
                        Label("Servers", systemImage: "globe.americas.fill")
                    }
                    .tag(0)

                ConnectView(vpnManager: vpnManager)
                    .tabItem {
                        Label("Connect", systemImage: "power.circle.fill")
                    }
                    .tag(1)

                SettingsView(vpnManager: vpnManager)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(2)
            }
            .tint(.vpnPrimary)
        }
        .onAppear {
            configureTabBar()
        }
        .task {
            await vpnManager.attemptAutoConnect()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            vpnManager.handleAppForeground()
            await vpnManager.attemptAutoConnect()
        }
    }

    private func configureTabBar() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(Color.vpnCardBackground)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
    }
}

#Preview {
    MainTabView(vpnManager: VPNManager())
}
