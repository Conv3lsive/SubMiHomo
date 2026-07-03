#!/bin/sh
# vm_check.sh — run inside the QEMU OpenWrt VM to verify SubMiHomo runtime state.
# shellcheck shell=sh
set -e

FAIL=0

ok()  { printf 'PASS: %s\n' "$*"; }
err() { printf 'FAIL: %s\n' "$*"; FAIL=1; }

# Service process
if pgrep -x mihomo >/dev/null 2>&1; then
    ok "mihomo process is running"
else
    err "mihomo process is not running"
fi

# procd thinks the service is running
if /etc/init.d/submihomo status >/dev/null 2>&1; then
    ok "init script reports running"
else
    err "init script does not report running"
fi

# Generated config exists and controller is bound to loopback
if [ -f /var/run/submihomo/config.yaml ]; then
    ok "runtime config exists"
    if grep -q 'external-controller: 127.0.0.1:9090' /var/run/submihomo/config.yaml; then
        ok "controller bound to 127.0.0.1:9090"
    else
        err "controller not bound to loopback"
    fi
else
    err "runtime config missing"
fi

# nftables table created by firewall.sh
if nft list tables 2>/dev/null | grep -q submihomo; then
    ok "nftables submihomo table exists"
else
    err "nftables submihomo table missing"
fi

# Policy routing
if ip rule show 2>/dev/null | grep -q 'fwmark 0x1 lookup 100'; then
    ok "ip rule for fwmark 0x1 present"
else
    err "ip rule for fwmark 0x1 missing"
fi

if ip route show table 100 2>/dev/null | grep -q 'local default dev lo'; then
    ok "TPROXY local route in table 100 present"
else
    err "TPROXY local route in table 100 missing"
fi

# DNS hijack
if [ -f /etc/dnsmasq.d/submihomo.conf ]; then
    ok "dnsmasq forwarding config present"
else
    err "dnsmasq forwarding config missing"
fi

# rpcd responds
if /usr/lib/rpcd/submihomo status >/dev/null 2>&1; then
    ok "rpcd status method responds"
else
    err "rpcd status method failed"
fi

# Cron entry
if grep -q submihomo-ctl /etc/crontabs/root 2>/dev/null; then
    ok "subscription cron entry present"
else
    err "subscription cron entry missing"
fi

if [ "$FAIL" -eq 0 ]; then
    printf '\nVM runtime checks: PASS\n'
    exit 0
else
    printf '\nVM runtime checks: FAIL\n'
    exit 1
fi
