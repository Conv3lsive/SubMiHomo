#!/bin/sh
# mihomo.sh — managed Mihomo binary lifecycle
# shellcheck shell=sh
. "${SUBMIHOMO_LIB:-/usr/lib/submihomo}/core.sh"

MIHOMO_TMP_MIN_KB=16000
MIHOMO_ROOT_MIN_KB=18000
MIHOMO_DOWNLOAD_TIMEOUT=120
MIHOMO_DOWNLOAD_RETRIES=3
MIHOMO_RETRY_DELAY=5

_mihomo_avail_kb() {
    df -k "$1" 2>/dev/null | awk 'NR==2 {print $4}'
}

_mihomo_space_check() {
    tmp_kb=$(_mihomo_avail_kb /tmp)
    [ -z "$tmp_kb" ] && tmp_kb=0
    if [ "$tmp_kb" -lt "$MIHOMO_TMP_MIN_KB" ] 2>/dev/null; then
        log_error "[mihomo] not enough free space in /tmp (${tmp_kb}KB available)"
        return 1
    fi

    mkdir -p "$MIHOMO_BIN_DIR" "$MIHOMO_STATE_DIR" 2>/dev/null || {
        log_error "[mihomo] cannot create managed binary directories"
        return 1
    }

    root_kb=$(_mihomo_avail_kb "$MIHOMO_BIN_DIR")
    [ -z "$root_kb" ] && root_kb=0
    if [ "$root_kb" -lt "$MIHOMO_ROOT_MIN_KB" ] 2>/dev/null; then
        log_error "[mihomo] not enough free space in $MIHOMO_BIN_DIR (${root_kb}KB available)"
        return 1
    fi
}

_mihomo_is_little_endian() {
    byte=$(hexdump -s 5 -n 1 -e '1/1 "%d"' /bin/busybox 2>/dev/null || echo 0)
    [ "$byte" = "1" ]
}

_mihomo_mips_float() {
    fpu=$(grep -c "FPU" /proc/cpuinfo 2>/dev/null || echo 0)
    [ "$fpu" -gt 0 ] 2>/dev/null && printf 'hardfloat' || printf 'softfloat'
}

mihomo_detect_arch() {
    apk_arch=$(cat /etc/apk/arch 2>/dev/null || apk --print-arch 2>/dev/null || true)
    case "$apk_arch" in
    x86_64)
        printf 'amd64'
        return 0
        ;;
    i386 | i486 | i586 | i686 | pentium*)
        printf '386'
        return 0
        ;;
    aarch64*)
        printf 'arm64'
        return 0
        ;;
    arm_cortex-a5* | arm_cortex-a7* | arm_cortex-a8* | arm_cortex-a9* | arm_cortex-a15*)
        printf 'armv7'
        return 0
        ;;
    arm_arm1176*)
        printf 'armv6'
        return 0
        ;;
    mipsel*)
        printf 'mipsle-%s' "$(_mihomo_mips_float)"
        return 0
        ;;
    mips*)
        printf 'mips-%s' "$(_mihomo_mips_float)"
        return 0
        ;;
    riscv64*)
        printf 'riscv64'
        return 0
        ;;
    esac

    uname_arch=$(uname -m 2>/dev/null || true)
    case "$uname_arch" in
    x86_64) printf 'amd64' ;;
    i?86) printf '386' ;;
    aarch64 | arm64) printf 'arm64' ;;
    armv7* | armv8*) printf 'armv7' ;;
    armv6*) printf 'armv6' ;;
    armv5* | armv4*) printf 'armv5' ;;
    mips*)
        if _mihomo_is_little_endian; then
            printf 'mipsle-%s' "$(_mihomo_mips_float)"
        else
            printf 'mips-%s' "$(_mihomo_mips_float)"
        fi
        ;;
    riscv64) printf 'riscv64' ;;
    *)
        log_error "[mihomo] unsupported architecture: ${apk_arch:-$uname_arch}"
        return 1
        ;;
    esac
}

