#!/bin/sh
# docker_lifecycle.sh — Docker integration harness for SubMiHomo
# Builds x86_64 APKs, starts an OpenWrt rootfs container, exercises the full
# install/configure/start/rpcd/stop/uninstall lifecycle, and verifies cleanup.
# shellcheck shell=sh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SDK_URL=${SDK_URL:-"https://downloads.openwrt.org/snapshots/targets/x86/64/openwrt-sdk-x86-64_gcc-14.4.0_musl.Linux-x86_64.tar.zst"}
TARGET=${TARGET:-x86_64}
WORK_DIR=${WORK_DIR:-/tmp/submihomo-docker}
OPENWRT_IMAGE=${OPENWRT_IMAGE:-"openwrt/rootfs:x86_64-openwrt-snapshot"}
CONTAINER_NAME=${CONTAINER_NAME:-submihomo-test}

APK_DIR="$WORK_DIR/sdk/bin/packages/$TARGET/submihomo"
HELPERS="$SCRIPT_DIR/docker_helpers"

# ── Build packages ────────────────────────────────────────────────────────────
printf '==> Building x86_64 APKs...\n'
SDK_URL="$SDK_URL" TARGET="$TARGET" WORK_DIR="$WORK_DIR" \
    sh "$SCRIPT_DIR/sdk_build.sh"

# ── Start OpenWrt container ───────────────────────────────────────────────────
printf '==> Starting OpenWrt container (%s)...\n' "$OPENWRT_IMAGE"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER_NAME" --privileged \
    -v "$APK_DIR:/apk:ro" \
    -v "$HELPERS:/helpers:ro" \
    "$OPENWRT_IMAGE" /sbin/init

# Wait for container init
for _ in 1 2 3 4 5; do
    if docker exec "$CONTAINER_NAME" sh -c 'echo ready' >/dev/null 2>&1; then break; fi
    sleep 1
done

# ── Install and configure ─────────────────────────────────────────────────────
printf '==> Installing packages and configuring...\n'
docker exec "$CONTAINER_NAME" sh /helpers/container_setup.sh

# ── Start service ─────────────────────────────────────────────────────────────
printf '==> Starting SubMiHomo service...\n'
docker exec "$CONTAINER_NAME" /etc/init.d/submihomo start
sleep 2

# ── Verify service is running ─────────────────────────────────────────────────
if docker exec "$CONTAINER_NAME" pgrep -x mihomo >/dev/null 2>&1; then
    printf 'PASS: mihomo process is running\n'
else
    printf 'FAIL: mihomo process is not running\n'
    exit 1
fi

# ── Exercise rpcd ─────────────────────────────────────────────────────────────
printf '==> Exercising rpcd methods...\n'
status_out=$(docker exec "$CONTAINER_NAME" /usr/lib/rpcd/submihomo status)
printf 'status: %s\n' "$status_out"
if printf '%s' "$status_out" | grep -q 'running'; then
    printf 'PASS: rpcd status reports running\n'
else
    printf 'FAIL: rpcd status did not report running\n'
    exit 1
fi

set_config_out=$(docker exec -i "$CONTAINER_NAME" /usr/lib/rpcd/submihomo set_config <<'EOF'
{"main":{"enabled":"1","subscription_url":"https://example.com/sub2","dns_mode":"fake-ip","log_level":"info","external_controller_port":"9090","allow_lan_access":"0","bypass_china":"0"}}
EOF
)
printf 'set_config: %s\n' "$set_config_out"
if printf '%s' "$set_config_out" | grep -q 'success":true'; then
    printf 'PASS: rpcd set_config accepted valid config\n'
else
    printf 'FAIL: rpcd set_config rejected valid config\n'
    exit 1
fi

# ── Stop service ──────────────────────────────────────────────────────────────
printf '==> Stopping service...\n'
docker exec "$CONTAINER_NAME" /etc/init.d/submihomo stop
sleep 1
if docker exec "$CONTAINER_NAME" pgrep -x mihomo >/dev/null 2>&1; then
    printf 'FAIL: mihomo still running after stop\n'
    exit 1
else
    printf 'PASS: mihomo stopped\n'
fi

# ── Uninstall packages ────────────────────────────────────────────────────────
printf '==> Uninstalling packages...\n'
docker exec "$CONTAINER_NAME" apk del submihomo luci-app-submihomo

# ── Verify cleanup ────────────────────────────────────────────────────────────
printf '==> Verifying cleanup...\n'
orphans=0
for path in /usr/lib/submihomo /usr/bin/submihomo-ctl /etc/init.d/submihomo \
            /usr/share/submihomo /usr/libexec/submihomo /var/run/submihomo; do
    if docker exec "$CONTAINER_NAME" sh -c "[ -e '$path' ]" 2>/dev/null; then
        printf 'FAIL: orphan path after uninstall: %s\n' "$path"
        orphans=1
    fi
done
if docker exec "$CONTAINER_NAME" grep -q submihomo-ctl /etc/crontabs/root 2>/dev/null; then
    printf 'FAIL: submihomo cron entry left behind\n'
    orphans=1
fi
if docker exec "$CONTAINER_NAME" pgrep -x mihomo >/dev/null 2>&1; then
    printf 'FAIL: mihomo process still alive after uninstall\n'
    orphans=1
fi

if [ "$orphans" -eq 0 ]; then
    printf 'PASS: no orphan files, cron entries, or runtime processes\n'
else
    exit 1
fi

# ── Tear down container ───────────────────────────────────────────────────────
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

printf '\nDocker lifecycle integration: PASS\n'
