// submihomo — rpcd ucode plugin for SubMiHomo
// Loaded by rpcd via ucode.so from /usr/share/rpcd/ucode/

'use strict';

import { popen, open } from 'fs';

const MODS_DIR = '/usr/lib/submihomo';
const SUB_DIR  = '/etc/submihomo/subscriptions';
const RUN_DIR  = '/var/run/submihomo';
const MIHOMO   = '/usr/libexec/submihomo/mihomo';

function shell(cmd) {
    let fh = popen(cmd, 'r');
    let out = fh ? fh.read('all') : '';
    if (fh) fh.close();
    return out;
}

function is_running() {
    let pid_out = trim(shell("cat '" + RUN_DIR + "/mihomo.pid' 2>/dev/null"));
    let pid = +pid_out || 0;
    if (pid > 0) {
        let r = trim(shell('kill -0 ' + pid + ' 2>/dev/null; echo $?'));
        if (r === '0') return pid;
    }
    let pid2 = trim(shell('pgrep -x mihomo 2>/dev/null | head -1'));
    return +pid2 || 0;
}

function count_proxies() {
    let out = shell("grep -c '^[[:space:]]*- name:' '" + SUB_DIR + "/current.yaml' 2>/dev/null");
    return +trim(out) || 0;
}

function mask_url(url) {
    if (!url || length(url) < 8) return url || '';
    return substr(url, 0, 30) + '...';
}

