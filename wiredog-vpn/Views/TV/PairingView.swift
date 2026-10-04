import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// tvOS-only sign-in screen. Siri Remote text entry is unreliable enough that this app
// never asks for a password or account number directly — see TvPairingService for the
// device-pairing flow this displays.
struct PairingView: View {
    @StateObject private var pairingService = TvPairingService.shared

    private static let qrContext = CIContext()

    var body: some View {
        HStack(spacing: 80) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 0) {
                    Text("Let's connect to ")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.vpnTextPrimary)

                    Text("WireDog VPN")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.clear)
                        .overlay(
                            LinearGradient(
                                colors: [.vpnRedBright, .vpnRedMedium, .vpnRedDark],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .mask(
                                Text("WireDog VPN")
                                    .font(.system(size: 44, weight: .bold))
                            )
                        )
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Text("Log in online by scanning the QR code or by visiting wiredogvpn.com/tv-pairing")
                    .font(.title3)
                    .foregroundColor(.vpnTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let code = pairingService.code {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Pairing Code:")
                            .font(.headline)
                            .foregroundColor(.vpnTextSecondary)

                        Text(formattedCode(code))
                            .font(.system(size: 60, weight: .bold, design: .monospaced))
                            .tracking(6)
                            .foregroundColor(.vpnTextPrimary)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                } else {
                    ProgressView()
                        .padding(.vertical, 40)
                }

                if let error = pairingService.error {
                    Text(error.localizedDescription)
                        .font(.headline)
                        .foregroundColor(.vpnRed)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)

            if let code = pairingService.code, let qrImage = qrImage(for: pairingURL(code: code)) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 260, height: 260)
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(16)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vpnBackground)
        .task {
            pairingService.start()
        }
        .onDisappear {
            pairingService.cancel()
        }
    }

    // "ABCD1234" -> "ABCD-1234", easier to read and to relay verbally at a distance.
    private func formattedCode(_ code: String) -> String {
        guard code.count == 8 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 4)
        return "\(code[..<mid])-\(code[mid...])"
    }

    private func pairingURL(code: String) -> URL {
        var components = URLComponents(url: Config.tvPairingURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "code", value: code)]
        return components?.url ?? Config.tvPairingURL
    }

    private func qrImage(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = Self.qrContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
