import SwiftUI

struct LoadingScreenView: View {
    var body: some View {
        ZStack {
            Color.vpnBackground
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Image("WireDog Head Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 160)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .vpnRedBright))
            }
        }
    }
}

#Preview {
    LoadingScreenView()
}
