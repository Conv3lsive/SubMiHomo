#!/bin/sh
# run_all.sh — discover and run all unit test files, aggregate results
# shellcheck shell=sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=""

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [ -f "$test_file" ] || continue
    printf '\n========== %s ==========\n' "$(basename "$test_file")"
    # Run each test in isolated subshell
    output=$(sh "$test_file" 2>&1)
    exit_code=$?
    printf '%s\n' "$output"
    # Parse pass/fail counts from summary line
    pass=$(printf '%s' "$output" | grep 'Passed:' | grep -o 'Passed: [0-9]*' | grep -o '[0-9]*')
    fail=$(printf '%s' "$output" | grep 'Failed:' | grep -o 'Failed: [0-9]*' | grep -o '[0-9]*')
    TOTAL_PASS=$((TOTAL_PASS + ${pass:-0}))
    TOTAL_FAIL=$((TOTAL_FAIL + ${fail:-0}))
    if [ $exit_code -ne 0 ]; then
        FAILED_FILES="$FAILED_FILES $(basename "$test_file")"
    fi
done

printf '\n========================================\n'
printf 'OVERALL RESULT: %d passed, %d failed\n' "$TOTAL_PASS" "$TOTAL_FAIL"
if [ -n "$FAILED_FILES" ]; then
    printf 'Failed test files:%s\n' "$FAILED_FILES"
    printf '========================================\n'
    exit 1
fi
printf 'All tests passed.\n'
printf '========================================\n'
exit 0
