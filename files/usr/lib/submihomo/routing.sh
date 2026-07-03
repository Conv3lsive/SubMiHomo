#!/bin/sh
# routing.sh — policy routing for TPROXY (ip rule + ip route table 100)
# shellcheck shell=sh
. "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/core.sh"

routing_setup() {
    # Idempotently add local default route in table 100
    if ! ip route show table "$RT_TABLE" 2>/dev/null | grep -q 'local default'; then
        ip route add local default dev lo table "$RT_TABLE" 2>/dev/null || {
            ip route show table "$RT_TABLE" 2>/dev/null | grep -q 'local default' || {
                log_error "[routing] failed to add local default route in table $RT_TABLE"
                return 1
            }
        }
        log_info "[routing] added local default dev lo table $RT_TABLE"
    else
        log_debug "[routing] local default route already present in table $RT_TABLE"
    fi

    # Idempotently add ip rule: fwmark 1 lookup 100 priority 1000
    if ! ip rule show 2>/dev/null | grep -q "fwmark 0x${FWMARK}.*lookup ${RT_TABLE}"; then
        ip rule add fwmark "$FWMARK" lookup "$RT_TABLE" priority 1000 2>/dev/null || {
            ip rule show 2>/dev/null | grep -q "fwmark 0x${FWMARK}.*lookup ${RT_TABLE}" || {
                log_error "[routing] failed to add ip rule fwmark $FWMARK lookup $RT_TABLE"
                return 1
            }
        }
        log_info "[routing] added ip rule fwmark $FWMARK lookup $RT_TABLE priority 1000"
    else
        log_debug "[routing] ip rule fwmark $FWMARK already present"
    fi

    return 0
}

routing_teardown() {
    ip rule del fwmark "$FWMARK" lookup "$RT_TABLE" priority 1000 2>/dev/null || true
    ip route del local default dev lo table "$RT_TABLE" 2>/dev/null || true
    log_info "[routing] routing state removed"
    return 0
}
