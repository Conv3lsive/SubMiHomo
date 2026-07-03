# SubMiHomo Pass/Fail Matrix

Legend:

- **PASS** — executed and passing in this sandbox
- **PEND** — automation provided, pending execution on capable host/device
- **N/A** — not applicable to this test layer
- **FAIL** — failing and blocking

## Static analysis (Layer 1)

| Check | Result | Notes |
|-------|--------|-------|
| shellcheck warning gate | PASS | No warnings in modules, init.d, install scripts |
| shfmt POSIX parse | PASS | All shell files parse |
| Lua syntax (rpcd) | PASS | `luac -p` clean |
| Lua 5.1 compatibility | PASS | No 5.2+ constructs |
| JSON validation | PASS | menu.d + ACL files valid |
| JS syntax (LuCI views) | PASS | All view files pass `node --check` |
| YAML render check | PASS | Template + fixtures render as YAML |
| BusyBox-ash hazard scan | PASS | No `[[`, `echo -e`, `readarray`, `==` hazards |

## Unit tests (Layer 2)

| Area | Result | Notes |
|------|--------|-------|
| Core constants / UCI / logging / locks | PASS | 35 tests |
| Config extraction & generation | PASS | 27 tests |
| DNS setup/teardown | PASS | 11 tests |
| Firewall / CIDR validation | PASS | 20 tests |
| Routing commands | PASS | 15 tests |
| Subscription validation / backup / restore | PASS | 21 tests |
| Dashboard download / version | PASS | 8 tests |
| rpcd validate() input gate | PASS | 10 tests |
| Security (permissions, binding, redaction, ACL) | PASS | 7 tests |
| BusyBox whitespace regression | PASS | 16 tests |
| Subscription compatibility matrix | PASS | 24 tests |

## Build & packaging (Layer 3)

| Check | Result | Notes |
|-------|--------|-------|
| Makefile syntax & structure | PASS | `validate_makefile.sh` |
| `submihomo` APK build | PEND | `sdk_build.sh` ready |
| `luci-app-submihomo` APK build | PEND | `sdk_build.sh` ready |
| Dummy `mihomo` dependency build | PEND | `mihomo-dummy` package ready |
| Conffiles / permissions / hooks | PASS | Verified statically |

## Docker integration (Layer 4)

| Check | Result | Notes |
|-------|--------|-------|
| x86_64 APK build | PEND | Part of `docker_lifecycle.sh` |
| OpenWrt rootfs boot | PEND | Requires Docker |
| APK install / postinst | PEND | Requires Docker |
| UCI configuration | PEND | Requires Docker |
| procd service start/stop | PEND | Requires Docker |
| rpcd status / set_config | PEND | Requires Docker |
| Uninstall cleanup | PEND | Requires Docker |
| No orphan files/cron/processes | PEND | Requires Docker |

## QEMU integration (Layer 5)

| Check | Result | Notes |
|-------|--------|-------|
| OpenWrt image boot (LAN+WAN) | PEND | Requires QEMU |
| APK install in VM | PEND | Requires QEMU |
| Service start with real procd | PEND | Requires QEMU |
| TPROXY nftables table present | PEND | Requires QEMU |
| Policy routing rule + local route | PEND | Requires QEMU |
| DNS hijack config present | PEND | Requires QEMU |
| rpcd status responds | PEND | Requires QEMU |
| Failure recovery (procd respawn) | PEND | Requires QEMU |
| Reboot survival | PEND | Requires QEMU |

## Security & performance (Layer 6)

| Check | Result | Notes |
|-------|--------|-------|
| Config file permissions 600 | PASS | `test_security.sh` |
| Subscription file permissions 600 | PASS | `test_security.sh` |
| Controller default loopback | PASS | `test_config_extraction.sh` + `test_security.sh` |
| Secret redaction in rpcd | PASS | `test_security.sh` |
| ACL JSON valid | PASS | `test_security.sh` |
| Embedded startup time | PEND | `embedded_perf.sh` |
| Embedded memory footprint | PEND | `embedded_perf.sh` |
| Embedded fork/FD count | PEND | `embedded_perf.sh` |
| Install/upgrade/reinstall/sysupgrade | PEND | Scripts exist; device test pending |
| Removal cleanup | PEND | `uninstall.sh` + Docker/QEMU harness pending |
