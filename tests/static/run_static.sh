#!/bin/sh
# tests/static/run_static.sh — Layer 1 static analysis for SubMiHomo
# Runs: shellcheck, shfmt parse, Lua syntax, Lua 5.1 compat, JSON, YAML render,
#        JS syntax, BusyBox-ash hazard scan.
# Exit 0 only if all gates pass. Reproducible; used by CI.
# shellcheck shell=sh
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 2
FAIL=0
note() { printf '  %s\n' "$*"; }
sec()  { printf '\n=== %s ===\n' "$*"; }

SHELL_FILES="files/usr/lib/submihomo/core.sh files/usr/lib/submihomo/config.sh \
files/usr/lib/submihomo/routing.sh files/usr/lib/submihomo/dns.sh \
files/usr/lib/submihomo/firewall.sh files/usr/lib/submihomo/subscription.sh \
files/usr/lib/submihomo/dashboard.sh files/usr/lib/submihomo/mihomo.sh \
files/usr/bin/submihomo-ctl \
install/install.sh install/update.sh install/uninstall.sh"

# ── shellcheck (warning gate) ────────────────────────────────────────────────
sec "shellcheck --shell=sh -x --severity=warning"
if command -v shellcheck >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    if shellcheck --shell=sh -x --source-path=files/usr/lib/submihomo \
        --severity=warning --exclude=SC2153 $SHELL_FILES; then
        note "PASS: no warning-or-higher findings"
    else
        note "FAIL: shellcheck warnings present"; FAIL=1
    fi
    # init script (procd rc.common): external sourcing + procd globals expected
    if shellcheck --shell=sh --severity=warning \
        --exclude=SC1091,SC2034 files/etc/init.d/submihomo; then
        note "PASS: init.d clean"
    else
        note "FAIL: init.d warnings"; FAIL=1
    fi
else
    note "SKIP: shellcheck not installed"
fi

# ── shfmt POSIX parse ────────────────────────────────────────────────────────
sec "shfmt POSIX parse"
if command -v shfmt >/dev/null 2>&1; then
    for f in $SHELL_FILES files/etc/init.d/submihomo; do
        if shfmt -ln posix "$f" >/dev/null 2>&1; then :; else
            note "FAIL: shfmt parse error in $f"; FAIL=1
        fi
    done
    note "PASS: all shell files parse as POSIX"
else
    note "SKIP: shfmt not installed"
fi

# ── Lua syntax + 5.1 compat ──────────────────────────────────────────────────
sec "Lua syntax (luac -p) + 5.1 compat"
if command -v luac >/dev/null 2>&1; then
    if luac -p files/usr/lib/rpcd/submihomo 2>/dev/null; then
        note "PASS: rpcd plugin Lua syntax OK"
    else
        note "FAIL: rpcd plugin Lua syntax error"; FAIL=1
    fi
else
    note "SKIP: luac not installed"
fi
# 5.1 incompatibility scan (real operators only, excludes // in URL literals)
if grep -nE '\bgoto\b|\bbit32\.|\bmath\.type\b|[0-9] // [0-9]|[a-z] << [0-9]|[a-z] >> [0-9]' \
    files/usr/lib/rpcd/submihomo >/dev/null 2>&1; then
    note "FAIL: Lua 5.2+ construct found (breaks OpenWrt Lua 5.1)"; FAIL=1
else
    note "PASS: no Lua 5.2+ only constructs"
fi

# ── JSON validation ──────────────────────────────────────────────────────────
sec "JSON validation"
for j in files/usr/share/luci/menu.d/luci-app-submihomo.json \
         files/usr/share/rpcd/acl.d/luci-app-submihomo.json; do
    if command -v jq >/dev/null 2>&1; then
        if jq empty "$j" 2>/dev/null; then note "PASS: $j"; else note "FAIL: $j"; FAIL=1; fi
    elif command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$j" 2>/dev/null; then
            note "PASS: $j"; else note "FAIL: $j"; FAIL=1; fi
    else
        note "SKIP: no jq/python3 for $j"
    fi
done

# ── JS syntax ────────────────────────────────────────────────────────────────
sec "JS syntax (node --check)"
if command -v node >/dev/null 2>&1; then
    for js in files/htdocs/luci-static/resources/view/submihomo/*.js; do
        if node --check "$js" 2>/dev/null; then note "PASS: $(basename "$js")"
        else note "FAIL: $(basename "$js")"; FAIL=1; fi
    done
else
    note "SKIP: node not installed"
fi

# ── YAML render check ────────────────────────────────────────────────────────
sec "YAML render (template + fixtures)"
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
    python3 tests/static/render_check.py || FAIL=1
else
    note "SKIP: python3+pyyaml not available"
fi

# ── BusyBox-ash hazard scan ──────────────────────────────────────────────────
sec "BusyBox-ash hazard scan"
HAZ=0
for pat in '\[\[[^:]' 'echo -[en]' '<<<' '\breadarray\b' '\bmapfile\b'; do
    if grep -nE "$pat" $SHELL_FILES files/etc/init.d/submihomo 2>/dev/null | grep -qvE '^[[:space:]]*#'; then
        note "HAZARD: pattern '$pat' found"; HAZ=1
    fi
done
# '==' inside single-bracket test
if grep -nE '\[ [^]]*== ' $SHELL_FILES files/etc/init.d/submihomo 2>/dev/null | grep -qv '#'; then
    note "HAZARD: '==' in single-bracket test"; HAZ=1
fi
if [ "$HAZ" -eq 0 ]; then note "PASS: no BusyBox-ash hazards"; else FAIL=1; fi

# ── Result ───────────────────────────────────────────────────────────────────
sec "RESULT"
if [ "$FAIL" -eq 0 ]; then
    note "LAYER 1 STATIC ANALYSIS: PASS"; exit 0
else
    note "LAYER 1 STATIC ANALYSIS: FAIL"; exit 1
fi
