#!/bin/sh
# config.sh — Mihomo config generator
# shellcheck shell=sh
. "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/core.sh"
_ensure_run_dir() {
    mkdir -p "$RUN_DIR" 2>/dev/null || {
        log_error "[config] cannot create $RUN_DIR"
        return 1
    }
    chmod 700 "$RUN_DIR"
}
# _build_dns_section — generates the dns: block from UCI settings
_build_dns_section() {
    mode=$(uci_get dns_mode fake-ip)
    nameservers=$(uci_get dns_nameserver "https://1.1.1.1/dns-query https://8.8.8.8/dns-query")
    fallback=$(uci_get dns_fallback "https://1.0.0.1/dns-query")
    fb_geoip=$(uci_get dns_fallback_filter_geoip 1)
    geoip_code=$(uci_get bypass_china_geoip_code CN)
    printf 'dns:\n'
    printf '  enable: true\n'
    printf '  listen: 127.0.0.1:%s\n' "$DNS_PORT"
    printf '  ipv6: false\n'

    if [ "$mode" = "fake-ip" ]; then
        printf '  enhanced-mode: fake-ip\n  fake-ip-range: 198.18.0.0/15\n  fake-ip-filter:\n'
        for entry in '*.lan' '*.local' '*.home' '*.home.arpa' \
            '*.invalid' '*.test' 'router.asus.com' 'repeater.asus.com' \
            '+.msftconnecttest.com' '+.msftncsi.com' '+.xbox.live.com' \
            '+.xboxlive.com' '+.time.windows.com' '+.ntp.org' '+.pool.ntp.org' \
            'time.apple.com' 'time.cloudflare.com' \
            '+.apple.com.cn' 'localhost.ptlogin2.qq.com' \
            'localhost.sec.qq.com' 'stun.l.google.com' \
            '+.n.n.srv.nintendo.net' '+.nintendo.net' '+.cdn.nintendo.net' \
            '+.battlenet.com.cn' '+.blzstatic.cn'; do
            printf '    - "%s"\n' "$entry"
        done
    else
        printf '  enhanced-mode: normal\n'
    fi

    printf '  nameserver:\n'
    for ns in $nameservers; do
        printf '    - %s\n' "$ns"
    done

    if [ "$mode" = "fake-ip" ] && [ -n "$fallback" ]; then
        printf '  fallback:\n'
        for fb in $fallback; do
            printf '    - %s\n' "$fb"
        done
        if [ "$fb_geoip" = "1" ]; then
            printf '  fallback-filter:\n'
            printf '    geoip: true\n'
            printf '    geoip-code: %s\n' "$geoip_code"
            printf '    ipcidr:\n'
            printf '      - 240.0.0.0/4\n'
            printf '      - 0.0.0.0/8\n'
        fi
    fi
}
# _extract_block <key> <file> — extracts top-level YAML block starting at "^key:"
_extract_block() {
    awk -v key="$1:" '
        /^[a-zA-Z_-][a-zA-Z0-9_-]*:/ { if (in_block) exit; if ($0 ~ "^" key) { in_block=1; print; next } }
        in_block { print }
    ' "$2"
}
_group_name_exists() {
    grep -q "^  - name: [\"']*${1}[\"']*$\|^  - name: ${1}$" "$2" 2>/dev/null
}

