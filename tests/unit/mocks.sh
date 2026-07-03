#!/bin/sh
# mocks.sh — shared mock implementations for unit tests
# Source this file BEFORE sourcing the module under test.
# shellcheck shell=sh

MOCK_LOG=${MOCK_LOG:-/tmp/submihomo_mock_$$.log}
MOCK_UCI_FILE=${MOCK_UCI_FILE:-/tmp/submihomo_mock_uci_$$}
: > "$MOCK_LOG"
export MOCK_LOG MOCK_UCI_FILE

# ── Mock: logger ──────────────────────────────────────────────────────────────
# Installed by prepending a mock dir to PATH
_setup_mock_bins() {
    MOCK_BIN_DIR="/tmp/sm_mock_bins_$$"
    mkdir -p "$MOCK_BIN_DIR"
    export MOCK_BIN_DIR

    # Point SUBMIHOMO_LIB to the repo's files/ tree so modules find core.sh
    # when they do: . "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/core.sh"
    SUBMIHOMO_LIB="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)/files/usr/lib/submihomo"
    export SUBMIHOMO_LIB

    # logger — embed the actual log path
    cat > "$MOCK_BIN_DIR/logger" <<MOCKEOF
#!/bin/sh
printf 'logger %s\n' "\$*" >> "${MOCK_LOG}"
MOCKEOF

    # uci — embed the actual file paths so subshells can find them
    cat > "$MOCK_BIN_DIR/uci" <<MOCKEOF
#!/bin/sh
_ML="${MOCK_LOG}"
_MU="${MOCK_UCI_FILE}"
printf 'uci %s\n' "\$*" >> "\$_ML"
# Normalize: strip leading -q flag
args="\$*"
case "\$args" in -q*) args=\$(printf '%s' "\$args" | sed 's/^-q //') ;; esac
case "\$args" in
    get*)
        key=\$(printf '%s' "\$args" | sed 's/^get //')
        val=\$(grep "^\${key}=" "\$_MU" 2>/dev/null | head -1 | cut -d= -f2-)
        [ -n "\$val" ] && printf '%s' "\$val" && exit 0
        exit 1 ;;
    set|set*|commit|add_list*|delete*) exit 0 ;;
    *) exit 0 ;;
esac
MOCKEOF

    # nft
    cat > "$MOCK_BIN_DIR/nft" <<MOCKEOF
#!/bin/sh
printf 'nft %s\n' "\$*" >> "${MOCK_LOG}"
[ "\${NFT_MOCK_FAIL:-0}" = "1" ] && { printf 'mock nft failure\n' >&2; exit 1; }
exit 0
MOCKEOF

    # ip
    cat > "$MOCK_BIN_DIR/ip" <<MOCKEOF
#!/bin/sh
printf 'ip %s\n' "\$*" >> "${MOCK_LOG}"
[ "\${IP_MOCK_FAIL:-0}" = "1" ] && exit 1
case "\$*" in
    *"rule show"*) [ "\${IP_RULE_EXISTS:-0}" = "1" ] && printf 'fwmark 0x1 lookup 100\n'; exit 0 ;;
    *"route show table 100"*) [ "\${IP_ROUTE_EXISTS:-0}" = "1" ] && printf 'local default dev lo table 100\n'; exit 0 ;;
    *) exit 0 ;;
esac
MOCKEOF

    # wget
    cat > "$MOCK_BIN_DIR/wget" <<MOCKEOF
#!/bin/sh
printf 'wget %s\n' "\$*" >> "${MOCK_LOG}"
outfile=""
prev=""
for a in "\$@"; do
    [ "\$prev" = "-O" ] && outfile="\$a"
    prev="\$a"
done
if [ -n "\$outfile" ] && [ "\$outfile" != "-" ]; then
    if [ -n "\${WGET_MOCK_FILE:-}" ] && [ -f "\${WGET_MOCK_FILE}" ]; then
        cp "\${WGET_MOCK_FILE}" "\$outfile"
    elif [ -n "\${WGET_MOCK_RESPONSE:-}" ]; then
        printf '%s' "\${WGET_MOCK_RESPONSE}" > "\$outfile"
    fi
fi
exit "\${WGET_MOCK_EXIT:-0}"
MOCKEOF

    # mihomo
    cat > "$MOCK_BIN_DIR/mihomo" <<MOCKEOF
