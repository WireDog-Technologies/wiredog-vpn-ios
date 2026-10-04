import SwiftUI

// tvOS-only. No password/account-number change flows here — this app never collected
// credentials in the first place (see PairingView), so there's nothing to edit locally.
// Styled to match TVHomeView (same background, card, and section-header treatment) rather
// than a plain system List, which looked visually inconsistent with the Home tab.
struct TVSettingsView: View {
    @ObservedObject var vpnManager: VPNManager
    @ObservedObject private var authService = AuthService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                Text("Settings")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)

                accountSection
                connectionSection
                dnsSection
            }
            .padding(80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vpnBackground)
    }

    // MARK: - Sections

    private var accountSection: some View {
        section(title: "Account") {
            if let profile = authService.currentUser {
                infoRow(label: "Signed in as", value: signedInAsValue(for: profile))
                divider()
                infoRow(label: "Account Number", value: profile.accountNumber ?? "—")
                divider()
                infoRow(
                    label: "Plan",
                    value: isSubscriptionActive(profile) ? "Active & Paid" : "Not Active",
                    valueColor: isSubscriptionActive(profile) ? .vpnTextPrimary : .vpnRed
                )
                divider()
                infoRow(
                    label: "Days Remaining",
                    value: isSubscriptionActive(profile) ? "\(daysRemaining(profile)) days" : "Expired",
                    valueColor: daysRemainingColor(profile)
                )
                divider()
            }

            Button(action: { Task { await authService.logout() } }) {
                Text("Sign Out")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.vpnRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .buttonStyle(.plain)
        }
        .task {
            if authService.currentUser == nil {
                try? await authService.fetchUserProfile()
            }
        }
    }

    // Anonymous accounts have no username — mirrors ProfileView's "if anonymous, say so"
    // treatment rather than falling back to the account number, which reads like a username.
    private func signedInAsValue(for profile: UserProfile) -> String {
        if profile.accountType == .anonymous {
            return "Anonymous"
        }
        return profile.username ?? profile.displayName ?? profile.accountNumber ?? "User"
    }

    private func isSubscriptionActive(_ profile: UserProfile) -> Bool {
        guard let expires = profile.subscriptionExpiresAt else { return false }
        return expires > Date()
    }

    private func daysRemaining(_ profile: UserProfile) -> Int {
        guard let expires = profile.subscriptionExpiresAt else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let expiresStart = calendar.startOfDay(for: expires)
        let days = calendar.dateComponents([.day], from: today, to: expiresStart).day ?? 0
        return max(days, 0)
    }

    private func daysRemainingColor(_ profile: UserProfile) -> Color {
        guard isSubscriptionActive(profile) else { return .vpnRed }
        return daysRemaining(profile) <= 7 ? .vpnYellow : .vpnTextPrimary
    }

    private var connectionSection: some View {
        section(title: "Connection") {
            toggleRow("Kill Switch", isOn: $vpnManager.settings.isKillSwitchEnabled)
            divider()
            toggleRow("Auto-Connect", isOn: $vpnManager.settings.isAutoConnectEnabled)
        }
    }

    private var dnsSection: some View {
        section(title: "DNS Filtering") {
            toggleRow("Block Ads", isOn: $vpnManager.settings.isBlockAdsEnabled)
            divider()
            toggleRow("Block Malware", isOn: $vpnManager.settings.isBlockMalwareEnabled)
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundColor(.vpnTextPrimary)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.vpnCardBackground)
            .cornerRadius(16)
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

    private func infoRow(label: String, value: String, valueColor: Color = .vpnTextPrimary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.vpnTextSecondary)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .fontWeight(.semibold)
        }
        .font(.body)
        .padding(20)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .foregroundColor(.vpnTextPrimary)
                .font(.body)
        }
        .padding(20)
    }

    private func divider() -> some View {
        Rectangle()
            .fill(Color.vpnBorderColor)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }
}
