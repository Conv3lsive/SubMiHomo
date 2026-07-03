#!/bin/sh
# embedded_perf.sh — performance/smoke measurements on a real OpenWrt device.
# Run as root on the target after installing submihomo and configuring UCI.
# shellcheck shell=sh

LOG=${1:-/tmp/submihomo_perf.log}
: >"$LOG"

log() { printf '%s\n' "$*" | tee -a "$LOG"; }

log "=== SubMiHomo embedded performance report ==="
log "date: $(date)"
log "device: $(cat /tmp/sysinfo/model 2>/dev/null || echo unknown)"
log "openwrt: $(cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_RELEASE | cut -d= -f2 | tr -d \")"
log ""

# ── Package footprint ─────────────────────────────────────────────────────────
log "--- Package footprint ---"
for pkg in mihomo submihomo luci-app-submihomo; do
    size=$(apk info -s "$pkg" 2>/dev/null | awk '/Installed-Size/{print $2}')
    log "${pkg}: ${size:-unknown}"
done
log ""

# ── Cold-start time ───────────────────────────────────────────────────────────
log "--- Cold-start time ---"
/etc/init.d/submihomo stop >/dev/null 2>&1 || true
start_ms=$(awk '/^now/{print $2}' /proc/timer_list 2>/dev/null || date +%s%N)
/etc/init.d/submihomo start >/dev/null 2>&1
# Wait until mihomo appears
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pid=$(pgrep -x mihomo 2>/dev/null | head -1)
    [ -n "$pid" ] && break
    sleep 1
done
end_ms=$(awk '/^now/{print $2}' /proc/timer_list 2>/dev/null || date +%s%N)
if [ -n "$pid" ]; then
    if [ "$start_ms" -gt 1000000000000 ] 2>/dev/null; then
        # timer_list returns nanoseconds
        elapsed_ms=$(((end_ms - start_ms) / 1000000))
    else
        elapsed_ms=$(((end_ms - start_ms) / 1000000))
    fi
    log "mihomo pid: $pid"
    log "cold-start time: ${elapsed_ms} ms"
else
    log "ERROR: mihomo did not start"
fi
log ""

# ── Memory footprint ──────────────────────────────────────────────────────────
log "--- Memory footprint ---"
if [ -n "$pid" ] && [ -f "/proc/$pid/status" ]; then
    grep -E 'VmRSS|VmSize|Threads' "/proc/$pid/status" | while IFS= read -r l; do
        log "$l"
    done
else
    log "mihomo process not found"
fi
log ""

# ── Process/fork count ────────────────────────────────────────────────────────
log "--- Process count ---"
count=$(pgrep -c -x mihomo 2>/dev/null || echo 0)
log "mihomo processes: $count (expected 1)"
log ""

# ── File descriptor count ─────────────────────────────────────────────────────
log "--- File descriptors ---"
if [ -n "$pid" ] && [ -d "/proc/$pid/fd" ]; then
    fd_count=$(find "/proc/$pid/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
    log "open file descriptors: $fd_count"
else
    log "mihomo process not found"
fi
log ""

# ── Config generation time ────────────────────────────────────────────────────
log "--- Config generation time ---"
rm -f /var/run/submihomo/config.yaml
cfg_start=$(awk '/^now/{print $2}' /proc/timer_list 2>/dev/null || date +%s%N)
/usr/bin/submihomo-ctl generate >/dev/null 2>&1 || true
cfg_end=$(awk '/^now/{print $2}' /proc/timer_list 2>/dev/null || date +%s%N)
if [ -f /var/run/submihomo/config.yaml ]; then
    cfg_ms=$(((cfg_end - cfg_start) / 1000000))
    log "config_generate time: ${cfg_ms} ms"
else
    log "ERROR: config.yaml not generated"
fi
log ""

log "=== Report written to $LOG ==="
