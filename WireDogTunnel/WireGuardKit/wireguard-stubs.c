/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2018-2023 WireGuard LLC. All Rights Reserved.
 *
 * Stub implementations for simulator builds where libwg-go is not available.
 * VPN extensions cannot run in simulator anyway, so these are just placeholders.
 * These stubs provide weak symbols that can be overridden by the real library.
 */

#include <stdint.h>
#include <stdlib.h>

typedef void(*logger_fn_t)(void *context, int level, const char *msg);

// Use weak symbols so the real library can override these if present

__attribute__((weak))
void wgSetLogger(void *context, logger_fn_t logger_fn) {
    // Stub: do nothing
}

__attribute__((weak))
int wgTurnOn(const char *settings, int32_t tun_fd) {
    // Stub: return error code indicating not supported
    return -1;
}

__attribute__((weak))
void wgTurnOff(int handle) {
    // Stub: do nothing
}

__attribute__((weak))
int64_t wgSetConfig(int handle, const char *settings) {
    // Stub: return error code
    return -1;
}

__attribute__((weak))
char *wgGetConfig(int handle) {
    // Stub: return NULL
    return NULL;
}

__attribute__((weak))
void wgBumpSockets(int handle) {
    // Stub: do nothing
}

__attribute__((weak))
void wgDisableSomeRoamingForBrokenMobileSemantics(int handle) {
    // Stub: do nothing
}

__attribute__((weak))
const char *wgVersion(void) {
    return "simulator-stub";
}
