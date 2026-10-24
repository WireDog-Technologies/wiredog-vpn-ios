#if os(iOS)
import SwiftUI

/// Shown once per account, right after the paywall is first dismissed without buying: one tap on
/// why, all optional. The answer is counted anonymously on the backend and also kept on this
/// device so reminder wording can match it (see ReminderService). Notification permission is not
/// asked here; that happens when the app opens.
struct PaywallExitSheet: View {
    /// Called with the chosen reason key, or nil when the sheet was skipped.
    let onFinish: (String?) -> Void

    @State private var selected: String?
    @State private var otherText = ""
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.vpnBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Not ready yet?")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.vpnTextPrimary)

                            Text("Tell us what's holding you back. It takes one tap and helps us make WireDog better. Your answer isn't linked to your account.")
                                .font(.system(size: 14))
                                .foregroundColor(.vpnTextSecondary)
                        }
                        .padding(.top, 28)

                        ExitReasonPicker(
                            reasons: ExitReason.paywall,
                            selected: $selected,
                            otherText: $otherText,
                            showsPrivacyHint: false
                        )
                    }
                    .padding(.horizontal, 20)
                }

                VStack(spacing: 12) {
                    GradientActionButton(
                        title: "Send",
                        isLoading: isSubmitting,
                        isDisabled: selected == nil || isSubmitting
                    ) {
                        submit()
                    }

                    Button {
                        onFinish(nil)
                        dismiss()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 15))
                            .foregroundColor(.vpnTextSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    private func submit() {
        guard let reason = selected, !isSubmitting else { return }
        isSubmitting = true
        Task {
            await ExitFeedbackService.shared.submit(kind: .paywall, reason: reason, text: otherText)
            onFinish(reason)
            dismiss()
        }
    }
}
#endif
