#if os(iOS)
import SwiftUI

/// Shown instead of the app when `/auth/me` says `mustChangePassword`: an organization admin
/// created this account (or reset its password) with a temporary password, and the employee has
/// to replace it before using anything. Mirrors the website's ForcedPasswordChange gate.
struct ForcedPasswordChangeView: View {
    @StateObject private var authService = AuthService.shared
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Set a New Password")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.vpnTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Your administrator gave you a temporary password. Choose your own to continue.")
                            .font(.system(size: 14))
                            .foregroundColor(.vpnTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 8)

                    SecureToggleField(label: "Temporary Password", placeholder: "Enter temporary password", text: $currentPassword)

                    SecureToggleField(label: "New Password", placeholder: "Enter new password", text: $newPassword)

                    SecureToggleField(label: "Confirm Password", placeholder: "Confirm new password", text: $confirmPassword)

                    Text("At least 8 characters, with a letter and a number.")
                        .font(.system(size: 12))
                        .foregroundColor(.vpnTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    GradientActionButton(
                        title: "Change Password",
                        isLoading: authService.isLoading,
                        isDisabled: !isValid,
                        action: submit
                    )

                    Button(action: { Task { await authService.logout() } }) {
                        Text("Sign Out")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.vpnTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .alert("Password Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var isValid: Bool {
        !currentPassword.isEmpty &&
            newPassword.count >= 8 &&
            newPassword.contains(where: { $0.isLetter }) &&
            newPassword.contains(where: { $0.isNumber }) &&
            newPassword == confirmPassword
    }

    private func submit() {
        Task {
            do {
                // On success AuthService reloads the profile; mustChangePassword comes back false
                // and the app root drops this screen.
                try await authService.changePassword(current: currentPassword, new: newPassword)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    ForcedPasswordChangeView()
}
#endif