mihomo_latest_version() {
    tmp="/tmp/submihomo_mihomo_release_$$.json"
    api="https://api.github.com/repos/${MIHOMO_SOURCE_REPO}/releases/latest"
    rm -f "$tmp"
    # Retry with exponential backoff on API rate-limit or transient errors
    attempt=0
    while [ "$attempt" -lt "$MIHOMO_DOWNLOAD_RETRIES" ]; do
        attempt=$((attempt + 1))
        if wget -q --timeout="$MIHOMO_DOWNLOAD_TIMEOUT" -O "$tmp" "$api" 2>/dev/null; then
            break
        fi
        if [ "$attempt" -lt "$MIHOMO_DOWNLOAD_RETRIES" ]; then
            delay=$((MIHOMO_RETRY_DELAY * attempt))
            log_warn "[mihomo] API query failed (attempt $attempt/$MIHOMO_DOWNLOAD_RETRIES), retrying in ${delay}s"
            sleep "$delay"
        fi
    done
    if [ ! -s "$tmp" ]; then
        log_error "[mihomo] could not query latest release after $MIHOMO_DOWNLOAD_RETRIES attempts: $api"
        rm -f "$tmp"
        return 1
    fi
    tag=$(awk '/"tag_name":/ {
        sub(/.*"tag_name":[[:space:]]*"/, "")
        sub(/".*/, "")
        print
        exit
    }' "$tmp")
    rm -f "$tmp"
    case "$tag" in
    v[0-9]*.[0-9]*.[0-9]*) printf '%s' "$tag" ;;
    *)
        log_error "[mihomo] invalid or missing latest release tag: ${tag:-empty}"
        return 1
        ;;
    esac
}

mihomo_installed_version() {
    if [ -f "$MIHOMO_VERSION_FILE" ]; then
        awk -F= '$1=="version" {print $2; exit}' "$MIHOMO_VERSION_FILE"
        return 0
    fi
    [ -x "$MIHOMO_BIN" ] || return 1
    "$MIHOMO_BIN" -v 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^v?[0-9]+\.[0-9]+\.[0-9]+/) {
                    v=$i; sub(/^[^0-9]*/, "v", v); print v; exit
                }
            }
        }'
}

_mihomo_write_metadata() {
    version=$1
    arch=$2
    url=$3
    hash=$4
    mkdir -p "$MIHOMO_STATE_DIR" 2>/dev/null || return 1
    {
        printf 'version=%s\n' "$version"
        printf 'arch=%s\n' "$arch"
        printf 'source=%s\n' "$url"
        printf 'sha256=%s\n' "$hash"
        printf 'installed_at=%s\n' "$(date +%s 2>/dev/null || echo 0)"
    } >"$MIHOMO_VERSION_FILE"
    chmod 600 "$MIHOMO_VERSION_FILE" 2>/dev/null || true
}

_mihomo_verify_sha256() {
    candidate=$1
    expected_hash=$2
    [ -s "$candidate" ] || {
        log_error "[mihomo] candidate binary is empty"
        return 1
    }
    computed_hash=$(sha256sum "$candidate" 2>/dev/null | awk '{print $1}')
    if [ -z "$computed_hash" ]; then
        log_error "[mihomo] could not compute SHA256 of candidate"
        return 1
    fi
    if [ "$computed_hash" != "$expected_hash" ]; then
        log_error "[mihomo] SHA256 mismatch: expected $expected_hash, got $computed_hash"
        return 1
    fi
    log_debug "[mihomo] SHA256 verification passed: $computed_hash"
    return 0
}

_mihomo_verify_executable() {
    candidate=$1
    expected=$2
    [ -s "$candidate" ] || {
        log_error "[mihomo] candidate binary is empty"
        return 1
    }
    chmod 755 "$candidate" 2>/dev/null || return 1
    out=$("$candidate" -v 2>&1)
    ret=$?
    if [ "$ret" -ne 0 ]; then
        log_error "[mihomo] candidate binary failed to execute: $out"
        return 1
    fi
    case "$out" in
    *"$expected"* | *[Mm]ihomo*) return 0 ;;
    *)
        log_warn "[mihomo] candidate version output did not include expected tag: $out"
        return 0
        ;;
    esac
}

_mihomo_download_with_retries() {
    url=$1
    output=$2
    attempt=0
    while [ "$attempt" -lt "$MIHOMO_DOWNLOAD_RETRIES" ]; do
        attempt=$((attempt + 1))
        # First try with certificate verification; fall back without it on embedded
        # devices where GitHub's release CDN redirect (objects.githubusercontent.com)
        # causes cross-domain SSL failures in busybox wget.
        if wget -q --timeout="$MIHOMO_DOWNLOAD_TIMEOUT" --tries=1 -O "$output" "$url" 2>/dev/null ||
            wget -q --timeout="$MIHOMO_DOWNLOAD_TIMEOUT" --tries=1 --no-check-certificate \
                -O "$output" "$url" 2>/dev/null; then
            return 0
        fi
        if [ "$attempt" -lt "$MIHOMO_DOWNLOAD_RETRIES" ]; then
            delay=$((MIHOMO_RETRY_DELAY * attempt))
            log_warn "[mihomo] download attempt $attempt/$MIHOMO_DOWNLOAD_RETRIES failed, retrying in ${delay}s"
            rm -f "$output"
            sleep "$delay"
        fi
    done
    return 1
}

