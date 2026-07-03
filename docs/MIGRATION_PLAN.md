# Migration Plan

## Goal

Make SubMiHomo self-contained: a user installs SubMiHomo, and SubMiHomo automatically obtains, verifies, installs, updates, and rolls back the correct Mihomo binary for the current OpenWrt architecture.

## Adopted Architectural Improvements

1. Remove the hard dependency on an external `mihomo` package.
2. Add a private managed binary path: `/usr/libexec/submihomo/mihomo`.
3. Add persistent Mihomo metadata under `/etc/submihomo/mihomo`.
4. Add one backend binary manager module used by init, CLI, installer, updater, config validation, subscription validation, and diagnostics.
5. Detect the upstream MetaCubeX asset architecture at runtime from OpenWrt/APK architecture, `uname -m`, endianness, and MIPS FPU information.
6. Download Mihomo from MetaCubeX releases using the detected architecture and latest release tag.
7. Verify downloads by HTTPS transport, non-empty asset, gzip decompression, executable launch test, version sanity check, and local hash recording.
8. Install atomically with a retained backup of the previous binary.
9. Add explicit rollback for the managed binary.
10. Keep SubMiHomo's UCI-generated config, one-service procd orchestration, and narrow rpcd/LuCI control surface.

## Non-Adopted mixomo-openwrt Designs

1. Do not generate package-owned files from the installer.
2. Do not install Mihomo at `/usr/bin/mihomo`.
3. Do not expose broad LuCI shell execution for arbitrary update steps.
4. Do not switch to user-edited raw Mihomo config as the primary configuration model.
5. Do not hardcode a single update architecture in LuCI.

## Implementation Steps

1. Add `files/usr/lib/submihomo/mihomo.sh`.
2. Add Mihomo path and metadata constants to `core.sh`.
3. Update `Makefile` dependencies and installed directories.
4. Update init startup to call `mihomo_ensure_installed` before config generation.
5. Replace direct `mihomo` calls in config and subscription validation with the managed binary path.
6. Update CLI with `core-install`, `core-update`, and `core-rollback`.
7. Update diagnostics and version reporting to show the managed binary.
8. Update installer to install SubMiHomo packages and then install the Mihomo core automatically.
9. Update updater to upgrade packages and then update the Mihomo core.
10. Update uninstall to remove downloaded Mihomo core files.
11. Add tests for architecture mapping and managed binary command usage.
12. Document the comparison and migration decisions.

## Rollback Strategy

1. Every binary replacement writes the candidate to a temporary file first.
2. The candidate must be executable and pass `-v`.
3. The current binary is copied to `/usr/libexec/submihomo/mihomo.backup` before replacement.
4. The candidate is moved into place only after validation.
5. If replacement or metadata writing fails, the backup is restored.
6. `submihomo-ctl core-rollback` restores the backup explicitly.

## Operational Behavior After Migration

1. Fresh install: APK installs SubMiHomo, then `submihomo-ctl core-install` downloads and installs Mihomo.
2. Service start: if the managed binary is missing or broken, startup attempts to install it before generating config.
3. Package update: APK upgrades SubMiHomo, then `submihomo-ctl core-update` updates Mihomo if a newer upstream release exists.
4. Running service update: the updater records whether SubMiHomo was running, updates package/core assets, and restarts only if it was running before.
5. Failure: existing binary remains active or is restored from backup; configuration and subscriptions are not removed.
