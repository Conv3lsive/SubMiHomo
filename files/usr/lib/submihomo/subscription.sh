#!/bin/sh
# subscription.sh — download, validate, backup, apply, schedule
# shellcheck shell=sh
. "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/core.sh"

SUB_MAX_BYTES=5242880

_subscription_download() {
    url=$1; tmpfile=$2
    ua=$(uci_get subscription_user_agent "SubMiHomo/1.0")
    rm -f "$tmpfile"
    if ! wget --timeout=30 --tries=1 --max-redirect=0 -U "$ua" -O "$tmpfile" "$url" 2>/dev/null; then
        log_error "[subscription] download failed"; rm -f "$tmpfile"; return 1
    fi
    size=$(wc -c < "$tmpfile" 2>/dev/null || echo 0)
    if [ "$size" -gt "$SUB_MAX_BYTES" ]; then
        log_error "[subscription] subscription exceeds 5MB size limit"; rm -f "$tmpfile"; return 1
    fi
    return 0
}

_subscription_validate() {
    file=$1
    [ -s "$file" ] || { log_error "[subscription] downloaded file is empty"; return 1; }
    grep -q '^proxies:' "$file" || {
        log_error "[subscription] no proxies found in subscription (missing 'proxies:' key)"; return 1; }
    grep -qE '^[[:space:]]*-[[:space:]]*name:|^[[:space:]]*-[[:space:]]*\{name:' "$file" || {
        log_error "[subscription] no proxy entries found in subscription"; return 1; }

    test_cfg="$RUN_DIR/config-test.yaml"
    mkdir -p "$RUN_DIR"
    {
        cat <<EOF
mixed-port: 7890
tproxy-port: 7891
allow-lan: false
mode: rule
log-level: silent
routing-mark: 255
external-controller: 127.0.0.1:9090
dns:
  enable: true
  listen: 127.0.0.1:1053
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.0/15
  nameserver:
    - https://1.1.1.1/dns-query
EOF
        awk '/^proxies:/{b=1} b{print} /^[a-zA-Z_-][a-zA-Z0-9_-]*:/ && !/^proxies:/{if(b)exit}' "$file"
        awk '/^proxy-groups:/{b=1} b{print} /^[a-zA-Z_-][a-zA-Z0-9_-]*:/ && !/^proxy-groups:/{if(b)exit}' "$file"
        printf 'rules:\n  - MATCH,DIRECT\n'
    } > "$test_cfg"
    err=$("$MIHOMO_BIN" -t -f "$test_cfg" 2>&1); ret=$?; rm -f "$test_cfg"
    if [ "$ret" -ne 0 ]; then
        log_error "[subscription] mihomo -t validation failed: $(printf '%s' "$err" | head -3)"; return 1
    fi
    log_debug "[subscription] all 3 validation levels passed"
}

_subscription_backup() {
    cur="$SUB_DIR/current.yaml"; bak="$SUB_DIR/backup.yaml"
    [ -f "$cur" ] || return 0
    if cp "$cur" "$bak"; then
        chmod 600 "$bak"
    else
        log_warn "[subscription] backup failed (continuing)"
    fi
}

_subscription_apply() {
    cur="$SUB_DIR/current.yaml"
    mkdir -p "$SUB_DIR"; chmod 700 "$SUB_DIR"; chmod 600 "$1"
    mv "$1" "$cur" || { log_error "[subscription] atomic apply failed"; return 1; }
    log_info "[subscription] subscription applied"
}

subscription_update() {
    acquire_lock || return 1
    url=$(uci_get subscription_url "")
    if [ -z "$url" ]; then
        log_warn "[subscription] no subscription URL configured"; release_lock; return 1; fi
    validate_url "$url" || {
        log_error "[subscription] URL must be HTTPS"; release_lock; return 1; }
    . "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/mihomo.sh"
    mihomo_ensure_installed || {
        log_error "[subscription] Mihomo binary is not installed and automatic install failed"
        release_lock
        return 1
    }
    log_info "[subscription] subscription update starting"
    tmpfile="/tmp/submihomo_sub_$$.yaml"
    _subscription_download "$url" "$tmpfile" || { release_lock; return 1; }
    _subscription_validate "$tmpfile" || { rm -f "$tmpfile"; release_lock; return 1; }
    _subscription_backup
    _subscription_apply "$tmpfile" || { rm -f "$tmpfile"; release_lock; return 1; }

    if . "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/config.sh" && config_generate; then
        pid=$(pgrep -x mihomo 2>/dev/null | head -1)
        if [ -n "$pid" ]; then
            port=$(uci_get external_controller_port "$CTRL_PORT")
            secret=$(uci_get external_controller_secret "")
            auth=""; [ -n "$secret" ] && auth="-H 'Authorization: Bearer $secret'"
            body="{\"path\":\"$RUN_DIR/config.yaml\"}"
            # shellcheck disable=SC2086  # $auth must word-split into wget args
            if eval wget -q -O /dev/null --method=PUT $auth \
                "--header=Content-Type: application/json" \
                "--body-data=$body" \
                "\"http://127.0.0.1:${port}/configs?force=true\"" 2>/dev/null; then
                log_info "[subscription] hot-reload succeeded"
            else
                log_warn "[subscription] hot-reload failed, will apply on next restart"
            fi
        fi
    fi
    subscription_cron_update
    log_info "[subscription] subscription update completed successfully"
    release_lock
}

subscription_status() {
    cur="$SUB_DIR/current.yaml"
    [ -s "$cur" ] || { printf 'status=absent\n'; return 0; }
    mtime=$(stat -c '%Y' "$cur" 2>/dev/null || echo 0)
    count=$(grep -cE '^[[:space:]]*- name:' "$cur" 2>/dev/null || echo 0)
    printf 'status=active\nmtime=%s\nproxy_count=%s\n' "$mtime" "$count"
}

subscription_restore() {
    bak="$SUB_DIR/backup.yaml"; cur="$SUB_DIR/current.yaml"
    [ -f "$bak" ] || { log_error "[subscription] no backup available"; return 1; }
    cp "$bak" "$cur" && chmod 600 "$cur"
    log_info "[subscription] restored backup.yaml to current.yaml"
}

subscription_cron_update() {
    interval=$(uci_get subscription_update_interval 24)
    cron_file=/etc/crontabs/root
    [ -f "$cron_file" ] && sed -i '/submihomo-ctl update/d' "$cron_file" 2>/dev/null || true
    if [ "$interval" -gt 0 ] 2>/dev/null; then
        mkdir -p /etc/crontabs
        printf '0 */%s * * * /usr/bin/submihomo-ctl update >/dev/null 2>&1\n' \
            "$interval" >> "$cron_file"
        log_debug "[subscription] cron every ${interval}h"
    else
        log_debug "[subscription] cron disabled"
    fi
}

[ "${1:-}" = "update_cron" ] && subscription_update
