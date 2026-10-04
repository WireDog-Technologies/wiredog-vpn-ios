import SwiftUI

@main
struct wiredog_vpnApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vpnManager = VPNManager()
    @StateObject private var authService = AuthService.shared
    @StateObject private var appConfigService = AppConfigService.shared
    @State private var showSoftUpdate = false
    @AppStorage("hasAcceptedPrivacyDisclosure") private var hasAcceptedDisclosure = false

    var body: some Scene {
        WindowGroup {
            Group {
                if appConfigService.isChecking {
                    LoadingScreenView()
                } else {
                    switch appConfigService.updateAction {
                    case .maintenance:
                        MaintenanceView()
                    case .forceUpdate(let message):
                        ForceUpdateView(message: message)
                    case .softUpdate(let message):
                        mainContent
                            .alert("Update Available", isPresented: $showSoftUpdate) {
                                Button("Later", role: .cancel) {}
                                Button("Update") {
                                    UIApplication.shared.open(Config.appStoreURL)
                                }
                            } message: {
                                Text(message)
                            }
                            .onAppear { showSoftUpdate = true }
                    case .none:
                        mainContent
                    }
                }
            }
            .preferredColorScheme(.dark)
            .task {
                await appConfigService.checkAppConfig()
                BroadcastService.shared.start()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if !hasAcceptedDisclosure {
            PrivacyDisclosureView()
        } else if authService.isAuthenticated {
            // Business accounts can be gated before the app opens. Same order as the website's
            // dashboard: replace the temporary password first, then the org-required 2FA setup.
            if authService.currentUser?.mustChangePassword == true {
                ForcedPasswordChangeView()
            } else if let user = authService.currentUser, user.twoFactorRequiredByOrg, !user.totpEnabled {
                TwoFactorSetupRequiredView()
            } else {
                MainTabView(vpnManager: vpnManager)
            }
        } else {
            LoginView()
        }
    }
}
