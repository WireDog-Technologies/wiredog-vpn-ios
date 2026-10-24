#if os(iOS)
import SwiftUI

/// Pick-one list of reasons, with a short text box under "Other". Used by the paywall exit sheet
/// and the account-deletion flow. Typed text is filtered as it is entered (see FeedbackText) and
/// again by the server.
struct ExitReasonPicker: View {
    let reasons: [ExitReason]
    @Binding var selected: String?
    @Binding var otherText: String
    /// Adds "Please don't include personal information." under the counter.
    var showsPrivacyHint = true

    var body: some View {
        VStack(spacing: 10) {
            ForEach(reasons) { reason in
                Button {
                    selected = (selected == reason.key) ? nil : reason.key
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(selected == reason.key ? Color.vpnRedMedium : Color.vpnBorderColor, lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                            if selected == reason.key {
                                Circle()
                                    .fill(Color.vpnRedMedium)
                                    .frame(width: 12, height: 12)
                            }
                        }
                        Text(reason.label)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.vpnTextPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.vpnCardBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selected == reason.key ? Color.vpnRedMedium : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }

            if selected == ExitReason.otherKey {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "",
                        text: $otherText,
                        prompt: Text("Tell us more (optional)").foregroundColor(.vpnTextTertiary)
                    )
                    .textFieldStyle(VPNTextFieldStyle())
                    .onChange(of: otherText) { newValue in
                        let filtered = FeedbackText.filterWhileTyping(newValue)
                        if filtered != newValue { otherText = filtered }
                    }

                    Text("\(otherText.count)/\(FeedbackText.maxLength)" + (showsPrivacyHint ? " · Please don't include personal information." : ""))
                        .font(.system(size: 11))
                        .foregroundColor(.vpnTextSecondary)
                }
            }
        }
    }
}
#endif
