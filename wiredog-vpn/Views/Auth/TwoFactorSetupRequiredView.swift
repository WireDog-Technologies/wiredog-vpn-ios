#if os(iOS)
import SwiftUI

/// Shown instead of the app when `/auth/me` says the user's organization requires 2FA
/// (`twoFactorRequiredByOrg`) and they have not enrolled (`totpEnabled == false`). Enrollment
/// happens on the website, as it does for Proton VPN: its setup wizard shows the QR code and a
/// manual key, which covers setting up an authenticator on this same phone. The backend also
/// refuses `/vpn/connect` for these members, so this screen is the explanation, not the lock.
struct TwoFactorSetupRequiredView: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.vpnPrimary)

                VStack(spacing: 8) {
                    Text("Two-Factor Authentication Required")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.vpnTextPrimary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(.vpnTextSecondary)
                        .multilineTextAlignment(.center)
                }

                GradientActionButton(
                    title: "Open Dashboard to Set Up",
                    isLoading: false,
                    isDisabled: false,
                    action: openDashboard
                )

                Button(action: refresh) {
                    Text("I've Set It Up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.vpnRedMedium)
                }
                .disabled(authService.isLoading)

                Button(action: { Task { await authService.logout() } }) {
                    Text("Sign Out")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.vpnTextSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        // Coming back from Safari after enrolling: re-check without making the user tap anything.
        .onChange(of: scenePhase) { phase in
            if phase == .active { refresh() }
        }
    }

    private var message: String {
        let org = authService.currentUser?.organizationName.map { "\($0) requires" } ?? "Your organization requires"
        return "\(org) two-factor authentication on your account. Open your dashboard, turn on two-factor authentication, then come back here."
    }

    /// Opens the website dashboard already signed in (one-time handoff code), so the setup wizard
    /// is the first thing the employee sees. Falls back to the plain dashboard URL, which just
    /// asks them to sign in, if the code can't be minted (e.g. offline).
    private func openDashboard() {
        Task {
            let url = (try? await authService.dashboardHandoffURL()) ?? Config.dashboardURL
            openURL(url)
        }
    }

    private func refresh() {
        Task { try? await authService.fetchUserProfile() }
    }
}

#Preview {
    TwoFactorSetupRequiredView()
}
#endif
