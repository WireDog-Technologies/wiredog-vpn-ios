# WireGuardKit Integration

This folder contains the WireGuard Swift sources for the VPN tunnel.

## Files Included

**Swift Sources** (from wireguard-apple):
- `WireGuardAdapter.swift` - Core tunnel management
- `TunnelConfiguration.swift` - Config parsing
- `PacketTunnelSettingsGenerator.swift` - NE settings
- `PrivateKey.swift`, `Endpoint.swift`, etc.

**C Bridge** (for key generation):
- `WireGuardKitC.h`, `key.c`, `key.h`, `x25519.c`, `x25519.h`

**Go Bridge Header**:
- `wireguard.h` - Interface to libwg-go

## Missing: libwg-go.a

The `libwg-go.a` static library is **NOT included** because it must be built from Go source code. You need to obtain this library and place it in:

```
WireDogTunnel/Frameworks/libwg-go.a
```

### Option 1: Build libwg-go.a Yourself (Recommended)

**Prerequisites:**
- Go 1.19 or later: `brew install go`
- Xcode Command Line Tools

**Build Steps:**
```bash
# Clone wireguard-apple
git clone https://git.zx2c4.com/wireguard-apple
cd wireguard-apple/Sources/WireGuardKitGo

# Build for iOS device (arm64)
make PLATFORM_NAME=iphoneos ARCHS=arm64

# Copy the output
cp libwg-go.a /path/to/wiredog-test-vpn/WireDogTunnel/Frameworks/
```

For simulator support (x86_64 + arm64):
```bash
make PLATFORM_NAME=iphonesimulator ARCHS="x86_64 arm64"
```

### Option 2: Use Xcode External Build System

Add an "External Build System" target in Xcode:

1. File > New > Target > External Build System
2. Name: `WireGuardGoBridge`
3. Build Tool: `/usr/bin/make`
4. Directory: Point to WireGuardKitGo source
5. Arguments: `PLATFORM_NAME=$(PLATFORM_NAME) SDKROOT=$(SDKROOT) CONFIGURATION_BUILD_DIR=$(CONFIGURATION_BUILD_DIR)`
6. Add as dependency to WireDogTunnel target

### Option 3: Find Pre-built Binary

Some community projects provide pre-built binaries:
- Check GitHub releases for WireGuard iOS projects
- Note: May not be up-to-date or may lack simulator support

## Xcode Setup

After placing `libwg-go.a`:

1. **Add Files to Project:**
   - Right-click WireDogTunnel > Add Files
   - Select all files in this WireGuardKit folder
   - Check "Copy items if needed"
   - Add to target: WireDogTunnel only

2. **Link Library:**
   - Select WireDogTunnel target
   - Build Phases > Link Binary With Libraries
   - Add `libwg-go.a` from Frameworks folder

3. **Library Search Paths:**
   - Build Settings > Library Search Paths
   - Add: `$(PROJECT_DIR)/WireDogTunnel/Frameworks`

4. **Header Search Paths (if needed):**
   - Build Settings > Header Search Paths
   - Add: `$(PROJECT_DIR)/WireDogTunnel/WireGuardKit`

5. **Bridging Header:**
   - Build Settings > Swift Compiler - General
   - Objective-C Bridging Header: `WireDogTunnel/WireGuardKit/WireGuardKitC.h`

## Verification

After setup, build the project. You should see:
- No "Cannot find type 'WireGuardAdapter'" errors
- No linker errors for `wgTurnOn`, `wgTurnOff` symbols

If you see linker errors, verify:
- libwg-go.a is properly linked
- Library Search Paths are correct
- Building for the correct architecture (device vs simulator)
