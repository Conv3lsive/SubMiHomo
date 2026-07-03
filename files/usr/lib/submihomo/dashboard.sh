#!/bin/sh
# dashboard.sh — Zashboard download and version management
# shellcheck shell=sh
. "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/core.sh"

# ── Public: dashboard_download ───────────────────────────────────────────────
dashboard_download() {
    repo=$(uci_get dashboard_repo "Zephyruso/zashboard")
    api_url="https://api.github.com/repos/${repo}/releases/latest"
    json_tmp="/tmp/submihomo_gh_$$.json"
    zip_tmp="/tmp/submihomo_dash_$$.zip"

    log_info "[dashboard] dashboard download starting"

    # Fetch release metadata
    wget -q --timeout=30 -O "$json_tmp" "$api_url" 2>/dev/null || {
        log_error "[dashboard] could not reach GitHub API: $api_url"
        rm -f "$json_tmp"
        return 1
    }

    # Extract dist.zip download URL via awk (no jq, no grep -A, no \s)
    dist_url=$(awk '
        /"assets":/ { assets=1 }
        assets && /"name":/ {
            line=$0
            gsub(/[",]/, "", line)
            if (line ~ /name:[[:space:]]*dist\.zip/) { want=1 }
        }
        assets && want && /"browser_download_url":/ {
            sub(/.*"browser_download_url":[[:space:]]*"/, "")
            sub(/".*/, "")
            print
            exit
        }
    ' "$json_tmp")

    if [ -z "$dist_url" ]; then
        log_error "[dashboard] dist.zip asset not found in latest release"
        rm -f "$json_tmp"
        return 1
    fi

    # Extract tag name for version file
    tag=$(awk '/"tag_name":/ {
        sub(/.*"tag_name":[[:space:]]*"/, "")
        sub(/".*/, "")
        print
        exit
    }' "$json_tmp")

    # Download dist.zip
    wget -q --timeout=120 -O "$zip_tmp" "$dist_url" 2>/dev/null || {
        log_error "[dashboard] dist.zip download failed"
        rm -f "$json_tmp" "$zip_tmp"
        return 1
    }

    # Only remove old content AFTER successful download
    mkdir -p "$DASHBOARD_DIR"
    rm -rf "${DASHBOARD_DIR:?}"/*

    # Extract
    unzip -q "$zip_tmp" -d "$DASHBOARD_DIR" 2>/dev/null || {
        log_error "[dashboard] extraction failed, dashboard directory may be incomplete"
        rm -f "$json_tmp" "$zip_tmp"
        return 1
    }

    # Write version file
    printf '%s\n' "$tag" >"$DASHBOARD_DIR/.version"
    chmod 644 "$DASHBOARD_DIR/.version"

    rm -f "$json_tmp" "$zip_tmp"
    log_info "[dashboard] dashboard downloaded successfully ($tag)"
    return 0
}

# ── Public: dashboard_version ────────────────────────────────────────────────
dashboard_version() {
    vfile="$DASHBOARD_DIR/.version"
    if [ -f "$vfile" ]; then
        cat "$vfile"
    else
        printf 'not installed\n'
    fi
}

# ── Entrypoint ───────────────────────────────────────────────────────────────
[ "$1" = "download" ] && dashboard_download
