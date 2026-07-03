#!/bin/sh
# install_direct.sh — Install SubMiHomo directly from GitHub (no APK repository needed)
# shellcheck shell=sh
#
# Usage:
#   sh <(wget -qO- https://raw.githubusercontent.com/Conv3lsive/SubMiHomo/main/install/install_direct.sh)

RAW="https://raw.githubusercontent.com/Conv3lsive/SubMiHomo/main"
SYSUPGRADE_CONF="/etc/sysupgrade.conf"

_die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}
_info() { printf '==> %s\n' "$*"; }
_warn() { printf 'WARN: %s\n' "$*"; }

_fetch() {
    url="${RAW}/${1}"
    dest="$2"
    mkdir -p "$(dirname "$dest")"
    if ! wget -q -O "$dest" "$url" 2>/dev/null; then
        _die "Failed to download: $url"
    fi
}

# ── Step 1: Verify OpenWrt ────────────────────────────────────────────────────
[ -f /etc/openwrt_release ] || _die "This script must be run on OpenWrt."
# shellcheck source=/dev/null
. /etc/openwrt_release
major=$(printf '%s' "${DISTRIB_RELEASE:-0}" | cut -d. -f1)
case "$major" in
'' | *[!0-9]*) _die "Cannot determine OpenWrt version: $DISTRIB_RELEASE" ;;
esac
[ "$major" -lt 23 ] && _die "OpenWrt $DISTRIB_RELEASE is not supported. Version 25+ required."
[ "$major" -lt 25 ] && _warn "OpenWrt $DISTRIB_RELEASE is not the recommended version (25+). Continuing."
_info "OpenWrt $DISTRIB_RELEASE — OK"

# ── Step 2: Check dependencies ────────────────────────────────────────────────
for dep in nft ip gzip wget logger; do
    command -v "$dep" >/dev/null 2>&1 || _die "Missing dependency: $dep"
done
_info "Dependencies OK"

# ── Step 3: Install core service files ───────────────────────────────────────
_info "Installing SubMiHomo service files..."

_fetch files/etc/init.d/submihomo /etc/init.d/submihomo
chmod 755 /etc/init.d/submihomo

_fetch files/usr/bin/submihomo-ctl /usr/bin/submihomo-ctl
chmod 755 /usr/bin/submihomo-ctl

mkdir -p /usr/lib/submihomo
for mod in core.sh config.sh dns.sh firewall.sh routing.sh subscription.sh dashboard.sh mihomo.sh; do
    _fetch "files/usr/lib/submihomo/${mod}" "/usr/lib/submihomo/${mod}"
    chmod 755 "/usr/lib/submihomo/${mod}"
done

mkdir -p /usr/libexec/submihomo

# ── Step 4: Install default config (only if not already present) ─────────────
if [ ! -f /etc/config/submihomo ]; then
    _fetch files/etc/config/submihomo /etc/config/submihomo
    chmod 600 /etc/config/submihomo
    _info "Default config installed."
else
    _info "Existing /etc/config/submihomo preserved."
fi

mkdir -p /etc/submihomo/templates
_fetch files/etc/submihomo/templates/base.yaml.tmpl \
    /etc/submihomo/templates/base.yaml.tmpl
chmod 644 /etc/submihomo/templates/base.yaml.tmpl

# ── Step 5: Install rpcd plugin ──────────────────────────────────────────────
_info "Installing rpcd plugin..."
_fetch files/usr/lib/rpcd/submihomo /usr/lib/rpcd/submihomo
chmod 755 /usr/lib/rpcd/submihomo

_fetch files/usr/share/rpcd/acl.d/luci-app-submihomo.json \
    /usr/share/rpcd/acl.d/luci-app-submihomo.json

# ── Step 6: Install LuCI frontend ────────────────────────────────────────────
_info "Installing LuCI frontend..."
_fetch files/usr/share/luci/menu.d/luci-app-submihomo.json \
    /usr/share/luci/menu.d/luci-app-submihomo.json

mkdir -p /www/luci-static/resources/view/submihomo
for js in logs.js overview.js proxies.js settings.js subscription.js; do
    _fetch "files/htdocs/luci-static/resources/view/submihomo/${js}" \
        "/www/luci-static/resources/view/submihomo/${js}"
done

# ── Step 7: Install managed Mihomo core ──────────────────────────────────────
_info "Installing Mihomo core..."
/usr/bin/submihomo-ctl core-install ||
    _die "Mihomo core installation failed — check network, storage, and architecture support"

# ── Step 8: Preserve config across sysupgrade ────────────────────────────────
if [ -f "$SYSUPGRADE_CONF" ]; then
    grep -qF '/etc/submihomo' "$SYSUPGRADE_CONF" 2>/dev/null ||
        printf '/etc/submihomo/\n' >>"$SYSUPGRADE_CONF"
    grep -qF '/usr/lib/submihomo' "$SYSUPGRADE_CONF" 2>/dev/null ||
        printf '/usr/lib/submihomo/\n' >>"$SYSUPGRADE_CONF"
    grep -qF '/usr/libexec/submihomo' "$SYSUPGRADE_CONF" 2>/dev/null ||
        printf '/usr/libexec/submihomo/\n' >>"$SYSUPGRADE_CONF"
    grep -qF '/usr/bin/submihomo-ctl' "$SYSUPGRADE_CONF" 2>/dev/null ||
        printf '/usr/bin/submihomo-ctl\n' >>"$SYSUPGRADE_CONF"
    grep -qF '/etc/init.d/submihomo' "$SYSUPGRADE_CONF" 2>/dev/null ||
        printf '/etc/init.d/submihomo\n' >>"$SYSUPGRADE_CONF"
else
    {
        printf '/etc/submihomo/\n'
        printf '/usr/lib/submihomo/\n'
        printf '/usr/libexec/submihomo/\n'
        printf '/usr/bin/submihomo-ctl\n'
        printf '/etc/init.d/submihomo\n'
    } >"$SYSUPGRADE_CONF"
fi

# ── Step 9: Enable and reload services ───────────────────────────────────────
/etc/init.d/submihomo enable 2>/dev/null || true
/etc/init.d/rpcd reload 2>/dev/null || true

# ── Done ─────────────────────────────────────────────────────────────────────
printf '\n'
printf '=================================================\n'
printf ' SubMiHomo installed.\n'
printf ' Open LuCI -> Services -> SubMiHomo to configure.\n'
printf ' Set your subscription URL and click Apply.\n'
printf '=================================================\n'
