#!/bin/sh
# validate_makefile.sh — static verification of the OpenWrt package Makefile
# Runs on the host (macOS/Linux) without the OpenWrt SDK.
# shellcheck shell=sh
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MF="$ROOT/Makefile"
FAIL=0

err() { printf 'FAIL: %s\n' "$*"; FAIL=1; }
ok()  { printf 'PASS: %s\n' "$*"; }

[ -f "$MF" ] || { printf 'FAIL: Makefile not found\n'; exit 1; }

# Required package definitions
for pkg in submihomo luci-app-submihomo; do
    if grep -q "define Package/${pkg}$" "$MF"; then
        ok "Package/${pkg} defined"
    else
        err "Package/${pkg} missing"
    fi
done

# Required metadata
for key in PKG_NAME PKG_VERSION PKG_RELEASE PKG_MAINTAINER PKG_LICENSE; do
    if grep -q "^${key}:=" "$MF"; then
        ok "metadata ${key} present"
    else
        err "metadata ${key} missing"
    fi
done

# BuildPackage calls
if grep -q 'call BuildPackage,submihomo' "$MF" && grep -q 'call BuildPackage,luci-app-submihomo' "$MF"; then
    ok "BuildPackage calls present for both packages"
else
    err "BuildPackage calls missing"
fi

# Dependency sanity: core package must not depend on an external mihomo package
if grep -A5 'define Package/submihomo$' "$MF" | grep -q 'DEPENDS:=.*+mihomo'; then
    err "submihomo should manage Mihomo itself, not depend on +mihomo"
else
    ok "submihomo has no external mihomo dependency"
fi

# LuCI app must depend on submihomo
if grep -A8 'define Package/luci-app-submihomo$' "$MF" | grep -q 'DEPENDS:=.*+submihomo'; then
    ok "luci-app-submihomo depends on submihomo"
else
    err "luci-app-submihomo missing submihomo dependency"
fi

# Install rules reference files that exist
while IFS= read -r line; do
    # match $(INSTALL_*) ./files/... $(1)/...
    src=$(printf '%s' "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^\.\/files\//) print $i}')
    [ -n "$src" ] || continue
    # expand wildcards via ls
    found=0
    for f in $src; do
        [ -e "$ROOT/$f" ] && found=1
    done
    if [ "$found" -eq 1 ]; then
        ok "install source exists: $src"
    else
        err "install source missing: $src"
    fi
done < "$MF"

# Conffiles must reference existing files
awk '/define Package\/submihomo\/conffiles/,/endef/' "$MF" | grep '^/etc/' | while IFS= read -r f; do
    if [ -e "$ROOT/files$f" ]; then
        ok "conffile exists: $f"
    else
        err "conffile missing: $f"
    fi
done

# postinst/prerm present for service lifecycle
for hook in postinst prerm; do
    if grep -q "define Package/submihomo/${hook}$" "$MF"; then
        ok "submihomo ${hook} hook present"
    else
        err "submihomo ${hook} hook missing"
    fi
done

if [ "$FAIL" -eq 0 ]; then
    printf '\nMakefile static validation: PASS\n'
    exit 0
else
    printf '\nMakefile static validation: FAIL\n'
    exit 1
fi
