import SwiftUI
import StoreKit

struct MainTabView: View {
    @ObservedObject var vpnManager: VPNManager
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 1
    @State private var showReportIssueFromReviewPrompt = false

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
            // Refresh the account profile on every foreground — most notably, this is what
            // picks up a subscription that was just purchased on the website checkout page
            // (the user pays in Safari, then manually switches back; nothing else would tell
            // us their plan changed). Cheap no-op the rest of the time.
            if authService.isAuthenticated {
                try? await authService.fetchUserProfile()
            }
            await vpnManager.attemptAutoConnect()
        }
        .sheet(isPresented: $vpnManager.showReviewPrompt) {
            ReviewPromptView(
                onPositive: {
                    ReviewPromptService.shared.recordPositiveResponse()
                    requestAppStoreReview()
                },
                onNegative: {
                    showReportIssueFromReviewPrompt = true
                }
            )
        }
        .sheet(isPresented: $showReportIssueFromReviewPrompt) {
            ReportIssueView(vpnManager: vpnManager)
        }
    }

    private func requestAppStoreReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return
        }
        SKStoreReviewController.requestReview(in: scene)
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
