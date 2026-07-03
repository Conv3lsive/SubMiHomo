#!/bin/sh
# test_config_extraction.sh — unit tests for config.sh YAML block extraction
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"
. "$SCRIPT_DIR/mocks.sh"

cat >"$MOCK_UCI_FILE" <<EOF
submihomo.main.enabled=1
submihomo.main.dns_mode=fake-ip
submihomo.main.log_level=warning
submihomo.main.external_controller_port=9090
submihomo.main.external_controller_secret=
submihomo.main.allow_lan_access=0
submihomo.main.bypass_china=0
submihomo.main.bypass_china_geoip_code=CN
submihomo.main.tproxy_port=7891
submihomo.main.mixed_port=7890
submihomo.main.internal_group_name=PROXY
submihomo.main.dns_nameserver=https://1.1.1.1/dns-query https://8.8.8.8/dns-query
submihomo.main.dns_fallback=https://1.0.0.1/dns-query
submihomo.main.dns_fallback_filter_geoip=1
EOF

export RUN_DIR="/tmp/sm_cfg_test_$$"
export SUB_DIR="/tmp/sm_sub_test_$$"
export CONFIG_DIR="/tmp/sm_conf_test_$$"
mkdir -p "$RUN_DIR" "$SUB_DIR" "$CONFIG_DIR/templates"

# Copy template
cp "$SCRIPT_DIR/../../files/etc/submihomo/templates/base.yaml.tmpl" \
    "$CONFIG_DIR/templates/base.yaml.tmpl"

. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/config.sh"

# Override paths AFTER sourcing (sourcing resets them from core.sh constants)
RUN_DIR="/tmp/sm_cfg_test_$$"
SUB_DIR="/tmp/sm_sub_test_$$"
CONFIG_DIR="/tmp/sm_conf_test_$$"
LOCK_FILE="$RUN_DIR/submihomo.lock"

FULL_FIXTURE="$FIXTURES/subscription_full_realistic.yaml"
MINIMAL_FIXTURE="$FIXTURES/subscription_valid_minimal.yaml"

# ── _extract_block: proxies ────────────────────────────────────────────────────
block=$(_extract_block proxies "$MINIMAL_FIXTURE")
assert_contains "extract proxies: block starts with proxies:" "proxies:" "$block"
assert_contains "extract proxies: block contains test-node-1" "test-node-1" "$block"

# Block must NOT bleed into proxy-groups
assert_not_contains "extract proxies: does not include proxy-groups" "proxy-groups:" "$block"

# ── _extract_block: proxy-groups ──────────────────────────────────────────────
block=$(_extract_block proxy-groups "$MINIMAL_FIXTURE")
assert_contains "extract proxy-groups: block present" "proxy-groups:" "$block"
assert_contains "extract proxy-groups: contains 'auto'" "auto" "$block"
assert_not_contains "extract proxy-groups: does not include rules:" "rules:" "$block"

# ── _extract_block: rules ─────────────────────────────────────────────────────
block=$(_extract_block rules "$MINIMAL_FIXTURE")
assert_contains "extract rules: block present" "rules:" "$block"
assert_contains "extract rules: contains MATCH" "MATCH" "$block"
assert_not_contains "extract rules: does not include proxies:" "proxies:" "$block"

# ── _extract_block: missing key returns empty ─────────────────────────────────
block=$(_extract_block nonexistent_key "$MINIMAL_FIXTURE")
assert_eq "extract missing key returns empty" "" "$block"

# ── _extract_block: adjacent keys (no blank line between) ────────────────────
adj_fixture="/tmp/sm_adj_$$"
printf 'proxies:\n  - name: p1\n    type: ss\n    server: 1.1.1.1\n    port: 443\n    cipher: aes-256-gcm\n    password: pw\nproxy-groups:\n  - name: Auto\n    type: select\n    proxies: [p1]\nrules:\n  - MATCH,DIRECT\n' >"$adj_fixture"

block=$(_extract_block proxies "$adj_fixture")
assert_contains "adjacent-key: proxies block starts with proxies:" "proxies:" "$block"
assert_not_contains "adjacent-key: proxies block does not include proxy-groups:" "proxy-groups:" "$block"

rm -f "$adj_fixture"

# ── config_generate: no subscription produces valid config ────────────────────
# No current.yaml — should produce empty-proxy config
config_generate 2>/dev/null
rc=$?
# mihomo -t mock returns 0, so should succeed
assert_zero "config_generate succeeds with no subscription (empty proxy list)" $rc
assert_zero "config.yaml was created" "$(
    [ -f "$RUN_DIR/config.yaml" ]
    echo $?
)"

# ── config_generate: with valid subscription ──────────────────────────────────
cp "$MINIMAL_FIXTURE" "$SUB_DIR/current.yaml"
config_generate 2>/dev/null
assert_zero "config_generate succeeds with valid subscription" $?
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "generated config contains tproxy-port" "tproxy-port:" "$out"
assert_contains "generated config contains dns section" "dns:" "$out"
assert_contains "generated config contains proxies" "test-node-1" "$out"
assert_contains "generated config contains PROXY selector group" "PROXY" "$out"
assert_contains "generated config ends with MATCH,PROXY" "MATCH,PROXY" "$out"

