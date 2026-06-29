# Changelog

All notable changes to WireDog VPN for iOS are documented here.

---

## [1.4.0] — 2026-06-07

### Added
- **AmneziaWG protocol** — WireDog now uses AmneziaWG as its VPN protocol, replacing standard WireGuard. AmneziaWG adds obfuscation parameters (Jc, Jmin, Jmax, S1, S2, H1–H4) sourced from the server config, making VPN traffic harder to detect and block on censored networks.
- **Real latency measurement** — Server latency is now measured via live TCP probes (port 443) rather than relying on server-reported values. DNS resolution is separated from the RTT measurement to avoid inflating results.
- **Smarter server recommendations** — The recommended servers list is now driven by actual measured latency, surfacing the fastest servers for your current network.

### Fixed
- **Latency polling accuracy** — Each server is now probed 3 times (200ms apart) and the lowest sample is used, reducing the impact of transient network spikes. Probes are capped at 20 concurrent connections to avoid flooding the network.

---

## [1.3.0] — 2026-05-12

### Added
- **Server Selector Sheet** — Tapping the server card on the Connect screen now opens a dedicated sheet with three sections: Favorites, Recommended (top 5 servers by speed), and All Servers. Previously tapping opened server stats regardless of context.
- **Server Stats Sheet** — When connected, tapping the active connection card opens a live stats view for the current server (latency, load, speed, uptime).
- **IP-based geo-location** — Current location is now determined via IP lookup instead of GPS. No location permission required. Displays as "City, ST" for US or "City, CC" international.
- **Favorites system improvements** — Star icons now update in real-time across all server list views including inline-expanded groups and the multi-server bottom sheet.
- **Server ID visible in server rows** — Server hostname is now shown in the server list for easier identification when selecting a specific node.

### Changed
- Connect screen card behavior redesigned: top card (active connection) opens stats when connected; bottom card (server selector) always opens the server picker.
- Server row layout updated to show country flag, city, server ID, load indicator, and speed together.

### Removed
- CoreLocation / GPS dependency fully removed. The app no longer requests location permission.
- Face ID / biometric authentication removed.
- Referral code field removed from account creation flow.
- `NSLocationWhenInUseUsageDescription` removed from Info.plist.
- `NSFaceIDUsageDescription` removed from Info.plist.

---

## [1.2.2] — 2026-04

### Added
- **In-App Purchases** — Subscription management via StoreKit. Monthly and annual plan options available.
- **Support section** — Report an issue directly from the Settings tab. Includes input validation and rate limiting.
- **Force update** — Server-driven minimum version check. Users on outdated builds are prompted to update before continuing.
- **Privacy disclosure** — Privacy policy link surfaced on the IAP presentation sheet per App Store guidelines.

### Changed
- Loading screen redesigned.
- Improved session ID reliability fixes.
- Active connection counter reworked for accuracy across reconnects.

### Fixed
- Server details tab showing incorrect data for the active server.
- Report an issue validation edge cases.
- Various small UI polish items.

---

## [1.2.1] — 2026-03

### Added
- **Unit test suite** — Initial coverage for auth service, keychain service, VPN manager state transitions, and API client.
- **Security hardening** — Increased security posture based on internal audit findings. Sensitive values redacted from logs.

### Changed
- Code cleanup pass across services and view models.
- Log verbosity reduced in production builds.

### Fixed
- Bug fixes across connection state management.

---

## [1.2.0] — 2026-02

### Added
- **Anonymous accounts** — Users can create and log in with a 16-digit account number, no email required.
- **Standard accounts** — Email and password registration with server-side validation.
- **Password reset flow** — Forgot password → email code → verify → set new password.
- **Kill switch** — Blocks all traffic if the VPN tunnel drops unexpectedly. Toggle in Settings.
- **DNS leak protection** — Forces DNS queries through the VPN tunnel. Always-on, independent of kill switch state.
- **IPv6 leak protection** — Disables IPv6 to prevent tunnel bypass. Configurable in Settings.
- **Auto-connect** — Automatically reconnects to the last-used server on app launch and when returning from background.
- **Interactive map** — SVG world map with server location markers. Tap a marker to select that server.
- **Server list with grouping** — Servers grouped by country. Single-server countries show as flat rows; multi-server countries expand inline (≤3 servers) or open a bottom sheet (>3 servers).
- **Favorites** — Star any server to pin it to the top of the list.
- **Server stats** — Load percentage, speed (mb/s), and latency displayed per server.

### Changed
- WireGuard used as the sole VPN protocol via the WireDogTunnel network extension.

---

## [1.0.0] — 2025

> Internal build. Not publicly released.

- Initial proof of concept.
- WireGuard tunnel integration via NetworkExtension.
- Basic connect/disconnect flow.
- Single hardcoded server for testing.
