#if os(iOS)
import SwiftUI

/// Second step of sign-in for an account with 2FA on. Reached from LoginView after the password
/// (or account number) was accepted. The challenge token is held in memory only: it is
/// single-use and short-lived, so it never goes to the Keychain.
struct TwoFactorCodeView: View {
    let challengeToken: String

    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) var dismiss
    @State private var code = ""
    @State private var useRecoveryCode = false
    @State private var showError = false
    @State private var errorMessage = ""
    // The challenge timed out: the alert's OK goes back to the password screen instead of retrying.
    @State private var challengeExpired = false

    private let codeLength = 6
    private let maxRecoveryCodeLength = 15

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
                        Text("Two-Factor Authentication")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.vpnTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(useRecoveryCode
                             ? "Enter one of your saved recovery codes. Each code works once."
                             : "Enter the 6-digit code from your authenticator app.")
                            .font(.system(size: 14))
                            .foregroundColor(.vpnTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(useRecoveryCode ? "Recovery Code" : "Authentication Code")
                            .font(.caption)
                            .foregroundColor(.vpnTextSecondary)

                        TextField(
                            "",
                            text: $code,
                            prompt: Text(useRecoveryCode ? "Recovery code" : "000000").foregroundColor(.vpnTextTertiary)
                        )
                        .textFieldStyle(VPNTextFieldStyle())
                        .textContentType(useRecoveryCode ? nil : .oneTimeCode)
                        .keyboardType(useRecoveryCode ? .asciiCapable : .numberPad)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: code) { newValue in
                            let sanitized = sanitize(newValue)
                            if sanitized != newValue { code = sanitized }
                            // Authenticator codes are always 6 digits, so submit as soon as the
                            // last one lands (including an autofill from the keyboard bar).
                            if !useRecoveryCode, sanitized.count == codeLength, !authService.isLoading {
                                submit()
                            }
                        }
                    }

                    GradientActionButton(
                        title: "Verify",
                        isLoading: authService.isLoading,
                        isDisabled: code.isEmpty || (!useRecoveryCode && code.count < codeLength),
                        action: submit
                    )

                    Button(action: toggleRecoveryMode) {
                        Text(useRecoveryCode ? "Use authenticator code instead" : "Use a recovery code instead")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.vpnRedMedium)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Verification Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                if challengeExpired { dismiss() }
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func toggleRecoveryMode() {
        useRecoveryCode.toggle()
        code = ""
    }

    private func sanitize(_ input: String) -> String {
        if useRecoveryCode {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
            let filtered = String(input.unicodeScalars.filter { allowed.contains($0) })
            return String(filtered.prefix(maxRecoveryCodeLength))
        }
        return String(input.filter { $0.isNumber }.prefix(codeLength))
    }

    private func submit() {
        guard !authService.isLoading, !code.isEmpty else { return }
        Task {
            do {
                try await authService.verifyTwoFactor(challengeToken: challengeToken, code: code)
                // On success AuthService flips isAuthenticated and the app swaps this whole
                // navigation stack for the main tabs, so there is nothing to dismiss here.
            } catch {
                if let authError = error as? AuthError, case .twoFactorChallengeExpired = authError {
                    challengeExpired = true
                }
                errorMessage = error.localizedDescription
                showError = true
                code = ""
            }
        }
    }
}

#Preview {
    NavigationView {
        TwoFactorCodeView(challengeToken: String(repeating: "a", count: 64))
    }
}
#endif
