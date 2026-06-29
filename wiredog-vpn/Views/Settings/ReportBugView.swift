import SwiftUI

struct ReportBugResponse: Codable {
    let message: String
    let issueId: Int
}

struct ReportBugView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var vpnManager: VPNManager

    @State private var subject = ""
    @State private var message = ""
    @State private var email = ""
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var osVersion: String {
        UIDevice.current.systemVersion
    }

    private var deviceModel: String {
        let model = UIDevice.current.model
        return model.contains("iPad") ? "iPad" : "iPhone"
    }

    private var isFormValid: Bool {
        let emailEmpty = email.trimmingCharacters(in: .whitespaces).isEmpty
        let subjectEmpty = subject.trimmingCharacters(in: .whitespaces).isEmpty
        let messageEmpty = message.trimmingCharacters(in: .whitespaces).count < 20
        return !emailEmpty && !subjectEmpty && !messageEmpty
    }

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
                    Text("Report a Bug")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.vpnTextPrimary)

                    Text("Help us improve WireDog VPN")
                        .font(.system(size: 14))
                        .foregroundColor(.vpnTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.vpnTextPrimary)

                            TextField("Your email address", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .padding(12)
                                .background(Color.vpnCardBackground)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Subject")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.vpnTextPrimary)

                            TextField("Brief description of the bug", text: $subject)
                                .padding(12)
                                .background(Color.vpnCardBackground)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 16)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.vpnTextPrimary)

                            Text("Please be as descriptive as possible. Include steps to recreate the issue, what you expected to happen, and what actually happened.")
                                .font(.system(size: 12))
                                .foregroundColor(.vpnTextSecondary)

                            TextEditor(text: $message)
                                .frame(height: 150)
                                .padding(12)
                                .background(Color.vpnCardBackground)
                                .cornerRadius(8)
                                .font(.system(size: 14))
                        }
                        .padding(.horizontal, 16)

                        Button(action: submitBugReport) {
                            HStack {
                                if isSubmitting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isSubmitting ? "Sending..." : "Submit Bug Report")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(isFormValid ? Color.vpnPrimary : Color.vpnTextSecondary.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .font(.system(size: 16, weight: .semibold))
                        }
                        .disabled(!isFormValid || isSubmitting)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 8)
                }

                Spacer()
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {
                if alertTitle == "Bug Report Submitted" {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func submitBugReport() {
        isSubmitting = true

        Task {
            do {
                let emailToSubmit = email.trimmingCharacters(in: .whitespaces)

                let payload: [String: Any] = [
                    "email": emailToSubmit,
                    "username": vpnManager.user?.username,
                    "os": "iOS",
                    "osVersion": osVersion,
                    "vpnVersion": appVersion,
                    "subject": subject.trimmingCharacters(in: .whitespaces),
                    "message": message.trimmingCharacters(in: .whitespaces)
                ]

                let jsonData = try JSONSerialization.data(withJSONObject: payload)
                let url = Config.apiBaseURL.appendingPathComponent("feedback/report-issue")

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData

                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                    DispatchQueue.main.async {
                        isSubmitting = false
                        alertTitle = "Bug Report Submitted"
                        alertMessage = "Thank you for helping us improve WireDog VPN. Our team will review your report shortly."
                        showAlert = true

                        subject = ""
                        message = ""
                        email = ""
                    }
                } else {
                    DispatchQueue.main.async {
                        isSubmitting = false
                        alertTitle = "Error"
                        alertMessage = "Failed to submit bug report. Please try again."
                        showAlert = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isSubmitting = false
                    alertTitle = "Error"
                    alertMessage = "An error occurred. Please try again later."
                    showAlert = true
                }
            }
        }
    }
}

#Preview {
    ReportBugView(vpnManager: VPNManager())
}
