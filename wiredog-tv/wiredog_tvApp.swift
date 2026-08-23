import SwiftUI

// tvOS app entry point — mirrors wiredog_vpnApp.swift's structure (same app-config gating,
// same privacy-disclosure gate) with PairingView/TVMainTabView standing in for
// iOS's LoginView/MainTabView. Not target-shared with the iOS app; add this file only to
// the new tvOS app target.
@main
struct wiredog_tvApp: App {
    @StateObject private var vpnManager = VPNManager()
    @StateObject private var authService = AuthService.shared
    @StateObject private var appConfigService = AppConfigService.shared
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
                    case .softUpdate, .none:
                        mainContent
                    }
                }
            }
            .preferredColorScheme(.dark)
            .task {
                await appConfigService.checkAppConfig()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if !hasAcceptedDisclosure {
            PrivacyDisclosureView()
        } else if authService.isAuthenticated {
            TVMainTabView(vpnManager: vpnManager)
        } else {
            PairingView()
        }
    }
}
