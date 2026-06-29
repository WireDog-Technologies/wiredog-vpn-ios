import SwiftUI

struct MaintenanceView: View {
    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.vpnYellow)

                Text("Under Maintenance")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.vpnTextPrimary)

                Text("WireDog VPN is currently undergoing maintenance. Please check back shortly.")
                    .font(.system(size: 16))
                    .foregroundColor(.vpnTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}
