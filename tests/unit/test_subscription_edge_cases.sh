#!/bin/sh
# test_subscription_edge_cases.sh — compatibility matrix fixtures
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/mocks.sh"

cat > "$MOCK_UCI_FILE" <<EOF
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
submihomo.main.dns_nameserver=https://1.1.1.1/dns-query
submihomo.main.dns_fallback=
submihomo.main.dns_fallback_filter_geoip=0
EOF

. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/config.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/subscription.sh"

SANDBOX="/tmp/sm_edge_test_$$"
mkdir -p "$SANDBOX/sub" "$SANDBOX/run" "$SANDBOX/conf/templates"
RUN_DIR="$SANDBOX/run"
SUB_DIR="$SANDBOX/sub"
CONFIG_DIR="$SANDBOX/conf"
cp "$SCRIPT_DIR/../../files/etc/submihomo/templates/base.yaml.tmpl" "$CONFIG_DIR/templates/base.yaml.tmpl"
export RUN_DIR SUB_DIR CONFIG_DIR

_run_fixture() {
    cp "$SCRIPT_DIR/fixtures/$1" "$SUB_DIR/current.yaml"
    config_generate >/dev/null 2>&1
}

# ── Unicode proxy and group names ─────────────────────────────────────────────
_run_fixture subscription_unicode.yaml
assert_zero "unicode fixture generates config" $?
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "unicode proxy name preserved" "日本-東京-01" "$out"
assert_contains "unicode Cyrillic proxy name preserved" "РФ-Москва-01" "$out"
assert_contains "unicode emoji proxy name preserved" "🚀 高速节点" "$out"
assert_contains "unicode group name in selector" "🌏 自动选择" "$out"
assert_contains "final MATCH routes through internal PROXY selector" "MATCH,PROXY" "$out"

# ── Comments and YAML anchors/aliases ─────────────────────────────────────────
_run_fixture subscription_comments_anchors.yaml
assert_zero "comments/anchors fixture generates config" $?
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "anchor node preserved" "anchor-node-1" "$out"
assert_contains "alias node preserved" "alias-node-2" "$out"
assert_contains "plain node preserved" "plain-node-3" "$out"
assert_contains "YAML comment preserved in generated config" "inline comment" "$out"

# ── No proxy-groups: selector still emitted with DIRECT ───────────────────────
_run_fixture subscription_no_groups.yaml
assert_zero "no-groups fixture generates config" $?
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "no-groups: proxy present" "solo-node" "$out"
assert_contains "no-groups: PROXY selector emitted" "name: \"PROXY\"" "$out"
assert_contains "no-groups: DIRECT in selector" "DIRECT" "$out"
assert_contains "no-groups: final MATCH rule" "MATCH,PROXY" "$out"

# ── No rules: final MATCH still emitted, no subscription rules ────────────────
_run_fixture subscription_no_rules.yaml
assert_zero "no-rules fixture generates config" $?
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "no-rules: proxy present" "ruleless-node" "$out"
assert_contains "no-rules: group present" "Auto" "$out"
assert_contains "no-rules: final MATCH rule" "MATCH,PROXY" "$out"

# ── Large 150-proxy fixture ───────────────────────────────────────────────────
_run_fixture subscription_large.yaml
assert_zero "large fixture generates config" $?
out=$(cat "$RUN_DIR/config.yaml")
assert_contains "large fixture: first node present" "bulk-node-001" "$out"
assert_contains "large fixture: last node present" "bulk-node-150" "$out"
count=$(_extract_block proxies "$SUB_DIR/current.yaml" | grep -cE '^[[:space:]]*- name:')
assert_eq "large fixture: 150 proxy entries counted" "150" "$count"

rm -rf "$SANDBOX"
cleanup_mocks
print_test_summary
