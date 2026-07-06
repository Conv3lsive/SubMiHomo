// submihomo.uc — rpcd ucode plugin for SubMiHomo
// Loaded by rpcd via ucode.so from /usr/share/rpcd/ucode/

'use strict';

import { popen, open } from 'fs';

const MODS_DIR = '/usr/lib/submihomo';
const SUB_DIR  = '/etc/submihomo/subscriptions';
const RUN_DIR  = '/var/run/submihomo';

function shell(cmd) {
    let fh = popen(cmd, 'r');
    let out = fh ? fh.read('all') : '';
    if (fh) fh.close();
    return out;
}

function count_proxies() {
    let out = shell("grep -c '^[[:space:]]*- name:' '" + SUB_DIR + "/current.yaml' 2>/dev/null");
    return +trim(out) || 0;
}

function read_sub_status() {
    let cur = SUB_DIR + '/current.yaml';
    let fh = open(cur, 'r');
    if (!fh) return { status: 'absent', proxy_count: 0 };
    fh.close();
    let cnt = count_proxies();
    let mtime_out = shell("stat -c '%Y' '" + cur + "' 2>/dev/null || stat -f '%m' '" + cur + "' 2>/dev/null");
    return {
        status: 'active',
        proxy_count: cnt,
        last_update: +trim(mtime_out) || 0
    };
}

return {
    get_config: {
        call: function() {
            let out = shell(". " + MODS_DIR + "/core.sh && " +
                "printf 'enabled=%s\\n' \"$(uci -q get submihomo.main.enabled 2>/dev/null || echo 0)\" && " +
                "for k in subscription_url subscription_update_interval dns_mode log_level " +
                "external_controller_port external_controller_secret allow_lan_access bypass_china " +
                "bypass_china_geoip_code dns_nameserver dns_fallback dns_fallback_filter_geoip " +
                "internal_group_name subscription_user_agent; do " +
                "v=$(uci -q get submihomo.main.$k 2>/dev/null); " +
                "[ -n \"$v\" ] && printf '%s=%s\\n' \"$k\" \"$v\"; done");
            let main = {};
            for (let line in split(out, '\n')) {
                let m = match(line, /^([^=]+)=(.*)$/);
                if (m) main[m[1]] = m[2];
            }
            // Redact secret
            if (main.external_controller_secret)
                main.external_controller_secret = 'REDACTED';
            // Bypass addresses
            let bypass_out = shell("uci -q get submihomo.bypass.address 2>/dev/null");
            let address = [];
            for (let a in split(trim(bypass_out), ' '))
                if (a) push(address, a);
            return { main, bypass: { address } };
        }
    },

    set_config: {
        args: { main: {}, bypass: {} },
        call: function(req) {
            let m = req.args?.main || {};
            let errors = [];

            // Validation
            if (m.enabled !== undefined && m.enabled !== '0' && m.enabled !== '1')
                push(errors, 'enabled: must be 0 or 1');
            if (m.subscription_url && !match(m.subscription_url, /^https:\/\//))
                push(errors, 'subscription_url: must be empty or begin with https://');
            let reserved = ['7890', '7891', '1053'];
            if (m.external_controller_port && index(reserved, m.external_controller_port) >= 0)
                push(errors, 'external_controller_port: conflicts with reserved SubMiHomo port');

            let bypass = req.args?.bypass || {};
            if (bypass.address) {
                let i = 0;
                for (let cidr in bypass.address) {
                    i++;
                    if (!match(cidr, /^\d+\.\d+\.\d+\.\d+\/\d+$/))
                        push(errors, 'bypass.address[' + i + ']: invalid CIDR');
                }
            }

            if (length(errors) > 0)
                return { success: false, errors };

            // Apply
            for (let k in keys(m)) {
                let v = m[k];
                shell("uci set submihomo.main." + k + "='" + replace(v, "'", "'\\''") + "' 2>/dev/null");
            }
            if (bypass.address) {
                shell("uci delete submihomo.bypass.address 2>/dev/null; uci set submihomo.bypass=bypass 2>/dev/null");
                for (let a in bypass.address)
                    shell("uci add_list submihomo.bypass.address='" + replace(a, "'", "'\\''") + "' 2>/dev/null");
            }
            shell('uci commit submihomo 2>/dev/null');
            return { success: true };
        }
    },

    get_status: {
        call: function() {
            let pid_out = shell("cat '" + RUN_DIR + "/mihomo.pid' 2>/dev/null || pgrep -x mihomo 2>/dev/null | head -1");
            let pid = +trim(pid_out) || 0;
            let running = pid > 0 && length(shell("kill -0 " + pid + " 2>/dev/null; echo $?")) > 0 &&
                          trim(shell("kill -0 " + pid + " 2>/dev/null; echo $?")) === '0';
            let sub = read_sub_status();
            let ver_out = shell("/usr/libexec/submihomo/mihomo -v 2>/dev/null | head -1");
            return {
                running,
                pid: running ? pid : 0,
                subscription: sub,
                mihomo_version: trim(ver_out) || 'unknown'
            };
        }
    },

    update_subscription: {
        call: function() {
            shell('rm -f ' + RUN_DIR + '/submihomo.lock 2>/dev/null; true');
            let out = shell('. ' + MODS_DIR + '/subscription.sh && subscription_update 2>&1; echo EXIT:$?');
            let m = match(out, /EXIT:(\d+)/);
            let ec = m ? +m[1] : 1;
            let proxy_count = count_proxies();
            if (ec === 0 || proxy_count > 0)
                return { success: true, proxy_count };
            let em = match(out, /\[ERROR\][^\n]*/);
            return { success: false, error: em || 'Update failed' };
        }
    },

    download_dashboard: {
        call: function() {
            let out = shell('. ' + MODS_DIR + '/dashboard.sh && dashboard_download 2>&1; echo EXIT:$?');
            let m = match(out, /EXIT:(\d+)/);
            return { success: m && +m[1] === 0 };
        }
    },

    get_logs: {
        args: { lines: 0 },
        call: function(req) {
            let n = req.args?.lines || 50;
            let out = shell('logread 2>/dev/null | grep submihomo | tail -n ' + (+n || 50));
            return { logs: out };
        }
    },

    run_diagnostics: {
        call: function() {
            let checks = [];
            function chk(label, cmd) {
                let ok = trim(shell(cmd + ' >/dev/null 2>&1; echo $?')) === '0';
                push(checks, { label, ok });
            }
            chk('mihomo binary', 'test -x /usr/libexec/submihomo/mihomo');
            chk('subscription file', 'test -s ' + SUB_DIR + '/current.yaml');
            chk('config template', 'test -f /etc/submihomo/templates/base.yaml.tmpl');
            chk('run directory', 'test -d ' + RUN_DIR);
            chk('dnsmasq config', 'test -f /etc/dnsmasq.d/submihomo.conf');
            chk('nftables table', 'nft list table inet submihomo');
            chk('ip rule', "ip rule show | grep -q fwmark");
            chk('routing table', "ip route show table 100 | grep -q 'local default'");
            return { checks };
        }
    }
};
