import SwiftUI

@main
struct wiredog_vpnApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vpnManager = VPNManager()
    @StateObject private var authService = AuthService.shared
    @StateObject private var appConfigService = AppConfigService.shared
    @State private var showSoftUpdate = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(LegalAcceptance.legacyAcceptedKey) private var hasAcceptedDisclosure = false
    @AppStorage(LegalAcceptance.privacyKey) private var acceptedPrivacyVersion = ""
    @AppStorage(LegalAcceptance.termsKey) private var acceptedTermsVersion = ""

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
            .onChange(of: scenePhase) { phase in
                // Pick up a legal-version bump without waiting for a cold launch.
                if phase == .active { Task { await appConfigService.checkAppConfig() } }
            }
            .onChange(of: appConfigService.legal) { legal in
                adoptLegacyAcceptance(legal)
            }
        }
    }

    private var pendingLegal: Set<LegalDocument> {
        LegalAcceptance.pending(
            legal: appConfigService.legal,
            acceptedPrivacy: acceptedPrivacyVersion,
            acceptedTerms: acceptedTermsVersion,
            legacyAccepted: hasAcceptedDisclosure
        )
    }

    private func adoptLegacyAcceptance(_ legal: LegalVersions?) {
        guard let legal else { return }
        let adopted = LegalAcceptance.adoptLegacyAcceptance(
            legal: legal,
            acceptedPrivacy: acceptedPrivacyVersion,
            acceptedTerms: acceptedTermsVersion,
            legacyAccepted: hasAcceptedDisclosure
        )
        acceptedPrivacyVersion = adopted.privacy
        acceptedTermsVersion = adopted.terms
    }

    private func acceptLegal(_ pending: Set<LegalDocument>) {
        // Only record versions for documents actually shown; with no config (first launch
        // offline) the legacy flag alone marks acceptance and versions are adopted later.
        if let legal = appConfigService.legal {
            if pending.contains(.privacy) { acceptedPrivacyVersion = legal.privacyVersion }
            if pending.contains(.terms) { acceptedTermsVersion = legal.termsVersion }
        }
        hasAcceptedDisclosure = true
    }

    @ViewBuilder
    private var mainContent: some View {
        let pending = pendingLegal
        if !pending.isEmpty {
            PrivacyDisclosureView(
                pending: pending,
                isUpdate: LegalAcceptance.isUpdate(
                    acceptedPrivacy: acceptedPrivacyVersion,
                    acceptedTerms: acceptedTermsVersion,
                    legacyAccepted: hasAcceptedDisclosure
                ),
                summary: appConfigService.legal?.summary,
                onAccept: { acceptLegal(pending) }
            )
        } else if authService.isAuthenticated {
            // Business accounts can be gated before the app opens. Same order as the website's
            // dashboard: replace the temporary password first, then the org-required 2FA setup.
            if authService.currentUser?.mustChangePassword == true {
                ForcedPasswordChangeView()
            } else if let user = authService.currentUser, user.twoFactorRequiredByOrg, !user.totpEnabled {
                TwoFactorSetupRequiredView()
            } else if let user = authService.currentUser, user.isRevoked {
                // Staff removed this account's access; a plan or paywall can't fix that.
                RevokedAccountView(reason: user.revokedReason)
            } else {
                MainTabView(vpnManager: vpnManager)
            }
        } else {
            LoginView()
        }
    }
}
