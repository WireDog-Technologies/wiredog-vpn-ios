import Testing
@testable import wiredog_vpn

struct TunnelConfigServiceTests {

    // MARK: - Fixtures

    private static let defaultAwg = AwgParams(
        jc: 4, jmin: 40, jmax: 70,
        s1: 0, s2: 0,
        h1: 1, h2: 2, h3: 3, h4: 4
    )

    private func makeConfig(
        privateKey: String = "YF4d8SZtNXPFOmQxgHr9SZ5QUt+gJCVmH0nZ3QvJvUQ=",
        address: String = "10.0.0.1/32,fd00::1/128",
        dns: String = "8.8.8.8",
        publicKey: String = "gN65BkIKpceTeGn0Fu4/4WucyAEjeU0efwKWSY+KaHc=",
        endpoint: String = "192.0.2.1:51820",
        allowedIPs: String = "0.0.0.0/0,::/0",
        persistentKeepalive: Int = 25,
        awg: AwgParams = defaultAwg
    ) -> WireGuardConfigResponse {
        WireGuardConfigResponse(
            privateKey: privateKey,
            address: address,
            dns: dns,
            peer: PeerConfig(
                publicKey: publicKey,
                endpoint: endpoint,
                allowedIPs: allowedIPs,
                persistentKeepalive: persistentKeepalive
            ),
            awg: awg
        )
    }

    // MARK: - buildWgQuickConfig Tests

    @Test func buildConfig_IPv6Enabled_containsBothAddresses() {
        let response = makeConfig(address: "10.0.0.1/32,fd00::1/128")
        let config = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: true)

        #expect(config.contains("10.0.0.1/32"))
        #expect(config.contains("fd00::1/128"))
    }

    @Test func buildConfig_IPv6Disabled_stripsIPv6Address() {
        let response = makeConfig(address: "10.0.0.1/32,fd00::1/128")
        let config = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: false)

        #expect(config.contains("10.0.0.1/32"))
        #expect(!config.contains("fd00::1/128"))
    }

    @Test func buildConfig_IPv6Disabled_keepsIPv6InAllowedIPs() {
        let response = makeConfig(address: "10.0.0.1/32,fd00::1/128")
        let config = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: false)

        // ::/0 must remain to black-hole IPv6 traffic and prevent leaks
        #expect(config.contains("::/0"))
    }

    @Test func buildConfig_containsAllSections() {
        let response = makeConfig()
        let config = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: true)

        #expect(config.contains("[Interface]"))
        #expect(config.contains("[Peer]"))
        #expect(config.contains("PrivateKey = YF4d8SZtNXPFOmQxgHr9SZ5QUt+gJCVmH0nZ3QvJvUQ="))
        #expect(config.contains("DNS = 8.8.8.8"))
        #expect(config.contains("PublicKey = gN65BkIKpceTeGn0Fu4/4WucyAEjeU0efwKWSY+KaHc="))
        #expect(config.contains("Endpoint = 192.0.2.1:51820"))
        #expect(config.contains("PersistentKeepalive = 25"))
    }

    @Test func buildConfig_IPv6Disabled_multipleIPv6Addresses() {
        let response = makeConfig(address: "10.0.0.1/32, fd00::1/128, fd00::2/128")
        let config = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: false)

        #expect(config.contains("10.0.0.1/32"))
        #expect(!config.contains("fd00::1/128"))
        #expect(!config.contains("fd00::2/128"))
    }

    @Test func buildConfig_IPv4Only_noChangeWhenIPv6Disabled() {
        let response = makeConfig(address: "10.0.0.1/32")
        let configEnabled = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: true)
        let configDisabled = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: false)

        #expect(configEnabled.contains("10.0.0.1/32"))
        #expect(configDisabled.contains("10.0.0.1/32"))
    }

    // MARK: - parseEndpoint Tests

    @Test func parseEndpoint_validIPv4WithPort() {
        let result = TunnelConfigService.parseEndpoint("192.0.2.1:51820")
        #expect(result?.ip == "192.0.2.1")
        #expect(result?.port == 51820)
    }

    @Test func parseEndpoint_maxPort() {
        let result = TunnelConfigService.parseEndpoint("192.0.2.1:65535")
        #expect(result?.ip == "192.0.2.1")
        #expect(result?.port == 65535)
    }

    @Test func parseEndpoint_minPort() {
        let result = TunnelConfigService.parseEndpoint("10.0.0.1:1")
        #expect(result?.ip == "10.0.0.1")
        #expect(result?.port == 1)
    }

    @Test func parseEndpoint_noPort_returnsNil() {
        #expect(TunnelConfigService.parseEndpoint("192.0.2.1") == nil)
    }

    @Test func parseEndpoint_nonNumericPort_returnsNil() {
        #expect(TunnelConfigService.parseEndpoint("192.0.2.1:abc") == nil)
    }

    @Test func parseEndpoint_portOverflow_returnsNil() {
        // UInt16 max is 65535, so 65536 should fail
        #expect(TunnelConfigService.parseEndpoint("192.0.2.1:65536") == nil)
    }

    @Test func parseEndpoint_emptyString_returnsNil() {
        #expect(TunnelConfigService.parseEndpoint("") == nil)
    }

    // MARK: - AWG Parameter Tests

    @Test func buildConfig_containsAwgParams() {
        let awg = AwgParams(jc: 4, jmin: 40, jmax: 70, s1: 0, s2: 0, h1: 1, h2: 2, h3: 3, h4: 4)
        let response = makeConfig(awg: awg)
        let config = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: true)

        #expect(config.contains("Jc = 4"))
        #expect(config.contains("Jmin = 40"))
        #expect(config.contains("Jmax = 70"))
        #expect(config.contains("S1 = 0"))
        #expect(config.contains("S2 = 0"))
        #expect(config.contains("H1 = 1"))
        #expect(config.contains("H2 = 2"))
        #expect(config.contains("H3 = 3"))
        #expect(config.contains("H4 = 4"))
    }

    @Test func buildConfig_awgParamsInInterfaceSection() {
        let awg = AwgParams(jc: 7, jmin: 10, jmax: 50, s1: 5, s2: 10, h1: 100, h2: 200, h3: 300, h4: 400)
        let response = makeConfig(awg: awg)
        let config = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: true)

        // AWG params must appear before [Peer] (i.e., in [Interface])
        let interfaceRange = config.range(of: "[Interface]")!
        let peerRange = config.range(of: "[Peer]")!
        let jcRange = config.range(of: "Jc = 7")!

        #expect(jcRange.lowerBound > interfaceRange.lowerBound)
        #expect(jcRange.lowerBound < peerRange.lowerBound)
    }

    @Test func buildConfig_awgParams_ipv6DisabledPreservesAwgValues() {
        let awg = AwgParams(jc: 4, jmin: 40, jmax: 70, s1: 0, s2: 0, h1: 1, h2: 2, h3: 3, h4: 4)
        let response = makeConfig(address: "10.0.0.1/32,fd00::1/128", awg: awg)
        let config = TunnelConfigService.buildWgQuickConfig(from: response, ipv6Enabled: false)

        #expect(config.contains("Jc = 4"))
        #expect(config.contains("H1 = 1"))
        #expect(!config.contains("fd00::1/128"))
    }
}
