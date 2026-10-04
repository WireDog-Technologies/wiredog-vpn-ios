import SwiftUI

// tvOS app entry point — mirrors wiredog_vpnApp.swift's structure (same app-config gating)
// with PairingView/TVMainTabView standing in for iOS's LoginView/MainTabView. Not
// target-shared with the iOS app; add this file only to the new tvOS app target.
//
// Deliberately skips iOS's privacy-disclosure gate: it's voluntary transparency copy, not a
// required consent flow (App Tracking Transparency etc.), the App Privacy Nutrition Label in
// App Store Connect covers the actual review requirement, and the web-based pairing/login step
// this app sends users through already surfaces privacy/terms normally. Also sidesteps a real
// tvOS focus-navigation issue found in manual testing on this screen.
@main
struct wiredog_tvApp: App {
    @StateObject private var vpnManager = VPNManager()
    @StateObject private var authService = AuthService.shared
    @StateObject private var appConfigService = AppConfigService.shared

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
        if authService.isAuthenticated {
            TVMainTabView(vpnManager: vpnManager)
        } else {
            PairingView()
        }
    }
}
