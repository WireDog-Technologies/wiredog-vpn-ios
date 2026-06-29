import SwiftUI

struct StandardAccountView: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""

    // Input limits
    private let maxEmailLength = 128
    private let maxPasswordLength = 64

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

                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("Create Standard Account")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.vpnTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Sign up with your email and password")
                            .font(.system(size: 14))
                            .foregroundColor(.vpnTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 12)

                    // Email field
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
                        .onChange(of: email) { newValue in
                            let sanitized = sanitizeEmail(newValue)
                            if sanitized != newValue { email = sanitized }
                        }
                    }

                    SecureToggleField(label: "Password", placeholder: "Enter password", text: $password)
                        .onChange(of: password) { newValue in
                            let sanitized = sanitizePassword(newValue)
                            if sanitized != newValue { password = sanitized }
                        }

                    SecureToggleField(label: "Confirm Password", placeholder: "Confirm password", text: $confirmPassword)
                        .onChange(of: confirmPassword) { newValue in
                            let sanitized = sanitizePassword(newValue)
                            if sanitized != newValue { confirmPassword = sanitized }
                        }

                    GradientActionButton(
                        title: "Create Account",
                        isLoading: authService.isLoading,
                        isDisabled: email.isEmpty || password.isEmpty || confirmPassword.isEmpty,
                        action: submitForm
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func submitForm() {
        // Validate email format
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            showError = true
            return
        }

        // Validate passwords match
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            showError = true
            return
        }

        // Validate password requirements
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            showError = true
            return
        }

        guard password.contains(where: { $0.isLetter }) else {
            errorMessage = "Password must contain at least one letter"
            showError = true
            return
        }

        guard password.contains(where: { $0.isNumber }) else {
            errorMessage = "Password must contain at least one number"
            showError = true
            return
        }

        Task {
            do {
                try await authService.registerStandard(
                    email: email,
                    password: password
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Input Sanitization

    private func sanitizeEmail(_ input: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@.+-_")
        let filtered = String(input.unicodeScalars.filter { allowed.contains($0) })
        return String(filtered.prefix(maxEmailLength))
    }

    private func sanitizePassword(_ input: String) -> String {
        let filtered = input.filter { char in
            guard let ascii = char.asciiValue else { return false }
            return ascii >= 0x20 && ascii <= 0x7E
        }
        return String(filtered.prefix(maxPasswordLength))
    }

    private func isValidEmail(_ email: String) -> Bool {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(email.startIndex..<email.endIndex, in: email)
        let matches = detector?.numberOfMatches(in: email, range: range) ?? 0
        return matches > 0 && email.contains("@")
    }
}

#Preview {
    StandardAccountView()
}
