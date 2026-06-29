// SPDX-License-Identifier: MIT
// Copyright © 2018-2023 WireGuard LLC. All Rights Reserved.

import Foundation
import Network

enum TunnelConfigurationParseError: Error {
    case missingPrivateKey
    case invalidPrivateKey
    case invalidPublicKey
    case invalidAddress
    case invalidDNS
    case invalidEndpoint
    case invalidAllowedIP
    case invalidPersistentKeepalive
    case noPeersSpecified
    case invalidConfigFormat
}

extension TunnelConfiguration {
    /// Parse a WireGuard configuration string in "wg-quick" format
    public convenience init(fromWgQuickConfig configString: String, called name: String? = nil) throws {
        var interfaceConfig: InterfaceConfiguration?
        var peerConfigs: [PeerConfiguration] = []

        var currentSection: String?
        var currentPeer: PeerConfiguration?

        let lines = configString.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Check for section headers
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // Save current peer if we're leaving a Peer section
                if currentSection == "Peer", let peer = currentPeer {
                    peerConfigs.append(peer)
                    currentPeer = nil
                }

                let sectionName = String(trimmed.dropFirst().dropLast())
                currentSection = sectionName

                if sectionName == "Peer" {
                    currentPeer = nil // Will be created when PublicKey is found
                }

                continue
            }

            // Parse key-value pairs
            guard let equalsIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = trimmed[..<equalsIndex].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)

            // Parse based on current section
            if currentSection == "Interface" {
                if interfaceConfig == nil {
                    // We need PrivateKey first to create InterfaceConfiguration
                    if key == "PrivateKey" {
                        guard let privateKey = PrivateKey(base64Key: value) else {
                            throw TunnelConfigurationParseError.invalidPrivateKey
                        }
                        interfaceConfig = InterfaceConfiguration(privateKey: privateKey)
                    }
                } else {
                    // Parse other interface fields
                    try TunnelConfiguration.parseInterfaceField(key: key, value: value, into: &interfaceConfig!)
                }
            } else if currentSection == "Peer" {
                // Create peer if we don't have one yet
                if currentPeer == nil {
                    if key == "PublicKey" {
                        guard let publicKey = PublicKey(base64Key: value) else {
                            throw TunnelConfigurationParseError.invalidPublicKey
                        }
                        currentPeer = PeerConfiguration(publicKey: publicKey)
                    }
                } else {
                    // Parse other peer fields
                    try TunnelConfiguration.parsePeerField(key: key, value: value, into: &currentPeer!)
                }
            }
        }

        // Save last peer if any
        if let peer = currentPeer {
            peerConfigs.append(peer)
        }

        // Validate we have required configuration
        guard let interface = interfaceConfig else {
            throw TunnelConfigurationParseError.missingPrivateKey
        }

        guard !peerConfigs.isEmpty else {
            throw TunnelConfigurationParseError.noPeersSpecified
        }

        self.init(name: name, interface: interface, peers: peerConfigs)
    }

    private static func parseInterfaceField(key: String, value: String, into config: inout InterfaceConfiguration) throws {
        switch key {
        case "PrivateKey":
            // Already handled during initialization
            break

        case "Address":
            // Parse comma-separated addresses
            let addressStrings = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for addressString in addressStrings {
                guard let addressRange = IPAddressRange(from: addressString) else {
                    throw TunnelConfigurationParseError.invalidAddress
                }
                config.addresses.append(addressRange)
            }

        case "DNS":
            // Parse comma-separated DNS servers
            let dnsStrings = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for dnsString in dnsStrings {
                guard let dnsServer = DNSServer(from: dnsString) else {
                    throw TunnelConfigurationParseError.invalidDNS
                }
                config.dns.append(dnsServer)
            }

        case "ListenPort":
            if let port = UInt16(value) {
                config.listenPort = port
            }

        case "MTU":
            if let mtu = UInt16(value) {
                config.mtu = mtu
            }

        case "Jc":
            if let v = UInt16(value) { config.junkPacketCount = v }
        case "Jmin":
            if let v = UInt16(value) { config.junkPacketMinSize = v }
        case "Jmax":
            if let v = UInt16(value) { config.junkPacketMaxSize = v }
        case "S1":
            if let v = UInt16(value) { config.initPacketJunkSize = v }
        case "S2":
            if let v = UInt16(value) { config.responsePacketJunkSize = v }
        case "H1":
            if let v = UInt32(value) { config.initPacketMagicHeader = v }
        case "H2":
            if let v = UInt32(value) { config.responsePacketMagicHeader = v }
        case "H3":
            if let v = UInt32(value) { config.underloadPacketMagicHeader = v }
        case "H4":
            if let v = UInt32(value) { config.transportPacketMagicHeader = v }

        default:
            // Ignore unknown fields
            break
        }
    }

    private static func parsePeerField(key: String, value: String, into peer: inout PeerConfiguration) throws {
        switch key {
        case "PublicKey":
            // Already handled during initialization
            break

        case "Endpoint":
            guard let endpoint = Endpoint(from: value) else {
                throw TunnelConfigurationParseError.invalidEndpoint
            }
            peer.endpoint = endpoint

        case "AllowedIPs":
            // Parse comma-separated allowed IPs
            let allowedIPStrings = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for allowedIPString in allowedIPStrings {
                guard let ipRange = IPAddressRange(from: allowedIPString) else {
                    throw TunnelConfigurationParseError.invalidAllowedIP
                }
                peer.allowedIPs.append(ipRange)
            }

        case "PersistentKeepalive", "PersistentKeepaliveInterval":
            if let keepalive = UInt16(value), keepalive > 0 {
                peer.persistentKeepAlive = keepalive
            }

        case "PreSharedKey", "PresharedKey":
            if let preSharedKey = PreSharedKey(base64Key: value) {
                peer.preSharedKey = preSharedKey
            }

        default:
            // Ignore unknown fields
            break
        }
    }
}
