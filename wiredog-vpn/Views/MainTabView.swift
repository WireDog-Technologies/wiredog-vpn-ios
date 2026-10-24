import SwiftUI
import StoreKit

struct MainTabView: View {
    @ObservedObject var vpnManager: VPNManager
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 1
    @State private var showReportIssueFromReviewPrompt = false
    // Once per MainTabView lifetime (i.e. per launch or login), so dismissing the paywall
    // doesn't bring it straight back.
    @State private var hasShownUpfrontPaywall = false

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
                // Keep the local reminders in step with whatever the profile now says.
                await ReminderService.shared.sync(for: authService.currentUser)
            }
            await vpnManager.attemptAutoConnect()
        }
        .task(id: authService.currentUser?.id) {
            await presentPaywallIfUnsubscribed()
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

    /// Unpaid accounts get the paywall as soon as they're in the app, rather than discovering
    /// it on their first Connect tap. Refetches first so a cached, stale "inactive" profile
    /// (e.g. just subscribed on the website) doesn't trigger it.
    private func presentPaywallIfUnsubscribed() async {
        guard authService.currentUser != nil else { return }
        try? await authService.fetchUserProfile()
        guard let user = authService.currentUser else { return }

        // Pick up notices staff sent to this account now that we know who is signed in.
        await BroadcastService.shared.refresh()

        // Notification permission comes first, so iOS's one-time prompt isn't hidden behind the
        // paywall. It only appears once per install; every later open skips straight on.
        await ReminderService.shared.requestPermissionIfNeeded(for: user)

        guard !hasShownUpfrontPaywall,
              !user.hasEntitlement,
              // An org that stopped covering this account gets its own message on connect;
              // a personal paywall wouldn't fix that.
              user.lostOrganizationAccess == nil,
              !user.isRevoked,
              !vpnManager.needsSubscription else { return }

        hasShownUpfrontPaywall = true
        vpnManager.presentPaywall()
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
