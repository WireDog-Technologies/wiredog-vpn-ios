#if os(iOS)
import SwiftUI

/// "Sign in with SSO" sheet: asks for the work email, checks whether that domain has SSO, then
/// hands off to the organization's identity provider in a system browser session.
struct SSOLoginView: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) var dismiss
    @State var email: String
    // Shown in red under the field, like Android's dedicated SSO page.
    @State private var errorMessage: String?

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
                            prompt: Text("Work Email").foregroundColor(.gray)
                        )
                        .textFieldStyle(VPNTextFieldStyle())
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit(start)
                        .onChange(of: email) { newValue in
                            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@.+-_")
                            let filtered = String(newValue.unicodeScalars.filter { allowed.contains($0) })
                            let limited = String(filtered.prefix(maxEmailLength))
                            if limited != newValue { email = limited }
                            errorMessage = nil
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundColor(.vpnRed)
                        }
                    }

                    GradientActionButton(
                        title: "Sign in with SSO",
                        isLoading: authService.isLoading,
                        isDisabled: email.trimmingCharacters(in: .whitespaces).isEmpty,
                        action: start
                    )

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
        }
        .onAppear {
            // A message left over from the login screen does not belong on this page.
            errorMessage = nil
        }
    }

    private func start() {
        guard looksLikeEmail(email) else {
            errorMessage = "Enter a valid work email address"
            return
        }
        errorMessage = nil
        Task {
            do {
                try await authService.signInWithSSO(email: email)
                // Success flips AuthService.isAuthenticated; the app replaces the login screen.
            } catch {
                // Includes "Single sign-on was cancelled." when the browser sheet is closed.
                errorMessage = error.localizedDescription
            }
        }
    }

    private func looksLikeEmail(_ value: String) -> Bool {
        value.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil
    }
}

#Preview {
    SSOLoginView()
}
#endif
