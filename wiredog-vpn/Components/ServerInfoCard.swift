import SwiftUI

struct ServerInfoCard: View {
    let server: Server

    var body: some View {
        HStack(spacing: 12) {
            Text(server.countryFlag())
                .font(.system(size: 32))

            VStack(alignment: .leading, spacing: 4) {
                Text(server.countryName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.vpnTextPrimary)

                if let city = server.city {
                    Text(city)
                        .font(.system(size: 12))
                        .foregroundColor(.vpnTextSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Server ID")
                    .font(.system(size: 16))
                    .foregroundColor(.vpnTextSecondary)

                Text(server.id)
                    .font(.custom("Iosevka Term Extended", size: 14))
                    .fontWeight(.semibold)
                    .foregroundColor(.vpnPrimary)
            }
        }
        .padding(16)
        .background(Color.vpnCardBackground)
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 16) {
        ServerInfoCard(server: MockData.servers[0])
        ServerInfoCard(server: MockData.servers[2])
    }
    .padding()
    .background(Color.vpnBackground)
}
