#!/bin/sh
# firewall.sh — nftables TPROXY table management
# shellcheck shell=sh
. "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/core.sh"

firewall_setup() {
    # Collect validated user bypass CIDRs into a temp file to avoid subshell
    bypass_tmp=$(mktemp /tmp/sm_bypass.XXXXXX)
    uci_get_bypass | while IFS= read -r cidr; do
        [ -z "$cidr" ] && continue
        if validate_cidr "$cidr"; then
            printf '%s\n' "$cidr" >>"$bypass_tmp"
        else
            log_warn "[firewall] skipping invalid bypass address: $cidr"
        fi
    done

    # Build user_bypass_ipv4 elements string
    user_elements=""
    while IFS= read -r cidr; do
        [ -z "$cidr" ] && continue
        if [ -z "$user_elements" ]; then
            user_elements="$cidr"
        else
            user_elements="$user_elements, $cidr"
        fi
    done <"$bypass_tmp"
    rm -f "$bypass_tmp"

    # Build user_bypass_ipv4 set body
    if [ -n "$user_elements" ]; then
        user_set_body="        elements = { $user_elements }"
    else
        user_set_body=""
    fi

    # Delete existing table first (replace-in-full strategy)
    nft list table inet submihomo >/dev/null 2>&1 &&
        nft delete table inet submihomo 2>/dev/null || true

    # Apply atomically via stdin
    nft -f - 2>/tmp/sm_nft_err <<NFTRULESET
table inet submihomo {

    set bypass_ipv4 {
        type ipv4_addr
        flags interval
        elements = {
            0.0.0.0/8,
            10.0.0.0/8,
            127.0.0.0/8,
            169.254.0.0/16,
            172.16.0.0/12,
            192.168.0.0/16,
            224.0.0.0/4,
            240.0.0.0/4,
            100.64.0.0/10
        }
    }

    set user_bypass_ipv4 {
        type ipv4_addr
        flags interval
$([ -n "$user_set_body" ] && printf '%s\n' "$user_set_body")
    }

    chain prerouting {
        type filter hook prerouting priority mangle - 1; policy accept;
        meta nfproto ipv4 ip daddr @bypass_ipv4 return
        meta nfproto ipv4 ip daddr @user_bypass_ipv4 return
        meta mark $BYPASS_MARK return
        meta nfproto ipv4 meta l4proto tcp tproxy ip to 127.0.0.1:$TPROXY_PORT meta mark set $FWMARK
        meta nfproto ipv4 meta l4proto udp tproxy ip to 127.0.0.1:$TPROXY_PORT meta mark set $FWMARK
    }

    chain output {
        type route hook output priority mangle - 1; policy accept;
        meta mark $BYPASS_MARK return
        meta nfproto ipv4 oif "lo" return
        meta nfproto ipv4 ip daddr @bypass_ipv4 return
        meta nfproto ipv4 ip daddr @user_bypass_ipv4 return
        meta nfproto ipv4 meta l4proto { tcp, udp } meta mark set $FWMARK
    }
}
NFTRULESET

    ret=$?
    if [ $ret -ne 0 ]; then
        err=$(cat /tmp/sm_nft_err 2>/dev/null)
        rm -f /tmp/sm_nft_err
        log_error "[firewall] nft apply failed: $err"
        return 1
    fi
    rm -f /tmp/sm_nft_err
    log_info "[firewall] nftables table inet submihomo applied"
}

firewall_teardown() {
    if ! nft list table inet submihomo >/dev/null 2>&1; then
        log_warn "[firewall] inet submihomo table not present during teardown"
        return 0
    fi
    nft delete table inet submihomo 2>/dev/null || true
    log_info "[firewall] nftables table inet submihomo removed"
}