_mihomo_fetch_checksums() {
    version=$1
    arch=$2
    tmp="/tmp/submihomo_mihomo_checksums_$$.txt"
    api="https://api.github.com/repos/${MIHOMO_SOURCE_REPO}/releases/tags/$version"
    rm -f "$tmp"

    if ! wget -q --timeout="$MIHOMO_DOWNLOAD_TIMEOUT" -O "$tmp" "$api" 2>/dev/null; then
        log_debug "[mihomo] could not fetch release info from GitHub API (checksums may not be available)"
        rm -f "$tmp"
        return 1
    fi

    # Extract checksum from release notes/body (common format)
    filename="mihomo-linux-${arch}-${version}.gz"
    checksum=$(awk -v fn="$filename" '/"body":/ {
        body=1
        next
    }
    body && /.*"/ {
        body=0
    }
    body && $0 ~ fn {
        for(i=1; i<=NF; i++) {
            if($i ~ /^[a-f0-9]{64}$/) { print $i; exit }
        }
    }' "$tmp")

    rm -f "$tmp"
    [ -n "$checksum" ] && printf '%s' "$checksum" && return 0
    return 1
}

mihomo_install_version() {
    version=${1:-}
    _mihomo_space_check || return 1

    arch=$(mihomo_detect_arch) || return 1
    [ -n "$version" ] || version=$(mihomo_latest_version) || return 1

    filename="mihomo-linux-${arch}-${version}.gz"
    url="https://github.com/${MIHOMO_SOURCE_REPO}/releases/download/${version}/${filename}"
    gz="/tmp/submihomo_mihomo_${version}_$$.gz"
    candidate="${MIHOMO_BIN}.new.$$"
    temp_binary="${MIHOMO_BIN}.install.$$"

    log_info "[mihomo] installing $version for $arch"
    rm -f "$gz" "$candidate" "$temp_binary"

    # Download with retries and timeout
    if ! _mihomo_download_with_retries "$url" "$gz"; then
        log_error "[mihomo] download failed after $MIHOMO_DOWNLOAD_RETRIES attempts: $url"
        rm -f "$gz" "$candidate" "$temp_binary"
        return 1
    fi

    if [ ! -s "$gz" ]; then
        log_error "[mihomo] downloaded archive is empty or corrupted"
        rm -f "$gz" "$candidate" "$temp_binary"
        return 1
    fi

    # Validate gzip archive integrity
    if ! gzip -t "$gz" 2>/dev/null; then
        log_error "[mihomo] downloaded archive failed gzip validation"
        rm -f "$gz" "$candidate" "$temp_binary"
        return 1
    fi

    # Decompress
    if ! gzip -dc "$gz" >"$candidate" 2>/dev/null; then
        log_error "[mihomo] decompression failed"
        rm -f "$gz" "$candidate" "$temp_binary"
        return 1
    fi
    rm -f "$gz"

    # Verify executable works
    if ! _mihomo_verify_executable "$candidate" "$version"; then
        log_error "[mihomo] candidate binary verification failed"
        rm -f "$candidate" "$temp_binary"
        return 1
    fi

    # Try to verify SHA256 from GitHub release
    if checksum=$(_mihomo_fetch_checksums "$version" "$arch" 2>/dev/null || true); then
        if ! _mihomo_verify_sha256 "$candidate" "$checksum"; then
            log_error "[mihomo] SHA256 verification failed, installation aborted"
            rm -f "$candidate" "$temp_binary"
            return 1
        fi
    else
        log_warn "[mihomo] GitHub release checksums not available, skipping SHA256 verification (executable verification passed)"
    fi

    # Backup current binary if it exists and is executable
    if [ -x "$MIHOMO_BIN" ]; then
        if ! cp "$MIHOMO_BIN" "$MIHOMO_BACKUP_BIN" 2>/dev/null; then
            log_error "[mihomo] could not backup existing binary"
            rm -f "$candidate" "$temp_binary"
            return 1
        fi
        chmod 755 "$MIHOMO_BACKUP_BIN" 2>/dev/null || true
        log_debug "[mihomo] backed up current binary to $MIHOMO_BACKUP_BIN"
    fi

    # Ensure binary directory exists
    mkdir -p "$MIHOMO_BIN_DIR" 2>/dev/null || {
        log_error "[mihomo] could not create binary directory"
        [ -x "$MIHOMO_BACKUP_BIN" ] && cp "$MIHOMO_BACKUP_BIN" "$MIHOMO_BIN" 2>/dev/null || true
        rm -f "$candidate" "$temp_binary"
        return 1
    }

    # Atomic installation: stage to temp location first
    if ! mv "$candidate" "$temp_binary"; then
        log_error "[mihomo] could not stage binary for installation"
        [ -x "$MIHOMO_BACKUP_BIN" ] && cp "$MIHOMO_BACKUP_BIN" "$MIHOMO_BIN" 2>/dev/null || true
        rm -f "$candidate" "$temp_binary"
        return 1
    fi

    # Final atomic move to destination
    if ! mv "$temp_binary" "$MIHOMO_BIN"; then
        log_error "[mihomo] final installation failed, attempting automatic rollback"
        rm -f "$temp_binary"
        if [ -x "$MIHOMO_BACKUP_BIN" ]; then
            if cp "$MIHOMO_BACKUP_BIN" "$MIHOMO_BIN" 2>/dev/null; then
                chmod 755 "$MIHOMO_BIN" 2>/dev/null || true
                log_warn "[mihomo] automatic rollback completed, restored previous binary"
            else
                log_error "[mihomo] rollback failed — binary may be missing or corrupted"
                return 1
            fi
        else
            log_error "[mihomo] no backup available for rollback"
            return 1
        fi
        return 1
    fi
    chmod 755 "$MIHOMO_BIN" 2>/dev/null || true

    # Post-installation verification: ensure binary still works after move
    if ! "$MIHOMO_BIN" -v >/dev/null 2>&1; then
        log_error "[mihomo] installed binary failed post-installation verification, rolling back"
        if [ -x "$MIHOMO_BACKUP_BIN" ]; then
            if cp "$MIHOMO_BACKUP_BIN" "$MIHOMO_BIN" 2>/dev/null; then
                chmod 755 "$MIHOMO_BIN" 2>/dev/null || true
                log_warn "[mihomo] rollback completed, restored previous binary"
            else
                log_error "[mihomo] rollback failed — binary may be missing or corrupted"
            fi
        fi
        return 1
    fi

    # Compute SHA256 of installed binary for audit trail
    hash=$(sha256sum "$MIHOMO_BIN" 2>/dev/null | awk '{print $1}')
    [ -n "$hash" ] || hash="unknown"

    if ! _mihomo_write_metadata "$version" "$arch" "$url" "$hash"; then
        log_warn "[mihomo] installed binary but could not write metadata file"
    fi

    log_info "[mihomo] successfully installed $version for $arch (SHA256: $(printf '%s' "$hash" | cut -c1-16)...)"
    return 0
}

