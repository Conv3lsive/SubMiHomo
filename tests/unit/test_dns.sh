#!/bin/sh
# test_dns.sh — unit tests for dns.sh (real functions via DNSMASQ_DIR override)
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/mocks.sh"

cat >"$MOCK_UCI_FILE" <<EOF
submihomo.main.enabled=1
submihomo.main.log_level=warning
EOF

. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"

# Sandbox dnsmasq dir, set BEFORE sourcing dns.sh so DNSMASQ_CONF picks it up
SANDBOX="/tmp/sm_dns_test_$$"
mkdir -p "$SANDBOX/dnsmasq.d"
export DNSMASQ_DIR="$SANDBOX/dnsmasq.d"

. "$SCRIPT_DIR/../../files/usr/lib/submihomo/dns.sh"

# Stub reload to avoid touching real dnsmasq/ubus; record invocation
_dnsmasq_reload() {
    printf 'reload_called\n' >>"$MOCK_LOG"
    return 0
}

# ── dns_setup writes the correct directive ────────────────────────────────────
: >"$MOCK_LOG"
dns_setup
assert_zero "dns_setup returns 0 with valid dir" $?
content=$(cat "$DNSMASQ_CONF" 2>/dev/null)
assert_contains "conf has no-resolv" "no-resolv" "$content"
assert_contains "conf forwards to 127.0.0.1#1053" "server=127.0.0.1#1053" "$content"
assert_contains "dns_setup triggers reload" "reload_called" "$(cat "$MOCK_LOG")"

# ── dns_setup guard: missing dir ─────────────────────────────────────────────
DNSMASQ_DIR="/nonexistent_dir_$$"
DNSMASQ_CONF="$DNSMASQ_DIR/submihomo.conf"
dns_setup 2>/dev/null
assert_nonzero "dns_setup fails when dir missing" $?
# restore
DNSMASQ_DIR="$SANDBOX/dnsmasq.d"
DNSMASQ_CONF="$DNSMASQ_DIR/submihomo.conf"

# ── dns_teardown removes the file ────────────────────────────────────────────
dns_setup >/dev/null 2>&1
[ -f "$DNSMASQ_CONF" ]
assert_zero "conf exists before teardown" $?
: >"$MOCK_LOG"
dns_teardown
assert_zero "dns_teardown returns 0" $?
[ ! -f "$DNSMASQ_CONF" ]
assert_zero "conf removed after teardown" $?
assert_contains "dns_teardown triggers reload" "reload_called" "$(cat "$MOCK_LOG")"

# ── dns_teardown idempotent when conf absent ─────────────────────────────────
dns_teardown 2>/dev/null
assert_zero "dns_teardown idempotent (no conf present)" $?

# ── DNS_PORT constant ─────────────────────────────────────────────────────────
assert_eq "DNS_PORT is 1053" "1053" "$DNS_PORT"

rm -rf "$SANDBOX"
cleanup_mocks
print_test_summary
