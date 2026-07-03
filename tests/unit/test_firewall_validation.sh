#!/bin/sh
# test_firewall_validation.sh — unit tests for firewall.sh bypass CIDR validation
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/mocks.sh"

cat >"$MOCK_UCI_FILE" <<EOF
submihomo.main.enabled=1
submihomo.bypass.address=192.168.0.0/16
EOF

. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"

# ── validate_cidr boundary tests ─────────────────────────────────────────────
validate_cidr "0.0.0.0/0"
assert_zero "valid: 0.0.0.0/0" $?

validate_cidr "255.255.255.255/32"
assert_zero "valid: 255.255.255.255/32" $?

validate_cidr "10.50.0.0/16"
assert_zero "valid: 10.50.0.0/16" $?

validate_cidr "203.0.113.42/32"
assert_zero "valid: 203.0.113.42/32 (single host)" $?

validate_cidr "100.64.0.0/10"
assert_zero "valid: 100.64.0.0/10 (CGNAT)" $?

validate_cidr "256.0.0.0/8"
assert_nonzero "invalid: 256.0.0.0/8 (octet out of range)" $?

validate_cidr "10.0.0.0/33"
assert_nonzero "invalid: /33 (prefix > 32)" $?

validate_cidr "10.0.0.0/-1"
assert_nonzero "invalid: negative prefix" $?

validate_cidr "10.0.0"
assert_nonzero "invalid: only 3 octets, no prefix" $?

validate_cidr "10.0.0.0"
assert_nonzero "invalid: no prefix length" $?

validate_cidr "not.an.ip/24"
assert_nonzero "invalid: non-numeric octets" $?

validate_cidr "fd00::/8"
assert_nonzero "invalid: IPv6 CIDR rejected" $?

validate_cidr "::/0"
assert_nonzero "invalid: pure IPv6" $?

validate_cidr ""
assert_nonzero "invalid: empty string" $?

# ── firewall_setup: records nft commands ─────────────────────────────────────
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/firewall.sh"
: >"$MOCK_LOG"
firewall_setup 2>/dev/null
assert_zero "firewall_setup returns 0 with mock nft" $?
assert_contains "firewall_setup calls nft" "nft" "$(cat "$MOCK_LOG")"

# ── firewall_teardown: records nft delete ────────────────────────────────────
: >"$MOCK_LOG"
firewall_teardown 2>/dev/null
assert_zero "firewall_teardown returns 0" $?

# ── firewall_setup with invalid bypass CIDR ───────────────────────────────────
cat >"$MOCK_UCI_FILE" <<EOF2
submihomo.main.enabled=1
submihomo.bypass.address=not.valid/99
EOF2
: >"$MOCK_LOG"
firewall_setup 2>/dev/null
assert_zero "firewall_setup succeeds even with invalid bypass CIDR (skips it)" $?
# The warning may be in a subshell (piped while loop) — verify no invalid CIDR ends up in the nft call
assert_not_contains "invalid CIDR not passed to nft" "not.valid" "$(cat "$MOCK_LOG")"

# ── bypass_china: not in firewall.sh rules ───────────────────────────────────
# Verify firewall.sh does not implement bypass_china via nft
grep -q "GEOIP" "$SCRIPT_DIR/../../files/usr/lib/submihomo/firewall.sh" 2>/dev/null
assert_nonzero "firewall.sh must not contain GEOIP logic (belongs in config.sh)" $?

cleanup_mocks
print_test_summary
