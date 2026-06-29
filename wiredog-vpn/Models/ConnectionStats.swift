import Foundation

struct ConnectionStats: Equatable {
    var downloadSpeed: Double  // Mbps
    var uploadSpeed: Double    // Mbps
    var connectionTime: TimeInterval  // seconds
    var dataTransferred: Double  // GB
}

extension TimeInterval {
    /// Formats a duration as HH:MM:SS
    var formattedHMS: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
