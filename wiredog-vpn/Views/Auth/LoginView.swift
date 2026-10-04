import SwiftUI

struct LoginView: View {
    @StateObject private var authService = AuthService.shared
    @Namespace private var tabIndicator
    @State private var selectedTab = 0
    @State private var email = ""
    @State private var password = ""
    @State private var accountNumber = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showForgotPassword = false
    @State private var showSSO = false
    // Set when a password/account-number login came back "2FA required". Held in memory only.
    @State private var twoFactorChallenge: String?
    @State private var showTwoFactor = false

    // Input limits
    private let maxEmailLength = 128
    private let maxPasswordLength = 64
    private let maxAccountNumberLength = 19

    var body: some View {
        NavigationView {
            ZStack {
                Color.vpnBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Logo and title
                    VStack(spacing: 8) {
                        Image("WireDog Head Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 125)

                        Image("WireDog Text Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 75)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)

                    // Tab selector
                    HStack(spacing: 0) {
                        TabButton(title: "Standard Login", isSelected: selectedTab == 0, namespace: tabIndicator) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTab = 0 }
                        }
                        TabButton(title: "Anonymous Login", isSelected: selectedTab == 1, namespace: tabIndicator) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTab = 1 }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Login forms
                    VStack(spacing: 20) {
                        if selectedTab == 0 {
                            standardLoginForm
                        } else {
                            anonymousLoginForm
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)

                    Spacer()

                    // Invisible link that pushes the 2FA code screen once a login asks for it.
                    NavigationLink(
                        destination: TwoFactorCodeView(challengeToken: twoFactorChallenge ?? ""),
                        isActive: $showTwoFactor
                    ) { EmptyView() }
                    .hidden()
                }
            }
            .alert("Login Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
            .onChange(of: showTwoFactor) { isShowing in
                // Backing out of the code screen abandons the challenge; do not keep it around.
                if !isShowing { twoFactorChallenge = nil }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showSSO) {
            SSOLoginView(prefilledEmail: email)
        }
    }

    // MARK: - Standard Login Form

    private var standardLoginForm: some View {
        VStack(spacing: 16) {
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

            SecureToggleField(label: "Password", placeholder: "Enter your password", text: $password)
                .onChange(of: password) { newValue in
                    let sanitized = sanitizePassword(newValue)
                    if sanitized != newValue { password = sanitized }
                }

            GradientActionButton(
                title: "Sign In",
                isLoading: authService.isLoading,
                isDisabled: email.isEmpty || password.isEmpty,
                action: loginStandard
            )
            .padding(.top, 8)

            // Create an account link
            NavigationLink(destination: CreateAccountView()) {
                Text("Create an Account")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.clear)
                    .overlay(
                        LinearGradient(
                            colors: [Color.vpnRedBright, Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .mask(Text("Create an Account").font(.system(size: 16, weight: .medium)))
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Forgot Password link
            Button(action: { showForgotPassword = true }) {
                Text("Forgot Password?")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.clear)
                    .overlay(
                        LinearGradient(
                            colors: [Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .mask(Text("Forgot Password?").font(.system(size: 16, weight: .medium)))
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }

            // Business employees whose organization uses single sign-on
            Button(action: { showSSO = true }) {
                Text("Sign in with SSO")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.vpnTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }

            Spacer()

            // Legal acceptance notice
            VStack(alignment: .center, spacing: 4) {
                HStack(spacing: 3) {
                    Text("By using this application you accept our")
                        .font(.system(size: 12))
                        .foregroundColor(.vpnTextSecondary)
                }

                HStack(spacing: 3) {
                    Link("Terms of Service", destination: Config.termsOfServiceURL)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.vpnRedMedium)

                    Text("and acknowledge our")
                        .font(.system(size: 12))
                        .foregroundColor(.vpnTextSecondary)

                    Link("Privacy Policy", destination: Config.privacyPolicyURL)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.vpnRedMedium)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Anonymous Login Form

    private var anonymousLoginForm: some View {
        VStack(spacing: 16) {
            // Account number field
            VStack(alignment: .leading, spacing: 8) {
                Text("Account Number")
                    .font(.caption)
                    .foregroundColor(.vpnTextSecondary)

                TextField(
                    "",
                    text: $accountNumber,
                    prompt: Text("XXXX-XXXX-XXXX-XXXX").foregroundColor(.vpnTextTertiary)
                )
                .textFieldStyle(VPNTextFieldStyle())
                .keyboardType(.numberPad)
                .onChange(of: accountNumber) { newValue in
                    let sanitized = sanitizeAccountNumber(newValue)
                    if sanitized != newValue { accountNumber = sanitized }
                }
            }

            GradientActionButton(
                title: "Sign In",
                isLoading: authService.isLoading,
                isDisabled: accountNumber.isEmpty,
                action: loginAnonymous
            )
            .padding(.top, 8)

            // Create an account link
            NavigationLink(destination: CreateAccountView()) {
                Text("Create an Account")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.clear)
                    .overlay(
                        LinearGradient(
                            colors: [Color.vpnRedBright, Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .mask(Text("Create an Account").font(.system(size: 16, weight: .medium)))
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }

            Spacer()

            // Legal acceptance notice
            VStack(alignment: .center, spacing: 4) {
                HStack(spacing: 3) {
                    Text("By using this application you accept our")
                        .font(.system(size: 12))
                        .foregroundColor(.vpnTextSecondary)
                }

                HStack(spacing: 3) {
                    Link("Terms of Service", destination: Config.termsOfServiceURL)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.vpnRedMedium)

                    Text("and acknowledge our")
                        .font(.system(size: 12))
                        .foregroundColor(.vpnTextSecondary)

                    Link("Privacy Policy", destination: Config.privacyPolicyURL)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.vpnRedMedium)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Actions

    private func loginStandard() {
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            showError = true
            return
        }

        Task {
            do {
                // SSO members have no password, so a password attempt on an SSO domain could only
                // ever fail with "Invalid credentials". Check first and route them to SSO instead.
                // A failed lookup counts as "no SSO", so a network blip never blocks password login.
                if await authService.ssoAvailable(for: email) {
                    showSSO = true
                    return
                }
                handle(try await authService.loginStandard(email: email, password: password))
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func loginAnonymous() {
        let stripped = accountNumber.replacingOccurrences(of: "-", with: "")
        guard stripped.count == 16 else {
            errorMessage = "Account number must be 16 characters (XXXX-XXXX-XXXX-XXXX)."
            showError = true
            return
        }

        Task {
            do {
                handle(try await authService.loginAnonymous(accountNumber: accountNumber))
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// A signed-in outcome needs nothing here: AuthService flips isAuthenticated and the app swaps
    /// this screen out. Only the 2FA challenge needs UI.
    private func handle(_ outcome: LoginOutcome) {
        if case .twoFactorRequired(let challengeToken) = outcome {
            twoFactorChallenge = challengeToken
            showTwoFactor = true
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

    private func sanitizeAccountNumber(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(16))
        var result = ""
        for (i, char) in limited.enumerated() {
            if i > 0 && i % 4 == 0 { result.append("-") }
            result.append(char)
        }
        return result
    }

    private func isValidEmail(_ email: String) -> Bool {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(email.startIndex..<email.endIndex, in: email)
        let matches = detector?.numberOfMatches(in: email, range: range) ?? 0
        return matches > 0 && email.contains("@")
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .vpnTextPrimary : .vpnTextPrimary.opacity(0.6))

                ZStack {
                    // Fixed-height spacer so both tabs always reserve indicator height
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 3)

                    if isSelected {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(height: 3)
                            .matchedGeometryEffect(id: "tabIndicator", in: namespace)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Text Field Style

struct VPNTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.vpnCardBackground)
            .foregroundColor(.vpnTextPrimary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.vpnBorderColor, lineWidth: 1)
            )
    }
}

#Preview {
    LoginView()
}
