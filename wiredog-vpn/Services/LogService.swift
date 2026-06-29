import Foundation

class LogService {
    static let shared = LogService()

    private let appLogFile = "app_logs.txt"
    private let serviceLogFile = "service_logs.txt"
    private let maxLogSize = 1024 * 1024 // 1MB
    private let maxLines = 1000
    private let queue = DispatchQueue(label: "com.wiredog.vpn.logservice")

    #if DEBUG
    private let minimumLogLevel: LogLevel = .debug
    #else
    private let minimumLogLevel: LogLevel = .info
    #endif

    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroupIdentifier)
    }

    private init() {}

    // MARK: - Write Logs

    func logApp(_ message: String, level: LogLevel = .info) {
        writeLog(to: appLogFile, message: message, level: level, source: "App")
    }

    func logService(_ message: String, level: LogLevel = .info) {
        writeLog(to: serviceLogFile, message: message, level: level, source: "VPN")
    }

    private func writeLog(to file: String, message: String, level: LogLevel, source: String) {
        guard let containerURL = containerURL else { return }

        // Skip debug logs in production builds
        if level == .debug && minimumLogLevel != .debug {
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] [\(level.rawValue.uppercased())] [\(source)] \(message)\n"

        queue.async { [maxLogSize] in
            let fileURL = containerURL.appendingPathComponent(file)

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int, size > maxLogSize {
                self.truncateLogFile(at: fileURL)
            }

            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        }
    }

    // MARK: - Read Logs

    func readAppLogs() -> String {
        readLogs(from: appLogFile)
    }

    func readServiceLogs() -> String {
        readLogs(from: serviceLogFile)
    }

    private func readLogs(from file: String) -> String {
        guard let containerURL = containerURL else {
            return "Unable to access log storage."
        }

        let fileURL = containerURL.appendingPathComponent(file)

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return "No logs available."
        }

        return content.isEmpty ? "No logs available." : content
    }

    // MARK: - Truncate

    private func truncateLogFile(at url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: "\n")
        let keepLines = Array(lines.suffix(maxLines / 2))
        let truncated = keepLines.joined(separator: "\n")

        try? truncated.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Types

    enum LogLevel: String {
        case info
        case warning
        case error
        case debug
    }
}
