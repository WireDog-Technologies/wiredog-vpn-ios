import SwiftUI

struct GradientActionButton: View {
    let title: String
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                LinearGradient(
                    colors: isLoading
                        ? [Color.vpnRedBright.opacity(0.5), Color.vpnRedMedium.opacity(0.5), Color.vpnRedDark.opacity(0.5)]
                        : [Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .cornerRadius(8)
        }
        .disabled(isLoading || isDisabled)
    }
}

#Preview {
    VStack(spacing: 16) {
        GradientActionButton(title: "Sign In", isLoading: false, isDisabled: false) {}
        GradientActionButton(title: "Sign In", isLoading: true, isDisabled: false) {}
        GradientActionButton(title: "Sign In", isLoading: false, isDisabled: true) {}
    }
    .padding()
    .background(Color.vpnBackground)
}
