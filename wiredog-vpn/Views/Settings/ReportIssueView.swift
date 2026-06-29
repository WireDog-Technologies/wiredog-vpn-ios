import SwiftUI
import MessageUI

struct ReportIssueView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var showMailCompose = false
    @State private var showMailUnavailableAlert = false
    @State private var showBugReport = false
    @ObservedObject var vpnManager: VPNManager

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                        }
                        .foregroundColor(.vpnPrimary)
                    }
                    Spacer()
                }
                .padding(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Report an Issue")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.vpnTextPrimary)

                    Text("Let us know what went wrong")
                        .font(.system(size: 14))
                        .foregroundColor(.vpnTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

                VStack(spacing: 0) {
                    Button(action: {
                        if MFMailComposeViewController.canSendMail() {
                            showMailCompose = true
                        } else {
                            showMailUnavailableAlert = true
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.vpnPrimary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Email Support")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.vpnTextPrimary)

                                Text(Config.supportEmail)
                                    .font(.system(size: 12))
                                    .foregroundColor(.vpnTextSecondary)
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

                    Button(action: { showBugReport = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "ant.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.vpnRed)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Report a Bug")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.vpnTextPrimary)

                                Text("Submit a detailed bug report")
                                    .font(.system(size: 12))
                                    .foregroundColor(.vpnTextSecondary)
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

                    Link(destination: Config.supportURL) {
                        HStack(spacing: 12) {
                            Image(systemName: "safari.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.vpnPrimary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Visit Help Center")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.vpnTextPrimary)

                                Text("Browse FAQs and known issues")
                                    .font(.system(size: 12))
                                    .foregroundColor(.vpnTextSecondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                        }
                        .padding(16)
                        .background(Color.vpnCardBackground)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        .sheet(isPresented: $showMailCompose) {
            MailComposeView(
                recipients: [Config.supportEmail],
                subject: "WireDog VPN – Issue Report",
                body: "\n\n---\nApp Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")\nDevice: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)"
            )
        }
        .sheet(isPresented: $showBugReport) {
            ReportBugView(vpnManager: vpnManager)
        }
        .alert("Mail Not Available", isPresented: $showMailUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please contact us at \(Config.supportEmail)")
        }
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
        }
    }
}

#Preview {
    ReportIssueView(vpnManager: VPNManager())
}
