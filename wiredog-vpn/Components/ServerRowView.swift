import SwiftUI

func latencyColor(_ ms: Int) -> Color {
    switch ms {
    case 0:       return .vpnTextSecondary
    case 1...80:  return .vpnGreen
    case 81...150: return .vpnYellow
    default:      return .vpnRed
    }
}

struct ServerRowView: View {
    var server: Server
    let isSelected: Bool
    let action: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Text(server.countryFlag())
                        .font(.system(size: 24))

                    VStack(alignment: .leading, spacing: 4) {
                        // An organization gateway shows its own name; everything else is unchanged.
                        Text(server.gatewayName ?? server.countryName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.vpnTextPrimary)

                        if let city = server.city {
                            Text(server.isDedicated ? "\(city), \(server.countryCode)" : city)
                                .font(.system(size: 13))
                                .foregroundColor(.vpnTextSecondary)
                        }

                        Text(server.isDedicated ? "DEDICATED GATEWAY" : server.id)
                            .font(.custom("Iosevka Term Extended", size: 11))
                            .foregroundColor(.vpnPrimary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        LoadIndicatorView(load: server.load, size: .small)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(server.latencyMs > 0 ? "\(server.latencyMs)" : "--")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(latencyColor(server.latencyMs))

                            Text("ms")
                                .font(.system(size: 10))
                                .foregroundColor(.vpnTextSecondary)
                        }
                    }
                }
            }

            Button(action: onToggleFavorite) {
                Image(systemName: server.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(server.isFavorite ? .vpnYellow : .vpnTextTertiary)
                    .frame(width: 20)
            }
        }
        .padding(12)
        .background(isSelected ? Color.vpnSecondaryBackground : Color.vpnCardBackground)
        .cornerRadius(8)
    }
}

#Preview {
    VStack(spacing: 8) {
        ServerRowView(server: MockData.servers[0], isSelected: false, action: {}, onToggleFavorite: {})
        ServerRowView(server: MockData.servers[1], isSelected: true, action: {}, onToggleFavorite: {})
        ServerRowView(server: MockData.servers[2], isSelected: false, action: {}, onToggleFavorite: {})
    }
    .padding()
    .background(Color.vpnBackground)
}
