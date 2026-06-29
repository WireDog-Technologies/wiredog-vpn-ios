import SwiftUI

struct PrivacyDisclosureView: View {
    @AppStorage("hasAcceptedPrivacyDisclosure") private var hasAccepted = false

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .center, spacing: 24) {
                    // Title and subtitle
                    VStack(spacing: 8) {
                        Text("Your Privacy, Our Commitment")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.vpnTextPrimary)

                        Text("Before you continue, here's what you should know about how WireDog handles your data.")
                            .font(.system(size: 14))
                            .foregroundColor(.vpnTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    // Data disclosure card
                    VStack(spacing: 20) {
                        // What we collect
                        VStack(spacing: 12) {
                            SectionHeader(title: "WHAT WE COLLECT")

                            DisclosureRow(
                                symbol: "checkmark.shield",
                                text: "Your account credentials (email or account number) for authentication",
                                isPositive: true
                            )

                            DisclosureRow(
                                symbol: "checkmark.shield",
                                text: "The VPN server you choose to connect to",
                                isPositive: true
                            )

                            DisclosureRow(
                                symbol: "checkmark.shield",
                                text: "A session ID assigned by our server (used to manage your connection, not linked to you)",
                                isPositive: true
                            )
                        }

                        Divider()
                            .background(Color.vpnBorderColor)

                        // What we do NOT collect
                        VStack(spacing: 12) {
                            SectionHeader(title: "WHAT WE DO NOT COLLECT")

                            DisclosureRow(
                                symbol: "xmark.circle",
                                text: "Your browsing history or DNS queries",
                                isPositive: false
                            )

                            DisclosureRow(
                                symbol: "xmark.circle",
                                text: "Your bandwidth usage (stored locally on your device only)",
                                isPositive: false
                            )

                            DisclosureRow(
                                symbol: "xmark.circle",
                                text: "Your device identifiers or location",
                                isPositive: false
                            )

                            DisclosureRow(
                                symbol: "xmark.circle",
                                text: "Your public IP address (displayed locally only - never sent to us)",
                                isPositive: false
                            )
                        }

                        Divider()
                            .background(Color.vpnBorderColor)

                        // Logs
                        VStack(spacing: 12) {
                            SectionHeader(title: "YOUR LOGS")

                            Text("App and connection logs are stored on your device only. They are only shared with us if you choose to submit a support report.")
                                .font(.system(size: 13))
                                .foregroundColor(.vpnTextSecondary)
                                .lineSpacing(1.5)
                        }
                    }
                    .padding(16)
                    .background(Color.vpnCardBackground)
                    .cornerRadius(12)
                    .padding(.horizontal, 24)

                    // Privacy policy link
                    Link(destination: Config.privacyPolicyURL) {
                        Text("Read our full Privacy Policy")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.vpnRedMedium)
                    }
                    .padding(.vertical, -14)

                    // CTA Button
                    Button(action: { hasAccepted = true }) {
                        Text("Agree & Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                LinearGradient(
                                    colors: [Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 0)
                    .padding(.bottom, 40)
                }
                .padding(.vertical, 24)
            }
            }
        }
    }

// MARK: - Helper Views

private struct DisclosureRow: View {
    let symbol: String
    let text: String
    let isPositive: Bool

    var symbolColor: Color {
        isPositive ? Color.vpnGreen : Color.vpnRedMedium
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(symbolColor)
                .frame(width: 20)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.vpnTextSecondary)
                .lineSpacing(1.2)
                .lineLimit(nil)

            Spacer()
        }
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.vpnTextSecondary)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PrivacyDisclosureView()
}
