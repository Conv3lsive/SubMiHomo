#!/bin/sh
# test_security.sh — security-focused unit tests
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/mocks.sh"

cat > "$MOCK_UCI_FILE" <<EOF
submihomo.main.enabled=1
submihomo.main.dns_mode=fake-ip
submihomo.main.log_level=warning
submihomo.main.external_controller_port=9090
submihomo.main.external_controller_secret=super_secret_123
submihomo.main.allow_lan_access=0
submihomo.main.bypass_china=0
submihomo.main.tproxy_port=7891
submihomo.main.mixed_port=7890
submihomo.main.internal_group_name=PROXY
submihomo.main.dns_nameserver=https://1.1.1.1/dns-query
submihomo.main.dns_fallback=
submihomo.main.dns_fallback_filter_geoip=0
EOF

. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/config.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/subscription.sh"

SANDBOX="/tmp/sm_sec_test_$$"
mkdir -p "$SANDBOX/sub" "$SANDBOX/run" "$SANDBOX/conf/templates"
RUN_DIR="$SANDBOX/run"
SUB_DIR="$SANDBOX/sub"
CONFIG_DIR="$SANDBOX/conf"
cp "$SCRIPT_DIR/../../files/etc/submihomo/templates/base.yaml.tmpl" "$CONFIG_DIR/templates/base.yaml.tmpl"
export RUN_DIR SUB_DIR CONFIG_DIR

# ── Generated config is not world-readable ────────────────────────────────────
config_generate >/dev/null 2>&1
mode=$(stat -f '%Lp' "$RUN_DIR/config.yaml" 2>/dev/null || stat -c '%a' "$RUN_DIR/config.yaml" 2>/dev/null)
assert_eq "generated config.yaml mode is 600" "600" "$mode"

# ── Controller defaults to loopback when LAN access disabled ──────────────────
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "controller bound to 127.0.0.1" "external-controller: 127.0.0.1:" "$out"
assert_not_contains "controller not bound to 0.0.0.0" "external-controller: 0.0.0.0:" "$out"

# ── Subscription files are applied with restricted permissions ───────────────
cat > "$SANDBOX/sub_input.yaml" <<'EOF'
proxies:
  - name: sec-node
    type: ss
    server: 1.1.1.1
    port: 443
    cipher: aes-256-gcm
    password: pw
rules:
  - MATCH,DIRECT
EOF
chmod 644 "$SANDBOX/sub_input.yaml"
_subscription_apply "$SANDBOX/sub_input.yaml"
mode=$(stat -f '%Lp' "$SUB_DIR/current.yaml" 2>/dev/null || stat -c '%a' "$SUB_DIR/current.yaml" 2>/dev/null)
assert_eq "subscription current.yaml mode is 600" "600" "$mode"

# ── rpcd get_config redacts the controller secret ─────────────────────────────
MOCK_LUA="$SANDBOX/lua"
mkdir -p "$MOCK_LUA/luci"
cp "$SCRIPT_DIR/mocks/lua/luci/jsonc.lua" "$MOCK_LUA/luci/jsonc.lua"
cat > "$MOCK_LUA/uci.lua" <<'EOF'
local M = {}
local data = {
    ["submihomo.main.external_controller_secret"] = "super_secret_123",
    ["submihomo.main.enabled"] = "1",
}
function M.cursor()
    return {
        load = function() return true end,
        get = function(_, cfg, sec, opt) return data[(cfg.."."..sec.."."..opt)] end,
        set = function() return true end,
        commit = function() return true end,
        delete = function() return true end,
        add_list = function() return true end,
        foreach = function() return true end,
    }
end
return M
EOF

out=$(LUA_PATH="$MOCK_LUA/?.lua;$MOCK_LUA/?/init.lua;;" \
    lua "$SCRIPT_DIR/../../files/usr/lib/rpcd/submihomo" get_config)
assert_contains "rpcd get_config redacts secret" '"external_controller_secret":"REDACTED"' "$out"
assert_not_contains "rpcd get_config does not leak secret" "super_secret_123" "$out"

# ── ACL files are valid JSON and restrict write access ────────────────────────
acl="$SCRIPT_DIR/../../files/usr/share/rpcd/acl.d/luci-app-submihomo.json"
if jq empty "$acl" 2>/dev/null; then
    assert_contains "ACL JSON is valid" "luci-app-submihomo" "$(cat "$acl")"
else
    TESTS_FAIL=$((TESTS_FAIL+1)); printf '[FAIL] ACL JSON is invalid\n'
fi

rm -rf "$SANDBOX"
cleanup_mocks
print_test_summary
