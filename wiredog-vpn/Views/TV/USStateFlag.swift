import Foundation

// tvOS-only. Maps a server's 2-letter US state code to the matching flag asset in
// wiredog-tv/Assets.xcassets (mirrors the same mapping used elsewhere in this app, same
// source SVGs). Falls back to the national flag for any state without server coverage
// yet — this app is US-only, so there are no country flags to fall back to instead.
enum USStateFlag {
    private static let assetNameByStateCode: [String: String] = [
        "AZ": "Flag_AZ",
        "CA": "Flag_CA",
        "CO": "Flag_CO",
        "FL": "Flag_FL",
        "GA": "Flag_GA",
        "IL": "Flag_IL",
        "MA": "Flag_MA",
        "MI": "Flag_MI",
        "MN": "Flag_MN",
        "NV": "Flag_NV",
        "NY": "Flag_NY",
        "NJ": "Flag_NJ",
        "NC": "Flag_NC",
        "OH": "Flag_OH",
        "OR": "Flag_OR",
        "PA": "Flag_PA",
        "TX": "Flag_TX",
        "VA": "Flag_VA",
        "WA": "Flag_WA",
    ]

    static func assetName(for stateCode: String) -> String {
        assetNameByStateCode[stateCode] ?? "Flag_US"
    }
}
