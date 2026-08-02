import Testing
import Foundation
import UIKit
import NetworkExtension
@testable import wiredog_vpn

/// Verifies VPNService's device-counter accounting: every connect attempt that fails, or drops
/// before proving itself stable, must fire a matching /disconnect so the backend's per-account
/// device counter never leaks. See the VPN counter-leak fix plan for full background.
@Suite(.serialized)
@MainActor
struct VPNServiceTests {

    // MARK: - Helpers

    private func makeAuthenticatedAuthService(
        subscriptionExpiresAt: String = "2030-01-01T00:00:00Z"
    ) -> AuthService {
        VPNServiceAuthMockURLProtocol.reset()
        VPNServiceAuthMockURLProtocol.configure(data: TestFixtures.userProfileJSON(subscriptionExpiresAt: subscriptionExpiresAt))
        let session = makeVPNServiceAuthMockSession()
        let authApiClient = APIClient(
            baseURL: URL(string: "https://api.example.com/api")!,
            session: session,
            keychainService: MockKeychainService()
        )
        let authService = AuthService(keychainService: MockKeychainService(), apiClient: authApiClient, checkSession: false)
        authService.isAuthenticated = true
        return authService
    }

    private func connectResponseJSON(sessionId: String) -> Data {
        """
        {
          "sessionId": "\(sessionId)",
          "config": {
            "privateKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "address": "10.0.0.1/32",
            "dns": "8.8.8.8",
            "peer": {
              "publicKey": "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
              "endpoint": "192.0.2.1:51820",
              "allowedIPs": "0.0.0.0/0,::/0",
              "persistentKeepalive": 25
            },
            "awg": {"Jc": 4, "Jmin": 40, "Jmax": 70, "S1": 0, "S2": 0, "H1": 1, "H2": 2, "H3": 3, "H4": 4}
          }
        }
        """.data(using: .utf8)!
    }

    /// Builds a VPNService wired to fully-controllable fakes: a mock APIClient (captures every
    /// /vpn/connect + /vpn/disconnect request), a fake tunnel manager (controllable status,
    /// force-throwing startVPNTunnel), and a pre-authenticated AuthService.
    private func makeService(
        connectSessionId: String = "sess-1",
        authService: AuthService? = nil,
        seedPendingDisconnectIds: [String] = []
    ) async -> (service: VPNService, tunnel: FakeVPNTunnelManager, auth: AuthService) {
        UserDefaults.standard.removeObject(forKey: "vpn_session_id")
        if seedPendingDisconnectIds.isEmpty {
            UserDefaults.standard.removeObject(forKey: "vpn_pending_disconnect_ids")
        } else {
            UserDefaults.standard.set(seedPendingDisconnectIds, forKey: "vpn_pending_disconnect_ids")
        }

        VPNServiceMockURLProtocol.reset()
        VPNServiceMockURLProtocol.configure(data: connectResponseJSON(sessionId: connectSessionId))
        VPNServiceMockURLProtocol.mockDisconnectData = #"{"success": true}"#.data(using: .utf8)
        let session = makeVPNServiceMockSession()
        let apiClient = APIClient(
            baseURL: URL(string: "https://api.example.com/api")!,
            session: session,
            keychainService: MockKeychainService()
        )

        let auth = authService ?? makeAuthenticatedAuthService()
        let provider = FakeVPNTunnelManagerProvider()
        let service = VPNService(
            apiClient: apiClient,
            authService: auth,
            tunnelManagerProvider: provider,
            autoLoadOnInit: false
        )
        service.disconnectNotifyDelayNanoseconds = 0
        // Scale reconnect timing way down so tests never wait on real 1s-15s backoff.
        service.reconnectBaseDelay = 0.001
        service.reconnectMaxDelay = 0.005

        // Wires vpnManager to our fake (no existing manager "in preferences", so
        // createNewVPNManager() resolves via the fake provider).
        await service.loadVPNManager()

        return (service, provider.manager, auth)
    }

