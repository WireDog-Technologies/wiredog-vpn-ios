import SwiftUI

struct ReviewPromptView: View {
    let onPositive: () -> Void
    let onNegative: () -> Void

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Enjoying WireDog VPN?")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)
                Text("We'd love to know how it's going.")
                    .font(.system(size: 14))
                    .foregroundColor(.vpnTextSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 32)

            HStack(spacing: 16) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                    onNegative()
                } label: {
                    VStack(spacing: 8) {
                        Text("👎")
                            .font(.system(size: 32))
                        Text("Not really")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.vpnTextPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.vpnCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    presentationMode.wrappedValue.dismiss()
                    onPositive()
                } label: {
                    VStack(spacing: 8) {
                        Text("👍")
                            .font(.system(size: 32))
                        Text("Loving it")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.vpnTextPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.vpnCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.bottom, 24)
        .background(Color.vpnBackground.ignoresSafeArea())
        .modifier(ReviewPromptDetentModifier())
    }
}

private struct ReviewPromptDetentModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.presentationDetents([.height(260)])
        } else {
            content
        }
    }
}

#Preview {
    ReviewPromptView(onPositive: {}, onNegative: {})
}
