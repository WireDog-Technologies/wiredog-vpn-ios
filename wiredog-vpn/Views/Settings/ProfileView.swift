import SwiftUI

struct ProfileView: View {
    @ObservedObject var vpnManager: VPNManager
    @StateObject private var authService = AuthService.shared
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.openURL) private var openURL
    @State private var showLogoutAlert = false
    @State private var showDeleteAlert = false
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?
    @State private var showDeleteError = false

    private var user: User {
        // Prefer the profile data from authService directly to avoid
        // the VPNManager Combine timing gap on first load
        if let profile = authService.currentUser {
            return User(
                username: profile.username ?? profile.displayName ?? profile.accountNumber ?? "User",
                accountNumber: profile.accountNumber ?? "",
                subscriptionPlan: profile.planTier.rawValue.capitalized,
                subscriptionEndDate: profile.subscriptionExpiresAt ?? Date()
            )
        }
        return vpnManager.user ?? User(
            username: "Unknown",
            accountNumber: "N/A",
            subscriptionPlan: "Free",
            subscriptionEndDate: Date()
        )
    }

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header with Back Button
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
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

                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.vpnTextPrimary)

                        Text("Your account information")
                            .font(.system(size: 14))
                            .foregroundColor(.vpnTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)

                    // Account Info Card
                    VStack(spacing: 0) {
                        HStack {
                            Text("ACCOUNT")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.vpnSecondaryBackground)

                        VStack(spacing: 0) {
                            // Username
                            HStack {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.vpnPrimary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Username")
                                            .font(.system(size: 14))
                                            .foregroundColor(.vpnTextSecondary)

                                        Text(authService.currentUser != nil ? user.username : "Loading...")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.vpnTextPrimary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)

                            Divider()
                                .overlay(Color.vpnBorderColor)

                            // Account Number
                            HStack {
                                HStack(spacing: 12) {
                                    Image(systemName: "number")
                                        .font(.system(size: 16))
                                        .foregroundColor(.vpnPrimary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Account Number")
                                            .font(.system(size: 14))
                                            .foregroundColor(.vpnTextSecondary)

                                        Text(authService.currentUser != nil ? user.accountNumber : "Loading...")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.vpnTextPrimary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)
                        }
                    }
                    .padding(.vertical, 12)

                    // Subscription Info Card
                    VStack(spacing: 0) {
                        HStack {
                            Text("SUBSCRIPTION")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.vpnTextSecondary)
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.vpnSecondaryBackground)

                        VStack(spacing: 0) {
                            // Plan
                            HStack {
                                HStack(spacing: 12) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.vpnYellow)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Plan")
                                            .font(.system(size: 14))
                                            .foregroundColor(.vpnTextSecondary)

                                        Text(user.isSubscriptionActive ? "Active & Paid" : "Not Active")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(user.isSubscriptionActive ? .vpnTextPrimary : .vpnRed)
                                    }
                                }

                                Spacer()
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)

                            Divider()
                                .overlay(Color.vpnBorderColor)

                            // Days Remaining
                            HStack {
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 16))
                                        .foregroundColor(user.isSubscriptionActive ? .vpnGreen : .vpnRed)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Days Remaining")
                                            .font(.system(size: 14))
                                            .foregroundColor(.vpnTextSecondary)

                                        let daysColor: Color = {
                                            if !user.isSubscriptionActive { return .vpnRed }
                                            if user.daysRemaining <= 7 { return .vpnYellow }
                                            return .vpnTextPrimary
                                        }()
                                        Text(user.isSubscriptionActive ? "\(user.daysRemaining) days" : "Expired")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(daysColor)
                                    }
                                }

                                Spacer()
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)
                        }
                    }
                    .padding(.vertical, 12)

                    Spacer(minLength: 20)

                    // Manage Account Button
                    Button(action: {
                        openURL(Config.dashboardURL)
                    }) {
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 16))
                            Text("Manage Account")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(Color.vpnCardBackground)
                        .foregroundColor(.vpnTextPrimary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.vpnBorderColor, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 16)

                    // Sign Out Button
                    Button(action: { showLogoutAlert = true }) {
                        HStack {
                            if authService.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16))
                                Text("Sign Out")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(Color.vpnCardBackground)
                        .foregroundColor(.vpnTextPrimary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.vpnBorderColor, lineWidth: 1)
                        )
                    }
                    .disabled(authService.isLoading)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 16)

                    // Delete Account Button
                    Button(action: { showDeleteAlert = true }) {
                        HStack {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16))
                            Text("Delete Account")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(Color.vpnCardBackground)
                        .foregroundColor(.vpnRed)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.vpnRed.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .onAppear {
            if authService.currentUser == nil {
                Task { try? await authService.fetchUserProfile() }
            }
        }
        .alert("Sign Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    // Disconnect VPN if connected
                    if vpnManager.connectionState == .connected {
                        vpnManager.disconnect()
                    }
                    await authService.logout()
                    presentationMode.wrappedValue.dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                showDeleteConfirm = true
            }
        } message: {
            Text("Are you sure you want to delete your account? This action is permanent and cannot be undone.")
        }
        .alert("Confirm Deletion", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete My Account", role: .destructive) {
                Task {
                    // Disconnect VPN if connected
                    if vpnManager.connectionState == .connected {
                        vpnManager.disconnect()
                    }

                    do {
                        try await authService.deleteAccount()
                        presentationMode.wrappedValue.dismiss()
                    } catch {
                        deleteError = error.localizedDescription
                        showDeleteError = true
                    }
                }
            }
        } message: {
            Text("This will permanently delete all your data. This cannot be recovered.")
        }
        .alert("Deletion Failed", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "An error occurred. Please try again.")
        }
    }
}

#Preview {
    ProfileView(vpnManager: VPNManager())
}