#!/bin/sh
printf 'mihomo %s\n' "\$*" >> "${MOCK_LOG}"
case "\$1" in
    -t) [ "\${MIHOMO_T_FAIL:-0}" = "1" ] && { printf 'mock validation failure\n' >&2; exit 1; }; exit 0 ;;
    -v) printf 'Mihomo 1.18.0 mock\n'; exit 0 ;;
    *) exit 0 ;;
esac
MOCKEOF
    MIHOMO_BIN="$MOCK_BIN_DIR/mihomo"
    MIHOMO_BIN_DIR="$MOCK_BIN_DIR"
    MIHOMO_BACKUP_BIN="$MOCK_BIN_DIR/mihomo.backup"
    MIHOMO_STATE_DIR="/tmp/sm_mock_mihomo_state_$$"
    MIHOMO_VERSION_FILE="$MIHOMO_STATE_DIR/version"
    export MIHOMO_BIN MIHOMO_BIN_DIR MIHOMO_BACKUP_BIN MIHOMO_STATE_DIR MIHOMO_VERSION_FILE

    # pgrep
    cat > "$MOCK_BIN_DIR/pgrep" <<MOCKEOF
#!/bin/sh
[ -n "\${PGREP_MOCK_PID:-}" ] && printf '%s\n' "\${PGREP_MOCK_PID}" && exit 0
exit 1
MOCKEOF

    chmod +x "$MOCK_BIN_DIR"/*
    export PATH="$MOCK_BIN_DIR:$PATH"
}

_setup_mock_bins

# ── Assertion helpers ─────────────────────────────────────────────────────────
TESTS_PASS=0
TESTS_FAIL=0

assert_eq() {
    desc=$1; expected=$2; actual=$3
    if [ "$actual" = "$expected" ]; then
        TESTS_PASS=$((TESTS_PASS+1)); printf '[PASS] %s\n' "$desc"
    else
        TESTS_FAIL=$((TESTS_FAIL+1)); printf '[FAIL] %s — expected "%s", got "%s"\n' "$desc" "$expected" "$actual"
    fi
}

assert_zero() {
    desc=$1; code=$2
    if [ "$code" -eq 0 ]; then
        TESTS_PASS=$((TESTS_PASS+1)); printf '[PASS] %s\n' "$desc"
    else
        TESTS_FAIL=$((TESTS_FAIL+1)); printf '[FAIL] %s — expected exit 0, got %s\n' "$desc" "$code"
    fi
}

assert_nonzero() {
    desc=$1; code=$2
    if [ "$code" -ne 0 ]; then
        TESTS_PASS=$((TESTS_PASS+1)); printf '[PASS] %s\n' "$desc"
    else
        TESTS_FAIL=$((TESTS_FAIL+1)); printf '[FAIL] %s — expected non-zero, got 0\n' "$desc"
    fi
}

assert_contains() {
    desc=$1; needle=$2; haystack=$3
    if printf '%s' "$haystack" | grep -q "$needle" 2>/dev/null; then
        TESTS_PASS=$((TESTS_PASS+1)); printf '[PASS] %s\n' "$desc"
    else
        TESTS_FAIL=$((TESTS_FAIL+1)); printf '[FAIL] %s — "%s" not found in output\n' "$desc" "$needle"
    fi
}

assert_not_contains() {
    desc=$1; needle=$2; haystack=$3
    if ! printf '%s' "$haystack" | grep -q "$needle" 2>/dev/null; then
        TESTS_PASS=$((TESTS_PASS+1)); printf '[PASS] %s\n' "$desc"
    else
        TESTS_FAIL=$((TESTS_FAIL+1)); printf '[FAIL] %s — "%s" should NOT appear but does\n' "$desc" "$needle"
    fi
}

mock_log_contains() { grep -q "$1" "$MOCK_LOG" 2>/dev/null; }

print_test_summary() {
    printf '\n--- Test Summary ---\n'
    printf 'Passed: %d  Failed: %d\n' "$TESTS_PASS" "$TESTS_FAIL"
    [ "$TESTS_FAIL" -eq 0 ]
}

cleanup_mocks() {
    rm -f "$MOCK_LOG" "$MOCK_UCI_FILE"
    rm -rf "$MOCK_BIN_DIR"
}
