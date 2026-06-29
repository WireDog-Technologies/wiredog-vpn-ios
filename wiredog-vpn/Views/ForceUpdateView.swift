import SwiftUI

struct ForceUpdateView: View {
    let message: String

    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.vpnRedMedium)

                Text("Update Required")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)

                Text("A new version of WireDog VPN is available that has critical changes. Please update to continue.")
                    .font(.system(size: 16))
                    .foregroundColor(.vpnTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button(action: openAppStore) {
                    ZStack {
                        LinearGradient(
                            colors: [Color.vpnRedBright, Color.vpnRedMedium, Color.vpnRedDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        Text("Update Now")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.top, 16)
            }
        }
    }

    private func openAppStore() {
        UIApplication.shared.open(Config.appStoreURL)
    }
}
