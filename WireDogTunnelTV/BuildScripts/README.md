# `libwg-go.a` for tvOS — build recipe

`Frameworks/libwg-go.a` in this folder's parent (`WireDogTunnelTV/`) was built with the recipe
below and verified tvOS-tagged — see "Verification" section.

## Source

The Go source (`api-apple.go`, cgo bridge exposing `wgTurnOn`/`wgTurnOff`/etc. as C symbols) comes
from a fork of upstream WireGuard's `wireguard-apple` with AmneziaWG obfuscation support, at the
`Sources/WireGuardKitGo/` path within that fork.

- Dependency pins (from that source's `go.mod`): `github.com/amnezia-vpn/amneziawg-go v0.2.8`,
  `golang.org/x/sys v0.21.0` (matches the AmneziaWG obfuscation params — Jc/Jmin/Jmax — already
  used throughout this app's `WireDogTunnel/`)
- Built with: `go1.25.5 darwin/arm64` (locally installed via Homebrew). The source declares
  `go 1.21` as its minimum; any reasonably current Go toolchain should work the same way, since
  the build process copies the *local* `go env GOROOT` and patches it (see below) rather than
  depending on a network-fetched toolchain version.

The Go source itself needed zero changes for tvOS. `api-apple.go` only touches Go stdlib,
`golang.org/x/sys/unix`, and `amneziawg-go`'s `conn`/`device`/`tun` packages — nothing
iOS-specific (no UIKit, no `#if TARGET_OS_IOS`). The only actual blocker was the build tooling.

## The fix

`WireGuardKitGo.Makefile` in this folder is the source `Makefile` (from the path above) with one
addition: it originally only mapped `GOOS_macosx := darwin` and `GOOS_iphoneos := ios` — there
was no `appletvos` case, so `PLATFORM_NAME=appletvos` silently resolved to an empty `GOOS`, i.e.
"whatever the host's default is." Fixed by adding:

```make
GOOS_appletvos := ios
GOOS_appletvsimulator := ios
```

Go has no `tvos` `GOOS` value at all (only `ios` and `darwin` exist for Apple platforms). tvOS is
close enough to iOS at the raw syscall/runtime level — same XNU/Darwin base, same tun/utun device
handling — that reusing the `ios` `GOOS` bucket works: the actual tvOS SDK/architecture/deployment
-target selection happens entirely through clang's `-isysroot`/`-arch`/`-mtvos-version-min` flags
(already wired generically in the Makefile's `CFLAGS_PREFIX`, driven by whatever `SDKROOT` /
`DEPLOYMENT_TARGET_CLANG_*` values get passed in), not through Go's own `GOOS` labeling.

The `goruntime-boottime-over-monotonic.diff` runtime patch (swaps `mach_absolute_time` for
`mach_continuous_time` in the Go runtime's `nanotime`, so timers survive device sleep) needed no
changes either — it touches generic Darwin runtime files (`sys_darwin.go`,
`sys_darwin_{amd64,arm64}.s`), and `mach_continuous_time` is available on tvOS identically to iOS.

## How to rebuild it

```bash
# 1. Get a clean copy of the Go source (don't build in-place inside an existing checkout of the
#    fork — its out/ and .tmp/ build-cache dirs can contain stale artifacts from a previous
#    macOS/iOS build, which will make `make` skip recompilation and just relink the old binary).
cp -R /path/to/wireguard-apple-fork/Sources/WireGuardKitGo /tmp/libwg-build
cp WireGuardKitGo.Makefile /tmp/libwg-build/Makefile   # this folder's patched copy

# 2. Build
cd /tmp/libwg-build
make \
  PLATFORM_NAME=appletvos \
  ARCHS=arm64 \
  SDKROOT="$(xcrun --sdk appletvos --show-sdk-path)" \
  DEPLOYMENT_TARGET_CLANG_FLAG_NAME=mtvos-version-min \
  DEPLOYMENT_TARGET_CLANG_ENV_NAME=TVOS_DEPLOYMENT_TARGET \
  TVOS_DEPLOYMENT_TARGET=17.0 \
  build

# Output: /tmp/libwg-build/out/libwg-go.a
```

Only `arm64` is built — there's no point building an x86_64/simulator slice, since
`NEPacketTunnelProvider` tunnels can't run in the tvOS Simulator at all regardless (same Apple
platform limitation as iOS Simulator) — a device is required to ever exercise this.

## Verification

```bash
# Every LC_BUILD_VERSION load command in the archive reports the same platform/version:
otool -l out/libwg-go.a | grep -A4 LC_BUILD_VERSION
#   platform 3      <- PLATFORM_TVOS (2 would be PLATFORM_IOS, 1 PLATFORM_MACOS)
#   minos 17.0      <- matches TVOS_DEPLOYMENT_TARGET

# All expected exported C symbols present (same interface the existing iOS libwg-go.a and this
# app's WireDogTunnel/ Swift wrapper already expect):
nm out/libwg-go.a | grep " T _wg"
#   _wgSetLogger _wgTurnOn _wgTurnOff _wgSetConfig _wgGetConfig _wgBumpSockets _wgVersion
#   _wgDisableSomeRoamingForBrokenMobileSemantics

# Links clean (no undefined symbols) against the tvOS SDK:
clang -isysroot "$(xcrun --sdk appletvos --show-sdk-path)" -arch arm64 -mtvos-version-min=17.0 \
  -o /tmp/wgtest main.c out/libwg-go.a -framework CoreFoundation -framework Security -lresolv
otool -l /tmp/wgtest | grep -A4 LC_BUILD_VERSION   # also platform 3, minos 17.0
```

This confirms the artifact is correctly built and linkable for tvOS. It has **not** been
exercised inside an actual running `NEPacketTunnelProvider` on a physical Apple TV yet — the
tvOS Simulator can't run packet-tunnel extensions at all, so a real device is required for that.
