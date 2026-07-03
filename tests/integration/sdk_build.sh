#!/bin/sh
# sdk_build.sh — reproducible OpenWrt SDK package build for SubMiHomo
# Usage: SDK_URL=<url> WORK_DIR=/tmp/sm-sdk ./tests/integration/sdk_build.sh
# Produces submihomo and luci-app-submihomo APKs under WORK_DIR/sdk/bin/packages/.
# shellcheck shell=sh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

SDK_URL=${SDK_URL:-"https://downloads.openwrt.org/snapshots/targets/ramips/mt7621/openwrt-sdk-ramips-mt7621_gcc-14.4.0_musl.Linux-x86_64.tar.zst"}
WORK_DIR=${WORK_DIR:-/tmp/submihomo-sdk}
TARGET=${TARGET:-mipsel_24kc}

SDK_TARBALL=$(basename "$SDK_URL")
SDK_DIR="$WORK_DIR/sdk"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ── Download SDK ──────────────────────────────────────────────────────────────
if [ ! -f "$SDK_TARBALL" ]; then
    printf '==> Downloading OpenWrt SDK...\n'
    wget -q --show-progress -O "$SDK_TARBALL" "$SDK_URL"
fi

# ── Extract SDK ───────────────────────────────────────────────────────────────
if [ ! -d "$SDK_DIR" ]; then
    printf '==> Extracting SDK...\n'
    mkdir -p "$SDK_DIR"
    tar --zstd -xf "$SDK_TARBALL" -C "$SDK_DIR" --strip-components=1
fi

cd "$SDK_DIR"

# ── Add feeds: submihomo ──────────────────────────────────────────────────────
if ! grep -qF "src-link submihomo $REPO_ROOT" feeds.conf 2>/dev/null; then
    printf 'src-link submihomo %s\n' "$REPO_ROOT" >> feeds.conf
fi

# ── Update/install feeds ──────────────────────────────────────────────────────
printf '==> Updating feeds...\n'
./scripts/feeds update submihomo
./scripts/feeds install -a -p submihomo

# ── Build packages ─────────────────────────────────────────────────────────────
printf '==> Building submihomo and luci-app-submihomo...\n'
make defconfig
make package/submihomo/compile V=s -j"$(nproc 2>/dev/null || echo 2)"
make package/luci-app-submihomo/compile V=s -j"$(nproc 2>/dev/null || echo 2)"

# ── Verify outputs ────────────────────────────────────────────────────────────
APK_DIR="$SDK_DIR/bin/packages/$TARGET/submihomo"
printf '==> Looking for APKs in %s...\n' "$APK_DIR"

ok=0
for pkg in submihomo luci-app-submihomo; do
    if ls "$APK_DIR/${pkg}"-*.apk >/dev/null 2>&1; then
        printf 'PASS: %s APK built\n' "$pkg"
        ls -l "$APK_DIR/${pkg}"-*.apk
    else
        printf 'FAIL: %s APK not found\n' "$pkg"
        ok=1
    fi
done

if [ "$ok" -eq 0 ]; then
    printf '\nSDK build completed successfully.\n'
    exit 0
else
    printf '\nSDK build failed: missing APK(s).\n'
    exit 1
fi
