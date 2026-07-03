#!/bin/sh
# test_busybox_whitespace.sh — regression test for BusyBox \s / grep -A incompatibilities
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/mocks.sh"

cat >"$MOCK_UCI_FILE" <<EOF
submihomo.main.enabled=1
submihomo.main.log_level=warning
EOF

. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/config.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/subscription.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/dashboard.sh"

SANDBOX="/tmp/sm_bb_test_$$"
mkdir -p "$SANDBOX/sub" "$SANDBOX/run" "$SANDBOX/dash" "$SANDBOX/conf/templates"
RUN_DIR="$SANDBOX/run"
SUB_DIR="$SANDBOX/sub"
DASHBOARD_DIR="$SANDBOX/dash"
CONFIG_DIR="$SANDBOX/conf"
cp "$SCRIPT_DIR/../../files/etc/submihomo/templates/base.yaml.tmpl" "$CONFIG_DIR/templates/base.yaml.tmpl"
export RUN_DIR SUB_DIR DASHBOARD_DIR CONFIG_DIR

# ── Fixture: indented YAML with spaces and tabs ───────────────────────────────
SUB_YAML="$SANDBOX/sub/current.yaml"
cat >"$SUB_YAML" <<'EOF'
proxies:
  - name: "node-1"
    type: ss
    server: 1.1.1.1
    port: 443
    cipher: aes-256-gcm
    password: pw
  - name: 'node-2'
    type: vmess
    server: 2.2.2.2
    port: 443
    uuid: 00000000-0000-0000-0000-000000000000
proxy-groups:
  - name: Auto
    type: select
    proxies:
      - "node-1"
      - 'node-2'
  - name: Fallback
    type: fallback
    url: http://www.gstatic.com/generate_204
    interval: 300
    proxies:
      - "node-1"
rules:
  - DOMAIN,google.com,Auto
  - MATCH,Auto
EOF

# ── POSIX whitespace patterns match indented YAML ─────────────────────────────
count=$(grep -cE '^[[:space:]]*- name:' "$SUB_YAML")
assert_eq "grep -cE '^[[:space:]]*- name:' counts 4 proxy/group names" "4" "$count"

proxy_count=$(grep -cE '^[[:space:]]*- name:' "$SUB_YAML" | head -1)
# subscription_status uses the same pattern
status_out=$(subscription_status)
assert_contains "subscription_status reports active" "status=active" "$status_out"
assert_eq "subscription_status name count is 4 (proxies + groups)" "proxy_count=4" "$(printf '%s' "$status_out" | grep proxy_count)"

# ── _build_proxy_selector extracts quoted group names without \s or -A ────────
selector=$(_build_proxy_selector PROXY "$SUB_YAML")
assert_contains "selector contains Auto" "Auto" "$selector"
assert_contains "selector contains Fallback" "Fallback" "$selector"
assert_contains "selector contains DIRECT" "DIRECT" "$selector"
assert_not_contains "selector does not include proxy names" "node-1" "$selector"

# ── config_generate filters MATCH rule and keeps indented subscription rules ──
# SUB_YAML is already $SUB_DIR/current.yaml
config_generate >/dev/null 2>&1
assert_zero "config_generate succeeds with indented subscription" $?
generated=$(cat "$RUN_DIR/config.yaml")
assert_contains "generated config keeps DOMAIN rule" "DOMAIN,google.com" "$generated"
assert_not_contains "generated config strips sub MATCH catch-all" "MATCH,Auto" "$generated"
assert_contains "generated config ends with MATCH,PROXY" "MATCH,PROXY" "$generated"

# ── dashboard_download extracts dist.zip URL and tag without \s / grep -A ─────
GH_JSON='{
  "tag_name": "v1.2.3",
  "assets": [
    {
      "name": "dist.zip",
      "browser_download_url": "https://example.com/zashboard/dist.zip"
    },
    {
      "name": "source.zip",
      "browser_download_url": "https://example.com/zashboard/source.zip"
    }
  ]
}'
export WGET_MOCK_RESPONSE="$GH_JSON"
export WGET_MOCK_EXIT=0
: >"$MOCK_LOG"
# download will fail at unzip (response is JSON), but extraction must pick the right URL
if dashboard_download >/dev/null 2>&1; then
    : # unexpected, but not a failure of extraction
fi
assert_contains "dashboard download extracts dist.zip URL" "https://example.com/zashboard/dist.zip" "$(cat "$MOCK_LOG")"
assert_not_contains "dashboard download does not extract source.zip URL" "source.zip" "$(cat "$MOCK_LOG")"

# ── dashboard_version reads version file ──────────────────────────────────────
printf 'v1.2.3\n' >"$DASHBOARD_DIR/.version"
assert_eq "dashboard_version returns installed tag" "v1.2.3" "$(dashboard_version)"

# ── No literal \s remains in production shell modules (excluding comments) ────
_suspect=$(grep -rn '\\s' "$SCRIPT_DIR/../../files/usr/lib/submihomo"/*.sh "$SCRIPT_DIR/../../files/usr/bin/submihomo-ctl" 2>/dev/null | while IFS= read -r line; do
    # strip leading path:line: prefix, then trim leading whitespace
    code=$(printf '%s' "$line" | sed 's/^[^:]*:[0-9]*://; s/^[[:space:]]*//')
    # skip comment-only lines
    if printf '%s' "$code" | grep -qE '^#'; then continue; fi
    printf '%s\n' "$line"
done)
if [ -n "$_suspect" ]; then
    TESTS_FAIL=$((TESTS_FAIL + 1))
    printf '[FAIL] literal \\s still present in production shell code:\n%s\n' "$_suspect"
else
    TESTS_PASS=$((TESTS_PASS + 1))
    printf '[PASS] no literal \\s in production shell code\n'
fi

# ── Patterns also parse under dash (POSIX shell) if available ─────────────────
if command -v dash >/dev/null 2>&1; then
    dash_count=$(dash -c 'grep -cE "^[[:space:]]*- name:" "$1"' _ "$SUB_YAML")
    assert_eq "dash grep -cE '^[[:space:]]*- name:' counts 4" "4" "$dash_count"
else
    printf '[SKIP] dash not installed, POSIX shell pattern check omitted\n'
fi

rm -rf "$SANDBOX"
cleanup_mocks
print_test_summary
