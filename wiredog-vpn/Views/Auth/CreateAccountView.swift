import SwiftUI

struct CreateAccountView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Logo Section
                VStack(spacing: 8) {
                    Image("WireDog Head Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)

                    Image("WireDog Text Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
                .padding(.bottom, 32)

                // Header Section
                VStack(spacing: 8) {
                    Text("Create an Account")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.vpnTextPrimary)

                    Text("Choose your account type")
                        .font(.system(size: 14))
                        .foregroundColor(.vpnTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                // Account Options
                VStack(spacing: 12) {
                    // Standard Account
                    NavigationLink(destination: StandardAccountView()) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .center, spacing: 0) {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.vpnRedMedium)
                                }
                                .frame(width: 48, height: 48)
                                .background(Color.vpnCardBackground)
                                .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Standard Account")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.vpnTextPrimary)

                                    Text("Email and password required")
                                        .font(.system(size: 13))
                                        .foregroundColor(.vpnTextSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.vpnTextSecondary)
                            }
                            .padding(16)
                        }
                        .background(Color.vpnCardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.vpnBorderColor, lineWidth: 1)
                        )
                    }

                    // Anonymous Account
                    NavigationLink(destination: AnonymousAccountView()) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .center, spacing: 0) {
                                    Image(systemName: "person.crop.circle.badge.questionmark.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.vpnRedMedium)
                                }
                                .frame(width: 48, height: 48)
                                .background(Color.vpnCardBackground)
                                .cornerRadius(8)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Anonymous Account")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.vpnTextPrimary)

                                    Text("16-digit account number only")
                                        .font(.system(size: 13))
                                        .foregroundColor(.vpnTextSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.vpnTextSecondary)
                            }
                            .padding(16)
                        }
                        .background(Color.vpnCardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.vpnBorderColor, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                // Info Section
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.vpnRedMedium)

                            Text("What's the difference?")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.vpnTextPrimary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("•")
                                    .foregroundColor(.vpnTextSecondary)

                                Text("Standard: Use email and password to log in, ability to recover and manage account")
                                    .font(.system(size: 12))
                                    .foregroundColor(.vpnTextSecondary)
                            }

                            HStack(spacing: 8) {
                                Text("•")
                                    .foregroundColor(.vpnTextSecondary)

                                Text("Anonymous: Log in with only a 16-digit account number, maximum privacy")
                                    .font(.system(size: 12))
                                    .foregroundColor(.vpnTextSecondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.vpnCardBackground)
                    .cornerRadius(8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)

                // Sign in link
                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .font(.system(size: 13))
                        .foregroundColor(.vpnTextSecondary)

                    Button(action: { dismiss() }) {
                        Text("Sign In")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.vpnRedMedium)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 20)

                Spacer(minLength: 20)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    CreateAccountView()
}
