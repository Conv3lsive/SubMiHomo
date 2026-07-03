# SubMiHomo Test Results

## Executive summary

| Layer | Scope | Status | Evidence |
|-------|-------|--------|----------|
| 1 | Static analysis | **PASS** (executed) | `tests/static/run_static.sh` |
| 2 | Unit tests | **PASS** (executed) | `tests/unit/run_all.sh` — 194 tests |
| 3 | OpenWrt SDK build | Makefile static validation **PASS** (executed); full SDK build **pending** | `tests/integration/validate_makefile.sh`, `tests/integration/sdk_build.sh` |
| 4 | Docker lifecycle | **Pending execution** | `tests/integration/docker_lifecycle.sh`, `docs/DOCKER_SETUP.md` |
| 5 | QEMU lifecycle | **Pending execution** | `tests/integration/qemu_lifecycle.sh`, `docs/QEMU_SETUP.md` |
| 6 | Embedded perf/security | Partially covered by unit tests; on-device scripts **pending** | `tests/integration/embedded_perf.sh` |

## Layer 1 — Static analysis

Command executed:

```sh
sh tests/static/run_static.sh
```

Result: `LAYER 1 STATIC ANALYSIS: PASS`

Gates passed:

- shellcheck (warning severity) on all shell modules, init script, and install scripts
- shfmt POSIX parse
- Lua syntax and Lua 5.1 compatibility for the rpcd plugin
- JSON validation for menu.d and ACL files
- JS syntax check for all LuCI view files
- YAML render check for template and fixtures
- BusyBox-ash hazard scan (no `[[`, `echo -e`, `readarray`, `==` in single-bracket tests)

## Layer 2 — Unit tests

Command executed:

```sh
sh tests/unit/run_all.sh
```

Result: `OVERALL RESULT: 194 passed, 0 failed`

Test files:

| File | Tests | Focus |
|------|-------|-------|
| `test_busybox_whitespace.sh` | 16 | Regression for BusyBox `\s` / `grep -A` incompatibilities |
| `test_config_extraction.sh` | 27 | YAML block extraction, config generation, controller binding |
| `test_core.sh` | 35 | Constants, UCI helpers, logging, locks, migrations, validation |
| `test_dashboard.sh` | 8 | GitHub JSON parsing, download, version, failure paths |
| `test_dns.sh` | 11 | dnsmasq forwarding config and teardown |
| `test_firewall_validation.sh` | 20 | CIDR validation and nftables invocation |
| `test_routing_commands.sh` | 15 | ip rule/route setup/teardown and idempotency |
| `test_rpcd_validate.sh` | 10 | rpcd `validate()` input gate |
| `test_security.sh` | 7 | File permissions, controller binding, secret redaction, ACL |
| `test_subscription_edge_cases.sh` | 24 | Unicode, comments/anchors, missing groups/rules, large fixture |
| `test_subscription_validation.sh` | 21 | Download, validate, backup, apply, restore |

## Layer 3 — OpenWrt SDK build

Static Makefile validation executed:

```sh
sh tests/integration/validate_makefile.sh
```

Result: `Makefile static validation: PASS`

Checks performed:

- `Package/submihomo` and `Package/luci-app-submihomo` defined
- Required metadata fields present
- `BuildPackage` calls present
- Dependency declarations correct (`submihomo` → `+mihomo`, `luci-app-submihomo` → `+submihomo`)
- All install source files exist
- Conffiles exist
- `postinst` and `prerm` hooks present

Full SDK build automation is provided in `tests/integration/sdk_build.sh` and is **pending execution** on a host with the OpenWrt SDK.

## Layer 4 — Docker lifecycle

Automation provided in `tests/integration/docker_lifecycle.sh`. Expected to verify:

- x86_64 APK build
- OpenWrt rootfs container boot
- APK install/postinst
- UCI configuration
- procd service start/stop
- rpcd `status` and `set_config`
- Uninstall cleanup

Status: **pending execution** (Docker not available in the validation sandbox).

## Layer 5 — QEMU lifecycle

Automation provided in `tests/integration/qemu_lifecycle.sh`. Expected to verify:

- x86_64 OpenWrt image boot with LAN/WAN virtio-net interfaces
- APK install and service start
- TPROXY nftables table, policy routing, DNS hijack
- rpcd responsiveness
- Failure recovery (procd respawn)
- Reboot survival

Status: **pending execution** (QEMU not available in the validation sandbox).

## Layer 6 — Embedded performance and security

Security coverage is included in Layer 2 via `test_security.sh`:

- Generated `config.yaml` mode `600`
- Subscription `current.yaml` mode `600`
- Controller defaults to `127.0.0.1` when LAN access disabled
- rpcd `get_config` redacts `external_controller_secret`
- ACL JSON is valid

On-device performance measurements are provided by `tests/integration/embedded_perf.sh` and are **pending execution** on a real OpenWrt device.

## Regression tests added

- `test_busybox_whitespace.sh`: ensures no literal `\s` remains in production shell code and that POSIX `[[:space:]]` patterns work under `dash`.
- `test_dashboard.sh`: covers GitHub JSON asset extraction without `grep -A` and dashboard version/failure paths.
- `test_rpcd_validate.sh`: exercises the rpcd `validate()` input gate with invalid and valid payloads.
- `test_subscription_edge_cases.sh`: compatibility matrix for Unicode, comments/anchors, missing sections, and 150-proxy fixture.
- `test_security.sh`: permissions, controller binding, secret redaction, ACL.
