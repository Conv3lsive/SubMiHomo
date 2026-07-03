# SubMiHomo QA Report

## Package under test

- **Name:** SubMiHomo
- **Version:** 1.0.0-rc1 candidate
- **Repository:** Conv3lsive/SubMiHomo
- **Target:** OpenWrt 25+ (APK), primary arch `mipsel_24kc`
- **Components:**
  - `submihomo` — service wrapper, config generator, TPROXY/routing/firewall/DNS integration
  - `luci-app-submihomo` — LuCI frontend and rpcd ACLs
  - `mihomo` — external proxy core dependency (dummy provided for CI)

## Validation scope

This release-validation effort followed a 6-layer pipeline:

1. Static analysis
2. Unit tests
3. OpenWrt SDK package build
4. Docker integration lifecycle
5. QEMU integration lifecycle
6. Embedded performance, security, install/upgrade/removal, compatibility matrix

## Critical bug fixed

A BusyBox incompatibility was discovered in production shell code:

- `\s` in `grep`/`sed`/`awk` patterns is treated as the literal character `s` by BusyBox grep/sed, breaking proxy/group extraction, proxy counting, and rule filtering on real OpenWrt hardware.
- `grep -A3` is unsupported by BusyBox grep, breaking dashboard asset URL extraction.

Fix applied:

- Replaced all `\s` with POSIX `[[:space:]]` (adding `-E` where needed).
- Rewrote dashboard GitHub JSON parsing in `awk` without `grep -A`.
- Added `tests/unit/test_busybox_whitespace.sh` regression test, including a `dash` POSIX-shell check.

## Test results

| Layer | Status |
|-------|--------|
| 1 Static analysis | PASS |
| 2 Unit tests | PASS (194/194) |
| 3 SDK build | Makefile static validation PASS; full SDK build pending |
| 4 Docker lifecycle | Automation provided, pending execution |
| 5 QEMU lifecycle | Automation provided, pending execution |
| 6 Embedded perf/security | Security covered by unit tests; on-device perf pending |

## Code quality metrics

- Module line counts within budget:
  - `core.sh`: 142 lines (≤150)
  - `config.sh`: 200 lines (≤200)
  - `subscription.sh`: 143 lines (≤200)
  - `dashboard.sh`: 90 lines (≤150)
- No shellcheck warnings.
- No BusyBox-ash hazards.
- No Lua 5.2+ constructs in the rpcd plugin.

## Security posture

- Generated runtime config is written with mode `600`.
- Subscription `current.yaml` is applied with mode `600`.
- External controller defaults to `127.0.0.1` unless `allow_lan_access=1`.
- rpcd `get_config` redacts `external_controller_secret` as `REDACTED`.
- rpcd `set_config` rejects `REDACTED` as a secret value, preventing accidental overwrite.
- ACL file restricts write access to the `submihomo` scope.

## Compatibility matrix

Verified via unit tests against fixtures with:

- Unicode proxy and group names (CJK, Cyrillic, emoji)
- YAML comments and anchors/aliases
- Subscriptions with no `proxy-groups`
- Subscriptions with no `rules`
- Large subscriptions (150 proxies)

## Known limitations

- Layers 3–5 and on-device performance scripts could not be executed in the macOS sandbox; they are provided as reproducible automation.
- Docker/QEMU harnesses use a dummy `mihomo` binary for lifecycle testing; real proxy forwarding is not validated.
- IPv6 transparent proxy is not implemented.
- Dashboard download depends on GitHub API availability.

## RC1 determination

**Recommendation: RC1 candidate, conditional on Layers 3–5 passing.**

All executable validation that can be performed in this environment passes. The critical BusyBox compatibility bug has been fixed and regression-tested. The package Makefile is structurally correct, and full integration automation is in place. Because the actual SDK build, Docker lifecycle, and QEMU lifecycle could not be executed here, RC1 should be declared only after those stages complete successfully on a capable Linux host or CI runner.
