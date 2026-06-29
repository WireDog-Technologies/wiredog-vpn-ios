import SwiftUI
import UIKit

struct AnonymousAccountView: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) var dismiss

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var generatedAccountNumber: String?
    @State private var showCopyMessage = false

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with back button (only show if still creating)
                if generatedAccountNumber == nil {
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
                }

                if let accountNumber = generatedAccountNumber {
                    // Show account number screen
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.vpnGreen)

                            Text("Account Created!")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.vpnTextPrimary)

                            Text("Your anonymous account is ready")
                                .font(.system(size: 14))
                                .foregroundColor(.vpnTextSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)

                        // Warning box
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.vpnYellow)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Keep This Number Safe")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.vpnTextPrimary)

                                    Text("This account number is your only way to log in. Save it somewhere secure.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.vpnTextSecondary)
                                }
                            }
                            .padding(12)
                            .background(Color.vpnCardBackground)
                            .cornerRadius(8)
                        }

                        // Account number display
                        VStack(spacing: 8) {
                            Text("Your Account Number")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 12) {
                                Text(accountNumber)
                                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.vpnTextPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button(action: copyAccountNumber) {
                                    Image(systemName: "doc.on.doc.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.vpnPrimary)
                                        .padding(.trailing, 4)
                                }
                            }
                            .padding(12)
                            .background(Color.vpnCardBackground)
                            .cornerRadius(8)

                            if showCopyMessage {
                                Text("Copied to clipboard!")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.vpnGreen)
                                    .transition(.opacity)
                            }
                        }

                        // Action buttons
                        VStack(spacing: 12) {
                            GradientActionButton(
                                title: "Got It",
                                isLoading: false,
                                isDisabled: false,
                                action: autoLoginAndDismiss
                            )

                            Button(action: { dismiss() }) {
                                Text("Discard Account")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.vpnRedMedium)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.vpnRedMedium, lineWidth: 1)
                                    )
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                } else {
                    // Loading state
                    VStack(spacing: 24) {
                        Spacer()

                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .vpnPrimary))
                                .scaleEffect(1.5)

                            VStack(spacing: 8) {
                                Text("Creating Your Account")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.vpnTextPrimary)

                                Text("This will only take a moment...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.vpnTextSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            createAccount()
        }
        .alert("Error", isPresented: $showError) {
            Button("Try Again") {
                createAccount()
            }
            Button("Go Back", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func createAccount() {
        Task {
            do {
                let accountNumber = try await authService.registerAnonymous()
                withAnimation {
                    generatedAccountNumber = accountNumber
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func autoLoginAndDismiss() {
        if let accountNumber = generatedAccountNumber {
            Task {
                do {
                    try await authService.loginAnonymous(accountNumber: accountNumber)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func copyAccountNumber() {
        if let accountNumber = generatedAccountNumber {
            // Copy to clipboard with 10-minute auto-expiration
            let pasteboard = UIPasteboard.general
            let items: [[String: Any]] = [["public.utf8-plain-text": accountNumber]]
            pasteboard.setItems(
                items,
                options: [.expirationDate: Date().addingTimeInterval(10 * 60)]
            )
            withAnimation {
                showCopyMessage = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showCopyMessage = false
                }
            }
        }
    }
}

#Preview {
    AnonymousAccountView()
}
