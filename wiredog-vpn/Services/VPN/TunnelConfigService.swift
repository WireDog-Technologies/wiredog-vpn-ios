import Foundation

class TunnelConfigService {

    /// Builds a WireGuard quick config string from the API response
    /// When IPv6 is disabled: removes IPv6 interface addresses but keeps ::/0 in AllowedIPs to black-hole IPv6 traffic (prevents leaks)
    static func buildWgQuickConfig(from response: WireGuardConfigResponse, ipv6Enabled: Bool = true) -> String {
        let address: String
        if ipv6Enabled {
            address = response.address
        } else {
            // Remove IPv6 addresses from interface, keep only IPv4
            let addresses = response.address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let ipv4Only = addresses.filter { !$0.contains(":") }
            address = ipv4Only.joined(separator: ", ")
        }

        // AllowedIPs: always keep ::/0 to prevent IPv6 leaks (black-holes IPv6 when disabled)
        let allowedIPs = response.peer.allowedIPs

        let awg = response.awg
        return """
        [Interface]
        PrivateKey = \(response.privateKey)
        Address = \(address)
        DNS = \(response.dns)
        Jc = \(awg.jc)
        Jmin = \(awg.jmin)
        Jmax = \(awg.jmax)
        S1 = \(awg.s1)
        S2 = \(awg.s2)
        H1 = \(awg.h1)
        H2 = \(awg.h2)
        H3 = \(awg.h3)
        H4 = \(awg.h4)

        [Peer]
        PublicKey = \(response.peer.publicKey)
        Endpoint = \(response.peer.endpoint)
        AllowedIPs = \(allowedIPs)
        PersistentKeepalive = \(response.peer.persistentKeepalive)
        """
    }

    /// Parses the server endpoint to extract IP address and port
    static func parseEndpoint(_ endpoint: String) -> (ip: String, port: UInt16)? {
        let components = endpoint.split(separator: ":")
        guard components.count == 2,
              let port = UInt16(components[1]) else {
            return nil
        }
        return (String(components[0]), port)
    }
}
