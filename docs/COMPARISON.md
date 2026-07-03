# SubMiHomo vs mixomo-openwrt Architectural Comparison

Reference studied: https://github.com/Internet-Helper/mixomo-openwrt

This comparison is architectural only. No source code from mixomo-openwrt is copied.

## Package Layout

1. SubMiHomo currently works as a normal OpenWrt package tree: `Makefile`, `files/etc/init.d`, shell modules in `files/usr/lib/submihomo`, rpcd Lua, LuCI JS, UCI defaults, installer scripts, and tests.
2. mixomo-openwrt is installer-script driven. Its repository contains standalone install/delete scripts that write service files, LuCI files, configs, binaries, and package dependencies directly on the router.
3. SubMiHomo is technically better.
4. Package layout is easier to build, audit, test, upgrade, uninstall, and integrate with OpenWrt feeds. The mixomo approach is convenient for bootstrap but makes ownership and upgrades less predictable.
5. SubMiHomo should not adopt script-generated installed files. It should keep package-owned files and use installer scripts only for bootstrap and runtime assets that cannot be shipped architecture-independently.

## APK Packaging

1. SubMiHomo targets APK and packages the service and LuCI UI separately. It currently depends on an external `mihomo` package.
2. mixomo-openwrt supports both APK and opkg through a small package-manager abstraction, but does not publish a conventional OpenWrt package for its own files.
3. SubMiHomo is better for OpenWrt 25+, but its external Mihomo dependency is worse.
4. APK-owned files give clean lifecycle semantics; relying on an external Mihomo package weakens self-containment and creates availability issues across architectures.
5. Adopt the self-contained Mihomo lifecycle, not the script-only packaging style.

## Mihomo Installation

1. SubMiHomo currently expects `/usr/bin/mihomo` to already exist via `+mihomo`; init, config validation, diagnostics, and version reporting call it directly.
2. mixomo-openwrt downloads the latest MetaCubeX Mihomo release, maps the router CPU to the upstream asset name, decompresses the `.gz`, installs the executable, records the architecture, and checks that the binary runs.
3. mixomo-openwrt is better for Mihomo installation.
4. It removes the manual install step and does not depend on a package feed having the right Mihomo build.
5. Adopt the design, but install into a SubMiHomo-owned private path instead of `/usr/bin/mihomo`.

## Mihomo Updates

1. SubMiHomo currently updates only its APK packages and subscription/dashboard data. Mihomo updates are delegated to the external package.
2. mixomo-openwrt checks the latest upstream release, downloads a replacement binary, backs up the current binary, tests the new binary, installs it, restarts Mihomo, and attempts rollback on failure. Its LuCI update path hardcodes one architecture, which is a flaw.
3. A corrected version of mixomo-openwrt's updater is better.
4. Binary update needs to be explicit, architecture-aware, atomic, and rollback-capable.
5. Adopt the updater architecture centrally in a shell module and expose it through CLI/installer/updater. Do not adopt architecture-specific LuCI shell command construction.

## Release Management

1. SubMiHomo has `PKG_VERSION` and `PKG_RELEASE` in the package Makefile, but no first-class Mihomo version metadata.
2. mixomo-openwrt carries an installer script version and derives the Mihomo version from upstream's latest GitHub release.
3. Split release management is better: SubMiHomo package version should remain separate from the managed Mihomo core version.
4. The wrapper and core have independent release cadences.
5. Adopt persistent Mihomo metadata: installed version, architecture, source URL, and local hash.

## Architecture Detection

1. SubMiHomo currently reads `/etc/apk/arch` only in the installer and warns unless it is `mipsel_24kc`; package metadata is `PKGARCH:=all`.
2. mixomo-openwrt maps `uname -m`, endian detection, and MIPS FPU detection to MetaCubeX asset names such as `arm64`, `amd64`, `mipsle-softfloat`, and `riscv64`.
3. mixomo-openwrt is better, with one exception: its LuCI update path bypasses this logic.
4. APK architecture names do not match upstream Mihomo asset names; runtime mapping is required.
5. Adopt architecture mapping in one backend function and use it for install, update, diagnostics, and metadata.

## procd Integration

1. SubMiHomo uses one `submihomo` procd service that generates config, sets routing/DNS/firewall state, then starts Mihomo with respawn and a pidfile.
2. mixomo-openwrt writes a separate `mihomo` init service that runs Mihomo only; other components have their own lifecycles.
3. SubMiHomo is better for its design.
4. SubMiHomo owns transparent proxy orchestration, so a single service can sequence prerequisites and teardown correctly.
5. Keep one service, but make startup ensure the managed Mihomo binary exists before config validation or process launch.

## Runtime Directories

