#!/bin/sh
# uninstall.sh — Completely remove SubMiHomo from OpenWrt
# shellcheck shell=sh

APK_REPOS="/etc/apk/repositories"
APK_KEYS_DIR="/etc/apk/keys"
APK_REPO_BASE="https://github.com/Conv3lsive/submihomo/releases/latest/download/packages"

_info() { printf '==> %s\n' "$*"; }
arch=$(cat /etc/apk/arch 2>/dev/null || apk --print-arch 2>/dev/null || uname -m)
APK_REPO_LINE="${APK_REPO_BASE}/${arch}"

# ── Step 1: Stop and disable service ─────────────────────────────────────────
_info "Stopping and disabling SubMiHomo..."
/etc/init.d/submihomo stop 2>/dev/null || true
/etc/init.d/submihomo disable 2>/dev/null || true

# ── Step 2: Remove packages ───────────────────────────────────────────────────
_info "Removing packages..."
apk del submihomo luci-app-submihomo 2>/dev/null || true

# ── Step 3: Remove repository configuration ──────────────────────────────────
_info "Removing repository configuration..."
if [ -f "$APK_REPOS" ]; then
    sed -i "\|$APK_REPO_LINE|d" "$APK_REPOS" 2>/dev/null || true
fi
rm -f "$APK_KEYS_DIR/submihomo.pub"

# ── Step 4: Remove dashboard (downloaded, not user data) ─────────────────────
_info "Removing downloaded dashboard files..."
rm -rf /usr/share/submihomo 2>/dev/null || true
rm -rf /usr/libexec/submihomo 2>/dev/null || true

# ── Step 5: Remove runtime state ─────────────────────────────────────────────
rm -f /var/log/submihomo.log 2>/dev/null || true

# ── Step 6: Ask about user config and subscription data ──────────────────────
printf '\nRemove configuration and subscription data?\n'
printf '  /etc/config/submihomo  (subscription URL, controller secret)\n'
printf '  /etc/submihomo/        (subscription YAML files)\n'
printf '[y/N] '
read -r answer
case "$answer" in
    [yY]|[yY][eE][sS])
        rm -rf /etc/submihomo 2>/dev/null || true
        rm -f /etc/config/submihomo 2>/dev/null || true
        _info "Configuration and subscription data removed."
        ;;
    *)
        _info "Configuration preserved at /etc/config/submihomo and /etc/submihomo/"
        ;;
esac

printf '\nSubMiHomo removed.\n'
