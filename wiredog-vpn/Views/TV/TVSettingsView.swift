import SwiftUI

// tvOS-only. No password/account-number change flows here — this app never collected
// credentials in the first place (see PairingView), so there's nothing to edit locally.
struct TVSettingsView: View {
    @ObservedObject var vpnManager: VPNManager
    @ObservedObject private var authService = AuthService.shared

    var body: some View {
        List {
            Section("Account") {
                if let user = vpnManager.user {
                    LabeledContent("Signed in as", value: user.username)
                    LabeledContent("Plan", value: user.subscriptionPlan)
                }
                Button("Sign Out") {
                    Task { await authService.logout() }
                }
            }

            Section("Connection") {
                Toggle("Kill Switch", isOn: $vpnManager.settings.isKillSwitchEnabled)
                Toggle("Auto-Connect", isOn: $vpnManager.settings.isAutoConnectEnabled)
                Toggle("IPv6", isOn: $vpnManager.settings.isIPv6Enabled)
                Toggle("Local Network Access", isOn: $vpnManager.settings.isLANAccessEnabled)
            }

            Section("DNS Filtering") {
                Toggle("Block Ads", isOn: $vpnManager.settings.isBlockAdsEnabled)
                Toggle("Block Malware", isOn: $vpnManager.settings.isBlockMalwareEnabled)
            }
        }
    }
}