1. SubMiHomo uses `/var/run/submihomo` for generated config and locks, `/etc/submihomo` for persistent config/subscriptions, and `/usr/share/submihomo/dashboard` for dashboard assets.
2. mixomo-openwrt uses `/etc/mihomo` for config and data, `/tmp` for downloads/backups, and `/usr/bin/mihomo` for the binary.
3. SubMiHomo is better, with one missing area.
4. Separating persistent user state, runtime generated state, and package assets is cleaner. The missing piece is a private binary/state location for Mihomo.
5. Add `/usr/libexec/submihomo` for the managed binary and `/etc/submihomo/mihomo` for version metadata.

## Configuration Generation

1. SubMiHomo generates Mihomo config from UCI plus subscription data, validates the generated config, and keeps secrets out of LuCI responses.
2. mixomo-openwrt creates or preserves a direct `/etc/mihomo/config.yaml` edited by the user.
3. SubMiHomo is better for its product goal.
4. UCI-driven generation provides repeatability, safer defaults, and a simpler LuCI workflow.
5. Do not adopt direct config editing. Only update validation to use the managed binary.

## Dashboard Management

1. SubMiHomo downloads Zashboard from a configurable GitHub release and serves it through Mihomo's `external-ui`.
2. mixomo-openwrt creates dashboard-capable config and downloads LuCI editor assets; dashboard URLs are embedded in the generated config comments.
3. SubMiHomo is better for dashboard management.
4. The dashboard is treated as an updateable asset, not mixed with raw config editing.
5. Keep the current dashboard model, but use atomic extract/replace in a later hardening pass.

## Startup Sequence

1. SubMiHomo startup checks UCI enabled state, runs migrations, requires subscription data, generates config, sets routing, DNS, firewall, starts dashboard download in the background, schedules subscription cron, then starts Mihomo.
2. mixomo-openwrt starts Mihomo if the binary and config exist; most setup happens during installation.
3. SubMiHomo is better for orchestration, but incomplete without binary ensure.
4. Runtime orchestration should happen at service start because OpenWrt state may be reset or partially changed.
5. Add `mihomo_ensure_installed` before config generation.

## Shutdown Sequence

1. SubMiHomo stops firewall, DNS, and routing state in reverse-ish order through its stop handler.
2. mixomo-openwrt's Mihomo service stop is procd-managed; its delete script stops and disables related services before removing files.
3. SubMiHomo is better for normal service shutdown.
4. It owns all network side effects and tears them down explicitly.
5. Keep this model. Add binary rollback/update operations that preserve the previous running state.

## Permissions

1. SubMiHomo writes generated config as `0600`, subscription state as private files, and keeps the controller on localhost unless LAN access is enabled.
2. mixomo-openwrt installs executable binaries as root-owned executable files and grants broad LuCI ACL file/exec access for shell-managed updates.
3. SubMiHomo is better.
4. Broad LuCI shell execution increases blast radius. Backend methods should perform constrained operations.
5. Keep narrow rpcd methods. Do binary management in backend shell modules, not arbitrary LuCI shell snippets.

## Installer

1. SubMiHomo installer configures an APK repo, installs SubMiHomo packages, preserves `/etc/submihomo`, and enables the service. It does not install Mihomo itself.
2. mixomo-openwrt installer installs dependencies, checks space, downloads Mihomo, creates service/config/UI files, installs tunnel/routing components, and restarts UI services.
3. mixomo-openwrt is better for end-user bootstrap completeness; SubMiHomo is better for package ownership.
4. Users should not be responsible for installing the core manually.
5. Update SubMiHomo installer to install packages and then invoke the packaged Mihomo manager.

## Updater

1. SubMiHomo updater only upgrades APK packages and restarts the service if it was running.
2. mixomo-openwrt re-running the installer updates Mihomo and related components while preserving config; its LuCI update has backup/rollback but flawed architecture handling.
3. A SubMiHomo-owned updater is better.
4. Package updates and core binary updates are different lifecycles and should both be handled.
5. Extend `install/update.sh` to upgrade packages, update the managed Mihomo binary, and restart only if previously running.

## Rollback

1. SubMiHomo has subscription rollback only.
2. mixomo-openwrt backs up the Mihomo binary before replacement and restores it if the update fails.
3. mixomo-openwrt is better for binary rollback.
4. Core updates can fail after download, extraction, execution test, or service restart; retaining the previous executable is cheap and important.
5. Adopt binary backup and explicit rollback command.

## OpenWrt Best Practices

1. SubMiHomo follows OpenWrt package layout, UCI config, procd, rpcd ACLs, LuCI JS, conffiles, and package scripts.
2. mixomo-openwrt optimizes for one-command install/update and broad OpenWrt version support, but writes many package-like files directly from scripts.
3. SubMiHomo is better as an OpenWrt package; mixomo-openwrt is better as a bootstrapper.
4. Package-owned files, UCI/procd integration, and narrow ACLs are easier to maintain and safer.
5. Adopt only bootstrap and binary lifecycle ideas. Preserve SubMiHomo's package-first design.
