#!/bin/sh
# test_subscription_validation.sh — unit tests for subscription.sh validation logic
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"
. "$SCRIPT_DIR/mocks.sh"

cat > "$MOCK_UCI_FILE" <<EOF
submihomo.main.subscription_url=https://example.com/sub
submihomo.main.subscription_user_agent=SubMiHomo/1.0
EOF

# Source core.sh then subscription.sh
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/subscription.sh"

# Override paths to temp dirs AFTER sourcing (sourcing core.sh resets them)
RUN_DIR="/tmp/sm_test_run_$$"
SUB_DIR="/tmp/sm_test_sub_$$"
LOCK_FILE="$RUN_DIR/submihomo.lock"
mkdir -p "$RUN_DIR" "$SUB_DIR"

# ── URL masking (from core.sh/subscription context) ───────────────────────────
mask_test() {
    url=$1
    [ -z "$url" ] && return
    printf '%s...' "$(printf '%s' "$url" | cut -c1-20)"
}

result=$(mask_test "https://provider.example.com/link/abcdef0123456789TOKEN")
assert_contains "mask_url takes first 20 chars" "https://provider.exa" "$result"
assert_contains "mask_url appends ..." "..." "$result"

result=$(mask_test "https://short.com/x")
assert_contains "mask_url short URL still appends ..." "..." "$result"

result=$(mask_test "")
assert_eq "mask_url empty string returns empty" "" "$result"

# ── validate_url ──────────────────────────────────────────────────────────────
validate_url "https://provider.example.com/sub?token=abc123"
assert_zero "validate_url: valid https URL with token" $?

validate_url "https://sub.example.com/link/aBcD1234EfGh5678"
assert_zero "validate_url: valid https URL with path token" $?

validate_url "http://example.com/sub"
assert_nonzero "validate_url: rejects http://" $?

validate_url ""
assert_nonzero "validate_url: rejects empty" $?

validate_url "example.com/sub"
assert_nonzero "validate_url: rejects bare hostname" $?

# ── Level 2 validation: non-empty ─────────────────────────────────────────────
tmpfile="/tmp/sm_val_test_$$"

# Empty file
: > "$tmpfile"
_subscription_validate "$tmpfile" 2>/dev/null
assert_nonzero "validation rejects empty file" $?

# File with proxies: key but no entries
printf 'proxies: []\nrules:\n  - MATCH,DIRECT\n' > "$tmpfile"
_subscription_validate "$tmpfile" 2>/dev/null
assert_nonzero "validation rejects proxies with no entries" $?

# File missing proxies: key entirely
printf 'proxy-groups:\n  - name: Auto\nrules:\n  - MATCH,DIRECT\n' > "$tmpfile"
_subscription_validate "$tmpfile" 2>/dev/null
assert_nonzero "validation rejects file with no proxies: key" $?

# Valid minimal subscription (mihomo mock returns 0)
cp "$FIXTURES/subscription_valid_minimal.yaml" "$tmpfile"
_subscription_validate "$tmpfile" 2>/dev/null
assert_zero "validation accepts valid minimal subscription" $?

# Invalid YAML structure (mihomo mock can be set to fail)
MIHOMO_T_FAIL=1
export MIHOMO_T_FAIL
cp "$FIXTURES/subscription_valid_minimal.yaml" "$tmpfile"
_subscription_validate "$tmpfile" 2>/dev/null
assert_nonzero "validation rejects subscription that fails mihomo -t" $?
MIHOMO_T_FAIL=0
export MIHOMO_T_FAIL

# ── subscription_update: empty URL ────────────────────────────────────────────
cat > "$MOCK_UCI_FILE" <<EOF
submihomo.main.subscription_url=
submihomo.main.subscription_user_agent=SubMiHomo/1.0
EOF

subscription_update 2>/dev/null
assert_nonzero "subscription_update returns non-zero when URL empty" $?

# ── Backup and apply atomicity ────────────────────────────────────────────────
# Seed a current.yaml
printf 'proxies:\n  - name: old-node\n    type: ss\n    server: 1.1.1.1\n    port: 443\n    cipher: aes-256-gcm\n    password: test\n' \
    > "$SUB_DIR/current.yaml"
_subscription_backup
assert_zero "backup step succeeds" $?
assert_eq "backup.yaml matches current.yaml content" \
    "$(cat "$SUB_DIR/current.yaml")" \
    "$(cat "$SUB_DIR/backup.yaml")"

# Apply a new file atomically
newfile="/tmp/sm_new_$$"
cp "$FIXTURES/subscription_valid_minimal.yaml" "$newfile"
_subscription_apply "$newfile" 2>/dev/null
assert_zero "apply step succeeds" $?
assert_zero "temp file removed after apply" "$([ ! -f "$newfile" ]; echo $?)"

# Restore
subscription_restore 2>/dev/null
assert_zero "restore succeeds with backup present" $?

# Restore with no backup
rm -f "$SUB_DIR/backup.yaml"
subscription_restore 2>/dev/null
assert_nonzero "restore returns non-zero with no backup" $?

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$RUN_DIR" "$SUB_DIR" "$tmpfile" 2>/dev/null || true
cleanup_mocks
print_test_summary
