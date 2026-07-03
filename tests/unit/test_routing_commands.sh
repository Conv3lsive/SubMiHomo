#!/bin/sh
# test_routing_commands.sh — unit tests for routing.sh command construction
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/mocks.sh"

cat >"$MOCK_UCI_FILE" <<EOF
submihomo.main.enabled=1
EOF

. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"

export RUN_DIR="/tmp/sm_rt_test_$$"
mkdir -p "$RUN_DIR"

# ── routing_setup: creates correct ip commands ────────────────────────────────
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/routing.sh"

IP_RULE_EXISTS=0
IP_ROUTE_EXISTS=0
export IP_RULE_EXISTS IP_ROUTE_EXISTS IP_MOCK_FAIL
: >"$MOCK_LOG"
routing_setup 2>/dev/null
assert_zero "routing_setup returns 0" $?

log_content=$(cat "$MOCK_LOG")
assert_contains "routing_setup calls 'ip route add'" "ip route add local default dev lo table 100" "$log_content"
assert_contains "routing_setup calls 'ip rule add'" "ip rule add fwmark 1 lookup 100 priority 1000" "$log_content"

# ── routing_setup: idempotent (skips when already present) ────────────────────
IP_RULE_EXISTS=1
IP_ROUTE_EXISTS=1
: >"$MOCK_LOG"
routing_setup 2>/dev/null
assert_zero "routing_setup returns 0 when already configured" $?
# Should NOT call add commands when already present
log_content=$(cat "$MOCK_LOG")
assert_not_contains "routing_setup skips route add when present" "ip route add" "$log_content"
assert_not_contains "routing_setup skips rule add when present" "ip rule add" "$log_content"

# ── routing_setup twice: idempotency with fresh state ────────────────────────
IP_RULE_EXISTS=0
IP_ROUTE_EXISTS=0
routing_setup 2>/dev/null
routing_setup 2>/dev/null
assert_zero "routing_setup called twice returns 0 (idempotency)" $?

# ── routing_teardown: uses correct ip del commands ────────────────────────────
: >"$MOCK_LOG"
routing_teardown 2>/dev/null
assert_zero "routing_teardown returns 0" $?
log_content=$(cat "$MOCK_LOG")
assert_contains "routing_teardown calls ip rule del" "ip rule del" "$log_content"
assert_contains "routing_teardown calls ip route del" "ip route del" "$log_content"

# ── routing_teardown: safe when nothing is set up ────────────────────────────
: >"$MOCK_LOG"
routing_teardown 2>/dev/null
assert_zero "routing_teardown returns 0 when nothing present" $?

# ── routing_setup failure propagates ────────────────────────────────────────
IP_MOCK_FAIL=1
IP_RULE_EXISTS=0
IP_ROUTE_EXISTS=0
routing_setup 2>/dev/null
assert_nonzero "routing_setup returns non-zero when ip fails" $?
IP_MOCK_FAIL=0

# ── Constants verify RT_TABLE and FWMARK match documented values ─────────────
assert_eq "RT_TABLE constant is 100" "100" "$RT_TABLE"
assert_eq "FWMARK constant is 1" "1" "$FWMARK"
assert_eq "BYPASS_MARK is 255" "255" "$BYPASS_MARK"

rm -rf "$RUN_DIR"
cleanup_mocks
print_test_summary
