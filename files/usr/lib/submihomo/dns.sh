#!/bin/sh
# dns.sh — dnsmasq integration for Mihomo DNS forwarding
# shellcheck shell=sh
. "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/core.sh"

# DNSMASQ_DIR may be overridden in test environments; defaults to the real path.
DNSMASQ_DIR="${DNSMASQ_DIR:-/etc/dnsmasq.d}"
DNSMASQ_CONF="$DNSMASQ_DIR/submihomo.conf"

dns_setup() {
    if [ ! -d "$DNSMASQ_DIR" ]; then
        log_error "[dns] $DNSMASQ_DIR does not exist — is dnsmasq installed?"
        return 1
    fi
    # Write forwarding directive. no-resolv prevents fallback to /etc/resolv.conf
    # when Mihomo is active, which is intentional — all DNS must go through Mihomo.
    if ! printf 'no-resolv\nserver=127.0.0.1#%s\n' "$DNS_PORT" >"$DNSMASQ_CONF"; then
        log_error "[dns] failed to write $DNSMASQ_CONF"
        return 1
    fi
    chmod 644 "$DNSMASQ_CONF"
    _dnsmasq_reload
    log_info "[dns] dnsmasq forwarding to 127.0.0.1#$DNS_PORT configured"
}

dns_teardown() {
    [ -f "$DNSMASQ_CONF" ] || {
        log_warn "[dns] $DNSMASQ_CONF not present, skipping"
        return 0
    }
    rm -f "$DNSMASQ_CONF"
    _dnsmasq_reload
    log_info "[dns] dnsmasq forwarding configuration removed"
}

_dnsmasq_reload() {
    # Prefer ubus call (OpenWrt native) over direct HUP
    if ubus call service dnsmasq reload '{}' >/dev/null 2>&1; then
        log_debug "[dns] dnsmasq reloaded via ubus"
        return 0
    fi
    # Fallback: find pid file and send HUP
    for pidfile in /var/run/dnsmasq/dnsmasq.pid /var/run/dnsmasq.pid /tmp/run/dnsmasq.pid; do
        if [ -f "$pidfile" ]; then
            pid=$(cat "$pidfile" 2>/dev/null)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                kill -HUP "$pid" 2>/dev/null &&
                    log_debug "[dns] sent HUP to dnsmasq (pid $pid)" && return 0
            fi
        fi
    done
    # Last resort: pgrep
    pid=$(pgrep -x dnsmasq 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        kill -HUP "$pid" 2>/dev/null &&
            log_debug "[dns] sent HUP to dnsmasq (pid $pid)" && return 0
    fi
    log_warn "[dns] dnsmasq not running; config will take effect when dnsmasq starts"
}
