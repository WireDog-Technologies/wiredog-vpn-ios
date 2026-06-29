import SwiftUI

struct SettingsView: View {
    @ObservedObject var vpnManager: VPNManager
    @State private var showProfile = false
    @State private var showLogs = false
    @State private var showChangeLog = false
    @State private var showReportIssue = false
    @State private var showReconnectWarning = false

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(version) (build \(build))"
    }

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Settings")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.vpnTextPrimary)

                        Text("Configure your VPN preferences")
                            .font(.system(size: 14))
                            .foregroundColor(.vpnTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)

                    // ACCOUNT SECTION
                    VStack(spacing: 0) {
                        HStack {
                            Text("ACCOUNT")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.vpnSecondaryBackground)

                        VStack(spacing: 0) {
                            // Profile
                            Button(action: { showProfile = true }) {
                                HStack {
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.vpnPrimary)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("View Profile")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.vpnTextPrimary)

                                            Text(vpnManager.user?.username ?? "")
                                                .font(.system(size: 12))
                                                .foregroundColor(.vpnTextSecondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                                .padding(16)
                                .background(Color.vpnCardBackground)
                            }
                        }
                    }
                    .padding(.vertical, 12)

                    // LEGAL SECTION
                    HStack(spacing: 12) {
                        Link("Privacy Policy", destination: Config.privacyPolicyURL)
                            .font(.system(size: 13))
                            .foregroundColor(.vpnPrimary)

                        Text("•")
                            .foregroundColor(.vpnTextSecondary)

                        Link("Terms of Service", destination: Config.termsOfServiceURL)
                            .font(.system(size: 13))
                            .foregroundColor(.vpnPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)

                    // CONNECTION SECTION
                    VStack(spacing: 0) {
                        HStack {
                            Text("CONNECTION")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.vpnSecondaryBackground)

                        VStack(spacing: 0) {
                            // Protocol
                            HStack {
                                HStack(spacing: 12) {
                                    Image(systemName: "network")
                                        .font(.system(size: 16))
                                        .foregroundColor(.vpnPrimary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Protocol")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.vpnTextPrimary)

                                        Text("Only AmneziaWG is currently supported")
                                            .font(.system(size: 12))
                                            .foregroundColor(.vpnTextSecondary)
                                    }
                                }

                                Spacer()

                                Text(vpnManager.settings.protocolType)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.vpnPrimary)
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)

                            Divider()
                                .overlay(Color.vpnBorderColor)

                            // Kill Switch
                            HStack(spacing: 12) {
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.vpnRed)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Kill Switch")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.vpnTextPrimary)

                                    Text("Block all traffic if VPN connection drops")
                                        .font(.system(size: 12))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Toggle("", isOn: $vpnManager.settings.isKillSwitchEnabled)
                                    .tint(.vpnGreen)
                                    .labelsHidden()
                                    .onChange(of: vpnManager.settings.isKillSwitchEnabled) { _ in
                                        if vpnManager.connectionState == .connected {
                                            showReconnectWarning = true
                                        }
                                    }
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)

                            Divider()
                                .overlay(Color.vpnBorderColor)

                            // Auto-Connect
                            HStack(spacing: 12) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.vpnYellow)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Auto-Connect")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.vpnTextPrimary)

                                    Text("Automatically connect to the last used server on device startup")
                                        .font(.system(size: 12))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Toggle("", isOn: $vpnManager.settings.isAutoConnectEnabled)
                                    .tint(.vpnGreen)
                                    .labelsHidden()
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)

                            Divider()
                                .overlay(Color.vpnBorderColor)

                            // IPv6
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .font(.system(size: 16))
                                    .foregroundColor(.vpnPrimary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("IPv6 Connections")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.vpnTextPrimary)

                                    Text("Configure IPv6 and leak protection")
                                        .font(.system(size: 12))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Toggle("", isOn: $vpnManager.settings.isIPv6Enabled)
                                    .tint(.vpnGreen)
                                    .labelsHidden()
                                    .onChange(of: vpnManager.settings.isIPv6Enabled) { _ in
                                        if vpnManager.connectionState == .connected {
                                            showReconnectWarning = true
                                        }
                                    }
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)

                            Divider()
                                .overlay(Color.vpnBorderColor)

                            // LAN Access
                            HStack(spacing: 12) {
                                Image(systemName: "wifi")
                                    .font(.system(size: 16))
                                    .foregroundColor(.vpnPrimary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Allow LAN Access")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.vpnTextPrimary)

                                    Text("Access local network devices while connected")
                                        .font(.system(size: 12))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Toggle("", isOn: $vpnManager.settings.isLANAccessEnabled)
                                    .tint(.vpnGreen)
                                    .labelsHidden()
                                    .onChange(of: vpnManager.settings.isLANAccessEnabled) { _ in
                                        if vpnManager.connectionState == .connected {
                                            showReconnectWarning = true
                                        }
                                    }
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)

                        }
                    }
                    .padding(.vertical, 12)

                    // SUPPORT SECTION
                    VStack(spacing: 0) {
                        HStack {
                            Text("SUPPORT")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.vpnSecondaryBackground)

                        VStack(spacing: 0) {
                            // View Logs
                            Button(action: { showLogs = true }) {
                                HStack {
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.text.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.vpnTextSecondary)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("View Logs")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.vpnTextPrimary)

                                            Text("Application and service diagnostic logs")
                                                .font(.system(size: 12))
                                                .foregroundColor(.vpnTextSecondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                                .padding(16)
                                .background(Color.vpnCardBackground)
                            }

                            Divider()
                                .overlay(Color.vpnBorderColor)

                            // Change Log
                            Button(action: { showChangeLog = true }) {
                                HStack {
                                    HStack(spacing: 12) {
                                        Image(systemName: "list.bullet.rectangle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.vpnPrimary)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Change Log")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.vpnTextPrimary)

                                            Text("View recent updates and release notes")
                                                .font(.system(size: 12))
                                                .foregroundColor(.vpnTextSecondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                                .padding(16)
                                .background(Color.vpnCardBackground)
                            }

                            Divider()
                                .overlay(Color.vpnBorderColor)

                            // Report an Issue
                            Button(action: { showReportIssue = true }) {
                                HStack {
                                    HStack(spacing: 12) {
                                        Image(systemName: "exclamationmark.bubble.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.vpnRed)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Report an Issue")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.vpnTextPrimary)

                                            Text("Contact support or report a bug")
                                                .font(.system(size: 12))
                                                .foregroundColor(.vpnTextSecondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                                .padding(16)
                                .background(Color.vpnCardBackground)
                            }
                        }
                    }
                    .padding(.vertical, 12)

                    Text(appVersion)
                        .font(.system(size: 11))
                        .foregroundColor(.vpnTextSecondary.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(vpnManager: vpnManager)
        }
        .sheet(isPresented: $showLogs) {
            NavigationView {
                LogsView()
            }
        }
        .sheet(isPresented: $showChangeLog) {
            ChangeLogView()
        }
        .sheet(isPresented: $showReportIssue) {
            ReportIssueView(vpnManager: vpnManager)
        }
        .alert("Reconnect Required", isPresented: $showReconnectWarning) {
            Button("Later", role: .cancel) {}
            Button("Reconnect Now") {
                if let server = vpnManager.selectedServer {
                    vpnManager.disconnect()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        vpnManager.connect(to: server)
                    }
                }
            }
        } message: {
            Text("Reconnect for changes to take effect.")
        }
    }
}

#Preview {
    SettingsView(vpnManager: VPNManager())
}
