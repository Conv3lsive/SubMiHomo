#!/bin/sh
# test_core.sh — unit tests for core.sh
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/mocks.sh"

# Set up a mock UCI config file
cat > "$MOCK_UCI_FILE" <<EOF
submihomo.main.enabled=1
submihomo.main.dns_mode=fake-ip
submihomo.main.log_level=warning
submihomo.main.external_controller_port=9090
submihomo.main.external_controller_secret=mysecret
submihomo.main.allow_lan_access=0
submihomo.main.bypass_china=0
submihomo.main.subscription_url=https://example.com/sub
submihomo.main.subscription_update_interval=24
submihomo.main.config_version=1
EOF

# Source core.sh (mocks are already in place)
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"

# ── Constants ─────────────────────────────────────────────────────────────────
assert_eq "TPROXY_PORT is 7891"  "7891"  "$TPROXY_PORT"
assert_eq "MIXED_PORT is 7890"   "7890"  "$MIXED_PORT"
assert_eq "DNS_PORT is 1053"     "1053"  "$DNS_PORT"
assert_eq "CTRL_PORT is 9090"    "9090"  "$CTRL_PORT"
assert_eq "FWMARK is 1"          "1"     "$FWMARK"
assert_eq "BYPASS_MARK is 255"   "255"   "$BYPASS_MARK"
assert_eq "RT_TABLE is 100"      "100"   "$RT_TABLE"

# ── uci_get ───────────────────────────────────────────────────────────────────
result=$(uci_get enabled 0)
assert_eq "uci_get enabled" "1" "$result"

result=$(uci_get dns_mode "fake-ip")
assert_eq "uci_get dns_mode" "fake-ip" "$result"

result=$(uci_get nonexistent_key "mydefault")
assert_eq "uci_get missing key returns default" "mydefault" "$result"

# ── is_enabled ───────────────────────────────────────────────────────────────
is_enabled
assert_zero "is_enabled returns 0 when enabled=1" $?

# Change enabled to 0 in the same mock file and test again
printf '%s\n' "submihomo.main.enabled=0" > "$MOCK_UCI_FILE"
is_enabled
assert_nonzero "is_enabled returns non-zero when enabled=0" $?
# Restore enabled=1
printf '%s\n' "submihomo.main.enabled=1" >> "$MOCK_UCI_FILE"

# ── validate_url ──────────────────────────────────────────────────────────────
validate_url "https://example.com/sub?token=abc123"
assert_zero "validate_url accepts https://" $?

validate_url "http://example.com/sub"
assert_nonzero "validate_url rejects http://" $?

validate_url ""
assert_nonzero "validate_url rejects empty string" $?

validate_url "ftp://example.com"
assert_nonzero "validate_url rejects ftp://" $?

# ── validate_cidr ─────────────────────────────────────────────────────────────
validate_cidr "10.0.0.0/8"
assert_zero "validate_cidr accepts 10.0.0.0/8" $?

validate_cidr "192.168.0.0/16"
assert_zero "validate_cidr accepts 192.168.0.0/16" $?

validate_cidr "0.0.0.0/0"
assert_zero "validate_cidr accepts 0.0.0.0/0 (boundary)" $?

validate_cidr "255.255.255.255/32"
assert_zero "validate_cidr accepts 255.255.255.255/32 (boundary)" $?

validate_cidr "999.1.1.1/24"
assert_nonzero "validate_cidr rejects 999.1.1.1/24 (invalid octet)" $?

validate_cidr "10.0.0.0/33"
assert_nonzero "validate_cidr rejects /33 (prefix too large)" $?

validate_cidr "10.0.0.0"
assert_nonzero "validate_cidr rejects bare IP (no prefix)" $?

validate_cidr "fd00::/8"
assert_nonzero "validate_cidr rejects IPv6" $?

validate_cidr "10.0.0.0/-1"
assert_nonzero "validate_cidr rejects negative prefix" $?

# ── Logging (verify logger mock called) ──────────────────────────────────────
: > "$MOCK_LOG"
log_info "test info message"
assert_contains "log_info calls logger with INFO" "INFO" "$(cat "$MOCK_LOG")"

: > "$MOCK_LOG"
log_warn "test warning"
assert_contains "log_warn calls logger with WARN" "WARN" "$(cat "$MOCK_LOG")"

: > "$MOCK_LOG"
log_error "test error"
assert_contains "log_error calls logger with ERROR" "ERROR" "$(cat "$MOCK_LOG")"

# ── Lock helpers ──────────────────────────────────────────────────────────────
RUN_DIR="/tmp/sm_lock_test_$$"
LOCK_FILE="$RUN_DIR/submihomo.lock"
mkdir -p "$RUN_DIR"

acquire_lock
assert_zero "acquire_lock succeeds on clean state" $?
assert_eq "lock file contains PID" "$$" "$(cat "$LOCK_FILE")"

# Second acquire should fail (lock already held by current process)
# Simulate a different PID in the lock file
printf '99999' > "$LOCK_FILE"  # Use a PID that doesn't exist
acquire_lock 2>/dev/null
assert_zero "acquire_lock succeeds when lock PID is dead" $?

release_lock
assert_nonzero "lock file removed after release_lock" "$([ -f "$LOCK_FILE" ]; echo $?)"

# ── Migration: v1 → v2 ────────────────────────────────────────────────────────
# Simulate a v1 config (missing new keys, config_version=1)
cat > "$MOCK_UCI_FILE" <<MIGEOF
submihomo.main.enabled=1
submihomo.main.config_version=1
submihomo.main.dns_mode=fake-ip
MIGEOF
run_migrations 2>/dev/null
assert_zero "run_migrations succeeds on v1 config" $?

# Already at current version — should be no-op
run_migrations 2>/dev/null
assert_zero "run_migrations is no-op when already current" $?

# Simulate a brand-new config with no config_version (treated as v0)
cat > "$MOCK_UCI_FILE" <<MIGEOF2
submihomo.main.enabled=1
submihomo.main.dns_mode=fake-ip
MIGEOF2
run_migrations 2>/dev/null
assert_zero "run_migrations handles missing config_version (v0)" $?

# ── Summary ───────────────────────────────────────────────────────────────────
cleanup_mocks
print_test_summary
