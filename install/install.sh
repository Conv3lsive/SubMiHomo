#!/bin/sh
# install.sh — Bootstrap SubMiHomo on OpenWrt 25+
# shellcheck shell=sh

APK_REPO_BASE="https://github.com/Conv3lsive/SubMiHomo/releases/latest/download/packages"
APK_REPOS="/etc/apk/repositories"
SYSUPGRADE_CONF="/etc/sysupgrade.conf"

_die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}
_info() { printf '==> %s\n' "$*"; }
_warn() { printf 'WARN: %s\n' "$*"; }

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

# ── Step 2: Verify APK is available ──────────────────────────────────────────
command -v apk >/dev/null 2>&1 || _die "apk package manager not found. This installer requires OpenWrt 23+."

# ── Step 3: Detect architecture ──────────────────────────────────────────────
arch=$(cat /etc/apk/arch 2>/dev/null || apk --print-arch 2>/dev/null || uname -m)
_info "Architecture: $arch"
APK_REPO_LINE="${APK_REPO_BASE}/${arch}"

# ── Step 4: Add repository ────────────────────────────────────────────────────
_info "Configuring repository..."
if ! grep -qF "$APK_REPO_LINE" "$APK_REPOS" 2>/dev/null; then
    printf '%s\n' "$APK_REPO_LINE" >>"$APK_REPOS"
    _info "Repository added."
else
    _info "Repository already configured."
fi

# ── Step 5: Update index ──────────────────────────────────────────────────────
_info "Updating package index..."
apk update --allow-untrusted || _die "apk update failed — check network connectivity"

# ── Step 6: Install packages ──────────────────────────────────────────────────
_info "Installing submihomo and luci-app-submihomo..."
apk add --allow-untrusted submihomo luci-app-submihomo ||
    _die "Package installation failed — see output above"

# ── Step 7: Install managed Mihomo core ──────────────────────────────────────
_info "Installing Mihomo core..."
/usr/bin/submihomo-ctl core-install ||
    _die "Mihomo core installation failed — check network, storage, and architecture support"

# ── Step 8: Add subscription data to sysupgrade preserve list ────────────────
if [ -f "$SYSUPGRADE_CONF" ]; then
    grep -qF '/etc/submihomo' "$SYSUPGRADE_CONF" 2>/dev/null ||
        printf '/etc/submihomo/\n' >>"$SYSUPGRADE_CONF"
else
    printf '/etc/submihomo/\n' >"$SYSUPGRADE_CONF"
fi

# ── Step 9: Enable service (postinst already does this, belt+suspenders) ─────
/etc/init.d/submihomo enable 2>/dev/null || true

# ── Done ─────────────────────────────────────────────────────────────────────
printf '\n'
printf '=================================================\n'
printf ' SubMiHomo installed.\n'
printf ' Open LuCI -> Services -> SubMiHomo to configure.\n'
printf ' Set your subscription URL and click Apply.\n'
printf '=================================================\n'
