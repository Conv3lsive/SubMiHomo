#!/bin/sh
# test_dashboard.sh — unit tests for dashboard.sh download/version logic
# shellcheck shell=sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/mocks.sh"

cat >"$MOCK_UCI_FILE" <<EOF
submihomo.main.log_level=warning
EOF

. "$SCRIPT_DIR/../../files/usr/lib/submihomo/core.sh"
. "$SCRIPT_DIR/../../files/usr/lib/submihomo/dashboard.sh"

SANDBOX="/tmp/sm_dash_test_$$"
mkdir -p "$SANDBOX/dash"
DASHBOARD_DIR="$SANDBOX/dash"
export DASHBOARD_DIR

# Build a real zip file containing an index.html
ZIP_FILE="$SANDBOX/dist.zip"
python3 - <<PYEOF
import zipfile, os
with zipfile.ZipFile("$ZIP_FILE", 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('index.html', '<html>zashboard</html>')
PYEOF

# Build GitHub release JSON pointing at our dist.zip URL
GH_JSON='{
  "tag_name": "v1.2.3",
  "assets": [
    {"name": "dist.zip", "browser_download_url": "https://example.com/zashboard/dist.zip"},
    {"name": "source.zip", "browser_download_url": "https://example.com/zashboard/source.zip"}
  ]
}'
JSON_FILE="$SANDBOX/gh.json"
printf '%s\n' "$GH_JSON" >"$JSON_FILE"

# Install a context-aware wget mock for this test
CUSTOM_MOCK="$SANDBOX/mockbin"
mkdir -p "$CUSTOM_MOCK"
cat >"$CUSTOM_MOCK/wget" <<WEOF
#!/bin/sh
printf 'wget %s\n' "\$*" >> "${MOCK_LOG}"
outfile=""
prev=""
for a in "\$@"; do
    [ "\$prev" = "-O" ] && outfile="\$a"
    prev="\$a"
done
if [ -n "\$outfile" ] && [ "\$outfile" != "-" ]; then
    case "\$*" in
        *api.github.com/repos/*)
            cp "$JSON_FILE" "\$outfile" ;;
        *example.com/zashboard/dist.zip*)
            cp "$ZIP_FILE" "\$outfile" ;;
        *)
            printf '%s' "\${WGET_MOCK_RESPONSE:-}" > "\$outfile" ;;
    esac
fi
exit 0
WEOF
chmod +x "$CUSTOM_MOCK/wget"
export PATH="$CUSTOM_MOCK:$PATH"

# ── dashboard_download succeeds with valid JSON + zip ─────────────────────────
: >"$MOCK_LOG"
dashboard_download >/dev/null 2>&1
assert_zero "dashboard_download succeeds with valid release" $?
assert_eq "dashboard_version returns installed tag" "v1.2.3" "$(dashboard_version)"
assert_zero "dashboard index.html extracted" "$(
    [ -f "$DASHBOARD_DIR/index.html" ]
    echo $?
)"
assert_contains "download log includes dist.zip URL" "example.com/zashboard/dist.zip" "$(cat "$MOCK_LOG")"
assert_not_contains "download log does not include source.zip URL" "example.com/zashboard/source.zip" "$(cat "$MOCK_LOG")"

# ── dashboard_download fails when dist.zip asset missing ──────────────────────
printf '%s\n' '{"tag_name":"v0.0.0","assets":[{"name":"source.zip","browser_download_url":"https://example.com/src.zip"}]}' >"$JSON_FILE"
rm -rf "${DASHBOARD_DIR:?}"/*
dashboard_download >/dev/null 2>&1
assert_nonzero "dashboard_download fails when dist.zip missing" $?

# ── dashboard_download fails when unzip payload is invalid ────────────────────
printf '%s\n' '{"tag_name":"v0.0.0","assets":[{"name":"dist.zip","browser_download_url":"https://example.com/zashboard/dist.zip"}]}' >"$JSON_FILE"
printf 'not-a-zip' >"$ZIP_FILE"
rm -rf "${DASHBOARD_DIR:?}"/*
dashboard_download >/dev/null 2>&1
assert_nonzero "dashboard_download fails when extraction fails" $?

# ── dashboard_version reports not installed when version file absent ──────────
rm -rf "${DASHBOARD_DIR:?}"
mkdir -p "$DASHBOARD_DIR"
assert_eq "dashboard_version reports not installed" "not installed" "$(dashboard_version)"

rm -rf "$SANDBOX" "$CUSTOM_MOCK"
cleanup_mocks
print_test_summary
