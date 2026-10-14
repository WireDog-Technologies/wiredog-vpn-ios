#if os(iOS)
import SwiftUI

/// "Sign in with SSO" sheet: asks for the work email, checks whether that domain has SSO, then
/// hands off to the organization's identity provider in a system browser session.
struct SSOLoginView: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) var dismiss
    @State var email: String
    @State private var showError = false
    @State private var errorMessage = ""

    private let maxEmailLength = 128

    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.vpnPrimary)
                    }
                    Spacer()
                }
                .padding(16)

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Sign In With SSO")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.vpnTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Enter your work email and you'll continue to your organization's sign-in page.")
                            .font(.system(size: 14))
                            .foregroundColor(.vpnTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Work Email")
                            .font(.caption)
                            .foregroundColor(.vpnTextSecondary)

                        TextField(
                            "",
                            text: $email,
                            prompt: Text("you@company.com").foregroundColor(.vpnTextTertiary)
                        )
                        .textFieldStyle(VPNTextFieldStyle())
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: email) { newValue in
                            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@.+-_")
                            let filtered = String(newValue.unicodeScalars.filter { allowed.contains($0) })
                            let limited = String(filtered.prefix(maxEmailLength))
                            if limited != newValue { email = limited }
                        }
                    }

                    GradientActionButton(
                        title: "Continue",
                        isLoading: authService.isLoading,
                        isDisabled: !email.contains("@"),
                        action: start
                    )

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
        }
        .alert("Single Sign-On", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func start() {
        Task {
            do {
                try await authService.signInWithSSO(email: email)
                // Success flips AuthService.isAuthenticated; the app replaces the login screen.
            } catch AuthError.ssoCancelled {
                // The user closed the browser sheet on purpose. Not an error worth an alert.
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    SSOLoginView()
}
#endif
