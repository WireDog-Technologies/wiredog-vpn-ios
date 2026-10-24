#if os(iOS)
import SwiftUI

/// Shown instead of the paywall when staff have revoked the account (fraud, chargeback, abuse).
/// A personal plan can't fix that, and purchases are refused server-side anyway, so the page says
/// what happened and who to contact. Works for Anonymous accounts, which have no email to tell.
struct RevokedAccountView: View {
    let reason: String?

    @ObservedObject private var authService = AuthService.shared
    @Environment(\.openURL) private var openURL

    private var reasonLine: String? {
        switch reason {
        case "fraud": return "Our systems flagged this account for suspected fraud."
        case "chargeback": return "A payment on this account was disputed with the card issuer."
        case "abuse": return "This account was flagged for a violation of our Terms of Service."
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            Color.vpnBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.vpnRedMedium)

                Text("Account Revoked")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)

                VStack(spacing: 12) {
                    Text("Access to this WireDog account has been removed.")
                        .font(.system(size: 16))
                        .foregroundColor(.vpnTextSecondary)

                    if let reasonLine {
                        Text(reasonLine)
                            .font(.system(size: 16))
                            .foregroundColor(.vpnTextSecondary)
                    }

                    Text("If you believe this was a mistake, contact \(Config.supportEmail).")
                        .font(.system(size: 16))
                        .foregroundColor(.vpnTextPrimary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

                VStack(spacing: 12) {
                    GradientActionButton(title: "Contact Support", isLoading: false, isDisabled: false) {
                        if let url = URL(string: "mailto:\(Config.supportEmail)?subject=Revoked%20account") {
                            openURL(url)
                        }
                    }

                    Button {
                        Task { await authService.logout() }
                    } label: {
                        Text("Sign Out")
                            .font(.system(size: 15))
                            .foregroundColor(.vpnTextSecondary)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}
#endif
