# core.sh — shared constants, UCI helpers, logging
# Sourced by all SubMiHomo shell modules. No side effects on source.
# SUBMIHOMO_LIB may be overridden in test environments to point at the repo files/ tree.
# The constants below are consumed by the modules that source this library;
# single-file linting cannot see that cross-file use, so it is silenced here.
# shellcheck shell=sh
# shellcheck disable=SC2034

# ── Constants ─────────────────────────────────────────────────────────────────
TPROXY_PORT=7891
MIXED_PORT=7890
DNS_PORT=1053
CTRL_PORT=9090
FWMARK=1
BYPASS_MARK=255
RT_TABLE=100
CONFIG_DIR=/etc/submihomo
RUN_DIR=/var/run/submihomo
SUB_DIR=/etc/submihomo/subscriptions
DASHBOARD_DIR=/usr/share/submihomo/dashboard
LOCK_FILE=/var/run/submihomo/submihomo.lock
MIHOMO_BIN_DIR=${MIHOMO_BIN_DIR:-/usr/libexec/submihomo}
MIHOMO_BIN=${MIHOMO_BIN:-$MIHOMO_BIN_DIR/mihomo}
MIHOMO_BACKUP_BIN=${MIHOMO_BACKUP_BIN:-$MIHOMO_BIN_DIR/mihomo.backup}
MIHOMO_STATE_DIR=${MIHOMO_STATE_DIR:-/etc/submihomo/mihomo}
MIHOMO_VERSION_FILE=${MIHOMO_VERSION_FILE:-$MIHOMO_STATE_DIR/version}
MIHOMO_SOURCE_REPO=${MIHOMO_SOURCE_REPO:-MetaCubeX/mihomo}

# ── UCI helpers ───────────────────────────────────────────────────────────────
uci_get() {
    val=$(uci -q get "submihomo.main.$1" 2>/dev/null)
    if [ -n "$val" ]; then printf '%s' "$val"
    else printf '%s' "${2:-}"; fi
}

uci_get_bypass() {
    uci -q get submihomo.bypass.address 2>/dev/null | tr ' ' '\n'
}

is_enabled() { [ "$(uci_get enabled 0)" = "1" ]; }

# ── Logging ───────────────────────────────────────────────────────────────────
_dbg_append() {
    f=/var/log/submihomo.log
    [ -f "$f" ] && [ "$(wc -c < "$f" 2>/dev/null || echo 0)" -gt 1048576 ] && : > "$f"
    printf '%s\n' "$*" >> "$f" 2>/dev/null || true
}
log_info()  { logger -t submihomo "[INFO] $*" 2>/dev/null || true; }
log_warn()  { logger -t submihomo "[WARN] $*" 2>/dev/null || true; }
log_error() { logger -t submihomo "[ERROR] $*" 2>/dev/null || true; }
log_debug() {
    [ "$(uci_get log_level warning)" = "debug" ] || return 0
    logger -t submihomo "[DEBUG] $*" 2>/dev/null || true
    _dbg_append "[DEBUG] $*"
}

# ── Lock helpers ──────────────────────────────────────────────────────────────
acquire_lock() {
    mkdir -p "$RUN_DIR" 2>/dev/null || true
    if [ -f "$LOCK_FILE" ]; then
        lpid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$lpid" ] && kill -0 "$lpid" 2>/dev/null; then
            log_warn "concurrent operation in progress (pid $lpid)"; return 1
        fi
        rm -f "$LOCK_FILE"
    fi
    printf '%s' "$$" > "$LOCK_FILE"
}
release_lock() { rm -f "$LOCK_FILE"; }

# ── Validation helpers ────────────────────────────────────────────────────────
validate_url() { case "$1" in https://*) return 0;; *) return 1;; esac; }

validate_cidr() {
    cidr=$1
    case "$cidr" in *:*) return 1;; esac
    ip="${cidr%/*}"; pfx="${cidr#*/}"
    [ "$ip" = "$cidr" ] && return 1
    IFS='.' read -r a b c d <<EOF
$ip
EOF
    for oct in "$a" "$b" "$c" "$d"; do
        case "$oct" in ''|*[!0-9]*) return 1;; esac
        [ "$oct" -ge 0 ] && [ "$oct" -le 255 ] || return 1
    done
    case "$pfx" in ''|*[!0-9]*) return 1;; esac
    [ "$pfx" -ge 0 ] && [ "$pfx" -le 32 ] || return 1
}

# ── Migration ────────────────────────────────────────────────────────────────
CURRENT_CONFIG_VERSION=2

_migrate_0_to_1() {
    # v1 was the initial schema — nothing to transform, just set the version
    return 0
}

_migrate_1_to_2() {
    # v2 adds: bypass_china_geoip_code, dns_nameserver, dns_fallback,
    # dns_fallback_filter_geoip, internal_group_name
    # Provide safe defaults for all new keys if absent
    uci -q get submihomo.main.bypass_china_geoip_code >/dev/null 2>&1 || \
        uci set submihomo.main.bypass_china_geoip_code='CN'
    uci -q get submihomo.main.dns_nameserver >/dev/null 2>&1 || \
        uci set submihomo.main.dns_nameserver='https://1.1.1.1/dns-query https://8.8.8.8/dns-query'
    uci -q get submihomo.main.dns_fallback >/dev/null 2>&1 || \
        uci set submihomo.main.dns_fallback='https://1.0.0.1/dns-query'
    uci -q get submihomo.main.dns_fallback_filter_geoip >/dev/null 2>&1 || \
        uci set submihomo.main.dns_fallback_filter_geoip='1'
    uci -q get submihomo.main.internal_group_name >/dev/null 2>&1 || \
        uci set submihomo.main.internal_group_name='PROXY'
}

run_migrations() {
    ver=$(uci_get config_version 0)
    while [ "$ver" -lt "$CURRENT_CONFIG_VERSION" ]; do
        next=$((ver + 1))
        log_info "[core] running config migration $ver -> $next"
        if ! "_migrate_${ver}_to_${next}" 2>/dev/null; then
            log_error "[core] migration $ver->$next failed"; return 1
        fi
        if ! { uci set "submihomo.main.config_version=$next" && uci commit submihomo; }; then
            log_error "[core] could not commit migration $ver->$next"; return 1
        fi
        ver=$next
    done
}

# ── Mihomo API helper ────────────────────────────────────────────────────────
mihomo_api() {
    _port=$(uci_get external_controller_port "$CTRL_PORT")
    _sec=$(uci_get external_controller_secret "")
    _url="http://127.0.0.1:${_port}${2}"
    _auth=""; [ -n "$_sec" ] && _auth="-H 'Authorization: Bearer $_sec'"
    # shellcheck disable=SC2086  # $_auth must word-split into wget args
    if [ -n "${3:-}" ]; then
        if ! _r=$(eval wget -q -O - --method="$1" $_auth \
            "--header=Content-Type: application/json" \
            "--body-data='${3}'" "\"$_url\"" 2>/dev/null); then
            log_error "[core] mihomo API unreachable: $_url"; return 1
        fi
    else
        if ! _r=$(eval wget -q -O - $_auth "\"$_url\"" 2>/dev/null); then
            log_error "[core] mihomo API unreachable: $_url"; return 1
        fi
    fi
    printf '%s' "$_r"
}
