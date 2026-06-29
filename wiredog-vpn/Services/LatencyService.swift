import Foundation
import Network

actor LatencyService {
    static let shared = LatencyService()

    private static let cacheKey = "server_latency_cache"
    static let timeoutSeconds: TimeInterval = 3.0
    private static let concurrencyCap = 20
    private static let sampleCount = 3
    private static let sampleGapSeconds: TimeInterval = 0.2

    /// Measures TCP RTT to port 443 for all servers, capped at 20 concurrent probes.
    /// Each server is probed 3 times (200ms apart) and the lowest result is kept.
    /// DNS is resolved once per server before the sample loop.
    /// Returns a dict of serverId → latencyMs for reachable servers.
    func measureAll(_ servers: [Server]) async -> [String: Int] {
        let eligible = servers.filter { !$0.host.isEmpty }
        var results: [String: Int] = [:]

        // Process in chunks of concurrencyCap to avoid hammering all servers at once
        let chunks = stride(from: 0, to: eligible.count, by: Self.concurrencyCap).map {
            Array(eligible[$0..<min($0 + Self.concurrencyCap, eligible.count)])
        }

        for chunk in chunks {
            let chunkResults = await withTaskGroup(of: (String, Int?).self) { group in
                for server in chunk {
                    group.addTask {
                        let ms = await Self.measure(host: server.host)
                        return (server.id, ms)
                    }
                }
                var partial: [String: Int] = [:]
                for await (id, ms) in group {
                    if let ms { partial[id] = ms }
                }
                return partial
            }
            results.merge(chunkResults) { _, new in new }
        }

        return results
    }

    // MARK: - Cache

    func loadCache() -> [String: Int] {
        guard let raw = UserDefaults.standard.string(forKey: Self.cacheKey) else { return [:] }
        var result: [String: Int] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let ms = Int(parts[1]) {
                result[String(parts[0])] = ms
            }
        }
        return result
    }

    func saveCache(_ latencies: [String: Int]) {
        let raw = latencies.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: Self.cacheKey)
    }

    // MARK: - TCP Probe

    /// Resolves hostname → IP once (untimed), then runs 3 TCP probes 200ms apart and returns the minimum.
    private static func measure(host: String) async -> Int? {
        guard let ip = await resolveIP(hostname: host) else { return nil }
        var samples: [Int] = []
        for i in 0..<sampleCount {
            if let ms = await TCPProbe(ip: ip).run() {
                samples.append(ms)
            }
            if i < sampleCount - 1 {
                try? await Task.sleep(nanoseconds: UInt64(sampleGapSeconds * 1_000_000_000))
            }
        }
        return samples.min()
    }

    /// Resolves a hostname to its first IPv4 address using getaddrinfo on a background thread.
    private static func resolveIP(hostname: String) async -> String? {
        await Task.detached(priority: .utility) {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = Int32(SOCK_STREAM)

            var res: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(hostname, nil, &hints, &res) == 0, let res else { return nil }
            defer { freeaddrinfo(res) }

            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let sinAddr = res.pointee.ai_addr
                .withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            guard inet_ntop(AF_INET, [sinAddr], &buf, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buf)
        }.value
    }
}

// Thread-safe, one-shot TCP RTT probe. Connects to a pre-resolved IP so DNS is excluded.
private final class TCPProbe: @unchecked Sendable {
    private let ip: String
    private let lock = NSLock()
    private var settled = false

    init(ip: String) {
        self.ip = ip
    }

    func run() async -> Int? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(ip),
                port: 443
            )
            let connection = NWConnection(to: endpoint, using: .tcp)
            let start = Date()

            let timeoutWork = DispatchWorkItem { [weak self] in
                guard let self, self.settle() else { return }
                connection.cancel()
                continuation.resume(returning: nil)
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + LatencyService.timeoutSeconds,
                execute: timeoutWork
            )

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard self.settle() else { return }
                    timeoutWork.cancel()
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    connection.cancel()
                    continuation.resume(returning: ms)

                case .failed(let error):
                    guard self.settle() else { return }
                    timeoutWork.cancel()
                    connection.cancel()
                    // TCP RST (ECONNREFUSED) still carries a valid RTT
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        continuation.resume(returning: ms)
                    } else {
                        continuation.resume(returning: nil)
                    }

                case .cancelled:
                    guard self.settle() else { return }
                    timeoutWork.cancel()
                    continuation.resume(returning: nil)

                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))
        }
    }

    /// Returns true the first time called; false thereafter (ensures one-shot resume).
    private func settle() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !settled else { return false }
        settled = true
        return true
    }
}
