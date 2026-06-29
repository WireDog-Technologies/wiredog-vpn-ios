import SwiftUI

struct LoadIndicatorView: View {
    let load: Double
    let size: Size

    enum Size {
        case small
        case medium
        case large

        var dimension: CGFloat {
            switch self {
            case .small:
                return 30
            case .medium:
                return 50
            case .large:
                return 70
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small:
                return 10
            case .medium:
                return 12
            case .large:
                return 16
            }
        }
    }

    init(load: Double, size: Size = .medium) {
        self.load = load
        self.size = size
    }

    var loadColor: Color {
        if load < 0.5 {
            return .vpnGreen
        } else if load < 0.8 {
            return .vpnYellow
        } else {
            return .vpnRed
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.vpnBorderColor, lineWidth: 2)

            Circle()
                .trim(from: 0, to: load)
                .stroke(loadColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int(load * 100))%")
                    .font(.system(size: size.fontSize, weight: .semibold))
                    .foregroundColor(.vpnTextPrimary)
            }
        }
        .frame(width: size.dimension, height: size.dimension)
    }
}

#Preview {
    HStack(spacing: 20) {
        LoadIndicatorView(load: 0.35, size: .small)
        LoadIndicatorView(load: 0.65, size: .medium)
        LoadIndicatorView(load: 0.85, size: .large)
    }
    .padding()
    .background(Color.vpnBackground)
}
