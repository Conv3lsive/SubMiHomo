#!/bin/sh
# qemu_lifecycle.sh — QEMU integration harness for SubMiHomo on x86_64 OpenWrt.
# Boots a real OpenWrt image, installs the package, and verifies TPROXY,
# nftables, policy routing, DNS hijack, rpcd, failure recovery, and reboot survival.
# shellcheck shell=sh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

SDK_URL=${SDK_URL:-"https://downloads.openwrt.org/snapshots/targets/x86/64/openwrt-sdk-x86-64_gcc-14.4.0_musl.Linux-x86_64.tar.zst"}
TARGET=${TARGET:-x86_64}
WORK_DIR=${WORK_DIR:-/tmp/submihomo-qemu}
IMAGE_URL=${IMAGE_URL:-"https://downloads.openwrt.org/snapshots/targets/x86/64/openwrt-x86-64-generic-ext4-combined.img.gz"}
SSH_PORT=${SSH_PORT:-2222}

APK_DIR="$WORK_DIR/sdk/bin/packages/$TARGET/submihomo"
IMAGE_GZ=$(basename "$IMAGE_URL")
IMAGE="$WORK_DIR/openwrt.img"
KEY="$WORK_DIR/id_qemu"
QEMU_PID_FILE="$WORK_DIR/qemu.pid"

mkdir -p "$WORK_DIR"

# ── Build packages ────────────────────────────────────────────────────────────
printf '==> Building x86_64 APKs...\n'
SDK_URL="$SDK_URL" TARGET="$TARGET" WORK_DIR="$WORK_DIR" \
    sh "$SCRIPT_DIR/sdk_build.sh"

# ── Download and prepare OpenWrt image ────────────────────────────────────────
cd "$WORK_DIR"
if [ ! -f "$IMAGE_GZ" ]; then
    printf '==> Downloading OpenWrt image...\n'
    wget -q --show-progress -O "$IMAGE_GZ" "$IMAGE_URL"
fi
if [ ! -f "$IMAGE" ]; then
    printf '==> Decompressing image...\n'
    gunzip -c "$IMAGE_GZ" >"$IMAGE"
    qemu-img resize -f raw "$IMAGE" +512M
fi

# ── Generate SSH key and inject public key into image ─────────────────────────
if [ ! -f "$KEY" ]; then
    ssh-keygen -t ed25519 -f "$KEY" -N "" -C "submihomo-qqa"
fi

printf '==> Injecting SSH key into image...\n'
MOUNT="$WORK_DIR/mnt"
mkdir -p "$MOUNT"
if command -v guestmount >/dev/null 2>&1; then
    guestmount -a "$IMAGE" -m /dev/sda2 --rw "$MOUNT"
    trap 'guestunmount "$MOUNT"' EXIT
else
    sudo mount -o loop,offset=272629760 "$IMAGE" "$MOUNT"
    trap 'sudo umount "$MOUNT"' EXIT
fi
mkdir -p "$MOUNT/etc/dropbear"
cp "${KEY}.pub" "$MOUNT/etc/dropbear/authorized_keys"
chmod 700 "$MOUNT/etc/dropbear"
chmod 600 "$MOUNT/etc/dropbear/authorized_keys"

# Unmount now so the trap does not fire after we start QEMU.
if command -v guestmount >/dev/null 2>&1; then
    guestunmount "$MOUNT"
else
    sudo umount "$MOUNT"
fi
trap - EXIT

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -p $SSH_PORT -i $KEY root@127.0.0.1"
SCP="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P $SSH_PORT -i $KEY"

# ── Start QEMU ────────────────────────────────────────────────────────────────
printf '==> Starting QEMU...\n'
qemu-system-x86_64 \
    -daemonize \
    -pidfile "$QEMU_PID_FILE" \
    -nographic \
    -m 512 \
    -smp 2 \
    -drive "file=$IMAGE,format=raw,if=virtio" \
    -netdev "user,id=lan,hostfwd=tcp::${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=lan \
    -netdev user,id=wan \
    -device virtio-net-pci,netdev=wan

# ── Wait for SSH ──────────────────────────────────────────────────────────────
printf '==> Waiting for SSH...\n'
for _ in $(seq 1 60); do
    if $SSH echo ready >/dev/null 2>&1; then break; fi
    sleep 2
done
$SSH echo ready >/dev/null 2>&1 || {
    printf 'FAIL: SSH not ready\n'
    exit 1
}

# ── Copy APKs and helpers into VM ─────────────────────────────────────────────
printf '==> Copying APKs and helpers to VM...\n'
$SSH mkdir -p /apk
$SCP "$APK_DIR"/*.apk "$SCRIPT_DIR/qemu_helpers/vm_setup.sh" \
    "$SCRIPT_DIR/qemu_helpers/vm_check.sh" \
    "$SCRIPT_DIR/qemu_helpers/subscription_minimal.yaml" \
    root@127.0.0.1:/apk/

# ── Install and start SubMiHomo ───────────────────────────────────────────────
printf '==> Installing and starting SubMiHomo in VM...\n'
$SSH sh /apk/vm_setup.sh

# ── Runtime verification ──────────────────────────────────────────────────────
printf '==> Running runtime checks...\n'
$SSH sh /apk/vm_check.sh

# ── Failure recovery: kill mihomo and verify procd respawn ────────────────────
printf '==> Testing failure recovery...\n'
$SSH killall mihomo
sleep 10
if $SSH pgrep -x mihomo >/dev/null 2>&1; then
    printf 'PASS: mihomo respawned after failure\n'
else
    printf 'FAIL: mihomo did not respawn\n'
    exit 1
fi

# ── Reboot survival ───────────────────────────────────────────────────────────
printf '==> Testing reboot survival...\n'
$SSH reboot || true

# Wait for SSH to go away and come back.
for _ in $(seq 1 30); do
    if ! $SSH echo ready >/dev/null 2>&1; then break; fi
    sleep 2
done
for _ in $(seq 1 60); do
    if $SSH echo ready >/dev/null 2>&1; then break; fi
    sleep 2
done
$SSH echo ready >/dev/null 2>&1 || {
    printf 'FAIL: SSH not ready after reboot\n'
    exit 1
}

printf '==> Running post-reboot checks...\n'
$SSH sh /apk/vm_check.sh

# ── Cleanup ───────────────────────────────────────────────────────────────────
printf '==> Shutting down QEMU...\n'
if [ -f "$QEMU_PID_FILE" ]; then
    kill "$(cat "$QEMU_PID_FILE")" 2>/dev/null || true
fi

printf '\nQEMU lifecycle integration: PASS\n'
