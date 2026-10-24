#if os(iOS)
import SwiftUI

/// The step before the existing delete confirmations. It does three things:
/// 1. Tells people what happens to their billing, so nobody is charged for an account that no
///    longer exists: card plans are cancelled automatically; an Apple subscription is NOT (only
///    the user can cancel it in Apple's Settings); prepaid time is forfeited.
/// 2. Offers "cancel auto-renew but keep my account" to people with a plan.
/// 3. Asks, optionally, why they are leaving (counted anonymously).
///
/// An Apple auto-renew warning never blocks deletion: it links to Apple's page and lets them
/// continue.
struct DeleteAccountFlowView: View {
    let profile: UserProfile?
    /// Called with the chosen reason key and typed text when the user chooses to continue.
    let onContinue: (_ reason: String?, _ otherText: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var otherText = ""
    @State private var appleRenews = false

    private var hasPlan: Bool {
        profile?.hasEntitlement == true && profile?.isOrganizationMember == false
    }

    private var daysLeft: Int {
        guard let end = profile?.subscriptionExpiresAt else { return 0 }
        let today = Calendar.current.startOfDay(for: Date())
        let endDay = Calendar.current.startOfDay(for: end)
        return max(Calendar.current.dateComponents([.day], from: today, to: endDay).day ?? 0, 0)
    }

    private var cardRenews: Bool {
        profile?.autoRenews == true
    }

    var body: some View {
        ZStack {
            Color.vpnBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        if hasPlan {
                            billingSection
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Why are you leaving? (optional)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.vpnTextPrimary)
                            ExitReasonPicker(
                                reasons: ExitReason.deletion,
                                selected: $selected,
                                otherText: $otherText
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                }

                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        onContinue(selected, otherText)
                    } label: {
                        Text("Continue with deleting my account")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.vpnRed)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.vpnRed.opacity(0.5), lineWidth: 1))
                    }

                    Button { dismiss() } label: {
                        Text("Keep my account")
                            .font(.system(size: 15))
                            .foregroundColor(.vpnTextSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .task {
            // Only an active plan can have an Apple subscription worth warning about.
            if hasPlan, !cardRenews {
                appleRenews = await IAPService.shared.isAutoRenewOn()
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hasPlan ? "Before you go" : "Delete your account?")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.vpnTextPrimary)

            if hasPlan {
                Text("Looking to cancel auto-renew, but want to keep your account?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.vpnTextPrimary)
            } else {
                Text("This permanently deletes your account and cannot be undone.")
                    .font(.system(size: 14))
                    .foregroundColor(.vpnTextSecondary)
            }
        }
    }

    @ViewBuilder
    private var billingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if cardRenews {
                Text("Your card subscription will be cancelled automatically when you delete your account, and you won't be charged again.")
                    .font(.system(size: 14))
                    .foregroundColor(.vpnTextSecondary)
                manageButton(title: "Manage subscription") {
                    let url = (try? await AuthService.shared.dashboardHandoffURL()) ?? Config.dashboardURL
                    await UIApplication.shared.open(url)
                }
            } else if appleRenews {
                // Deleting a WireDog account cannot cancel Apple's billing. Say so plainly.
                Text("Your Apple subscription is set to renew. Deleting your WireDog account does not cancel it, and Apple will keep billing you until you cancel in your Apple settings.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.vpnRed)
                manageButton(title: "Manage subscription") {
                    await UIApplication.shared.open(Config.manageAppleSubscriptionsURL)
                }
            } else if daysLeft > 0 {
                Text("You have \(daysLeft) day\(daysLeft == 1 ? "" : "s") of paid time left. It can't be refunded or moved to another account, so it will be lost.")
                    .font(.system(size: 14))
                    .foregroundColor(.vpnTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vpnCardBackground)
        .cornerRadius(12)
    }

    private func manageButton(title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.vpnTextPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.vpnBorderColor, lineWidth: 1))
        }
    }
}
#endif