mihomo_ensure_installed() {
    if [ -x "$MIHOMO_BIN" ] && "$MIHOMO_BIN" -v >/dev/null 2>&1; then
        return 0
    fi
    log_warn "[mihomo] managed binary missing or not executable, installing"
    mihomo_install_version
}

mihomo_update() {
    latest=$(mihomo_latest_version) || return 1
    current=$(mihomo_installed_version 2>/dev/null || true)
    if [ -x "$MIHOMO_BIN" ] && [ "$current" = "$latest" ]; then
        log_info "[mihomo] already up to date ($latest)"
        return 0
    fi
    log_info "[mihomo] updating from ${current:-unknown} to $latest"
    mihomo_install_version "$latest"
}

mihomo_rollback() {
    [ -x "$MIHOMO_BACKUP_BIN" ] || {
        log_error "[mihomo] no backup binary available for rollback"
        return 1
    }
    if ! cp "$MIHOMO_BACKUP_BIN" "$MIHOMO_BIN" 2>/dev/null; then
        log_error "[mihomo] rollback copy failed"
        return 1
    fi
    chmod 755 "$MIHOMO_BIN" 2>/dev/null || true
    if ! "$MIHOMO_BIN" -v >/dev/null 2>&1; then
        log_error "[mihomo] rollback binary failed verification"
        return 1
    fi
    log_info "[mihomo] rollback restored previous binary version"
    return 0
}

case "${1:-}" in
install) mihomo_install_version "${2:-}" ;;
ensure) mihomo_ensure_installed ;;
update) mihomo_update ;;
rollback) mihomo_rollback ;;
arch) mihomo_detect_arch ;;
latest) mihomo_latest_version ;;
esac