# _resolve_group_name <preferred> <sub_file> — returns a unique group name
_resolve_group_name() {
    preferred=$1
    sub=$2
    candidate=$preferred
    n=1
    while _group_name_exists "$candidate" "$sub" 2>/dev/null; do
        candidate="${preferred}_${n}"
        n=$((n + 1))
    done
    printf '%s' "$candidate"
}
# _build_proxy_selector <group_name> <sub_file> — builds the PROXY selector group
_build_proxy_selector() {
    gname=$1
    sub=$2
    groups=$(_extract_block proxy-groups "$sub" | awk '
        /^[[:space:]]*- name:/ {
            sub(/.*name:[[:space:]]*/, "")
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            sub(/^["'"'"']+/, "")
            sub(/["'"'"']+$/, "")
            print
        }
    ')
    printf 'proxy-groups:\n  - name: "%s"\n    type: select\n    proxies:\n' "$gname"
    printf '%s\n' "$groups" | while IFS= read -r g; do
        [ -n "$g" ] && printf '      - "%s"\n' "$g"
    done
    printf '      - DIRECT\n'
}
_build_bypass_rules() {
    for cidr in 0.0.0.0/8 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 \
        192.168.0.0/16 169.254.0.0/16 224.0.0.0/4 \
        240.0.0.0/4 100.64.0.0/10; do
        printf '  - IP-CIDR,%s,DIRECT,no-resolve\n' "$cidr"
    done
    geoip_code=$(uci_get bypass_china_geoip_code CN)
    [ "$(uci_get bypass_china 0)" = "1" ] &&
        printf '  - GEOIP,%s,DIRECT\n' "$geoip_code"
}
config_generate() {
    tmpl="$CONFIG_DIR/templates/base.yaml.tmpl"
    sub_file="$SUB_DIR/current.yaml"
    out_file="$RUN_DIR/config.yaml"
    [ -f "$tmpl" ] || {
        log_error "[config] template not found: $tmpl"
        return 1
    }
    _ensure_run_dir || return 1
    # Read UCI values
    mixed_port=$(uci_get mixed_port "$MIXED_PORT")
    tproxy_port=$(uci_get tproxy_port "$TPROXY_PORT")
    ctrl_port=$(uci_get external_controller_port "$CTRL_PORT")
    log_lvl=$(uci_get log_level warning)
    allow_lan=$(uci_get allow_lan_access 0)
    ctrl_secret=$(uci_get external_controller_secret "")
    [ "$allow_lan" = "1" ] && allow_lan_val=true || allow_lan_val=false
    # Fix 1: bind controller to loopback unless LAN access is explicitly enabled
    [ "$allow_lan" = "1" ] && ctrl_bind="0.0.0.0" || ctrl_bind="127.0.0.1"
    # YAML-safe escape for the secret
    escaped_secret=$(printf '%s' "$ctrl_secret" | sed 's/\\/\\\\/g;s/"/\\"/g')
    # Dashboard dir is canonical constant
    dash_dir="$DASHBOARD_DIR"
    tmp_cfg=$(mktemp "$RUN_DIR/config_tmp.XXXXXX")
    sed -e "s|{{MIXED_PORT}}|$mixed_port|g" -e "s|{{TPROXY_PORT}}|$tproxy_port|g" \
        -e "s|{{CTRL_PORT}}|$ctrl_port|g" -e "s|{{CTRL_BIND}}|$ctrl_bind|g" \
        -e "s|{{LOG_LEVEL}}|$log_lvl|g" -e "s|{{ALLOW_LAN}}|$allow_lan_val|g" \
        -e "s|{{CTRL_SECRET}}|$escaped_secret|g" -e "s|{{DASHBOARD_DIR}}|$dash_dir|g" \
        "$tmpl" >"$tmp_cfg" || {
        log_error "[config] template substitution failed"
        rm -f "$tmp_cfg"
        return 1
    }
    # Splice DNS section (file-based to avoid awk multiline variable issues)
    dns_tmp=$(mktemp "$RUN_DIR/dns_tmp.XXXXXX")
    _build_dns_section >"$dns_tmp"
    awk -v dnsf="$dns_tmp" '
        index($0, "{{DNS_SECTION}}") > 0 {
            while ((getline line < dnsf) > 0) print line
            close(dnsf); next
        }{ print }
    ' "$tmp_cfg" >"${tmp_cfg}.2" && mv "${tmp_cfg}.2" "$tmp_cfg"
    rm -f "$dns_tmp"
    # No subscription — generate a safe empty config
    if [ ! -s "$sub_file" ]; then
        log_warn "[config] no subscription found, using empty proxy list"
        chmod 600 "$tmp_cfg"
        mv "$tmp_cfg" "$out_file"
        SAFE_PATHS="$MIHOMO_SAFE_PATHS" "$MIHOMO_BIN" -t -f "$out_file" >/dev/null 2>&1 || {
            log_error "[config] empty config validation failed"
            return 1
        }
        return 0
    fi
    # Extract subscription blocks
    proxies_block=$(_extract_block proxies "$sub_file")
    proxy_groups_raw=$(_extract_block proxy-groups "$sub_file")
    rule_providers_block=$(_extract_block rule-providers "$sub_file")
    rules_block=$(_extract_block rules "$sub_file")
    [ -z "$proxies_block" ] && log_warn "[config] subscription has no proxies section"
    proxy_count=$(printf '%s\n' "$proxies_block" | grep -cE '^[[:space:]]*- name:' 2>/dev/null || echo 0)

    # Fix 6: detect proxy-group name collision, pick unique internal group name
    preferred_name=$(uci_get internal_group_name "PROXY")
    if [ -n "$proxy_groups_raw" ]; then
        group_name=$(_resolve_group_name "$preferred_name" "$sub_file")
        [ "$group_name" != "$preferred_name" ] &&
            log_warn "[config] group name '$preferred_name' conflicts, using '$group_name'"
    else
        group_name="$preferred_name"
    fi
    # Build final config
    {
        awk '/^proxies: \[\]$/{exit}{print}' "$tmp_cfg"
        # Fix 8: always emit proxies section
        if [ -n "$proxies_block" ]; then
            printf '%s\n' "$proxies_block"
        else
            printf 'proxies: []\n'
        fi
        printf '\n'
        # Fix 6: inject our selector, then subscription groups
        _build_proxy_selector "$group_name" "$sub_file"
        if [ -n "$proxy_groups_raw" ]; then
            printf '%s\n' "$proxy_groups_raw" | tail -n +2
        fi
        printf '\n'
        # Include rule-providers from subscription so RULE-SET rules resolve
        if [ -n "$rule_providers_block" ]; then
            printf '%s\n' "$rule_providers_block"
            printf '\n'
        fi
        # Fix 7: rule ordering: LAN bypass, GEOIP bypass, sub rules (no MATCH catch-all), final MATCH
        printf 'rules:\n'
        _build_bypass_rules
        if [ -n "$rules_block" ]; then
            printf '%s\n' "$rules_block" | tail -n +2 |
                grep -vE '^[[:space:]]*$' |
                grep -vE '^[[:space:]]*- MATCH,' || true
        fi
        printf '  - MATCH,%s\n' "$group_name"
    } >"$out_file"
    chmod 600 "$out_file"
    rm -f "$tmp_cfg"
    # Validate
    if ! SAFE_PATHS="$MIHOMO_SAFE_PATHS" "$MIHOMO_BIN" -t -f "$out_file" >/dev/null 2>&1; then
        err=$(SAFE_PATHS="$MIHOMO_SAFE_PATHS" "$MIHOMO_BIN" -t -f "$out_file" 2>&1 | head -5)
        log_error "[config] config validation failed: $err"
        return 1
    fi
    log_info "[config] config generated ($proxy_count proxies, group=$group_name)"
}