# Bypass rules must come before MATCH rule (group name may vary)
proxies_pos=$(grep -n 'IP-CIDR,10.0.0.0' "$RUN_DIR/config.yaml" | head -1 | cut -d: -f1)
match_pos=$(grep -nE '^[[:space:]]*- MATCH,' "$RUN_DIR/config.yaml" | tail -1 | cut -d: -f1)
[ -n "$proxies_pos" ] && [ -n "$match_pos" ] && [ "$proxies_pos" -lt "$match_pos" ]
assert_zero "bypass rules appear before MATCH rule" $?

# ── config_generate: bypass_china injects GEOIP rule with configurable code ──
cat >"$MOCK_UCI_FILE" <<EOF3
submihomo.main.enabled=1
submihomo.main.dns_mode=fake-ip
submihomo.main.log_level=warning
submihomo.main.external_controller_port=9090
submihomo.main.external_controller_secret=
submihomo.main.allow_lan_access=0
submihomo.main.bypass_china=1
submihomo.main.bypass_china_geoip_code=CN
submihomo.main.tproxy_port=7891
submihomo.main.mixed_port=7890
submihomo.main.internal_group_name=PROXY
submihomo.main.dns_nameserver=https://1.1.1.1/dns-query
submihomo.main.dns_fallback=https://1.0.0.1/dns-query
submihomo.main.dns_fallback_filter_geoip=1
EOF3
config_generate 2>/dev/null
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "bypass_china=1 injects GEOIP,CN,DIRECT rule" "GEOIP,CN,DIRECT" "$out"

# ── config_generate: custom geoip_code is used ───────────────────────────────
cat >"$MOCK_UCI_FILE" <<EOF4
submihomo.main.enabled=1
submihomo.main.dns_mode=fake-ip
submihomo.main.log_level=warning
submihomo.main.external_controller_port=9090
submihomo.main.external_controller_secret=
submihomo.main.allow_lan_access=0
submihomo.main.bypass_china=1
submihomo.main.bypass_china_geoip_code=RU
submihomo.main.tproxy_port=7891
submihomo.main.mixed_port=7890
submihomo.main.internal_group_name=PROXY
submihomo.main.dns_nameserver=https://1.1.1.1/dns-query
submihomo.main.dns_fallback=https://1.0.0.1/dns-query
submihomo.main.dns_fallback_filter_geoip=1
EOF4
config_generate 2>/dev/null
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "bypass_china uses custom geoip_code RU" "GEOIP,RU,DIRECT" "$out"
assert_not_contains "custom geoip_code RU does not emit CN" "GEOIP,CN,DIRECT" "$out"

# ── config_generate: external-controller binds correctly ─────────────────────
# allow_lan_access=0 → 127.0.0.1
cat >"$MOCK_UCI_FILE" <<EOF5
submihomo.main.enabled=1
submihomo.main.dns_mode=fake-ip
submihomo.main.log_level=warning
submihomo.main.external_controller_port=9090
submihomo.main.external_controller_secret=
submihomo.main.allow_lan_access=0
submihomo.main.bypass_china=0
submihomo.main.tproxy_port=7891
submihomo.main.mixed_port=7890
submihomo.main.internal_group_name=PROXY
submihomo.main.dns_nameserver=https://1.1.1.1/dns-query
submihomo.main.dns_fallback=
submihomo.main.dns_fallback_filter_geoip=0
EOF5
config_generate 2>/dev/null
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "allow_lan_access=0 binds to 127.0.0.1" "external-controller: 127.0.0.1:" "$out"
assert_not_contains "allow_lan_access=0 does not bind 0.0.0.0" "0.0.0.0:9090" "$out"

# allow_lan_access=1 → 0.0.0.0
cat >"$MOCK_UCI_FILE" <<EOF6
submihomo.main.enabled=1
submihomo.main.dns_mode=fake-ip
submihomo.main.log_level=warning
submihomo.main.external_controller_port=9090
submihomo.main.external_controller_secret=
submihomo.main.allow_lan_access=1
submihomo.main.bypass_china=0
submihomo.main.tproxy_port=7891
submihomo.main.mixed_port=7890
submihomo.main.internal_group_name=PROXY
submihomo.main.dns_nameserver=https://1.1.1.1/dns-query
submihomo.main.dns_fallback=
submihomo.main.dns_fallback_filter_geoip=0
EOF6
config_generate 2>/dev/null
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "allow_lan_access=1 binds to 0.0.0.0" "external-controller: 0.0.0.0:" "$out"

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$RUN_DIR" "$SUB_DIR" "$CONFIG_DIR" 2>/dev/null || true
cleanup_mocks
print_test_summary
