#!/bin/sh
# update.sh — Upgrade SubMiHomo to the latest published version
# shellcheck shell=sh
set -e

_die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
_info() { printf '==> %s\n' "$*"; }

# Record whether service was running before upgrade
was_running=0
/etc/init.d/submihomo status >/dev/null 2>&1 && was_running=1

_info "Refreshing package index..."
apk update --allow-untrusted || _die "apk update failed"

_info "Upgrading SubMiHomo packages..."
old_ver=$(apk info -e submihomo 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1 || echo "unknown")
apk upgrade --allow-untrusted submihomo luci-app-submihomo || \
    _die "apk upgrade failed — previous version remains active"
new_ver=$(apk info -e submihomo 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1 || echo "unknown")

_info "submihomo: $old_ver -> $new_ver"

_info "Updating Mihomo core..."
/usr/bin/submihomo-ctl core-update || \
    _die "Mihomo core update failed — previous core remains available for rollback"

if [ "$was_running" -eq 1 ]; then
    _info "Restarting SubMiHomo service..."
    /etc/init.d/submihomo restart || true
else
    _info "Service was stopped before upgrade — leaving stopped"
fi

printf '\nSubMiHomo updated.\n'
