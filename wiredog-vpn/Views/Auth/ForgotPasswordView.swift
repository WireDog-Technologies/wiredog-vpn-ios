import SwiftUI

struct ForgotPasswordView: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) var dismiss

    @State private var currentStep: PasswordResetStep = .emailInput
    @State private var email = ""
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    // Set by the code-verification step when the account has 2FA on; the reset then also needs a
    // current authenticator (or recovery) code.
    @State private var twoFactorRequired = false
    @State private var twoFactorCode = ""
    @State private var showResetSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with back button
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

                // Content based on step
                Group {
                    switch currentStep {
                    case .emailInput:
                        emailInputStep
                    case .codeVerification:
                        codeVerificationStep
                    case .passwordReset:
                        passwordResetStep
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Password Updated", isPresented: $showResetSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your password was changed. Sign in with your new password.")
        }
    }

    // MARK: - Email Input Step

    private var emailInputStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Reset Your Password")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Enter the email associated with your account")
                    .font(.system(size: 14))
                    .foregroundColor(.vpnTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.caption)
                    .foregroundColor(.vpnTextSecondary)

                TextField(
                    "",
                    text: $email,
                    prompt: Text("Enter your email").foregroundColor(.vpnTextTertiary)
                )
                .textFieldStyle(VPNTextFieldStyle())
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            }

            GradientActionButton(
                title: "Send Reset Code",
                isLoading: authService.isLoading,
                isDisabled: email.isEmpty,
                action: submitEmail
            )

            VStack(spacing: 8) {
                Text("If an account under this email exists, instructions to reset your password will be sent.")
                    .font(.system(size: 12))
                    .foregroundColor(.vpnTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Code Verification Step

    private var codeVerificationStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Verify Reset Code")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Enter the 6-digit code sent to your email")
                    .font(.system(size: 14))
                    .foregroundColor(.vpnTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Reset Code")
                    .font(.caption)
                    .foregroundColor(.vpnTextSecondary)

                TextField(
                    "",
                    text: $resetCode,
                    prompt: Text("000000").foregroundColor(.vpnTextTertiary)
                )
                .textFieldStyle(VPNTextFieldStyle())
                .keyboardType(.numberPad)
                .onChange(of: resetCode) { newValue in
                    resetCode = String(newValue.prefix(6))
                }
            }

            GradientActionButton(
                title: "Verify Code",
                isLoading: authService.isLoading,
                isDisabled: resetCode.count < 6,
                action: submitCode
            )

            VStack(spacing: 8) {
                Text("Code expires in 10 minutes")
                    .font(.system(size: 12))
                    .foregroundColor(.vpnTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer()
        }
    }

    // MARK: - Password Reset Step

    private var passwordResetStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Create New Password")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Enter and confirm your new password")
                    .font(.system(size: 14))
                    .foregroundColor(.vpnTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 16)

            SecureToggleField(label: "New Password", placeholder: "Enter new password", text: $newPassword)

            SecureToggleField(label: "Confirm Password", placeholder: "Confirm password", text: $confirmPassword)

            if twoFactorRequired {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Two-Factor Code")
                        .font(.caption)
                        .foregroundColor(.vpnTextSecondary)

                    TextField(
                        "",
                        text: $twoFactorCode,
                        prompt: Text("Authenticator or recovery code").foregroundColor(.vpnTextTertiary)
                    )
                    .textFieldStyle(VPNTextFieldStyle())
                    .textContentType(.oneTimeCode)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: twoFactorCode) { newValue in
                        twoFactorCode = String(newValue.prefix(15))
                    }

                    Text("Your account has two-factor authentication on. Enter a code from your authenticator app, or a recovery code.")
                        .font(.system(size: 12))
                        .foregroundColor(.vpnTextSecondary)
                }
            }

            GradientActionButton(
                title: "Reset Password",
                isLoading: authService.isLoading,
                isDisabled: !isPasswordValid,
                action: submitPassword
            )

            Spacer()
        }
    }

    // MARK: - Actions

    private func submitEmail() {
        guard email.contains("@") && email.contains(".") else {
            errorMessage = "Please enter a valid email address."
            showError = true
            return
        }

        Task {
            do {
                try await authService.forgotPassword(email: email)
                withAnimation {
                    currentStep = .codeVerification
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func submitCode() {
        guard resetCode.count == 6 else {
            errorMessage = "Please enter a valid 6-digit code."
            showError = true
            return
        }

        Task {
            do {
                twoFactorRequired = try await authService.verifyResetCode(email: email, code: resetCode)
                withAnimation {
                    currentStep = .passwordReset
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func submitPassword() {
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match."
            showError = true
            return
        }

        guard newPassword.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            showError = true
            return
        }

        guard newPassword.contains(where: { $0.isLetter }) else {
            errorMessage = "Password must contain at least one letter"
            showError = true
            return
        }

        guard newPassword.contains(where: { $0.isNumber }) else {
            errorMessage = "Password must contain at least one number"
            showError = true
            return
        }

        Task {
            do {
                let signedIn = try await authService.resetPassword(
                    email: email,
                    code: resetCode,
                    newPassword: newPassword,
                    twoFactorCode: twoFactorRequired ? twoFactorCode : nil
                )
                if signedIn {
                    dismiss()
                } else {
                    // 2FA accounts are not auto-signed-in (see AuthService.resetPassword).
                    showResetSuccess = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private var isPasswordValid: Bool {
        newPassword.count >= 8 &&
            newPassword.contains(where: { $0.isLetter }) &&
            newPassword.contains(where: { $0.isNumber }) &&
            newPassword == confirmPassword &&
            !newPassword.isEmpty &&
            (!twoFactorRequired || !twoFactorCode.isEmpty)
    }
}

// MARK: - Password Reset Step Enum

enum PasswordResetStep {
    case emailInput
    case codeVerification
    case passwordReset
}

#Preview {
    ForgotPasswordView()
}
