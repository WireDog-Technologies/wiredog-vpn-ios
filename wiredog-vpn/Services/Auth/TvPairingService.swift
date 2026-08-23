import Foundation

// tvOS-only: signs the TV into an existing WireDog account via the device-pairing flow
// (TV shows a code, user confirms it on wiredogvpn.com/tv-pairing from another device).
// Backend counterpart: wiredog-backend/src/services/tvPairing.ts.

enum TvPairingError: LocalizedError {
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class TvPairingService: ObservableObject {
    static let shared = TvPairingService()

    @Published private(set) var code: String?
    @Published private(set) var isPolling = false
    @Published var error: TvPairingError?

    private let apiClient: APIClient
    private let keychainService: KeychainServiceProtocol
    private var pollTask: Task<Void, Never>?
    private static let pollInterval: UInt64 = 3_000_000_000 // 3s, matches backend's tvPairingPollLimiter budget

    init(
        apiClient: APIClient = .shared,
        keychainService: KeychainServiceProtocol = KeychainService.shared
    ) {
        self.apiClient = apiClient
        self.keychainService = keychainService
    }

    /// Requests a new pairing code and polls until it's confirmed, expires, or `cancel()` is
    /// called (e.g. the pairing screen disappears). On confirmation, saves the token and signs
    /// the app in via `AuthService` — from that point on the tvOS app is indistinguishable from
    /// a logged-in iOS app to the rest of the codebase.
    func start() {
        cancel()
        error = nil
        code = nil

        pollTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response: TvPairingStartResponse = try await self.apiClient.request(endpoint: .startTvPairing)
                guard !Task.isCancelled else { return }
                self.code = response.code
                await self.poll(code: response.code, expiresIn: response.expiresIn)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = .networkError(error)
            }
        }
    }

    func cancel() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    private func poll(code: String, expiresIn: Int) async {
        isPolling = true
        defer { isPolling = false }

        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        while Date() < deadline {
            guard !Task.isCancelled else { return }

            do {
                let status: TvPairingStatusResponse = try await apiClient.request(
                    endpoint: .tvPairingStatus(code: code)
                )
                switch status.status {
                case "delivered":
                    if let token = status.token {
                        _ = keychainService.saveAuthToken(token)
                        try? await AuthService.shared.signInWithStoredToken()
                    }
                    return
                case "expired":
                    LogService.shared.logApp("[TvPairingService] Code expired, requesting a new one", level: .info)
                    self.start() // cancels this task and replaces pollTask with a fresh cycle
                    return
                default:
                    break // still pending — keep polling
                }
            } catch {
                LogService.shared.logApp("[TvPairingService] Poll error: \(error.localizedDescription)", level: .warning)
                // Transient network error — keep polling rather than aborting the whole flow.
            }

            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: Self.pollInterval)
        }

        guard !Task.isCancelled else { return }
        self.start() // ran past expiresIn without a status flip — same recovery as an explicit "expired"
    }
}