const methods = {
    // ── Status ──────────────────────────────────────────────────────────────
    status: {
        call: function() {
            let pid = is_running();
            let url = trim(shell('uci -q get submihomo.main.subscription_url 2>/dev/null'));
            let dns_mode = trim(shell('uci -q get submihomo.main.dns_mode 2>/dev/null')) || 'fake-ip';
            let proxy_count = count_proxies();
            let mtime = +trim(shell(
                "stat -c '%Y' '" + SUB_DIR + "/current.yaml' 2>/dev/null || " +
                "stat -f '%m' '" + SUB_DIR + "/current.yaml' 2>/dev/null"
            )) || 0;
            let ver_out = trim(shell(MIHOMO + ' -v 2>/dev/null | head -1'));
            return {
                running: pid > 0,
                pid: pid,
                version: ver_out || null,
                subscription_url_masked: url ? mask_url(url) : null,
                last_update: mtime || null,
                proxy_count: proxy_count,
                dns_mode: dns_mode
            };
        }
    },

    // ── Service control ──────────────────────────────────────────────────────
    start: {
        call: function() {
            shell('/etc/init.d/submihomo start 2>&1');
            return { success: true };
        }
    },

    stop: {
        call: function() {
            shell('/etc/init.d/submihomo stop 2>&1');
            return { success: true };
        }
    },

    restart: {
        call: function() {
            shell('/etc/init.d/submihomo restart 2>&1');
            return { success: true };
        }
    },

    // ── Config ───────────────────────────────────────────────────────────────
    get_config: {
        call: function() {
            let keys_list = 'enabled subscription_url subscription_update_interval dns_mode log_level ' +
                'external_controller_port external_controller_secret allow_lan_access bypass_china ' +
                'bypass_china_geoip_code dns_nameserver dns_fallback dns_fallback_filter_geoip ' +
                'internal_group_name subscription_user_agent';
            let main = {};
            for (let k in split(keys_list, ' ')) {
                let v = trim(shell('uci -q get submihomo.main.' + k + ' 2>/dev/null'));
                if (length(v)) main[k] = v;
            }
            if (main.external_controller_secret)
                main.external_controller_secret = 'REDACTED';
            let bypass_out = trim(shell('uci -q get submihomo.bypass.address 2>/dev/null'));
            let address = [];
            for (let a in split(bypass_out, ' '))
                if (length(a)) push(address, a);
            return { main, bypass: { address } };
        }
    },

    set_config: {
        args: { main: {}, bypass: {} },
        call: function(req) {
            let m = req.args?.main || {};
            let errors = [];

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

            for (let k in keys(m)) {
                let v = m[k];
                shell("uci set submihomo.main." + k + "='" + replace(v, "'", "'\\''") + "' 2>/dev/null");
            }
            if (bypass.address) {
                shell('uci delete submihomo.bypass.address 2>/dev/null; uci set submihomo.bypass=bypass 2>/dev/null');
                for (let a in bypass.address)
                    shell("uci add_list submihomo.bypass.address='" + replace(a, "'", "'\\''") + "' 2>/dev/null");
            }
            shell('uci commit submihomo 2>/dev/null');
            return { success: true };
        }
    },

    // ── Subscription ─────────────────────────────────────────────────────────
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

    // ── Proxies ──────────────────────────────────────────────────────────────
    get_proxies: {
        call: function() {
            let pid = is_running();
            if (!pid) return { groups: [], proxies: [], error: 'not_running' };
            let port = trim(shell('uci -q get submihomo.main.external_controller_port 2>/dev/null')) || '9090';
            let secret = trim(shell('uci -q get submihomo.main.external_controller_secret 2>/dev/null')) || '';
            let auth = length(secret) ? "-H 'Authorization: Bearer " + secret + "'" : '';
            let raw = shell('wget -q -O - ' + auth + " 'http://127.0.0.1:" + port + "/proxies' 2>/dev/null");
            // Parse minimal JSON: extract proxy names and types
            let groups = [];
            let proxies = [];
            // Simple extraction - find each "name" field
            let re = /"name":"([^"]+)","type":"([^"]+)"/g;
            let mm;
            while ((mm = exec(re, raw)) !== null) {
                push(proxies, { name: mm[1], type: mm[2] });
            }
            return { groups, proxies, raw: length(raw) > 0 };
        }
    },

    test_connection: {
        call: function() {
            let pid = is_running();
            if (!pid) return { success: false, error: 'not_running' };
            let port = trim(shell('uci -q get submihomo.main.external_controller_port 2>/dev/null')) || '9090';
            let secret = trim(shell('uci -q get submihomo.main.external_controller_secret 2>/dev/null')) || '';
            let auth = length(secret) ? "-H 'Authorization: Bearer " + secret + "'" : '';
            let out = shell('wget -q -O - ' + auth + " 'http://127.0.0.1:" + port + "/version' 2>/dev/null");
            return { success: length(out) > 0, response: trim(out) };
        }
    },

    // ── Diagnostics ──────────────────────────────────────────────────────────
    run_diagnostics: {
        call: function() {
            let checks = [];
            function chk(name, cmd) {
                let ok = trim(shell(cmd + ' >/dev/null 2>&1; echo $?')) === '0';
                push(checks, { name, status: ok ? 'ok' : 'fail', message: ok ? 'OK' : 'FAIL' });
            }
            chk('Mihomo binary', 'test -x ' + MIHOMO);
            chk('Subscription file', 'test -s ' + SUB_DIR + '/current.yaml');
            chk('Config template', 'test -f /etc/submihomo/templates/base.yaml.tmpl');
            chk('Run directory', 'test -d ' + RUN_DIR);
            chk('Dnsmasq config', 'test -f /etc/dnsmasq.d/submihomo.conf');
            chk('Nftables table', 'nft list table inet submihomo');
            chk('IP rule', "ip rule show | grep -q fwmark");
            chk('Routing table', "ip route show table 100 | grep -q 'local default'");
            chk('Dashboard', 'test -f /usr/share/submihomo/dashboard/index.html');
            return { checks };
        }
    },

    // ── Dashboard ────────────────────────────────────────────────────────────
    download_dashboard: {
        call: function() {
            let out = shell('. ' + MODS_DIR + '/dashboard.sh && dashboard_download 2>&1; echo EXIT:$?');
            let m = match(out, /EXIT:(\d+)/);
            return { success: m && +m[1] === 0 };
        }
    },

    // ── Logs ─────────────────────────────────────────────────────────────────
    get_logs: {
        args: { lines: 0 },
        call: function(req) {
            let n = +(req.args?.lines) || 50;
            let out = shell('logread 2>/dev/null | grep submihomo | tail -n ' + n);
            return { logs: out };
        }
    }
};

return { submihomo: methods };
