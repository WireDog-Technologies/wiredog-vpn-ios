import SwiftUI

struct SecureToggleField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.vpnTextSecondary)

            Group {
                if isRevealed {
                    TextField(
                        "",
                        text: $text,
                        prompt: Text(placeholder).foregroundColor(.vpnTextTertiary)
                    )
                } else {
                    SecureField(
                        "",
                        text: $text,
                        prompt: Text(placeholder).foregroundColor(.vpnTextTertiary)
                    )
                }
            }
            .textFieldStyle(VPNTextFieldStyle())
            .overlay(alignment: .trailing) {
                Button(action: { isRevealed.toggle() }) {
                    Image(systemName: isRevealed ? "eye.fill" : "eye.slash.fill")
                        .foregroundColor(.vpnTextSecondary)
                        .padding(.trailing, 16)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SecureToggleField(label: "Password", placeholder: "Enter your password", text: .constant(""))
        SecureToggleField(label: "Confirm Password", placeholder: "Confirm password", text: .constant("secret123"))
    }
    .padding()
    .background(Color.vpnBackground)
}
