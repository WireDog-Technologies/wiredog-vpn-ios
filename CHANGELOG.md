# Changelog

All notable changes to WireDog VPN for iOS are documented here.

---

## [1.6.0] — 2026-08-01

### Added
- **Live connection-status map markers** — Server markers on the map now reflect real-time connection state: green while connected, gold while connecting/reconnecting/disconnecting, red when idle. Previously markers only showed a static "selected" highlight regardless of tunnel state.
- **Cancel an in-progress connection** — Tapping Connect again while connecting or reconnecting now cancels the attempt, instead of leaving no way to back out. Surfaces as a new `VPNError.cancelled` case with no error alert, since it's user-initiated.
- **Live server switching** — Tapping a different server while already connected or connecting now automatically disconnects the current tunnel and connects to the new selection, instead of just updating the highlighted server and requiring a manual disconnect first.

### Changed
- **Reworked connect/disconnect session lifecycle** — Session cleanup is now tracked more reliably: a leaked session (e.g. connect failing after the backend already incremented the device counter) is cleaned up immediately, pending `/disconnect` calls that failed to confirm (e.g. due to lost connectivity) are persisted and retried on next launch/foreground, and reconnect backoff timing is now configurable internally rather than fixed.
- **Loading state during connection transitions** — The public IP and location text now show "Loading..." while connecting, disconnecting, or reconnecting, instead of briefly displaying stale or misleading values from before the transition.
- **Smarter auto-reconnect abort** — Auto-reconnect now stops immediately when the failure is "another VPN app's configuration is active," instead of burning through all retry attempts against a system VPN slot it can't win back on its own.

### Fixed
- **Connection timer resetting after force-quit** — Reopening the app while still connected showed the timer restarting from 0 instead of continuing from the original connection time. A spurious initial state event was clearing the persisted start time before the real tunnel status was known; that event is now ignored.
- **Inaccurate location shown after force-quit → disconnect** — The displayed location wasn't refreshed after disconnecting, so it could continue showing the VPN server's exit location captured at launch instead of the user's real location.
- **Selected server not restored after force-quitting while connected** — Relaunching the app while still connected could default the server selection to the first server in the list instead of the one actually connected, causing the wrong server name to display.
- **False "Unable to verify subscription status" errors** — The pre-connect profile refresh could fail on a stale pooled network connection left over from a recent network change (e.g. relaunching after switching Wi-Fi/cellular), incorrectly blocking connection even with a valid subscription. Network connections are now reset before this check.
- **Public IP not updating reliably after connect/disconnect** — IP lookups could keep reusing a pooled socket opened over the previous network interface, silently returning the pre-change IP. Pooled connections are now reset after every connect and disconnect.

---

## [1.5.0] — 2026-07-17

### Added
- **Togglable DNS filters** — Block Ads and Block Malware can now be enabled or disabled independently in Settings, rather than being bundled together.

### Fixed
- **Conflicting VPN configuration error messaging** — Connecting while another VPN app's configuration is active previously surfaced a raw system error (`NEVPNErrorDomain error 2`). Now shows a clear, actionable message: "Another VPN configuration is selected. Go to Settings > VPN, and select WireDog VPN."
- **iOS update-policy version check** — The app-update version comparison was parsing only the major digit of the marketing version string (e.g. "1.4.0" → 1), so it could never distinguish between builds sharing a major version. Now compares `CFBundleVersion` (build number) directly, matching Android's `versionCode` convention.
- **Tunnel extension bundle version mismatch** — WireDogTunnel's `CURRENT_PROJECT_VERSION` was out of sync with the parent app, triggering an Xcode validation warning on every build. Now kept in lockstep with the app's build number.

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
