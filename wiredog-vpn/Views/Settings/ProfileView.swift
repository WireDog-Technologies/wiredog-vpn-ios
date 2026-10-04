import SwiftUI

struct ProfileView: View {
    @ObservedObject var vpnManager: VPNManager
    @StateObject private var authService = AuthService.shared
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.openURL) private var openURL
    @State private var showLogoutAlert = false
    @State private var showLogoutBlockedAlert = false
    @State private var showDeleteAlert = false
    @State private var showDeleteBlockedAlert = false
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

    // Organization seats are paid for and managed by the employer: the plan row says so instead of
    // showing a personal renewal countdown, and account deletion is an admin action
    // (Business decision 2026-09-16: email and deletion are org-locked).
    private var organizationName: String? {
        guard let profile = authService.currentUser, profile.subscriptionManagedByOrganization else { return nil }
        return profile.organizationName ?? "your organization"
    }

    // Set when an organization used to cover this account and no longer does.
    private var organizationAccessLostText: String? {
        switch authService.currentUser?.lostOrganizationAccess {
        case .inactive: return "Organization plan inactive"
        case .revoked: return "Organization access removed"
        default: return nil
        }
    }

    private var isOrganizationMember: Bool {
        authService.currentUser?.isOrganizationMember ?? false
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

                                        if let lostText = organizationAccessLostText {
                                            Text(lostText)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.vpnRed)
                                        } else if let organizationName {
                                            Text("Covered by \(organizationName)")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.vpnTextPrimary)
                                        } else {
                                            Text(user.isSubscriptionActive ? "Active & Paid" : "Not Active")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(user.isSubscriptionActive ? .vpnTextPrimary : .vpnRed)
                                        }
                                    }
                                }

                                Spacer()
                            }
                            .padding(16)
                            .background(Color.vpnCardBackground)

                            if organizationName == nil && organizationAccessLostText == nil {
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
                    Button(action: {
                        if vpnManager.connectionState == .disconnected {
                            showLogoutAlert = true
                        } else {
                            showLogoutBlockedAlert = true
                        }
                    }) {
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

                    // Delete Account Button. Hidden for organization members: only an admin removes them.
                    if isOrganizationMember {
                        Text("Your account is managed by your organization. Contact your administrator to remove it.")
                            .font(.system(size: 12))
                            .foregroundColor(.vpnTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    } else {
                        Button(action: {
                            if vpnManager.connectionState == .disconnected {
                                showDeleteAlert = true
                            } else {
                                showDeleteBlockedAlert = true
                            }
                        }) {
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
                    await authService.logout()
                    presentationMode.wrappedValue.dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Disconnect Required", isPresented: $showLogoutBlockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please disconnect the VPN before signing out.")
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
        .alert("Disconnect Required", isPresented: $showDeleteBlockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please disconnect the VPN before deleting your account.")
        }
    }
}

#Preview {
    ProfileView(vpnManager: VPNManager())
}
