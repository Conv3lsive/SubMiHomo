#!/bin/sh
# test_rpcd_validate.sh — unit tests for the rpcd Lua validate() input gate
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/mocks.sh"

RPCD="$SCRIPT_DIR/../../files/usr/lib/rpcd/submihomo"
MOCK_LUA="$SCRIPT_DIR/mocks/lua"
[ -f "$RPCD" ] || { printf '[FAIL] rpcd plugin not found\n'; exit 1; }

_run_set_config() {
    LUA_PATH="$MOCK_LUA/?.lua;$MOCK_LUA/?/init.lua;;" \
        lua "$RPCD" set_config <<EOF
$1
EOF
}

_parse_success() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("success"))'; }
_parse_errors() { printf '%s' "$1" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("errors",[])))'; }

# ── Invalid: enabled=2 ────────────────────────────────────────────────────────
out=$(_run_set_config '{"main":{"enabled":"2"}}')
assert_nonzero "validate rejects enabled=2" "$(printf '%s' "$out" | grep -c 'success":false')"
assert_contains "enabled error present" "enabled: must be 0 or 1" "$(_parse_errors "$out")"

# ── Invalid: subscription_url not HTTPS ───────────────────────────────────────
out=$(_run_set_config '{"main":{"subscription_url":"http://example.com/sub"}}')
assert_nonzero "validate rejects http subscription_url" "$(printf '%s' "$out" | grep -c 'success":false')"
assert_contains "subscription_url error present" "subscription_url: must be empty or begin with https://" "$(_parse_errors "$out")"

# ── Invalid: external_controller_port conflicts with reserved port ────────────
out=$(_run_set_config '{"main":{"external_controller_port":"7891"}}')
assert_nonzero "validate rejects reserved controller port" "$(printf '%s' "$out" | grep -c 'success":false')"
assert_contains "reserved port error present" "external_controller_port: conflicts with reserved SubMiHomo port" "$(_parse_errors "$out")"

# ── Invalid: bypass address CIDR ──────────────────────────────────────────────
out=$(_run_set_config '{"main":{},"bypass":{"address":["256.0.0.0/8"]}}')
assert_nonzero "validate rejects invalid bypass CIDR" "$(printf '%s' "$out" | grep -c 'success":false')"
assert_contains "bypass CIDR error present" "bypass.address\\[1\\]: invalid CIDR" "$(_parse_errors "$out")"

# ── Valid: minimal acceptable config ──────────────────────────────────────────
out=$(_run_set_config '{"main":{"enabled":"1","subscription_url":"https://example.com/sub","dns_mode":"fake-ip","log_level":"warning","external_controller_port":"9090","allow_lan_access":"0","bypass_china":"0"}}')
assert_eq "validate accepts minimal valid config" "True" "$(_parse_success "$out")"

# ── Valid: bypass address CIDR accepted ───────────────────────────────────────
out=$(_run_set_config '{"main":{},"bypass":{"address":["192.168.1.0/24","10.0.0.0/8"]}}')
assert_eq "validate accepts valid bypass CIDRs" "True" "$(_parse_success "$out")"

cleanup_mocks
print_test_summary
