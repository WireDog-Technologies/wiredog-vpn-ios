import SwiftUI

struct PrivacyDisclosureView: View {
    // Which documents the user must accept. `isUpdate` switches from the first-launch copy
    // to "we've updated…" copy naming only what changed.
    let pending: Set<LegalDocument>
    let isUpdate: Bool
    let summary: String?
    let onAccept: () -> Void

    private var termsLink: String { "[Terms of Service](\(Config.termsOfServiceURL.absoluteString))" }
    private var privacyLink: String { "[Privacy Policy](\(Config.privacyPolicyURL.absoluteString))" }

    private var title: String {
        guard isUpdate else { return "We value your privacy" }
        switch (pending.contains(.terms), pending.contains(.privacy)) {
        case (true, true): return "We've updated our Terms and Privacy Policy"
        case (true, false): return "We've updated our Terms of Service"
        default: return "We've updated our Privacy Policy"
        }
    }

    private var agreement: LocalizedStringKey {
        let both = "\(termsLink) and to how we handle data as explained in our \(privacyLink)"
        let text: String
        switch (pending.contains(.terms), pending.contains(.privacy)) {
        case (true, true): text = "you agree to our \(both)"
        case (true, false): text = "you agree to our updated \(termsLink)"
        default: text = "you agree to our updated \(privacyLink)"
        }
        // Built as one String so SwiftUI parses the markdown links; markdown inside values
        // interpolated into a LocalizedStringKey literal is shown verbatim.
        return LocalizedStringKey("By selecting \u{201C}Accept,\u{201D} " + text + ".")
    }

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.vpnTextPrimary)

                    if isUpdate {
                        if let summary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: 15))
                                .foregroundColor(.vpnTextSecondary)
                        }
                    } else {
                        Text("We only collect the bare minimum of information required to offer a smooth and stable VPN experience.")
                            .font(.system(size: 15))
                            .foregroundColor(.vpnTextSecondary)

                        Text("Your browsing activity stays private. We never log the sites you visit or your DNS queries.")
                            .font(.system(size: 15))
                            .foregroundColor(.vpnTextSecondary)
                    }

                    Text(agreement)
                        .font(.system(size: 15))
                        .foregroundColor(.vpnTextSecondary)
                        .tint(.vpnRedMedium)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

                Spacer()

                Button(action: onAccept) {
                    Text("Accept")
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
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    PrivacyDisclosureView(pending: [.privacy, .terms], isUpdate: false, summary: nil, onAccept: {})
}

#Preview("Privacy updated") {
    PrivacyDisclosureView(pending: [.privacy], isUpdate: true, summary: "We clarified how long we keep account data.", onAccept: {})
}
