# WireDog VPN - iOS Application

Copyright (c) 2026 WireDog Technologies

[![License: GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Swift 5.5+](https://img.shields.io/badge/Swift-5.5%2B-orange.svg)](https://swift.org)
[![iOS 14+](https://img.shields.io/badge/iOS-14%2B-green.svg)](https://www.apple.com/ios/)

## Features

- **WireGuard VPN Protocol** - Modern, efficient, and secure VPN implementation
- **Secure Authentication** - Email/password and anonymous account options
- **Kill Switch** - Prevents data leaks if VPN connection drops
- **Auto-Connect** - Automatically reconnect to VPN on network changes
- **Server Selection** - Choose from multiple VPN servers with favorites/recents
- **Subscription Management** - Built-in subscription validation and management
- **Network Extension** - Native iOS integration using NetworkExtension framework
- **On-Device Logging** - Privacy-respecting debug logs with PII redaction

## Requirements

- **macOS**: 12.0 or later (for development)
- **Xcode**: 14.0 or later
- **Swift**: 5.5 or later
- **iOS**: 14.0 or later (target)
- **Developer Account**: Apple Developer Program membership (required for VPN entitlements)

### VPN Entitlements

Building this project requires special VPN entitlements from Apple:

1. **App Group Capability** - For keychain sharing between app and network extension
2. **Network Extension Capability** - For VPN tunnel implementation
3. **VPN Configuration** - Request through Apple Developer Portal

To enable VPN capabilities:

1. Log in to [Apple Developer Portal](https://developer.apple.com)
2. Go to **Certificates, Identifiers & Profiles** → **Identifiers**
3. Select your app identifier and enable the required capabilities:
   - App Groups
   - Network Extension
   - Personal VPN
4. Save and update your provisioning profiles
5. In Xcode, go to **Signing & Capabilities** and confirm all entitlements are present

## Setup

1. **Clone the repository**

2. **Create a Config.xcconfig build configuration**

3. **Open wiredog-vpn.xcodeproj in Xcode**
   - Go to **Signing & Capabilities** → Select your team
   - Update bundle identifiers for all targets
   - Clean build folder: Cmd+Shift+K


## Project Structure

```
wiredog-vpn-ios/
├── wiredog-vpn/              # Main iOS app
│   ├── Services/             # Auth, API, VPN, Keychain, Logging
│   ├── ViewModels/           # MVVM view models
│   ├── Views/                # SwiftUI UI
│   ├── Models/               # Data models
│   └── Components/           # Reusable UI components
├── WireDogTunnel/            # Network extension (VPN tunnel)
├── wiredog-vpnTests/         # Unit and UI tests
```

## Security Issues

**Do not open public GitHub issues for security vulnerabilities.**

If you believe you have found a security vulnerability, please email support@wiredogvpn.com with a description of the vulnerability, steps to reproduce, potential impact, and suggested fix if available.

## License

Licensed under the **GNU General Public License v3 (GPLv3)**. See [`LICENSE`](LICENSE) for details.

This project includes WireGuardKit (MIT License). See [`ACKNOWLEDGMENTS.md`](ACKNOWLEDGMENTS.md) for full attribution.

## Questions?

- Open a [GitHub Issue](https://github.com/[fill]/wiredog-vpn-ios/issues)
- Read [`CONTRIBUTING.md`](CONTRIBUTING.md) for contribution guidelines