    private func connectRequests() -> [URLRequest] {
        VPNServiceMockURLProtocol.capturedRequests.filter { $0.url?.path.hasSuffix("/vpn/connect") == true }
    }

    private func disconnectRequests() -> [URLRequest] {
        VPNServiceMockURLProtocol.capturedRequests.filter { $0.url?.path.hasSuffix("/vpn/disconnect") == true }
    }

    /// `URLSession.data(for:)` moves the request body into `httpBodyStream` rather than keeping it
    /// as `httpBody` `Data`, so captured requests must be read back via the stream.
    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }
        return data
    }

    private func disconnectSessionIds() -> [String] {
        disconnectRequests().compactMap { request -> String? in
            guard let body = bodyData(from: request),
                  let dict = try? JSONSerialization.jsonObject(with: body) as? [String: String] else { return nil }
            return dict["sessionId"]
        }
    }

    // MARK: - a. Successful connect

    @Test func connect_success_oneConnectZeroDisconnect() async throws {
        let (service, tunnel, _) = await makeService()

        try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)

        #expect(connectRequests().count == 1)
        #expect(disconnectRequests().count == 0)
        #expect(service.sessionId == "sess-1")
        #expect(tunnel.connection.startVPNTunnelCallCount == 1)
    }

    // MARK: - b. Guard-clause failures never leak a call

    @Test func connect_notAuthenticated_noNetworkCalls() async {
        let unauthenticated = AuthService(keychainService: MockKeychainService(), checkSession: false)
        unauthenticated.isAuthenticated = false
        let (service, _, _) = await makeService(authService: unauthenticated)

        await #expect(throws: VPNError.self) {
            try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)
        }

        #expect(connectRequests().isEmpty)
        #expect(disconnectRequests().isEmpty)
        #expect(service.sessionId == nil)
    }

    @Test func connect_subscriptionExpired_noBackendCallsLeaked() async {
        let expiredAuth = makeAuthenticatedAuthService(subscriptionExpiresAt: "2020-01-01T00:00:00Z")
        let (service, _, _) = await makeService(authService: expiredAuth)

        await #expect(throws: VPNError.self) {
            try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)
        }

        #expect(connectRequests().isEmpty)
        #expect(disconnectRequests().isEmpty)
        #expect(service.sessionId == nil)
    }

    // MARK: - c. startVPNTunnel throws after sessionId obtained -> net zero

    @Test func connect_startVPNTunnelThrows_netZero() async throws {
        let (service, tunnel, _) = await makeService(connectSessionId: "sess-c")
        tunnel.connection.startVPNTunnelError = FakeError("simulated tunnel start failure")

        await #expect(throws: VPNError.self) {
            try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)
        }
        await service.lastCleanupTask?.value

        #expect(connectRequests().count == 1)
        #expect(disconnectRequests().count == 1)
        #expect(disconnectSessionIds() == ["sess-c"])
        #expect(service.sessionId == nil)
    }

    // MARK: - d. Drop before stability threshold -> cleanup fires before reconnect

    @Test func updateConnectionState_dropsBeforeStability_disconnectFiresBeforeReconnect() async throws {
        let (service, tunnel, _) = await makeService(connectSessionId: "sess-d")
        service.minimumStableConnectionDuration = 10 // never reached in this test

        try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)

        tunnel.connection.status = .connected
        service.updateConnectionState()
        #expect(service.connectionState == .connected)

        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms, well under the 10s threshold

        tunnel.connection.status = .disconnected
        service.updateConnectionState()
        await service.lastCleanupTask?.value

        #expect(disconnectSessionIds().contains("sess-d"))
        #expect(service.isReconnecting == true)

        // Stop the retry loop this test triggered — otherwise its backoff-scheduled reconnect
        // Task keeps running in the background after this test returns and can leak a stray
        // cleanup call into whichever test runs next.
        service.cancelConnect()
    }

    // MARK: - e. Drop after stability threshold -> no extra cleanup

    @Test func updateConnectionState_dropsAfterStability_noExtraDisconnect() async throws {
        let (service, tunnel, _) = await makeService(connectSessionId: "sess-e")
        service.minimumStableConnectionDuration = 0.05 // 50ms

        try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)

        tunnel.connection.status = .connected
        service.updateConnectionState()

        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms, past the 50ms threshold

        tunnel.connection.status = .disconnected
        service.updateConnectionState()
        // sessionId is cleared synchronously inside updateConnectionState() itself — check it
        // immediately, before the async auto-reconnect retry (scheduled by this same call) has a
        // chance to complete and repopulate it with a fresh session from the mock.
        #expect(service.sessionId == nil)

        // Give any (incorrect) cleanup Task a chance to run before asserting its absence.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(disconnectSessionIds().isEmpty)
    }

    // MARK: - f. Reconnect exhaustion -> final cleanup, state cleared

    @Test func attemptReconnect_exhaustsAttempts_finalDisconnectAndStateCleared() async throws {
        let (service, _, _) = await makeService(connectSessionId: "sess-f")

        try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)
        #expect(service.sessionId == "sess-f")
        #expect(service.currentServerId == "us-east-1")

        // Force immediate exhaustion rather than looping through real reconnect attempts.
        service.maxReconnectAttempts = 0
        service.attemptReconnect()
        await service.lastCleanupTask?.value

        #expect(disconnectSessionIds().contains("sess-f"))
        #expect(service.currentServerId == nil)
        #expect(service.sessionId == nil)
    }

    // MARK: - g. Normal user-initiated disconnect

    @Test func disconnect_userInitiated_oneDisconnectCorrectSessionId() async throws {
        let (service, _, _) = await makeService(connectSessionId: "sess-g")

        try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)
        await service.disconnect()
        await service.lastCleanupTask?.value

        #expect(disconnectRequests().count == 1)
        #expect(disconnectSessionIds() == ["sess-g"])
        #expect(service.sessionId == nil)
    }

    // MARK: - h. Disconnect fails while offline -> survives in the pending-retry list

    @Test func cleanupOrphanedSession_networkFailure_retriedViaPendingList() async throws {
        let (service, _, _) = await makeService(connectSessionId: "sess-h")
        try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)

        // Simulate no connectivity for the disconnect call.
        VPNServiceMockURLProtocol.mockError = URLError(.notConnectedToInternet)

        await service.disconnect()
        await service.lastCleanupTask?.value

        // The failed call must have been attempted...
        #expect(disconnectRequests().count == 1)
        // ...but since it never succeeded, the durable record must survive for a future retry.
        #expect(VPNService.pendingDisconnectIds().contains("sess-h"))

        // Restore connectivity and retry, as loadVPNManager() would do on next app launch.
        VPNServiceMockURLProtocol.mockError = nil
        service.retryPendingDisconnects()
        await service.lastCleanupTask?.value

        #expect(disconnectRequests().count == 2)
        #expect(!VPNService.pendingDisconnectIds().contains("sess-h"))
    }

    // MARK: - i. loadVPNManager() retries stale pending disconnects on launch

    @Test func loadVPNManager_retriesPendingDisconnectsFromPreviousLaunch() async throws {
        let (service, _, _) = await makeService(seedPendingDisconnectIds: ["stale-session-1"])

        await service.lastCleanupTask?.value

        #expect(disconnectSessionIds().contains("stale-session-1"))
        #expect(!VPNService.pendingDisconnectIds().contains("stale-session-1"))
    }

    // MARK: - j. Returning to foreground retries stale pending disconnects

    @Test func foregroundNotification_retriesPendingDisconnects() async throws {
        let (service, _, _) = await makeService()

        // Seed a stale pending id *after* construction — loadVPNManager() already ran its
        // (empty) retry pass during makeService(), so this simulates a disconnect that failed
        // sometime after launch, while the app was backgrounded.
        UserDefaults.standard.set(["stale-fg-session"], forKey: "vpn_pending_disconnect_ids")

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        // The observer is registered with queue: .main, which enqueues asynchronously — give it
        // a beat to run before checking, then await the cleanup Task it schedules.
        try? await Task.sleep(nanoseconds: 50_000_000)
        await service.lastCleanupTask?.value

        #expect(disconnectSessionIds().contains("stale-fg-session"))
        #expect(!VPNService.pendingDisconnectIds().contains("stale-fg-session"))
    }

    // MARK: - k. Cancel lands right after the tunnel starts

    @Test func connect_cancelledAfterTunnelStarts_stopsTunnelAndDisconnects() async throws {
        let (service, tunnel, _) = await makeService(connectSessionId: "sess-cancel-1")

        var capturedTask: Task<Void, Error>?
        // Fires synchronously inside connect(), exactly at the checkpoint we added right after
        // startVPNTunnel() succeeds — deterministic, unlike racing real async cancellation timing.
        tunnel.connection.onStartVPNTunnel = {
            capturedTask?.cancel()
        }

        let task = Task {
            try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)
        }
        capturedTask = task

        await #expect(throws: VPNError.self) {
            try await task.value
        }
        await service.lastCleanupTask?.value

        #expect(tunnel.connection.stopVPNTunnelCallCount == 1)
        #expect(disconnectSessionIds().contains("sess-cancel-1"))
        #expect(service.sessionId == nil)
        // A user-initiated cancel shouldn't surface as an error alert.
        #expect(service.error == nil)
    }

    // MARK: - l. Cancel during the auto-reconnect backoff wait

    @Test func cancelConnect_duringReconnectBackoff_stopsRetrying() async throws {
        let (service, tunnel, _) = await makeService(connectSessionId: "sess-cancel-2")
        service.minimumStableConnectionDuration = 10 // never reached in this test

        try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)

        tunnel.connection.status = .connected
        service.updateConnectionState()

        tunnel.connection.status = .disconnected
        service.updateConnectionState() // cleanup fires (unstable) + attemptReconnect() schedules a retry
        #expect(service.isReconnecting == true)

        let connectCallsBeforeCancel = connectRequests().count
        service.cancelConnect()
        await service.lastCleanupTask?.value

        #expect(service.isReconnecting == false)

        // Give a (wrongly) still-scheduled retry a chance to fire before asserting its absence.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(connectRequests().count == connectCallsBeforeCancel)
    }

    // MARK: - m. Reconnect against a system VPN slot another app owns must not loop

    /// Reproduces: user is connected to WireDog, switches to another VPN app (e.g. Proton) which
    /// takes over the system's single VPN slot, then switches back. iOS reports our tunnel as
    /// dropped, so auto-reconnect kicks in — but every retry hits NEVPNError.configurationDisabled
    /// (mapped to .anotherVPNActive) for as long as the other VPN stays active. Retrying is never
    /// going to succeed, so this must surface the error and stop, not burn through every attempt.
    @Test func attemptReconnect_anotherVPNActive_stopsInsteadOfLooping() async throws {
        let (service, tunnel, _) = await makeService(connectSessionId: "sess-m")
        service.maxReconnectAttempts = 10

        try await service.connect(serverId: "us-east-1", killSwitchEnabled: false)
        tunnel.connection.status = .connected
        service.updateConnectionState()

        // Every subsequent startVPNTunnel call fails as it would while another VPN app holds
        // the system's VPN slot.
        tunnel.connection.startVPNTunnelError = NSError(
            domain: NEVPNErrorDomain,
            code: NEVPNError.Code.configurationDisabled.rawValue
        )

        tunnel.connection.status = .disconnected
        service.updateConnectionState() // schedules the first auto-reconnect attempt
        #expect(service.isReconnecting == true)

        // Let the (near-instant, test-scaled) backoff and the failed retry run to completion.
        try? await Task.sleep(nanoseconds: 50_000_000)
        await service.lastCleanupTask?.value

        #expect(service.isReconnecting == false)
        #expect(service.currentServerId == nil)
        if case .anotherVPNActive = service.error {
            // expected
        } else {
            Issue.record("Expected service.error == .anotherVPNActive, got \(String(describing: service.error))")
        }

        // Must have given up after the single doomed retry, not burned through all 10 attempts.
        #expect(connectRequests().count == 2)
    }
}
