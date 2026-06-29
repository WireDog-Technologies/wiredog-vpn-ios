import SwiftUI

extension Color {
    // Background colors — matched to Android theme
    static let vpnBackground = Color(red: 0.059, green: 0.078, blue: 0.102)       // #0F141A
    static let vpnCardBackground = Color(red: 0.102, green: 0.122, blue: 0.161)   // #1A1F29
    static let vpnSecondaryBackground = Color(red: 0.141, green: 0.169, blue: 0.212) // #242B36

    // Accent colors
    static let vpnPrimary = Color(red: 0.290, green: 0.569, blue: 0.890)          // #4A91E3
    static let vpnGreen = Color(red: 0.180, green: 0.800, blue: 0.443)            // #2ECC71
    static let vpnRed = Color(red: 0.910, green: 0.298, blue: 0.235)              // #E84C3C
    static let vpnYellow = Color(red: 0.950, green: 0.612, blue: 0.071)           // #F29C12

    // Red gradient colors — matched to Android login button gradient
    static let vpnRedBright = Color(red: 1.0, green: 0.0, blue: 0.0)             // #FF0000
    static let vpnRedMedium = Color(red: 0.902, green: 0.0, blue: 0.0)           // #E60000
    static let vpnRedDark   = Color(red: 0.412, green: 0.008, blue: 0.008)       // #690202

    // Text colors
    static let vpnTextPrimary = Color.white
    static let vpnTextSecondary = Color(red: 0.561, green: 0.580, blue: 0.624)    // #8F949F
    static let vpnTextTertiary = Color(red: 0.350, green: 0.380, blue: 0.440)

    // UI element colors
    static let vpnBorderColor = Color(red: 0.169, green: 0.212, blue: 0.251)      // #2B3640
    static let vpnShadow = Color.black.opacity(0.3)
}
