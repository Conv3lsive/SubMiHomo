# SubMiHomo — Granular Task Breakdown

## 0. Conventions Used in This Document

This document decomposes the 16 phases in `docs/ROADMAP.md` into 98 individually implementable tasks, `T-001` through `T-098`, organized in strict phase order. Every task is scoped so a single engineer can pick it up, implement it, and validate it without needing to ask clarifying questions about file locations, function names, or expected behavior — those are all fixed in advance by cross-referencing the existing architecture documents (`docs/ARCHITECTURE.md`, `docs/COMPONENTS.md`, `docs/FILESYSTEM.md`, `docs/UCI.md`, `docs/NETWORK.md`, `docs/SUBSCRIPTIONS.md`, `docs/DASHBOARD.md`, `docs/LUCI.md`, `docs/BOOT.md`, `docs/LOGGING.md`, `docs/SECURITY.md`).

### 0.1 Task Fields

Every task entry below carries the following fields:

- **Task ID** — `T-XXX`, three digits, monotonically increasing, never reused.
- **Phase** — the roadmap phase (1–16) this task belongs to.
- **Title** — short descriptive summary.
- **Purpose** — why the task exists, in terms of the system behavior it enables.
- **Files affected** — exact repository-relative paths created or modified. All paths are given relative to the `SubMiHomo/` project root.
- **Dependencies** — other task IDs that must be complete first. `None` means the task can start as soon as its phase's entry criteria (see `docs/ROADMAP.md` §2) are met.
- **Acceptance criteria** — specific, testable conditions. Every criterion is phrased so it can be checked with a concrete command or observation, not a subjective judgment.
- **Expected output** — the concrete artifact or capability that exists once the task is done.
- **Estimated complexity** — `Simple` (< 1 hour), `Medium` (1–4 hours), or `Complex` (4–8 hours).

### 0.2 Complexity Legend

| Rating | Duration | Typical characteristics |
|---|---|---|
| Simple | < 1 hour | Boilerplate, configuration, single well-understood function, no new integration surface |
| Medium | 1–4 hours | New integration surface, moderate error handling, some cross-file coordination |
| Complex | 4–8 hours | Fragile parsing logic, security-sensitive kernel state, multi-step orchestration, or wide blast radius on failure |

### 0.3 Module Size Budgets (Do Not Exceed)

Several tasks contribute lines to the same file across multiple phases. Every task below that touches one of these files states the running budget explicitly so no single task inadvertently blows the total. Exceeding a budget is a signal to split responsibilities into a new module rather than keep appending.

| Module | Max lines | Contributing tasks |
|---|---|---|
| `files/usr/lib/submihomo/core.sh` | 150 | T-009, T-010, T-019, T-020 |
| `files/usr/lib/submihomo/config.sh` | 200 | T-044, T-045, T-046, T-047, T-048, T-049 |
| `files/usr/lib/submihomo/routing.sh` | 100 | T-056, T-057 |
| `files/usr/lib/submihomo/dns.sh` | 80 | T-052, T-053 |
| `files/usr/lib/submihomo/firewall.sh` | 150 | T-060, T-061, T-062, T-063 |
| `files/usr/lib/submihomo/subscription.sh` | 200 | T-035, T-036, T-037, T-038, T-039 |
| `files/usr/lib/submihomo/dashboard.sh` | 100 | T-087, T-088, T-089 (init.d call site only, not this file) |
| `files/etc/init.d/submihomo` | 120 | T-012, T-014, T-015, T-016, T-017, T-089 |
| `files/usr/bin/submihomo-ctl` | 150 | T-077, T-080 |
| `files/usr/lib/rpcd/submihomo` | 400 | T-023 through T-033 (11 tasks) |
| Each LuCI JS view (`overview.js`, `subscription.js`, `settings.js`, `proxies.js`, `logs.js`) | 300 each | T-067–T-071, plus T-076/T-090 amendments |

`files/etc/init.d/submihomo` deserves special attention: six separate tasks across three phases (3, 4, 15) contribute to a file with only a 120-line ceiling. Each task must add the minimum code necessary and delegate real logic to the shell modules under `files/usr/lib/submihomo/` rather than inlining it — the init script is an orchestrator, never an implementer (see `docs/COMPONENTS.md` §3.8.9).

### 0.4 RPC-from-Lua Execution Policy

The architectural brief forbids "direct shell execution from Lua" in favor of ubus service calls. This is applied as follows throughout Phase 6 and Phase 13's RPC tasks:

- **`start` / `stop` / `restart`** call the ubus `service` object (`ubus call service start '{"name":"submihomo"}'` and its `stop`/`restart` equivalents) — a genuine ubus-native call, never `io.popen()` against `/etc/init.d/submihomo`.
- **`get_logs`** calls the ubus `log` object (`ubus call log read '{"lines": N}'`), filtering client-side (in the plugin) for the `submihomo` and `submihomo.mihomo` syslog tags — no shell execution at all.
- **`get_proxies` / `test_connection`** call Mihomo's local REST API directly over HTTP (`127.0.0.1:<external_controller_port>`) using OpenWrt's built-in `nixio` Lua sockets — an HTTP call, not a shell execution, and strictly more efficient than shelling out to `curl`/`wget`.
- **`update_subscription` / `download_dashboard`** are the only two methods with no ubus-native equivalent, because their logic (subscription download/validation/apply, dashboard archive fetch/extract) is implemented in POSIX shell modules with no corresponding ubus object. These two methods are documented, reviewed exceptions: each invokes exactly one **fixed, zero-argument, non-interpolated** script entry point (no RPC caller input is ever concatenated into a shell command string). This preserves the actual security intent of the forbidden pattern — preventing command injection via dynamically-built shell strings — without pretending a non-existent ubus bridge exists for shell-module business logic.
- **`get_config` / `set_config`** use the native `luci.model.uci` Lua library, never shelling out to the `uci` binary.

### 0.5 Validation Tooling Referenced Throughout

- **`shellcheck --shell=sh`** (or equivalent) — run against every POSIX shell file on every task that creates or modifies one.
- **`ubus-cli` (`ubus call ...`)** — used to exercise rpcd methods directly, bypassing the browser, for fast iteration and CI.
- **A local HTTP fixture server** — used by subscription/dashboard tests to serve controlled valid/invalid/malformed responses without depending on real third-party endpoints.
- **A headless browser harness (e.g., Playwright)** — used for LuCI page-load and form-submission verification.
- **`mihomo -t -f <file>`** — the single source of truth for "is this a valid Mihomo config," used throughout Phases 7, 8, and 13.

---

## 1. Phase 1 — Repository Skeleton

### T-001 — Create Repository Directory Structure

- **Phase:** 1 — Repository skeleton
- **Purpose:** Establish every directory referenced by `docs/FILESYSTEM.md` §2 before any file-creation task begins, so later tasks never need to first check "does this directory exist."
- **Files affected:** `SubMiHomo/docs/` (already present), `SubMiHomo/files/etc/config/`, `SubMiHomo/files/etc/init.d/`, `SubMiHomo/files/etc/submihomo/templates/`, `SubMiHomo/files/usr/lib/submihomo/`, `SubMiHomo/files/usr/lib/rpcd/`, `SubMiHomo/files/usr/bin/`, `SubMiHomo/files/usr/share/luci/menu.d/`, `SubMiHomo/files/usr/share/rpcd/acl.d/`, `SubMiHomo/files/htdocs/luci-static/resources/view/submihomo/`, `SubMiHomo/install/`
- **Dependencies:** None
- **Acceptance criteria:**
  1. Every directory listed in `docs/FILESYSTEM.md` §2.1–§2.8 exists in the repository (verified with a `find`/`test -d` script).
  2. `git status` shows the new directories tracked (via placeholder `.gitkeep` files where a directory would otherwise be empty).
  3. No directory outside the `files/`, `docs/`, `install/` trees, or repository root is created (no stray top-level clutter).
- **Expected output:** A complete, empty (or placeholder-only) directory skeleton matching the documented repository layout exactly.
- **Estimated complexity:** Simple

### T-002 — Create Root Makefile Skeleton

- **Phase:** 1 — Repository skeleton
- **Purpose:** Provide the minimal, syntactically valid OpenWrt package `Makefile` shell that Phase 2 will flesh out with real package definitions.
- **Files affected:** `SubMiHomo/Makefile`
- **Dependencies:** T-001
- **Acceptance criteria:**
  1. The file includes the standard OpenWrt package Makefile header (`include $(TOPDIR)/rules.mk`, `PKG_NAME`, `PKG_VERSION`, `PKG_RELEASE`, `include $(INCLUDE_DIR)/package.mk`).
  2. The file parses without error under `make -n` from an OpenWrt SDK checkout (empty `define Package/...` stanzas are acceptable at this stage).
  3. No package logic (install rules, dependencies) is implemented yet — that is explicitly deferred to Phase 2.
- **Expected output:** A `Makefile` that `make menuconfig`/`make package/submihomo/compile` can at least parse, even though it builds nothing meaningful yet.
- **Estimated complexity:** Simple

### T-003 — Create README.md

- **Phase:** 1 — Repository skeleton
- **Purpose:** Give end users and contributors a single entry point describing what SubMiHomo is, the one-command install path, and where to find deeper documentation.
- **Files affected:** `SubMiHomo/README.md`
- **Dependencies:** T-001
- **Acceptance criteria:**
  1. Contains a one-paragraph project description consistent with `docs/ARCHITECTURE.md` §1 (scope and target platform).
  2. Contains the exact one-command install invocation that Phase 14's `install/install.sh` will implement (even if the script does not exist yet — this is the target contract, written first).
  3. Links to `docs/` for architecture detail rather than duplicating it.
  4. Does not describe any implementation detail more specific than "paste your subscription URL into LuCI and click Apply" — no port numbers, file paths, or shell function names (those live in `docs/`).
- **Expected output:** A renderable `README.md` suitable as the repository's landing page.
- **Estimated complexity:** Simple

### T-004 — Create .gitignore and Git Setup Files

- **Phase:** 1 — Repository skeleton
- **Purpose:** Prevent build artifacts, OpenWrt SDK output, and editor/OS cruft from being committed.
- **Files affected:** `SubMiHomo/.gitignore`, initial `git init`/first commit (if not already present)
- **Dependencies:** T-001
- **Acceptance criteria:**
  1. `.gitignore` excludes at minimum: OpenWrt SDK build output directories (`build_dir/`, `bin/`, `staging_dir/`, `dl/`), editor artifacts (`.vscode/`, `.idea/`, `*.swp`), OS artifacts (`.DS_Store`), and any local key material generated during Phase 16 testing (`*.rsa`, `*.pem` outside a documented `keys/` directory).
  2. A test `make package/submihomo/compile` run produces no files that `git status` reports as untracked-but-should-be-ignored.
  3. Repository has a valid initial commit history with no accidentally committed secrets or build output.
- **Expected output:** A clean git working tree convention that stays clean through every subsequent phase's build-and-test cycles.
- **Estimated complexity:** Simple

---

## 2. Phase 2 — Package Build System

### T-005 — Write Complete `Package/submihomo` Makefile Definition

- **Phase:** 2 — Package build system
- **Purpose:** Define the `submihomo` APK package's metadata, dependency on the upstream `mihomo` package, and file-installation rules within the root `Makefile`.
- **Files affected:** `SubMiHomo/Makefile` (adds the `define Package/submihomo ... endef` and `define Package/submihomo/install ... endef` stanzas)
- **Dependencies:** T-002
- **Acceptance criteria:**
  1. `define Package/submihomo` sets `SECTION`, `CATEGORY`, `TITLE`, `URL`, and `DEPENDS:=+mihomo` (upstream binary dependency per `docs/ARCHITECTURE.md` §7).
  2. `define Package/submihomo/install` copies every file under `files/etc/`, `files/usr/bin/submihomo-ctl`, `files/usr/lib/submihomo/`, and `files/usr/lib/rpcd/submihomo` into the correct `$(1)/...` target paths.
  3. `files/etc/config/submihomo` is declared a `conffile` (via `CONFFILES` or equivalent APK metadata) so user configuration survives upgrades — this is a direct prerequisite for acceptance criterion 10 of the project-wide acceptance list in `docs/ROADMAP.md` §6.
  4. `files/etc/init.d/submihomo` is installed with mode `0755`; `files/etc/config/submihomo` is installed with mode `0600` (per `docs/FILESYSTEM.md` §5, since it may contain a secret).
- **Expected output:** A `Package/submihomo` Makefile stanza that, once Phase 2's SDK build task (T-008) runs, produces an installable `.apk`.
- **Estimated complexity:** Medium

### T-006 — Write Complete `Package/luci-app-submihomo` Makefile Definition

- **Phase:** 2 — Package build system
- **Purpose:** Define the `luci-app-submihomo` APK package's metadata, dependency on `submihomo`, and installation of the LuCI JS assets, menu, and ACL files.
- **Files affected:** `SubMiHomo/Makefile` (adds the `define Package/luci-app-submihomo ... endef` and its `install` stanza)
- **Dependencies:** T-002, T-005
- **Acceptance criteria:**
  1. `define Package/luci-app-submihomo` sets `DEPENDS:=+submihomo` (per the dependency chain in `docs/ARCHITECTURE.md` §7: `luci-app-submihomo` → `submihomo` → `mihomo`).
  2. `define Package/luci-app-submihomo/install` copies `files/htdocs/luci-static/resources/view/submihomo/*.js`, `files/usr/share/luci/menu.d/luci-app-submihomo.json`, and `files/usr/share/rpcd/acl.d/luci-app-submihomo.json` into their target paths.
  3. Installing `luci-app-submihomo` alone (with no prior packages installed) transitively pulls in both `submihomo` and `mihomo` via APK dependency resolution.
- **Expected output:** A `Package/luci-app-submihomo` Makefile stanza producing an installable `.apk` whose dependency metadata is correct.
- **Estimated complexity:** Medium

### T-007 — Write postinst and prerm Package Scripts

- **Phase:** 2 — Package build system
- **Purpose:** Ensure the service is enabled automatically on first install and cleanly stopped/disabled on removal, without any manual step.
- **Files affected:** `SubMiHomo/Makefile` (adds `define Package/submihomo/postinst ... endef` and `define Package/submihomo/prerm ... endef`)
- **Dependencies:** T-005
- **Acceptance criteria:**
  1. `postinst` calls `/etc/init.d/submihomo enable` only on a real target install (guarded by the standard `[ -n "$${IPKG_INSTROOT}" ]` check so it is skipped during image-build/staging), and never calls `start` (starting is left to the boot sequence or the installer, since the service is `enabled 0` by default per `docs/UCI.md` §3.1).
  2. `prerm` calls `/etc/init.d/submihomo stop` and `/etc/init.d/submihomo disable` under the same install-root guard, ensuring `firewall_teardown()`/`dns_teardown()`/`routing_teardown()` all run before package files are removed.
  3. Both scripts exit `0` on success and do not abort the package transaction on a non-fatal condition (e.g., service already stopped).
- **Expected output:** A package that self-enables on install and self-cleans on removal with zero operator intervention.
- **Estimated complexity:** Simple

### T-008 — Test Package Builds with OpenWrt SDK

- **Phase:** 2 — Package build system
- **Purpose:** Prove the Makefile stanzas from T-005–T-007 actually produce valid, installable APK artifacts for the mipsel_24kc target.
- **Files affected:** None (verification task; may add a CI script under a future `SubMiHomo/.github/workflows/` — that workflow file itself is formally introduced in Phase 16, T-094, but a local/manual verification script may be added here as `SubMiHomo/install/dev-build.sh` if useful)
- **Dependencies:** T-005, T-006, T-007
- **Acceptance criteria:**
  1. `make package/submihomo/{clean,compile}` and `make package/luci-app-submihomo/{clean,compile}` both succeed from a clean OpenWrt 25+ SDK checkout targeting `mipsel_24kc`.
  2. The resulting `.apk` files appear under the SDK's `bin/packages/mipsel_24kc/` output tree with non-zero size.
  3. `apk verify` (or the SDK-provided equivalent packaging sanity check) reports no errors against both artifacts.
  4. Installing both packages into a test rootfs/chroot (or VM) via `apk add --allow-untrusted` succeeds and places every file at its documented path with the correct mode bits.
- **Expected output:** Confirmed, reproducible build instructions and two valid (though still functionally inert) `.apk` packages.
- **Estimated complexity:** Medium

---

## 3. Phase 3 — Core Service (core.sh + init.d)

### T-009 — Write core.sh Constants and UCI Helper Functions

- **Phase:** 3 — Core service
- **Purpose:** Establish the single source of truth for every port number, mark value, routing table number, and filesystem path used across all other shell modules — eliminating hardcoded values anywhere else in the codebase.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/core.sh`
- **Dependencies:** T-001
- **Acceptance criteria:**
  1. Defines `TPROXY_PORT=7891`, `MIXED_PORT=7890`, `DNS_PORT=1053`, `CTRL_PORT=9090`, `FWMARK=1`, `BYPASS_MARK=255`, `RT_TABLE=100`, `CONFIG_DIR=/etc/submihomo`, `RUN_DIR=/var/run/submihomo`, `SUB_DIR=/etc/submihomo/subscriptions`, `DASHBOARD_DIR=/usr/share/submihomo/dashboard` exactly as specified in `docs/COMPONENTS.md` §3.1.2.
  2. Defines `uci_get()` with the signature `uci_get <option> [default]`, returning the value of `submihomo.config.<option>` or the supplied default if unset, with no error raised on an absent key.
  3. Defines `is_enabled()` returning success (`0`) only when `uci_get enabled` is exactly `1`.
  4. Passes `shellcheck --shell=sh` with zero warnings.
  5. Sourcing the file twice in the same shell session produces no errors and no duplicate side effects (the file is a pure declaration set, per `docs/COMPONENTS.md` §3.1.5).
  6. File does not call `exit` anywhere.
- **Expected output:** A sourceable constants/UCI-helpers library ready for every other module to depend on.
- **Estimated complexity:** Simple

### T-010 — Write core.sh Logging Functions

- **Phase:** 3 — Core service
- **Purpose:** Provide the four standardized logging functions every module and the init script will use, per the logging design in `docs/LOGGING.md` §2–§3.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/core.sh` (appended; combined file must stay ≤ 150 lines total with T-009)
- **Dependencies:** T-009
- **Acceptance criteria:**
  1. Defines `log_info()`, `log_warn()`, `log_error()`, `log_debug()`, each wrapping `logger -t submihomo` with the appropriate level prefix in the message body (`INFO:`, `WARN:`, `ERROR:`, `DEBUG:`).
  2. `log_debug()` is a no-op unless `uci_get log_level` equals `debug`; `log_info`/`log_warn`/`log_error` are always emitted regardless of `log_level`, per `docs/LOGGING.md` §3.
  3. `logread -e submihomo` after calling each function shows the expected tagged line.
  4. The absence of the `logger` binary does not crash the calling script (verified by temporarily `PATH`-hiding `logger` in a test and confirming the calling script still completes).
  5. Combined `core.sh` (T-009 + T-010) is ≤ 150 lines total, verified with `wc -l`.
- **Expected output:** A complete, budget-compliant `core.sh` ready to be sourced by every other module and the init script.
- **Estimated complexity:** Simple

### T-011 — Write /etc/config/submihomo Default UCI Config

- **Phase:** 3 — Core service
- **Purpose:** Ship safe, non-invasive default settings so a freshly installed package does nothing harmful until an operator explicitly configures and enables it.
- **Files affected:** `SubMiHomo/files/etc/config/submihomo`
- **Dependencies:** T-009
- **Acceptance criteria:**
  1. Declares `config submihomo 'main'` with `enabled '0'`, `subscription_url ''`, `dns_mode 'fake-ip'`, `log_level 'warning'`, `allow_lan_access '0'`, `bypass_china '0'`, `subscription_update_interval '24'` — matching the defaults table in `docs/UCI.md` §3.13 exactly (full option set completed in Phase 5; this task ships the subset needed for Phase 3's inert skeleton to load without error).
  2. Declares an empty (or RFC1918-populated) `config bypass 'bypass'` section with `list address` entries, matching `docs/UCI.md` §4.1.
  3. `uci show submihomo` on a freshly installed system returns exactly these values with no parse errors.
  4. File mode is `0600` on install (verified via the Phase 2 Makefile install rule, cross-checked here).
- **Expected output:** A valid, safe-by-default UCI config file consumable by `core.sh`'s `uci_get()`.
- **Estimated complexity:** Simple

### T-012 — Write /etc/init.d/submihomo procd Skeleton (Start/Stop, No Mihomo)

- **Phase:** 3 — Core service
- **Purpose:** Prove the package registers correctly with procd and responds to lifecycle commands, before any risky kernel-level or process-supervision logic is added.
- **Files affected:** `SubMiHomo/files/etc/init.d/submihomo` (first ~30–40 lines of the eventual ≤ 120-line file)
- **Dependencies:** T-010, T-011
- **Acceptance criteria:**
  1. Declares `START=95`, `STOP=5`, `USE_PROCD=1` per `docs/FILESYSTEM.md` §2.3.
  2. `start_service()` sources `core.sh`, checks `is_enabled`, logs an informational message, and returns without opening any procd instance yet (no Mihomo invocation — deferred to Phase 4).
  3. `stop_service()` logs an informational message and returns cleanly.
  4. `shellcheck --shell=sh` passes with zero warnings.
  5. File is ≤ 120 lines (well under budget at this stage, leaving headroom for Phases 4 and 15).
- **Expected output:** A procd-registerable, harmless init script.
- **Estimated complexity:** Simple

### T-013 — Verify Service Enable/Disable/Start/Stop on OpenWrt

- **Phase:** 3 — Core service
- **Purpose:** Confirm, on a real router or VM, that the packaging (Phase 2) and skeleton (T-009–T-012) combine into a working, harmless service — the Milestone M1 acceptance check from `docs/ROADMAP.md` §5.
- **Files affected:** None (verification task)
- **Dependencies:** T-008, T-012
- **Acceptance criteria:**
  1. `service submihomo enable && service submihomo start` exits `0`.
  2. `service submihomo status` reports the service as running.
  3. `service submihomo stop` exits `0` and leaves no residual processes (`ps` shows no `mihomo` process, since none was ever started).
  4. `nft list ruleset`, `ip rule show`, `ip route show table 100`, and `/etc/dnsmasq.d/` are byte-for-byte identical before and after the start/stop cycle (proving zero kernel-level side effects at this phase, as designed).
  5. `service submihomo disable && service submihomo enable` round-trips correctly (`/etc/rc.d/` symlinks appear/disappear as expected).
- **Expected output:** Confirmed Milestone M1 (`docs/ROADMAP.md` §5) — a real, installable, safely inert procd service.
- **Estimated complexity:** Simple

---

## 4. Phase 4 — procd Integration

### T-014 — Add Mihomo Binary Invocation to init.d

- **Phase:** 4 — procd integration
- **Purpose:** Make `start_service()` actually launch the Mihomo binary as a procd-supervised instance.
- **Files affected:** `SubMiHomo/files/etc/init.d/submihomo`
- **Dependencies:** T-012, T-013
- **Acceptance criteria:**
  1. `start_service()` calls `procd_open_instance`, then `procd_set_param command /usr/bin/mihomo -f $RUN_DIR/config.yaml -d $RUN_DIR`, then `procd_close_instance` — exactly the invocation documented in `docs/COMPONENTS.md` §3.13.1.
  2. A missing `/usr/bin/mihomo` binary is detected before `procd_open_instance` is called, logging `log_error` and returning non-zero rather than letting procd repeatedly fail to spawn a nonexistent binary.
  3. `service submihomo start` results in a visible `mihomo` process in `ps` with the correct command-line arguments.
  4. (Full config generation, routing, DNS, and firewall setup are not yet wired here — this task only proves process invocation; those integrations land in their respective phases 7–11. For this task's verification, a minimal hand-written placeholder `config.yaml` may be used.)
- **Expected output:** A procd instance that successfully launches and supervises the real Mihomo binary.
- **Estimated complexity:** Medium

### T-015 — Configure procd Respawn Parameters

- **Phase:** 4 — procd integration
- **Purpose:** Ensure Mihomo automatically recovers from crashes without creating a restart storm on persistent failure.
- **Files affected:** `SubMiHomo/files/etc/init.d/submihomo`
- **Dependencies:** T-014
- **Acceptance criteria:**
  1. `procd_set_param respawn` is configured with a threshold/timeout/retry policy consistent with `docs/FILESYSTEM.md` §2.3's "5 attempts / 60s" moderate-recovery guidance.
  2. Killing the Mihomo PID (`kill -9 <pid>`) results in procd respawning a new instance within the configured window, verified by observing a new PID in `ps`.
  3. Repeatedly killing the process faster than the respawn threshold allows causes procd to give up after the configured attempt count, and this terminal failure is visible in `logread` (not silently swallowed).
- **Expected output:** A resilient, but not runaway, crash-recovery policy.
- **Estimated complexity:** Simple

### T-016 — Configure procd stdout/stderr Capture

- **Phase:** 4 — procd integration
- **Purpose:** Route Mihomo's own log output into syslog under a distinct tag, per `docs/LOGGING.md` §2.
- **Files affected:** `SubMiHomo/files/etc/init.d/submihomo`
- **Dependencies:** T-014
- **Acceptance criteria:**
  1. `procd_set_param stdout 1` and `procd_set_param stderr 1` are set on the Mihomo instance.
  2. Mihomo's own log lines appear in `logread` under the `submihomo.mihomo` tag, distinct from the `submihomo` tag used by shell-module logging (verified by `logread -e submihomo.mihomo` showing only Mihomo-originated lines).
  3. `logread -e submihomo.mihomo` and `logread -e submihomo` can be viewed independently without one polluting the other.
- **Expected output:** Correctly tagged, dual-stream logging as specified in `docs/LOGGING.md`.
- **Estimated complexity:** Simple

### T-017 — Add service_triggers() for UCI and Network Changes

- **Phase:** 4 — procd integration
- **Purpose:** Make the service automatically restart when its own UCI configuration changes, without requiring a manual `service submihomo restart`.
- **Files affected:** `SubMiHomo/files/etc/init.d/submihomo`
- **Dependencies:** T-014
- **Acceptance criteria:**
  1. `service_triggers()` calls `procd_add_reload_trigger submihomo` (and any documented interface trigger per `docs/BOOT.md` §12.1) so that `uci commit submihomo` followed by the standard reload-trigger event causes an automatic restart.
  2. Changing an unrelated UCI package's configuration does **not** trigger a SubMiHomo restart (verified by committing a change to, e.g., `network` and confirming the Mihomo PID is unchanged).
  3. Changing `submihomo`'s own UCI config and firing the reload event results in a new Mihomo PID (full restart, not merely a signal) within a bounded, observable time window.
- **Expected output:** Automatic, correctly-scoped restart-on-configuration-change behavior.
- **Estimated complexity:** Medium

### T-018 — Test procd Service Lifecycle

- **Phase:** 4 — procd integration
- **Purpose:** Validate the complete Phase 4 deliverable end-to-end — the Milestone M2 prerequisite of "procd supervises a real Mihomo process."
- **Files affected:** None (verification task)
- **Dependencies:** T-015, T-016, T-017
- **Acceptance criteria:**
  1. A full start → observe-running → kill → observe-respawn → UCI-change → observe-restart → stop → observe-clean-exit cycle completes with the expected process and log behavior at every step.
  2. No stray Mihomo process remains after `service submihomo stop` under any of the above scenarios.
  3. `shellcheck --shell=sh` is clean on the fully assembled `init.d/submihomo` file (T-012 + T-014–T-017 combined), and the file remains ≤ 120 lines.
- **Expected output:** A confirmed, robust procd integration ready for UCI (Phase 5) and RPC (Phase 6) to build on.
- **Estimated complexity:** Medium

---

## 5. Phase 5 — UCI

### T-019 — Implement UCI Validation Functions in core.sh

- **Phase:** 5 — UCI
- **Purpose:** Enforce every validation rule in `docs/UCI.md` §3 in one shared location, so both the CLI/shell path and the RPC path (Phase 6) can call the same logic instead of duplicating rules.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/core.sh` (combined file must remain ≤ 150 lines with T-009/T-010/T-020 — if this cannot be achieved, split validation into a clearly justified addition, but only after confirming no further trimming is possible)
- **Dependencies:** T-010
- **Acceptance criteria:**
  1. A validation function exists (or a per-option dispatch table) enforcing every rule in `docs/UCI.md` §3.13: boolean fields restricted to `0`/`1`; `subscription_url` empty or `https://`-prefixed; `subscription_update_interval` in `0`–`168`; `dns_mode` in `{fake-ip, real-ip}`; `log_level` in `{debug, info, warning, error, silent}`; `external_controller_port` in `1024`–`65535` and not colliding with `7891`/`7890`/`1053`; `dashboard_repo` matching `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`; `subscription_user_agent` non-empty with control characters/CRLF stripped.
  2. Bypass-list entries are validated per `docs/UCI.md` §4.5 (IPv4 CIDR regex, octet range 0–255, prefix 0–32); non-matching entries (including valid IPv6 CIDRs) are logged and skipped, never hard-rejected at the UCI-write layer, per the documented "silently ignored" behavior.
  3. A test matrix covering at least one valid and one invalid value per option (14+ cases) all resolve as expected when run through the validation function directly (shell-level test, independent of any RPC/UI layer).
- **Expected output:** A single, shared, exhaustively tested validation library.
- **Estimated complexity:** Medium

### T-020 — Implement config_version Migration Mechanism

- **Phase:** 5 — UCI
- **Purpose:** Provide the extensibility hook that will let future SubMiHomo releases evolve the UCI schema without breaking existing installations.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/core.sh`
- **Dependencies:** T-019
- **Acceptance criteria:**
  1. A function (e.g., `run_migrations()`) reads `config_version` (absent treated as `0`, per `docs/UCI.md` §3.12), compares it against the current code's expected version (`1`), and would sequentially apply any migration steps between the two — for v1.0 there are zero real migrations to run, so this is a correctly-shaped no-op skeleton.
  2. Running the function against a config with `config_version=1` completes with exit `0` and makes no changes.
  3. Running the function against a config with `config_version` absent completes successfully and writes `config_version=1` afterward (proving the "absence treated as version 0, migrated forward" path works even with nothing to migrate).
  4. A partial-migration failure (simulated by forcing a migration step to fail, for test purposes only) does not leave `config_version` updated — the migration is all-or-nothing per option group, matching `docs/UCI.md` §7.5.
- **Expected output:** A working, tested migration skeleton ready to carry real migrations in future releases.
- **Estimated complexity:** Medium

### T-021 — Write UCI Schema Documentation/Validation Table

- **Phase:** 5 — UCI
- **Purpose:** Produce a single, implementation-adjacent reference table (consumed by both engineers writing `set_config` in Phase 6 and QA writing the Phase 5/6 test matrices) enumerating every option, its type, range, and default, cross-checked against `docs/UCI.md` for consistency.
- **Files affected:** A comment block or table at the top of `SubMiHomo/files/usr/lib/submihomo/core.sh`'s validation section (documentation only, not a separate file, to avoid a second source of truth diverging from `docs/UCI.md`)
- **Dependencies:** T-019
- **Acceptance criteria:**
  1. Every row of `docs/UCI.md` §3.13's consolidated option table is represented, with no option added, removed, or renamed relative to that document.
  2. The in-code table and `docs/UCI.md` are cross-verified (manually or via a small consistency-check script) to contain identical option names, defaults, and ranges.
  3. Any future divergence between code and `docs/UCI.md` is caught by this cross-check rather than discovered as a runtime bug.
- **Expected output:** A guaranteed-consistent, implementation-adjacent schema reference.
- **Estimated complexity:** Simple

### T-022 — Test UCI Read/Write via uci Commands

- **Phase:** 5 — UCI
- **Purpose:** Validate the complete Phase 5 deliverable directly against the `uci` CLI, independent of any future RPC layer.
- **Files affected:** None (verification task)
- **Dependencies:** T-020, T-021
- **Acceptance criteria:**
  1. `uci set submihomo.main.dns_mode='real-ip'; uci commit submihomo` followed by `uci_get dns_mode` (via the shell helper) returns `real-ip`.
  2. Setting an invalid value (e.g., `external_controller_port=99`) through the validation function is rejected with a clear error and the underlying UCI value is left unchanged.
  3. `uci add_list submihomo.bypass.address='10.50.0.0/16'; uci commit submihomo` correctly appends to the bypass list without disturbing existing entries.
  4. `run_migrations()` executes successfully as part of a full `uci commit` + service reload cycle.
- **Expected output:** Confirmed Phase 5 completeness — a fully validated, migration-ready UCI schema.
- **Estimated complexity:** Simple

---

## 6. Phase 6 — RPC

### T-023 — Write rpcd Plugin Lua Skeleton with `list` Method

- **Phase:** 6 — RPC
- **Purpose:** Establish the Lua rpcd plugin's registration boilerplate and the mandatory `list` method every rpcd plugin must implement so rpcd can enumerate available methods and their expected parameters.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo` (first section of the eventual ≤ 400-line file)
- **Dependencies:** T-008 (packages must install so the plugin can be loaded by a real `rpcd` process)
- **Acceptance criteria:**
  1. The file is valid Lua, loadable by `rpcd` without error (`rpcd -d` debug/reload confirms no load errors).
  2. `ubus call submihomo list` returns a JSON object enumerating all 12 method names with their declared input parameter shapes (bodies of the 12 methods are stubbed to return a fixed placeholder at this point; real implementations land in T-024–T-032).
  3. The plugin never calls `os.execute()`/`io.popen()` in this skeleton — that capability is introduced narrowly and only in T-029/T-030 per the execution policy in §0.4.
- **Expected output:** A loadable rpcd plugin skeleton with a correct method inventory.
- **Estimated complexity:** Medium

### T-024 — Implement `status` RPC Method

- **Phase:** 6 — RPC
- **Purpose:** Expose Mihomo's running/stopped state, PID, and uptime as the primary health signal consumed by the LuCI Overview page and the CLI.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-023, T-018 (a real procd-supervised Mihomo instance must exist to report on)
- **Acceptance criteria:**
  1. `ubus call submihomo status '{}'` returns `{"running": true/false, "pid": <int>, "uptime": <int>}` matching the process's actual state (cross-checked against `ps`/`/proc/<pid>`).
  2. When Mihomo is not running, the method returns `{"running": false}` — not an error — per `docs/COMPONENTS.md` §3.10.6.
  3. Uses the ubus `service` object (or direct procd introspection) rather than shelling out to `ps`/`pidof` via `io.popen()`, consistent with the execution policy in §0.4.
- **Expected output:** A working, side-effect-free status query.
- **Estimated complexity:** Medium

### T-025 — Implement `start`/`stop`/`restart` RPC Methods

- **Phase:** 6 — RPC
- **Purpose:** Let the UI and other RPC consumers control the service lifecycle without shelling out to `/etc/init.d/submihomo` directly.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-023, T-018
- **Acceptance criteria:**
  1. Each method calls the ubus `service` object (`ubus call service start/stop/restart '{"name":"submihomo"}'`) — never `io.popen("/etc/init.d/submihomo ...")` — per the execution policy in §0.4.
  2. `ubus call submihomo start '{}'` on a stopped service results in a running Mihomo process within a bounded, observable time window; the method returns `{"result": true}`.
  3. `ubus call submihomo stop '{}'` results in a clean stop (mirrors the Phase 3/4 exit criteria) and `{"result": true}`.
  4. A failed underlying `service` call (e.g., service object unreachable) results in `{"result": false, "error": "<text>"}`, never an uncaught Lua exception that could crash the shared `rpcd` process.
- **Expected output:** Three working, ubus-native lifecycle control methods.
- **Estimated complexity:** Medium

### T-026 — Implement `get_config`/`set_config` RPC Methods

- **Phase:** 6 — RPC
- **Purpose:** Give the UI full read/write access to the UCI schema through a single, validated, ACL-gated surface — the backbone of the Settings and Subscription LuCI pages.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-023, T-022 (the UCI schema and validation logic must exist to wrap)
- **Acceptance criteria:**
  1. `get_config` uses `luci.model.uci`, not shell-outs, to enumerate every option under `submihomo.main` (and the `bypass` list section), returning `{"config": {...}}` with every option in `docs/UCI.md` §3.13 present.
  2. `set_config` accepts `{key, value}`, applies the same validation rules as T-019 (either by calling into the shell-side validation via a narrow, documented bridge, or by reimplementing identical rules natively in Lua — whichever approach is chosen, a consistency test in T-034 must prove the two never disagree), writes via `luci.model.uci`, and calls `uci:commit("submihomo")`.
  3. An invalid value passed to `set_config` returns `{"result": false, "error": "<validation message>"}` and leaves the underlying UCI value unchanged.
  4. A UCI commit failure (simulated, e.g., read-only filesystem) returns `{"result": false, "error": "UCI commit failed"}` per `docs/COMPONENTS.md` §3.10.6.
- **Expected output:** A fully validated, ACL-appropriate configuration read/write surface.
- **Estimated complexity:** Complex

### T-027 — Implement `get_logs` RPC Method

- **Phase:** 6 — RPC
- **Purpose:** Expose SubMiHomo's and Mihomo's syslog output to the UI's Logs page without shelling out.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-023, T-016 (dual-tag logging must exist to filter)
- **Acceptance criteria:**
  1. `ubus call submihomo get_logs '{"lines": 50}'` calls the ubus `log` object (`ubus call log read '{"lines": N}'`) — no `io.popen("logread ...")` — and returns `{"lines": [...]}` filtered to entries tagged `submihomo` and/or `submihomo.mihomo`.
  2. Requesting more lines than exist in the buffer returns all available lines without error.
  3. `lines` defaults to a sane value (e.g., 50) if omitted from the request.
- **Expected output:** A working, ubus-native log retrieval method.
- **Estimated complexity:** Medium

### T-028 — Implement `run_diagnostics` RPC Method (Phase 13 Stub)

- **Phase:** 6 — RPC
- **Purpose:** Reserve and correctly shape the diagnostics RPC surface now, so Phase 13 only needs to fill in real check logic rather than design a new method and risk a breaking interface change after Phase 12's LuCI pages are already built against it.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-023
- **Acceptance criteria:**
  1. `ubus call submihomo run_diagnostics '{}'` returns a structured array of check results, each shaped `{"name": string, "passed": bool, "detail": string}`, even though at this stage all 12 entries are placeholder checks that always report `passed: true` with `detail: "not yet implemented"`.
  2. The final schema (array of 12 named entries) is treated as fixed as of this task — Phase 13 (T-074, T-075) may only change each entry's internal logic, never the outer JSON shape, since Phase 12's LuCI code will already be written against it.
  3. The method never fails outright — even a placeholder call always returns `200`-equivalent success with the fixed array shape.
- **Expected output:** A stable, forward-compatible diagnostics RPC contract ready for Phase 13 to complete.
- **Estimated complexity:** Simple

### T-029 — Implement `update_subscription` RPC Method

- **Phase:** 6 — RPC
- **Purpose:** Let the UI and CLI trigger a subscription refresh through the RPC layer.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-023; logically completed once Phase 7's `subscription_update()` exists (T-038), though the RPC stub may be written now and wired to a placeholder until then
- **Acceptance criteria:**
  1. `ubus call submihomo update_subscription '{}'` invokes exactly one fixed, zero-argument shell entry point (e.g., a documented `subscription.sh update` invocation path) — the RPC caller's request body is never interpolated into the invoked command string, per the execution policy in §0.4.
  2. Returns `{"result": true, "message": "<summary>"}` on success and `{"result": false, "message": "<error detail>"}` on failure, matching `docs/COMPONENTS.md` §3.10.2's schema for `subscription.update`.
  3. A concurrent second call while one is already in progress is safely serialized or rejected (no two subscription updates run simultaneously), verified once Phase 7's locking exists.
- **Expected output:** A working, injection-safe subscription-update trigger.
- **Estimated complexity:** Medium

### T-030 — Implement `download_dashboard` RPC Method

- **Phase:** 6 — RPC
- **Purpose:** Let the UI and CLI trigger a Zashboard update through the RPC layer.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-023; logically completed once Phase 15's `dashboard_download()` exists (T-087), though the RPC stub may be written now
- **Acceptance criteria:**
  1. `ubus call submihomo download_dashboard '{}'` invokes exactly one fixed, zero-argument shell entry point (e.g., `dashboard.sh download`) — again, no RPC input is ever interpolated into the shell command, per §0.4.
  2. Returns `{"result": true}` on success and `{"result": false, "error": "<detail>"}` on failure.
  3. A slow (multi-second) GitHub download does not block the entire rpcd process for other unrelated ubus calls (verified by issuing a `status` call concurrently and confirming it returns promptly).
- **Expected output:** A working, injection-safe dashboard-update trigger.
- **Estimated complexity:** Medium

### T-031 — Implement `get_proxies` RPC Method

- **Phase:** 6 — RPC
- **Purpose:** Expose Mihomo's live proxy-group/node tree to the Proxies and Overview LuCI pages.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-023, T-024 (needs to know whether Mihomo is even running before querying its API)
- **Acceptance criteria:**
  1. `ubus call submihomo get_proxies '{}'` performs an HTTP `GET` to `http://127.0.0.1:<external_controller_port>/proxies` using OpenWrt's `nixio` Lua sockets (never `io.popen("curl ...")`), attaching the `external_controller_secret` as a bearer token/header if configured.
  2. Returns `{"proxies": [...]}` reflecting Mihomo's actual group/node hierarchy.
  3. When Mihomo is not running or the API is unreachable, returns `{"error": "mihomo API unavailable"}` rather than throwing, per `docs/COMPONENTS.md` §3.10.6.
- **Expected output:** A working, non-shelling proxy-list query.
- **Estimated complexity:** Medium

### T-032 — Implement `test_connection` RPC Method

- **Phase:** 6 — RPC
- **Purpose:** Let the Proxies page perform a per-node (or per-group) latency test without the browser talking to Mihomo's API directly.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-023, T-031
- **Acceptance criteria:**
  1. `ubus call submihomo test_connection '{"proxy": "<name>"}'` performs an HTTP `GET` to Mihomo's own `/proxies/{name}/delay?url=...&timeout=...` endpoint via `nixio` (an HTTP call to Mihomo's already-open local API port, not a shell execution), and returns `{"result": true, "delay_ms": <int>}` on success.
  2. An unreachable proxy or a Mihomo-reported timeout returns `{"result": false, "error": "<detail>"}` rather than hanging the RPC call indefinitely (a request-level timeout is enforced).
  3. Calling with a non-existent proxy name returns a clear `{"result": false, "error": "unknown proxy"}` rather than a raw Mihomo API error passthrough.
- **Expected output:** A working, bounded-latency connectivity test method.
- **Estimated complexity:** Medium

### T-033 — Write ACL Definition File

- **Phase:** 6 — RPC
- **Purpose:** Enforce that only authenticated, appropriately-privileged LuCI sessions can call state-mutating RPC methods, per `docs/SECURITY.md` §9.
- **Files affected:** `SubMiHomo/files/usr/share/rpcd/acl.d/luci-app-submihomo.json`
- **Dependencies:** T-024 through T-032 (the full method inventory must be final before the ACL can name them all)
- **Acceptance criteria:**
  1. `luci-user` is granted **read** access to exactly the six read-only methods: `status`, `get_config`, `get_logs`, `get_proxies`, `run_diagnostics`, `test_connection`.
  2. `luci-admin` is granted full read **and** write access to all 12 methods (`"*"` or an explicit enumeration).
  3. `luci-user` is **not** granted access to `start`, `stop`, `restart`, `set_config`, `update_subscription`, or `download_dashboard` under any circumstance.
  4. rpcd reloads the ACL file without error (`/etc/init.d/rpcd reload` or equivalent) and `ubus call session access` reflects the intended grants for both roles.
- **Expected output:** A correctly scoped, tested ACL file matching the security model in `docs/SECURITY.md`.
- **Estimated complexity:** Simple

### T-034 — Test All RPC Methods with ubus-cli

- **Phase:** 6 — RPC
- **Purpose:** Prove the entire Phase 6 deliverable end-to-end before any LuCI page (Phase 12) is built against it.
- **Files affected:** None (verification task; may produce a reusable test script, e.g. `SubMiHomo/install/dev-rpc-test.sh`, for regression use in Phase 16's CI)
- **Dependencies:** T-024 through T-033
- **Acceptance criteria:**
  1. Every one of the 12 methods is called via `ubus call submihomo <method> '<json>'` with both a valid and an invalid input, and the response JSON shape matches the schema declared in T-023's `list` output for every case.
  2. A `set_config`/`get_config` round trip (`set_config` a value, then `get_config` and confirm it reflects) succeeds for at least one option of each type (boolean, integer, enum, string).
  3. An ACL test confirms a `luci-user`-scoped session can call the six read-only methods and is rejected (with a clear ubus permission-denied error, not a crash) when attempting any of the six write methods.
  4. No method call, valid or invalid input, ever causes the `rpcd` process itself to crash or hang (verified by confirming `rpcd` remains responsive to unrelated ubus calls, e.g. `ubus call system board`, throughout the entire test run).
- **Expected output:** A confirmed, complete, safe RPC surface — the technical foundation Phase 12 depends on.
- **Estimated complexity:** Complex

---

## 7. Phase 7 — Subscription Manager

### T-035 — Write subscription_download() Function

- **Phase:** 7 — Subscription manager
- **Purpose:** Implement Level 1 (HTTP-level) validation and the safe, tmpfs-scoped download step described in `docs/SUBSCRIPTIONS.md` §2–§4.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/subscription.sh` (first section of the eventual ≤ 200-line file)
- **Dependencies:** T-022 (needs `subscription_url`/`subscription_user_agent` validated and readable)
- **Acceptance criteria:**
  1. Downloads to `/tmp/submihomo-sub-download.yaml` (tmpfs) via `wget`, sending the configured `subscription_user_agent` header and a `--timeout=30` bound.
  2. Rejects (returns non-zero, logs `log_error`) any URL not beginning with `https://`, before attempting any network call.
  3. Rejects any response that is not HTTP `200`, any transfer exceeding the 30-second timeout, and any downloaded file exceeding 5 MB — cleaning up the temp file in every rejection case.
  4. A successful call leaves exactly one file, `/tmp/submihomo-sub-download.yaml`, with the downloaded content and no other droppings in `/tmp`.
- **Expected output:** A safe, bounded, Level-1-validating download primitive.
- **Estimated complexity:** Medium

### T-036 — Write subscription_validate() Function (3-Level Validation)

- **Phase:** 7 — Subscription manager
- **Purpose:** Implement Levels 2 and 3 of the validation system from `docs/SUBSCRIPTIONS.md` §4, ensuring no malformed or malicious subscription content is ever promoted to `current.yaml`.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/subscription.sh`
- **Dependencies:** T-035
- **Acceptance criteria:**
  1. Level 2: rejects an empty file (`[ -s file ]` check), rejects a file with no `^proxies:` anchored key, and rejects a `proxies:` section with zero proxy entries (matching neither `^\s*-\s*name:` nor `^\s*-\s*\{name:`).
  2. Level 3: assembles a complete test config merging the candidate subscription with current UCI settings, writes it to `/var/run/submihomo/config-test.yaml`, runs `mihomo -t -f`, and treats any non-zero exit as rejection.
  3. `config-test.yaml` is deleted immediately after the `mihomo -t` call regardless of outcome.
  4. Every rejection path leaves `current.yaml` and `backup.yaml` completely untouched and removes the candidate temp file.
- **Expected output:** A complete, three-level, fail-closed validation function.
- **Estimated complexity:** Complex

### T-037 — Write subscription_backup() and subscription_apply() Functions

- **Phase:** 7 — Subscription manager
- **Purpose:** Implement the atomic promote-with-rollback-point mechanics described in `docs/SUBSCRIPTIONS.md` §2.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/subscription.sh`
- **Dependencies:** T-036
- **Acceptance criteria:**
  1. `subscription_backup()` copies the existing `current.yaml` to `backup.yaml` before any promotion, and is a no-op (not an error) when `current.yaml` does not yet exist (first-run case).
  2. `subscription_apply()` performs an atomic `mv` of the validated temp file onto `current.yaml` (same filesystem, so it is a rename, never a cross-filesystem copy that could leave a partial file on interruption).
  3. A simulated interruption between backup and apply (kill the process mid-way, for test purposes) never results in a `current.yaml` that is missing, truncated, or a mix of old and new content — it is always fully one or fully the other.
- **Expected output:** A genuinely atomic, crash-safe promotion mechanism.
- **Estimated complexity:** Medium

### T-038 — Write subscription_update() Orchestration Function

- **Phase:** 7 — Subscription manager
- **Purpose:** Tie T-035–T-037 together into the single public entry point documented as `subscription_update()` in `docs/COMPONENTS.md` §3.6.2, plus the `subscription_status()` and `subscription_restore()` public functions.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/subscription.sh`
- **Dependencies:** T-037
- **Acceptance criteria:**
  1. `subscription_update()` implements the exact decision tree in `docs/SUBSCRIPTIONS.md` §3: empty URL → warn and skip (not an error); HTTP/size/timeout failure → error, unchanged state; Level 2/3 failure → error, unchanged state; success → backup, apply, regenerate config, hot-reload if running, else skip reload.
  2. `subscription_status()` prints whether `current.yaml` exists, its modification time, and a proxy count (derived via the same `awk` counting technique used in config generation).
  3. `subscription_restore()` copies `backup.yaml` back onto `current.yaml` and returns non-zero with a clear message if no backup exists.
  4. A lock (per `docs/COMPONENTS.md`'s lock-helper convention) prevents two concurrent `subscription_update()` invocations from racing (e.g., a manual trigger firing while a cron-triggered update is already in progress).
- **Expected output:** The complete public `subscription.sh` interface.
- **Estimated complexity:** Complex

### T-039 — Write subscription_cron_update() Function

- **Phase:** 7 — Subscription manager
- **Purpose:** Implement the scheduled-update mechanism described in `docs/SUBSCRIPTIONS.md` §9 and `docs/COMPONENTS.md` §3.12, keeping the cron entry synchronized with the `subscription_update_interval` UCI option.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/subscription.sh` (final section; combined file with T-035–T-038 must remain ≤ 200 lines)
- **Dependencies:** T-038
- **Acceptance criteria:**
  1. A function writes/rewrites a `/etc/crontabs/root` entry of the form `0 */N * * * <fixed invocation of subscription_update>` where `N` is the current `subscription_update_interval` (range 1–168), and removes the entry entirely when the interval is `0` or the service is disabled.
  2. Changing `subscription_update_interval` via UCI and re-running this function results in exactly one SubMiHomo-owned crontab line, correctly updated (no duplicate lines accumulate across repeated calls).
  3. The cron entry never contains user-supplied, uninterpolated content — the invoked command is fixed, matching the execution-policy constraint used for the RPC layer (§0.4), even though this is a shell-only, non-RPC code path.
  4. Combined `subscription.sh` (T-035–T-039) is ≤ 200 lines, verified with `wc -l`.
- **Expected output:** A correctly self-maintaining scheduled-update mechanism.
- **Estimated complexity:** Medium

### T-040 — Test Subscription Download with Valid URL

- **Phase:** 7 — Subscription manager
- **Purpose:** Validate the happy path against a controlled fixture, independent of any real third-party subscription provider.
- **Files affected:** None (verification task; may add fixture files under a test-only directory, e.g. `SubMiHomo/install/test-fixtures/` if the team adopts on-repo fixtures)
- **Dependencies:** T-038
- **Acceptance criteria:**
  1. A local HTTP fixture server serving a known-good Clash/Mihomo YAML (flat proxy list, at least one `proxy-groups` entry, at least one rule) results in `subscription_update()` returning success, `current.yaml` matching the fixture's proxy/group/rule content, and `backup.yaml` reflecting whatever `current.yaml` held immediately prior (or absent, on first run).
  2. `mihomo -t -f` against the resulting merged config (via `config_generate()`, once Phase 8 exists — until then, against the Level 3 test config produced internally by T-036) passes.
- **Expected output:** A confirmed, fixture-driven happy-path test.
- **Estimated complexity:** Medium

### T-041 — Test Subscription Validation Failure Modes

- **Phase:** 7 — Subscription manager
- **Purpose:** Exhaustively confirm every documented failure mode in `docs/SUBSCRIPTIONS.md` §10 behaves as fail-closed.
- **Files affected:** None (verification task)
- **Dependencies:** T-040
- **Acceptance criteria:**
  1. Non-HTTPS URL, non-200 response, 30-second-plus hang, > 5 MB body, empty body, missing `proxies:` key, `proxies:` with zero entries, and a Level-3 `mihomo -t` rejection (e.g., a proxy referencing an undefined type) are each individually tested and each leaves `current.yaml`/`backup.yaml` byte-for-byte unchanged.
  2. Every failure path leaves zero temp files behind in `/tmp` afterward (`config-test.yaml` and the download temp file are both cleaned up in all 8 scenarios).
  3. Every failure logs a distinguishable, actionable `log_error` message (verified by `logread -e submihomo` content, not just exit code).
- **Expected output:** A fully confirmed fail-closed validation system.
- **Estimated complexity:** Medium

### T-042 — Test Subscription Rollback

- **Phase:** 7 — Subscription manager
- **Purpose:** Confirm the manual recovery path (`subscription_restore()`) genuinely restores prior service behavior.
- **Files affected:** None (verification task)
- **Dependencies:** T-038
- **Acceptance criteria:**
  1. After two successful sequential updates (subscription A, then subscription B), calling `subscription_restore()` results in `current.yaml` matching subscription A's content exactly.
  2. Calling `subscription_restore()` with no `backup.yaml` present returns non-zero with a clear "no backup available" message, and does not create or corrupt `current.yaml`.
  3. Following a restore, `config_generate()` (once Phase 8 exists) succeeds against the restored file, proving the restored subscription is fully usable, not just textually present.
- **Expected output:** A confirmed, reliable manual rollback path.
- **Estimated complexity:** Simple

---

## 8. Phase 8 — Mihomo Config Generator

### T-043 — Write Mihomo base.yaml.tmpl Template

- **Phase:** 8 — Config generator
- **Purpose:** Provide the static, UCI-driven scaffold that `config_generate()` will fill in and splice subscription content into.
- **Files affected:** `SubMiHomo/files/etc/submihomo/templates/base.yaml.tmpl`
- **Dependencies:** T-022 (all referenced UCI options must already be validated and stable)
- **Acceptance criteria:**
  1. Contains placeholder tokens for every UCI-derived value needed: TPROXY/mixed/DNS/controller ports, `log_level`, `external_controller_secret`, `allow_lan_access`-driven bind address, `dns_mode`-driven enhanced-mode, and `external-ui: /usr/share/submihomo/dashboard`.
  2. Contains empty placeholders (`proxies: []`, `proxy-groups: []`, and a `rules:` stanza) that `config.sh` will locate and replace — the template itself is never a complete, valid Mihomo config on its own (it is always paired with extracted subscription content).
  3. `TPROXY_PORT`/`MIXED_PORT`/`DNS_PORT`/`CTRL_PORT` placeholders are never hardcoded numbers duplicated from `core.sh` — the template uses named tokens substituted at generation time so the constants remain single-sourced.
- **Expected output:** A ready-to-substitute Mihomo config template.
- **Estimated complexity:** Medium

### T-044 — Write config_read_uci() Function

- **Phase:** 8 — Config generator
- **Purpose:** Centralize the read of every UCI value `config_generate()` needs into one function, keeping the rest of `config.sh` free of scattered `uci_get` calls.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/config.sh` (first section of the eventual ≤ 200-line file)
- **Dependencies:** T-043
- **Acceptance criteria:**
  1. Reads and exposes (as shell variables) every value listed in `docs/COMPONENTS.md` §3.2.3 step 2: mixed/tproxy/dns/controller ports, `log_level`, `external_controller_secret`, `allow_lan_access`, `dns_mode`.
  2. Applies the shared validation helpers from T-019 rather than trusting raw UCI content, even though values should already be validated at write time — defense in depth per `docs/COMPONENTS.md` §3.2.7.
  3. Missing or malformed values fall back to documented safe defaults rather than propagating an empty token into the rendered YAML.
- **Expected output:** A single, reliable UCI-to-shell-variable bridge for the rest of `config.sh`.
- **Estimated complexity:** Simple

### T-045 — Write Proxies Extraction awk Function

- **Phase:** 8 — Config generator
- **Purpose:** Implement the column-0 state-machine `proxies:` block extraction described in `docs/SUBSCRIPTIONS.md` §5.1.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/config.sh`
- **Dependencies:** T-044
- **Acceptance criteria:**
  1. Extracts the entire `proxies:` block from `$SUB_DIR/current.yaml`, correctly handling arbitrary internal indentation, blank lines, and comments, and stopping exactly at the next column-0 key.
  2. Correctly extracts a section regardless of its position in the source document (first, middle, or last top-level key).
  3. Tested against at least three real-world subscription fixture styles (2-space indent, 4-space indent, flow-mapping style) with zero entries dropped or duplicated, verified by comparing extracted proxy-entry counts against an independently computed ground truth for each fixture.
- **Expected output:** A robust, fixture-tested `proxies:` extractor.
- **Estimated complexity:** Complex

### T-046 — Write Proxy-Groups Extraction awk Function (+ PROXY Selector Injection)

- **Phase:** 8 — Config generator
- **Purpose:** Extract `proxy-groups:` and prepend the synthetic `PROXY` selector group described in `docs/SUBSCRIPTIONS.md` §5.3.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/config.sh`
- **Dependencies:** T-045
- **Acceptance criteria:**
  1. Extracts `proxy-groups:` using the same column-0 state-machine approach as T-045, generalized to a parameterized key name.
  2. Prepends a synthetic group named `PROXY`, `type: select`, whose member list is every top-level group name found in the subscription's own `proxy-groups:` plus a literal `DIRECT` — exactly as shown in `docs/SUBSCRIPTIONS.md` §5.3's example.
  3. When the subscription defines zero proxy-groups, the `PROXY` group still exists with `DIRECT` as its sole, functional member (verified against a fixture with a flat `proxies:` list and no `proxy-groups:` key at all).
- **Expected output:** A correct groups extractor with a guaranteed, stable top-level selector.
- **Estimated complexity:** Complex

### T-047 — Write Rules Extraction awk Function (+ Bypass Rules + bypass_china + MATCH,PROXY)

- **Phase:** 8 — Config generator
- **Purpose:** Extract `rules:` and assemble the final rule order (bypass rules → optional `bypass_china` GEOIP rule → subscription rules → `MATCH,PROXY`) exactly as specified in `docs/SUBSCRIPTIONS.md` §5.2 and §5.4, and `docs/NETWORK.md` §14.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/config.sh`
- **Dependencies:** T-046
- **Acceptance criteria:**
  1. Extracts `rules:` using the same column-0 approach, generalized further from T-045/T-046 (all three extractions should share one parameterized helper rather than three near-duplicate `awk` scripts, keeping the module within its line budget).
  2. Prepends the static private/reserved-range bypass rules (matching the `bypass_ipv4` ranges in `docs/NETWORK.md` §4.1) before any subscription-sourced rule, unconditionally.
  3. Injects `GEOIP,CN,DIRECT` immediately after the bypass rules and before subscription rules, if and only if `bypass_china=1`; omits it entirely when `bypass_china=0`.
  4. Appends `MATCH,PROXY` as the final rule, always, regardless of what the subscription's own rules contain — even if the subscription itself included a catch-all rule (which is superseded, since it comes earlier in the list and Mihomo's first-match evaluation means SubMiHomo's own bypass/`MATCH,PROXY` rules govern precedence for their respective positions).
- **Expected output:** A correct, safety-ordered rules assembler.
- **Estimated complexity:** Complex

### T-048 — Write config_build_dns_section() Function

- **Phase:** 8 — Config generator
- **Purpose:** Render the correct `dns:` block for the configured `dns_mode`, per `docs/NETWORK.md` §9.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/config.sh`
- **Dependencies:** T-044
- **Acceptance criteria:**
  1. When `dns_mode=fake-ip`, renders `enhanced-mode: fake-ip`, the `198.18.0.0/15` fake-ip range, a `fake-ip-filter` list, `nameserver`/`fallback`/`fallback-filter` sections matching `docs/NETWORK.md` §9.1.
  2. When `dns_mode=real-ip`, renders `enhanced-mode: normal` with a plain `nameserver` list, matching §9.2, and omits the fake-ip-specific keys entirely.
  3. The listener is always `127.0.0.1:1053` (the constant `DNS_PORT`), regardless of mode.
- **Expected output:** A correctly mode-branching DNS section generator.
- **Estimated complexity:** Medium

### T-049 — Write config_generate() Main Orchestration Function

- **Phase:** 8 — Config generator
- **Purpose:** Assemble T-043–T-048 into the single public entry point documented in `docs/COMPONENTS.md` §3.2.2–§3.2.3.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/config.sh` (final section; combined file with T-044–T-048 must remain ≤ 200 lines)
- **Dependencies:** T-045, T-046, T-047, T-048
- **Acceptance criteria:**
  1. Executes the exact 12-step sequence in `docs/COMPONENTS.md` §3.2.3: source `core.sh`, read UCI, read template, token-substitute, extract three sections, splice into the template, `mkdir -p $RUN_DIR`, write `$RUN_DIR/config.yaml`, validate with `mihomo -t -f`, return 0/1.
  2. A missing template file, a missing subscription file, a `sed` substitution failure, an unwritable `$RUN_DIR`, or a `mihomo -t` failure each produce a distinct `log_error` and a non-zero return — with no partial or corrupt `config.yaml` left in place on any failure path (the file is written completely or not updated at all, e.g., via a write-to-temp-then-rename pattern).
  3. An empty (but syntactically present) `proxies:` extraction logs `log_warn` and continues rather than failing outright (Mihomo may still start with `MATCH,DIRECT`-equivalent behavior), per `docs/COMPONENTS.md` §3.2.7.
  4. Combined `config.sh` (T-044–T-049) is ≤ 200 lines, verified with `wc -l`.
- **Expected output:** The complete, single public `config_generate()` entry point.
- **Estimated complexity:** Complex

### T-050 — Test Config Generation with Sample Subscriptions

- **Phase:** 8 — Config generator
- **Purpose:** Confirm `config_generate()` behaves correctly across a representative range of real-world subscription shapes.
- **Files affected:** None (verification task; may add fixtures under a test-only directory)
- **Dependencies:** T-049
- **Acceptance criteria:**
  1. A flat, group-less subscription (proxies only); a subscription with nested proxy-groups; and a large (100+ proxy) subscription each produce a `config.yaml` whose extracted proxy/group/rule counts match independently computed ground truth (no silent truncation).
  2. Re-running `config_generate()` twice against the same subscription and UCI state produces byte-identical output (deterministic generation, no timestamp/ordering nondeterminism that would complicate diagnostics or testing).
  3. Both `dns_mode` values are exercised against at least one fixture each, confirming the correct `dns:` block per T-048.
- **Expected output:** A confirmed, fixture-tested config generator.
- **Estimated complexity:** Medium

### T-051 — Test Config Validation with mihomo -t

- **Phase:** 8 — Config generator
- **Purpose:** Confirm the final validation gate genuinely catches invalid output before it can ever reach a running Mihomo instance.
- **Files affected:** None (verification task)
- **Dependencies:** T-050
- **Acceptance criteria:**
  1. Every fixture from T-050 passes `mihomo -t -f` against its generated `config.yaml`.
  2. A deliberately corrupted subscription (e.g., a proxy-group referencing a non-existent proxy name) results in `config_generate()` returning non-zero, with the underlying `mihomo -t` failure text captured in the `log_error` message.
  3. `start_service()` (once wired in Phase 11's integration point) genuinely aborts startup — no routing, DNS, or firewall changes occur — when `config_generate()` returns non-zero, matching the failure-mode design in `docs/BOOT.md` §5.
- **Expected output:** A confirmed, unbypassable validation gate.
- **Estimated complexity:** Medium

---

## 9. Phase 9 — DNS Manager

### T-052 — Write dns_setup() Function

- **Phase:** 9 — DNS manager
- **Purpose:** Forward all dnsmasq-served DNS queries to Mihomo's DNS listener, per `docs/NETWORK.md` §10.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/dns.sh` (first section of the eventual ≤ 80-line file)
- **Dependencies:** T-049 (the DNS port is fixed by the generated config Mihomo will run against)
- **Acceptance criteria:**
  1. Writes `/etc/dnsmasq.d/submihomo.conf` containing `no-resolv` and `server=127.0.0.1#1053` (or the documented equivalent forwarding directive), matching `docs/COMPONENTS.md` §3.4.3.
  2. Signals dnsmasq via `HUP` (not a full `restart`/`reload_config` that could interrupt DHCP), per `docs/NETWORK.md` §10.
  3. If `/etc/dnsmasq.d/` does not exist, returns non-zero with `log_error` rather than silently doing nothing.
  4. If dnsmasq is not currently running, logs `log_warn` and returns success (non-fatal), matching `docs/COMPONENTS.md` §3.4.7.
- **Expected output:** A working DNS-forwarding setup primitive.
- **Estimated complexity:** Simple

### T-053 — Write dns_teardown() Function

- **Phase:** 9 — DNS manager
- **Purpose:** Cleanly remove the forwarding configuration so dnsmasq reverts to its original upstream resolvers.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/dns.sh` (combined file with T-052 must remain ≤ 80 lines)
- **Dependencies:** T-052
- **Acceptance criteria:**
  1. Removes `/etc/dnsmasq.d/submihomo.conf` and signals dnsmasq via `HUP`.
  2. Calling teardown when the conf file is already absent logs `log_warn` and returns success (idempotent, non-fatal), per `docs/COMPONENTS.md` §3.4.7.
  3. After teardown, dnsmasq resolves using its pre-SubMiHomo upstream configuration (verified by comparing resolved results before setup, after setup, and after teardown for a fixed test domain).
- **Expected output:** A complete, idempotent `dns_setup()`/`dns_teardown()` pair within budget.
- **Estimated complexity:** Simple

### T-054 — Test dnsmasq Config Creation in Both DNS Modes

- **Phase:** 9 — DNS manager
- **Purpose:** Confirm DNS forwarding functions correctly regardless of `dns_mode`.
- **Files affected:** None (verification task)
- **Dependencies:** T-053, T-048 (both DNS modes must be generatable in the Mihomo config to test against)
- **Acceptance criteria:**
  1. With `dns_mode=fake-ip`, a LAN client's DNS query for a known-good filtered domain resolves to an address within `198.18.0.0/15`.
  2. With `dns_mode=real-ip`, the same query resolves to the domain's genuine public IP (not a fake-ip address).
  3. `/etc/dnsmasq.d/submihomo.conf`'s content is identical regardless of `dns_mode` (the mode only affects Mihomo's own DNS listener behavior, not the dnsmasq forwarding directive itself) — confirming the correct separation of concerns between `dns.sh` and `config.sh`.
- **Expected output:** Confirmed correct DNS behavior across both modes.
- **Estimated complexity:** Simple

### T-055 — Test dnsmasq Reload Behavior

- **Phase:** 9 — DNS manager
- **Purpose:** Confirm the `HUP`-based reload does not disrupt DHCP, per the rationale in `docs/COMPONENTS.md` §3.4.4 and `docs/NETWORK.md` §10.
- **Files affected:** None (verification task)
- **Dependencies:** T-054
- **Acceptance criteria:**
  1. An active DHCP lease survives a `dns_setup()`/`dns_teardown()` cycle without being renewed/reassigned (verified by comparing the lease table before and after).
  2. dnsmasq's PID does not change across the `HUP` signal (proving it was reloaded, not restarted).
  3. A `dns_setup()` call while dnsmasq is not running logs the documented warning and does not crash the calling `start_service()` sequence.
- **Expected output:** Confirmed DHCP-safe reload behavior.
- **Estimated complexity:** Simple

---

## 10. Phase 10 — Routing Manager

### T-056 — Write routing_setup() Function

- **Phase:** 10 — Routing manager
- **Purpose:** Install the two kernel policy-routing constructs TPROXY depends on, per `docs/NETWORK.md` §8 and `docs/COMPONENTS.md` §3.3.3.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/routing.sh` (first section of the eventual ≤ 100-line file)
- **Dependencies:** T-018 (a running service context to install routing state for)
- **Acceptance criteria:**
  1. Checks `ip route show table $RT_TABLE` before adding; only issues `ip route add local default dev lo table 100` if no such route already exists.
  2. Checks `ip rule show` before adding; only issues `ip rule add fwmark 1 table 100 priority 1000` if no matching rule already exists.
  3. Running the function twice in a row results in exactly one route and one rule (idempotency verified via `ip rule show`/`ip route show table 100` diffing before/after each call).
  4. A missing `ip` binary results in `log_error` and a non-zero return, not a silent no-op.
- **Expected output:** A correct, idempotent routing setup primitive.
- **Estimated complexity:** Simple

### T-057 — Write routing_teardown() Function

- **Phase:** 10 — Routing manager
- **Purpose:** Cleanly remove both routing constructs, tolerating their absence.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/routing.sh` (combined file with T-056 must remain ≤ 100 lines)
- **Dependencies:** T-056
- **Acceptance criteria:**
  1. Removes the fwmark rule and the table-100 local route, in that order, each with errors redirected/ignored (`2>/dev/null`) since a missing target during teardown is expected, not exceptional.
  2. Calling teardown against a system where setup never ran completes with exit `0` and no error output.
  3. After teardown, `ip rule show` and `ip route show table 100` show zero SubMiHomo-owned entries.
- **Expected output:** A complete, budget-compliant `routing_setup()`/`routing_teardown()` pair.
- **Estimated complexity:** Simple

### T-058 — Test ip rule and route Creation

- **Phase:** 10 — Routing manager
- **Purpose:** Confirm the routing constructs actually deliver fwmark-1 packets locally, as designed.
- **Files affected:** None (verification task)
- **Dependencies:** T-057
- **Acceptance criteria:**
  1. A synthetically fwmark-1-tagged local packet (e.g., via a test `iptables`/`nft`-marked loopback probe, or observed once Phase 11's firewall exists) is routed via table 100 to the local default route, confirmed via `ip route get` with the appropriate mark.
  2. The main routing table is provably unaffected (a `ip route show` diff before/after setup shows changes scoped only to table 100 and the rule database, never the main table).
- **Expected output:** Confirmed correct routing-table semantics.
- **Estimated complexity:** Simple

### T-059 — Test Idempotent Routing Setup

- **Phase:** 10 — Routing manager
- **Purpose:** Guard specifically against the "second `service submihomo restart` fails startup entirely" regression called out as a key risk in `docs/ROADMAP.md` §2 (Phase 10).
- **Files affected:** None (verification task)
- **Dependencies:** T-058
- **Acceptance criteria:**
  1. `routing_setup(); routing_setup(); routing_setup()` (three consecutive calls) all return `0`, and the system state after the third call is identical to the state after the first.
  2. A full `service submihomo restart` cycle repeated five times in a row never fails at the routing step.
- **Expected output:** Confirmed, regression-proof idempotency.
- **Estimated complexity:** Simple

---

## 11. Phase 11 — Firewall Manager

### T-060 — Write firewall.sh nftables Table Definition

- **Phase:** 11 — Firewall manager
- **Purpose:** Construct the complete `inet submihomo` nftables ruleset (sets and both chains) as a single string/heredoc suitable for atomic application, per `docs/NETWORK.md` §4.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/firewall.sh` (first section of the eventual ≤ 150-line file)
- **Dependencies:** T-049 (needs the fixed `TPROXY_PORT`/`FWMARK`/`BYPASS_MARK` values the generated config will actually use)
- **Acceptance criteria:**
  1. Defines the static `bypass_ipv4` set with exactly the ranges listed in `docs/COMPONENTS.md` §3.5.3 (`0.0.0.0/8`, `10.0.0.0/8`, `127.0.0.0/8`, `169.254.0.0/16`, `172.16.0.0/12`, `192.168.0.0/16`, `224.0.0.0/4`, `240.0.0.0/4`).
  2. Defines a separate, dynamically populated `user_bypass_ipv4` set (kept distinct from the static set, per the "dual sets" rationale in `docs/NETWORK.md` §13).
  3. Defines the `prerouting` chain (hook `prerouting`, priority `mangle - 1`) and `output` chain (hook `output`, type `route`, priority `mangle - 1`) exactly matching the rule bodies in `docs/COMPONENTS.md` §3.5.3.
  4. The entire definition is a single string/heredoc suitable for one `nft -f -` invocation (no multi-step incremental rule application).
- **Expected output:** A correct, ready-to-apply ruleset template.
- **Estimated complexity:** Complex

### T-061 — Write firewall_setup() with Dynamic Bypass Set Population

- **Phase:** 11 — Firewall manager
- **Purpose:** Apply the T-060 ruleset atomically, with the `user_bypass_ipv4` set populated from the live UCI bypass list.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/firewall.sh`
- **Dependencies:** T-060, T-022 (bypass-list validation from Phase 5)
- **Acceptance criteria:**
  1. If `inet submihomo` already exists, it is deleted and fully recreated (replace-in-full strategy), per `docs/COMPONENTS.md` §3.5.4 — never incrementally patched.
  2. Every validated UCI bypass address is added to `user_bypass_ipv4`; any entry that fails IPv4-CIDR validation (including well-formed IPv6 CIDRs) is skipped with a `log_warn`, never causing the whole `firewall_setup()` call to fail.
  3. `nft -f -` application is atomic — if any single rule is rejected by the kernel, no partial table is left behind (verified by forcing a deliberately invalid rule in a test build and confirming `nft list table inet submihomo` shows either the complete previous table or nothing, never a half-applied one).
  4. A missing `nft` binary results in `log_error` and non-zero return.
- **Expected output:** A correct, atomic, UCI-driven firewall setup primitive.
- **Estimated complexity:** Complex

### T-062 — Write firewall_teardown() Function

- **Phase:** 11 — Firewall manager
- **Purpose:** Remove the entire `inet submihomo` table in one atomic operation, guaranteed to never touch any other table.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/firewall.sh` (combined file with T-060/T-061/T-063 must remain ≤ 150 lines)
- **Dependencies:** T-061
- **Acceptance criteria:**
  1. Executes `nft delete table inet submihomo` as a single atomic operation.
  2. Calling teardown when the table does not exist logs `log_warn` and returns `0`, never an error.
  3. `nft list ruleset` before and after teardown is identical outside of the `inet submihomo` table's removal — `inet fw4` and every other table are provably untouched (byte-for-byte diff of their respective `nft list table` output).
- **Expected output:** A complete, safe `firewall_setup()`/`firewall_teardown()` pair.
- **Estimated complexity:** Simple

### T-063 — Write firewall_bypass_china() Integration Point

- **Phase:** 11 — Firewall manager
- **Purpose:** Wire the `bypass_china` UCI toggle through to its actual implementation point — the Mihomo rules GEOIP injection in `config.sh` (T-047) — and document why this is deliberately not an nftables rule, per `docs/NETWORK.md` §14.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/firewall.sh` (a short comment/no-op guard confirming `firewall.sh` correctly does **not** attempt to implement `bypass_china` at the nftables layer), cross-referenced against `SubMiHomo/files/usr/lib/submihomo/config.sh` (T-047, already implements the real logic)
- **Dependencies:** T-047, T-062
- **Acceptance criteria:**
  1. `firewall.sh` contains no GEOIP or per-country logic whatsoever — confirmed by inspection that `bypass_china` never appears in any `nft` rule string.
  2. Toggling `bypass_china` via UCI and regenerating the config (T-049) changes the presence/absence of `GEOIP,CN,DIRECT` in the generated `rules:` section, without requiring any change to the applied nftables table.
  3. This boundary (UCI toggle → Mihomo rule engine, never → nftables) is explicitly asserted by a test that toggles `bypass_china` off/on/off and confirms `nft list table inet submihomo` is byte-identical across all three states.
- **Expected output:** A confirmed, correctly-layered implementation of the `bypass_china` feature with no logic duplicated or misplaced across modules.
- **Estimated complexity:** Simple

### T-064 — Test nftables Table Creation and Packet Marking

- **Phase:** 11 — Firewall manager
- **Purpose:** Prove the firewall module actually intercepts and marks traffic as designed — the single highest-risk verification in the entire project.
- **Files affected:** None (verification task)
- **Dependencies:** T-061
- **Acceptance criteria:**
  1. A LAN client's TCP connection to a non-bypassed destination appears as a new connection in Mihomo's own `/connections` API output (confirming genuine TPROXY interception, not just a rule existing on paper).
  2. A LAN client's connection to an address within `bypass_ipv4` or `user_bypass_ipv4` does **not** appear in Mihomo's connection list and is routed normally.
  3. Mihomo's own outbound connections (marked `BYPASS_MARK=255`) are confirmed, via `conntrack`/`nft` rule counters, to hit the `return` rule in both `prerouting` and `output` chains and are never re-marked with `FWMARK=1` — the specific mechanism that prevents a routing loop, per `docs/COMPONENTS.md` §3.13.4.
  4. Router-originated traffic (e.g., a `wget` run directly on the router shell, not from a LAN client) is also correctly intercepted via the `output` chain.
- **Expected output:** Confirmed, empirically verified TPROXY interception with no routing loop.
- **Estimated complexity:** Complex

### T-065 — Test Firewall Teardown Removes All Rules

- **Phase:** 11 — Firewall manager
- **Purpose:** Confirm the project-wide acceptance criterion "disabling the service completely removes all routing/DNS/firewall changes" (`docs/ROADMAP.md` §6, item 3) holds specifically at the firewall layer.
- **Files affected:** None (verification task)
- **Dependencies:** T-062, T-064
- **Acceptance criteria:**
  1. After `firewall_teardown()`, `nft list ruleset` shows no `inet submihomo` table.
  2. `inet fw4` (captured via `nft list table inet fw4` before service start) is byte-for-byte identical after a full setup → teardown cycle.
  3. Post-teardown, a LAN client's traffic that was previously intercepted now flows normally (no TPROXY redirection), confirmed by its absence from Mihomo's connection list (or, if Mihomo itself is also stopped at this point, by direct reachability of the destination without proxy involvement).
- **Expected output:** Confirmed complete, isolated firewall cleanup.
- **Estimated complexity:** Medium

---

## 12. Phase 12 — LuCI Frontend

### T-066 — Write LuCI menu.d JSON

- **Phase:** 12 — LuCI frontend
- **Purpose:** Register the five-page SubMiHomo application in the LuCI navigation tree, per `docs/LUCI.md` §2.
- **Files affected:** `SubMiHomo/files/usr/share/luci/menu.d/luci-app-submihomo.json`
- **Dependencies:** T-006 (package must exist to install this file), T-033 (ACL scope name must exist for `depends.acl` gating)
- **Acceptance criteria:**
  1. Defines a parent node `admin/services/submihomo` (order 60) whose `action.path` resolves to `submihomo/overview`, plus four child nodes: `subscription` (order 10), `settings` (order 20), `proxies` (order 30), `logs` (order 40) — matching `docs/LUCI.md` §2.1 and §2.3 exactly.
  2. `depends.acl` on the parent node references the `luci-app-submihomo` ACL scope, so the entire menu tree (including all four children) is hidden from sessions without at least read access, per `docs/LUCI.md` §2.4.
  3. The tab bar renders in the documented left-to-right order: `Overview | Subscription | Settings | Proxies | Logs`.
- **Expected output:** A correctly ordered, ACL-gated menu registration.
- **Estimated complexity:** Simple

### T-067 — Write overview.js View

- **Phase:** 12 — LuCI frontend
- **Purpose:** Implement the primary status/dashboard page.
- **Files affected:** `SubMiHomo/files/htdocs/luci-static/resources/view/submihomo/overview.js`
- **Dependencies:** T-066, T-024, T-025, T-031 (needs `status`, `start`/`stop`, `get_proxies` RPC methods)
- **Acceptance criteria:**
  1. Implements `view.extend({ load, render })`, declaring `rpc.declare()` bindings for `status`, `start`, `stop`, `get_proxies` (and, once Phase 13 lands, `run_diagnostics` — the placeholder call is wired now per T-028's stable stub).
  2. Displays a status card (running/stopped, Mihomo version, PID, uptime), an enable/disable toggle wired to `start`/`stop`, and a summary of the active top-level `PROXY` group's current selection.
  3. Every RPC call site uses `L.resolveDefault()` or an explicit `.catch()` so a stopped service or unreachable API never produces an unhandled promise rejection or a blank page.
  4. File is ≤ 300 lines.
- **Expected output:** A working Overview page.
- **Estimated complexity:** Complex

### T-068 — Write subscription.js View

- **Phase:** 12 — LuCI frontend
- **Purpose:** Implement subscription URL management and manual update triggering.
- **Files affected:** `SubMiHomo/files/htdocs/luci-static/resources/view/submihomo/subscription.js`
- **Dependencies:** T-066, T-026, T-029 (needs `get_config`/`set_config`, `update_subscription`)
- **Acceptance criteria:**
  1. Renders a text input bound to `subscription_url` and a dropdown bound to `subscription_update_interval`, using standalone `ui.Textfield`/`ui.Select` widgets (not `form.Map`), per the rationale in `docs/LUCI.md` §1.3.
  2. A "Save & Update Now" button calls `set_config()` followed by `update_subscription()`, showing a blocking progress indicator (`ui.showModal()`) during the update and an `ui.addNotification()` toast on completion or failure.
  3. Displays last-update timestamp and current subscription validity, sourced from a subscription-status equivalent surfaced through the RPC layer.
  4. File is ≤ 300 lines.
- **Expected output:** A working Subscription page.
- **Estimated complexity:** Complex

### T-069 — Write settings.js View

- **Phase:** 12 — LuCI frontend
- **Purpose:** Implement the full UCI configuration form.
- **Files affected:** `SubMiHomo/files/htdocs/luci-static/resources/view/submihomo/settings.js`
- **Dependencies:** T-066, T-026, T-025
- **Acceptance criteria:**
  1. Uses `form.Map`/`form.Section`/`form.Value` (per `docs/LUCI.md` §1.3) to render every option from `docs/UCI.md` §3.13: `dns_mode`, `log_level`, `external_controller_port`, `external_controller_secret` (password-masked input), `allow_lan_access`, the dynamic `bypass` address list, `dashboard_repo`, `subscription_user_agent`.
  2. On save, calls `set_config()` for each changed option and, for options flagged as service-impacting (e.g., `dns_mode`, ports), offers/performs a `restart()` call.
  3. Client-side field validation mirrors the server-side rules from T-019 (range checks, enum checks) so obviously invalid input is caught before an RPC round-trip, without being the sole line of defense (the RPC layer still re-validates).
  4. File is ≤ 300 lines.
- **Expected output:** A working Settings page.
- **Estimated complexity:** Complex

### T-070 — Write proxies.js View

- **Phase:** 12 — LuCI frontend
- **Purpose:** Implement live proxy-group browsing and manual selection/testing.
- **Files affected:** `SubMiHomo/files/htdocs/luci-static/resources/view/submihomo/proxies.js`
- **Dependencies:** T-066, T-031, T-032
- **Acceptance criteria:**
  1. Renders a `ui.Table` of proxy groups (name, type, current selection, member proxies), refreshed via `poll.add()`.
  2. For `select`-type groups, provides a dropdown that switches the active proxy, calling the group-selection RPC path (built atop the `get_proxies`/Mihomo-API integration from Phase 6).
  3. A per-proxy "test" control calls `test_connection` and displays the returned latency (or a clear failure indicator).
  4. File is ≤ 300 lines.
- **Expected output:** A working Proxies page.
- **Estimated complexity:** Complex

### T-071 — Write logs.js View

- **Phase:** 12 — LuCI frontend
- **Purpose:** Implement the syslog viewer page.
- **Files affected:** `SubMiHomo/files/htdocs/luci-static/resources/view/submihomo/logs.js`
- **Dependencies:** T-066, T-027
- **Acceptance criteria:**
  1. Renders a text area showing the last N lines from `get_logs`, with a line-count selector (50/100/200/500) and an auto-refresh toggle using `poll.add()` at a 5-second interval.
  2. A client-side filter input greps the currently displayed lines without an additional RPC round-trip per keystroke.
  3. Auto-refresh stops when navigating away from the page (verified `poll` cleanup on view teardown, per the LuCI JS lifecycle).
  4. File is ≤ 300 lines.
- **Expected output:** A working Logs page.
- **Estimated complexity:** Medium

### T-072 — Test All LuCI Pages Load Without JavaScript Errors

- **Phase:** 12 — LuCI frontend
- **Purpose:** Confirm the complete Phase 12 deliverable across every realistic service state.
- **Files affected:** None (verification task)
- **Dependencies:** T-067 through T-071
- **Acceptance criteria:**
  1. A headless-browser smoke test loads all five pages against three service states — stopped, running-with-no-subscription, running-with-active-subscription — and asserts zero browser console errors in all 15 combinations.
  2. Every page's primary data element (status card, subscription form, settings form, proxy table, log textarea) is present and populated with the expected data (not a permanently-loading spinner) within a bounded timeout.
  3. Navigating between all five tabs in sequence produces no memory leak or duplicate polling interval (verified by confirming only one active `poll` timer exists at any time).
- **Expected output:** Confirmed, robust LuCI page-load behavior.
- **Estimated complexity:** Medium

### T-073 — Test Form Submission and UCI Update Flow

- **Phase:** 12 — LuCI frontend
- **Purpose:** Confirm the complete save round-trip works end-to-end through the browser, not just at the RPC layer.
- **Files affected:** None (verification task)
- **Dependencies:** T-072
- **Acceptance criteria:**
  1. Changing a value on the Settings page and clicking Save results in the corresponding UCI option being updated on the router (`uci get` reflects the new value) and a success toast rendered in the browser.
  2. Submitting an invalid value (e.g., an out-of-range port) surfaces a clear, field-level or toast-level error and does **not** silently accept the value.
  3. The Subscription page's "Save & Update Now" flow results in `current.yaml` reflecting the newly saved subscription URL's content after the browser-visible progress indicator completes.
  4. Milestone M3 (`docs/ROADMAP.md` §5) acceptance check passes: pasting a subscription URL and clicking Apply results in verifiable, proxied LAN traffic.
- **Expected output:** Confirmed Milestone M3 — full feature completeness.
- **Estimated complexity:** Medium

---

## 13. Phase 13 — Diagnostics

### T-074 — Implement All 12 Diagnostic Check Functions

- **Phase:** 13 — Diagnostics
- **Purpose:** Implement the complete, read-only health-check suite covering every architectural layer, so both `run_diagnostics` (RPC) and `submihomo-ctl test` (CLI) can share one implementation.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/core.sh` is **not** extended further for this (it is already at its 150-line budget) — diagnostic check functions are implemented as a dedicated section within `SubMiHomo/files/usr/bin/submihomo-ctl` (shared by both call paths, since `submihomo-ctl` already depends on every other module per `docs/COMPONENTS.md` §3.9.4) and invoked identically from the rpcd plugin's fixed-command bridge described in §0.4
- **Dependencies:** T-038 (subscription), T-049 (config), T-057 (routing), T-053 (dns), T-062 (firewall), T-022 (UCI)
- **Acceptance criteria:**
  1. Implements exactly these 12 checks: (1) Mihomo binary present and executable at `/usr/bin/mihomo`; (2) Mihomo process running and matching the procd-supervised instance; (3) Mihomo REST API reachable (`GET /` on `127.0.0.1:<external_controller_port>` returns success); (4) `/var/run/submihomo/config.yaml` present and passes `mihomo -t -f`; (5) `$SUB_DIR/current.yaml` present and non-empty; (6) nftables table `inet submihomo` present with the expected set/chain names; (7) policy routing rule present (`ip rule show` contains the fwmark-1/table-100 rule); (8) routing table 100 contains the expected local default route; (9) `/etc/dnsmasq.d/submihomo.conf` present and dnsmasq running; (10) end-to-end DNS resolution through `127.0.0.1:1053` succeeds for a fixed test domain; (11) UCI configuration internally consistent (no port collisions, all enum values valid, `config_version` at the expected value); (12) overlay filesystem free space above a documented minimum threshold.
  2. Every check is purely observational — no check modifies any file, process, routing, DNS, or firewall state under any circumstance, verified by diffing full system state (routing tables, nftables ruleset, dnsmasq config, UCI content) before and after a full diagnostic run.
  3. Each check returns a structured `{name, passed, detail}` result consumable by both the RPC method and the CLI formatter.
- **Expected output:** A complete, shared, side-effect-free diagnostic suite.
- **Estimated complexity:** Complex

### T-075 — Wire Diagnostic Checks into run_diagnostics() RPC

- **Phase:** 13 — Diagnostics
- **Purpose:** Complete the Phase 6 stub (T-028) with real check logic, without altering its already-fixed outer JSON shape.
- **Files affected:** `SubMiHomo/files/usr/lib/rpcd/submihomo`
- **Dependencies:** T-074, T-028
- **Acceptance criteria:**
  1. `ubus call submihomo run_diagnostics '{}'` now returns the real 12-entry array with genuine `passed`/`detail` values, replacing the Phase 6 placeholder — the outer array-of-12-named-entries shape is unchanged from T-028, so no LuCI code written in Phase 12 needs modification.
  2. The RPC method invokes the shared check functions from T-074 via the same fixed, non-interpolated shell-invocation bridge documented in §0.4 (diagnostics is read-only, but the same injection-avoidance discipline still applies).
  3. A full diagnostic run completes within a bounded time (no check hangs indefinitely; each network-touching check — API reachability, DNS resolution — has an explicit timeout).
- **Expected output:** A fully functional `run_diagnostics` RPC method.
- **Estimated complexity:** Medium

### T-076 — Add Diagnostics Display to LuCI Overview Page

- **Phase:** 13 — Diagnostics
- **Purpose:** Surface the 12 diagnostic results to operators without requiring CLI access.
- **Files affected:** `SubMiHomo/files/htdocs/luci-static/resources/view/submihomo/overview.js` (amendment; combined file must remain ≤ 300 lines)
- **Dependencies:** T-075, T-067
- **Acceptance criteria:**
  1. A "Run Diagnostics" button calls `run_diagnostics` and renders all 12 results in a `ui.Table`, with a clear pass/fail visual indicator per row and the `detail` text visible (e.g., on hover or inline).
  2. The button is available to `luci-user`-scoped sessions (read-only ACL grant per T-033) as well as `luci-admin`.
  3. Running diagnostics does not require a page reload and does not interfere with the page's existing status polling.
- **Expected output:** A working, ACL-appropriate diagnostics panel on the Overview page.
- **Estimated complexity:** Medium

### T-077 — Add submihomo-ctl test Command

- **Phase:** 13 — Diagnostics
- **Purpose:** Expose the same diagnostic suite at the CLI for headless/SSH-only operators, per `docs/COMPONENTS.md` §3.9.3.
- **Files affected:** `SubMiHomo/files/usr/bin/submihomo-ctl`
- **Dependencies:** T-074
- **Acceptance criteria:**
  1. `submihomo-ctl test` runs all 12 checks and prints a human-readable pass/fail summary, exiting `0` if all pass and `1` if any fail.
  2. Safely runnable at any time, including against a fully running production instance, with zero side effects (same guarantee as T-074, re-verified at the CLI entry point specifically).
  3. Output is scriptable (e.g., one line per check, a parseable pass/fail token) so it can be used in automated regression scripts (T-096).
- **Expected output:** A working `submihomo-ctl test` command sharing logic with the RPC path.
- **Estimated complexity:** Simple

### T-078 — Test Diagnostics on Working Installation

- **Phase:** 13 — Diagnostics
- **Purpose:** Confirm the baseline "everything is fine" case reports cleanly, with no false positives.
- **Files affected:** None (verification task)
- **Dependencies:** T-075, T-077
- **Acceptance criteria:**
  1. On a fully configured, running installation with a valid subscription, all 12 checks report `passed: true` via both `run_diagnostics` (RPC) and `submihomo-ctl test` (CLI), and the two call paths agree on every result.
  2. No check produces a false negative under normal, expected conditions (e.g., check 12's disk-space threshold is not so aggressive that a typical, healthy router trips it).
- **Expected output:** Confirmed zero-false-positive baseline behavior.
- **Estimated complexity:** Simple

### T-079 — Test Diagnostics on Broken Installation

- **Phase:** 13 — Diagnostics
- **Purpose:** Confirm each check fails precisely and only under its corresponding fault condition — the fault-injection matrix promised in `docs/ROADMAP.md` §2 (Phase 13).
- **Files affected:** None (verification task)
- **Dependencies:** T-078
- **Acceptance criteria:**
  1. Twelve independent fault-injection scenarios (one per check: removed binary, killed process, blocked API port, corrupted config, removed subscription, deleted nftables table, removed routing rule, removed default route in table 100, removed dnsmasq drop-in, broken DNS forwarding, invalid UCI value, simulated full overlay filesystem) each cause exactly the corresponding check to fail, with the other 11 checks unaffected (no false positives cascading from one broken subsystem to an unrelated check's result).
  2. Each failure's `detail` text is specific enough that an operator reading only that string could identify the actual root cause without consulting source code.
  3. Restoring each broken condition individually causes only that check to return to `passed: true`, confirming no check result is "sticky" or cached incorrectly.
- **Expected output:** A confirmed, precise, actionable diagnostic suite — ready for Phase 14/16 regression use.
- **Estimated complexity:** Complex

---

## 14. Phase 14 — Installer

### T-080 — Write submihomo-ctl CLI Script

- **Phase:** 14 — Installer
- **Purpose:** Complete the full CLI command surface described in `docs/COMPONENTS.md` §3.9.2, beyond the `test` command already added in T-077.
- **Files affected:** `SubMiHomo/files/usr/bin/submihomo-ctl` (combined file with T-077 must remain ≤ 150 lines)
- **Dependencies:** T-077, T-038, T-087 (dashboard, once available — may be stubbed until Phase 15 completes)
- **Acceptance criteria:**
  1. Implements `status`, `start`, `stop`, `restart` (delegating to `service submihomo <action>`), `update` (sourcing `subscription.sh`, calling `subscription_update()`), `dashboard` (sourcing `dashboard.sh`, calling `dashboard_download()`), `logs [N]` (`logread -e submihomo`, tailing `N` lines, default 50), `test` (from T-077), and `version` (prints SubMiHomo package version, Mihomo version via `mihomo -v`, and dashboard version via `dashboard_version()`).
  2. Every command prints human-readable diagnostics to stderr on failure and sets a non-zero exit code, per `docs/COMPONENTS.md` §3.9.6.
  3. `submihomo-ctl` never writes UCI configuration directly and never invokes `nft`/`ip`/dnsmasq commands directly — always delegates to the shell modules, per `docs/COMPONENTS.md` §3.9.7.
  4. File is ≤ 150 lines total (T-077 + T-080 combined), verified with `wc -l`.
- **Expected output:** The complete `submihomo-ctl` CLI tool.
- **Estimated complexity:** Medium

### T-081 — Write install.sh

- **Phase:** 14 — Installer
- **Purpose:** Implement the single-command bootstrap path described in `docs/FILESYSTEM.md` §2.8 and promised in `README.md` (T-003).
- **Files affected:** `SubMiHomo/install/install.sh`
- **Dependencies:** T-080, T-008 (a real APK feed/repository must exist to point at)
- **Acceptance criteria:**
  1. Verifies the target is OpenWrt 25+ by reading `/etc/openwrt_release`, aborting with a clear error on any earlier version or non-OpenWrt system.
  2. Downloads and installs the APK repository public key, adds the repository URL to `/etc/apk/repositories`, runs `apk update`, then `apk add submihomo luci-app-submihomo`.
  3. Enables (`/etc/init.d/submihomo enable`) and starts (`/etc/init.d/submihomo start`) the service, then prints the LuCI URL and a reminder to configure a subscription.
  4. Every step checks its command's return code; any failure aborts the script immediately with a clear message rather than continuing into an ambiguous partial-install state.
- **Expected output:** A working one-command installer.
- **Estimated complexity:** Medium

### T-082 — Write update.sh

- **Phase:** 14 — Installer
- **Purpose:** Let an existing installation be upgraded to the latest published version without losing configuration.
- **Files affected:** `SubMiHomo/install/update.sh`
- **Dependencies:** T-081
- **Acceptance criteria:**
  1. Runs `apk update`, then `apk upgrade submihomo luci-app-submihomo`, then `/etc/init.d/submihomo restart`.
  2. UCI configuration (`/etc/config/submihomo`) and subscription data (`/etc/submihomo/subscriptions/`) are provably unchanged before and after the script runs (byte-for-byte comparison), satisfying project-wide acceptance criterion 10.
  3. A failed `apk upgrade` (e.g., network failure) leaves the previously installed version fully functional — the script never leaves the router in a half-upgraded state.
- **Expected output:** A working, configuration-preserving update path.
- **Estimated complexity:** Simple

### T-083 — Write uninstall.sh

- **Phase:** 14 — Installer
- **Purpose:** Let a user completely and cleanly remove SubMiHomo, including all kernel-level state, per `docs/FILESYSTEM.md` §2.8.
- **Files affected:** `SubMiHomo/install/uninstall.sh`
- **Dependencies:** T-081
- **Acceptance criteria:**
  1. Stops and disables the service (triggering full `firewall_teardown()`/`dns_teardown()`/`routing_teardown()` via the normal `stop_service()` path), then runs `apk del submihomo luci-app-submihomo`.
  2. Removes the APK repository entry and its key from `/etc/apk/repositories`/the key store.
  3. Prompts for confirmation before removing `/etc/submihomo/subscriptions/` (user data) and removes `/usr/share/submihomo/` (dashboard) unconditionally (it is downloaded, reproducible content, not user data).
  4. Prints a final confirmation summarizing exactly what was and was not removed.
- **Expected output:** A working, complete, confirmation-guarded uninstaller.
- **Estimated complexity:** Medium

### T-084 — Test One-Line Install on Clean OpenWrt

- **Phase:** 14 — Installer
- **Purpose:** Confirm project-wide acceptance criterion 1 ("a fresh OpenWrt 25+ router can be set up with one command") holds on real or realistically emulated hardware.
- **Files affected:** None (verification task)
- **Dependencies:** T-081
- **Acceptance criteria:**
  1. A freshly flashed OpenWrt 25+ mipsel_24kc image (or equivalent VM), given only network access and the single `install.sh` command, results in a running, enabled SubMiHomo service and a reachable LuCI Overview page.
  2. No manual step beyond running the command and (separately, per the product's intended UX) pasting a subscription URL is required.
  3. Running `install.sh` a second time on an already-installed system either safely no-ops or safely upgrades, without error.
- **Expected output:** Confirmed project-wide acceptance criterion 1.
- **Estimated complexity:** Medium

### T-085 — Test Update Preserves Configuration

- **Phase:** 14 — Installer
- **Purpose:** Confirm project-wide acceptance criterion 10 holds across a real version-to-version upgrade, not just a same-version reinstall.
- **Files affected:** None (verification task)
- **Dependencies:** T-082, T-084
- **Acceptance criteria:**
  1. Install an older tagged version, customize every UCI option to a non-default value, add subscription data, then run `update.sh` to the current version.
  2. Every customized UCI value and the subscription content are identical after the update.
  3. The service is running and passes all 12 diagnostics (T-078) after the update completes.
- **Expected output:** Confirmed project-wide acceptance criterion 10.
- **Estimated complexity:** Medium

### T-086 — Test Uninstall Leaves Clean System

- **Phase:** 14 — Installer
- **Purpose:** Confirm project-wide acceptance criterion 3 ("disabling the service completely removes all routing/DNS/firewall changes") holds through the full uninstall path, not just a `service stop`.
- **Files affected:** None (verification task)
- **Dependencies:** T-083
- **Acceptance criteria:**
  1. A full snapshot of `nft list ruleset`, `ip rule show`, `ip route show table 100`, `/etc/dnsmasq.d/`, and `crontab -l` taken before install is byte-for-byte identical to a snapshot taken after `uninstall.sh` completes (aside from any explicitly user-retained subscription data, per the confirmation prompt).
  2. No SubMiHomo package, UCI config, or file under `/usr/lib/submihomo/`, `/usr/lib/rpcd/submihomo`, `/usr/bin/submihomo-ctl`, or `/htdocs/luci-static/resources/view/submihomo/` remains.
  3. The router boots cleanly afterward with no error referencing SubMiHomo in `logread`.
- **Expected output:** Confirmed project-wide acceptance criterion 3, verified at the full-uninstall level.
- **Estimated complexity:** Medium

---

## 15. Phase 15 — Dashboard

### T-087 — Write dashboard_download() Function

- **Phase:** 15 — Dashboard
- **Purpose:** Implement the GitHub-Releases-driven Zashboard provisioning flow described in `docs/DASHBOARD.md` §4.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/dashboard.sh` (first section of the eventual ≤ 100-line file)
- **Dependencies:** T-022 (needs `dashboard_repo` validated and readable)
- **Acceptance criteria:**
  1. Fetches `https://api.github.com/repos/<dashboard_repo>/releases/latest`, extracts the `dist.zip` asset's `browser_download_url` via `grep`/`sed` (no `jq` dependency, per `docs/FILESYSTEM.md` §2.4), and downloads it to a `/tmp` scratch path.
  2. Removes existing `$DASHBOARD_DIR` contents **only after** the new archive has downloaded successfully — never before — matching the ordering in `docs/DASHBOARD.md` §4's flowchart, to minimize the window with no dashboard served.
  3. Extracts the archive into `$DASHBOARD_DIR` via `unzip`, writes the resolved release tag into `$DASHBOARD_DIR/.version`, and removes all temp files regardless of outcome.
  4. Every failure point (API unreachable, no matching asset, download failure, extraction failure, disk full) logs a distinct `log_error` and returns non-zero, per `docs/COMPONENTS.md` §3.7.6.
- **Expected output:** A working, safe dashboard provisioning function.
- **Estimated complexity:** Medium

### T-088 — Write dashboard_version() Function

- **Phase:** 15 — Dashboard
- **Purpose:** Expose the installed dashboard's version for display in the CLI (`submihomo-ctl version`) and the LuCI Overview page.
- **Files affected:** `SubMiHomo/files/usr/lib/submihomo/dashboard.sh` (combined file with T-087 must remain ≤ 100 lines)
- **Dependencies:** T-087
- **Acceptance criteria:**
  1. Reads and prints `$DASHBOARD_DIR/.version` if present.
  2. Prints a clear `not installed` sentinel (not an error) when the dashboard has never been downloaded.
  3. Combined `dashboard.sh` (T-087 + T-088) is ≤ 100 lines, verified with `wc -l`.
- **Expected output:** A complete, budget-compliant `dashboard.sh` module.
- **Estimated complexity:** Simple

### T-089 — Add Auto-Download Trigger to init.d start_service

- **Phase:** 15 — Dashboard
- **Purpose:** Ensure a fresh install automatically has a working dashboard on first start, with zero manual step, per `docs/DASHBOARD.md` §8.
- **Files affected:** `SubMiHomo/files/etc/init.d/submihomo` (final amendment; combined file across all contributing tasks — T-012, T-014–T-017, T-089 — must remain ≤ 120 lines)
- **Dependencies:** T-088, T-018
- **Acceptance criteria:**
  1. `start_service()` checks whether `$DASHBOARD_DIR` is empty and, only if so, calls `dashboard_download()` — an already-populated dashboard directory is never re-downloaded automatically on every restart.
  2. A `dashboard_download()` failure (e.g., no internet access on first boot) is logged as a warning and does **not** abort `start_service()` — the proxy service itself must start successfully regardless of dashboard provisioning outcome, per the risk noted in `docs/ROADMAP.md` §2 (Phase 15).
  3. Combined `init.d/submihomo` is ≤ 120 lines total, verified with `wc -l` — if the budget is at risk, the auto-download check is reduced to the minimum possible inline logic (a one-line directory-empty test) with all real work delegated to `dashboard.sh`.
- **Expected output:** A correctly non-blocking, budget-compliant auto-provisioning trigger.
- **Estimated complexity:** Medium

### T-090 — Wire download_dashboard RPC to LuCI Button

- **Phase:** 15 — Dashboard
- **Purpose:** Let operators manually trigger a dashboard update from the browser, completing the Phase 6 stub (T-030).
- **Files affected:** `SubMiHomo/files/htdocs/luci-static/resources/view/submihomo/overview.js` (amendment; combined file must remain ≤ 300 lines)
- **Dependencies:** T-030, T-088, T-067
- **Acceptance criteria:**
  1. The Overview page displays the current dashboard version (via a `dashboard_version`-backed data point exposed through the RPC layer) and a "Download/Update Dashboard" button calling `download_dashboard`.
  2. The button shows a progress/blocking indicator during the (potentially multi-second) download and an `ui.addNotification()` result on completion or failure.
  3. A successful update is reflected in the displayed version string without requiring a full page reload.
- **Expected output:** A working, LuCI-integrated dashboard update control.
- **Estimated complexity:** Medium

### T-091 — Test Dashboard Download and Serving

- **Phase:** 15 — Dashboard
- **Purpose:** Confirm project-wide acceptance criterion 5 ("Zashboard is accessible and shows correct proxy data").
- **Files affected:** None (verification task)
- **Dependencies:** T-089, T-090
- **Acceptance criteria:**
  1. A fresh install with no prior dashboard content results in `http://<router-ip>:<external_controller_port>/ui/index.html` becoming reachable and rendering the Zashboard SPA after the first successful start.
  2. Zashboard's displayed proxy-group hierarchy matches the actual output of `get_proxies`/Mihomo's own `/proxies` endpoint.
  3. A manual re-trigger (via LuCI or `submihomo-ctl dashboard`) fetches and swaps in the latest release with no window in which `/ui/index.html` returns a 404 or empty response (verified by polling the endpoint continuously across the swap and confirming zero failed requests).
  4. A simulated GitHub-API-unreachable condition on first boot still results in a fully running, proxying service (dashboard absent but proxy fully functional), confirmed against diagnostic check 1–2 (T-074) still passing.
- **Expected output:** Confirmed project-wide acceptance criterion 5.
- **Estimated complexity:** Medium

---

## 16. Phase 16 — Release Packaging

### T-092 — Generate APK Signing Key Pair and Document Process

- **Phase:** 16 — Release packaging
- **Purpose:** Establish the cryptographic trust root the published APK feed will use, and document the process so it is reproducible and auditable, not tribal knowledge.
- **Files affected:** A `keys/` directory holding only the **public** key (e.g., `SubMiHomo/keys/submihomo-release.rsa.pub`); the private key is generated but never committed to the repository (stored in a secrets manager / CI secret store instead); a documentation note describing the key-generation and rotation process (may be appended to `README.md` or a new `docs/RELEASE.md`, at the implementing engineer's discretion, so long as it is written down somewhere in `docs/`)
- **Dependencies:** T-008
- **Acceptance criteria:**
  1. An RSA key pair suitable for APK signing (e.g., via `abuild-keygen` or the OpenWrt/Alpine-compatible equivalent) is generated, with the public key committed to the repository and the private key never committed anywhere in git history (verified via a repository history scan for key-like PEM/RSA content).
  2. The documented process describes exactly how to rotate the key in the future and what happens to previously-published packages if rotation occurs (they remain valid under the old key until reissued).
  3. The private key is stored as a CI secret (e.g., a GitHub Actions encrypted secret) accessible only to the release workflow (T-095), not the CI or build workflows (T-093, T-094).
- **Expected output:** A working, documented, appropriately-scoped signing key setup.
- **Estimated complexity:** Medium

### T-093 — Write GitHub Actions Workflow for CI Unit Tests

- **Phase:** 16 — Release packaging
- **Purpose:** Run the full shell/Lua/JS unit and integration test suite automatically on every push and pull request.
- **Files affected:** `SubMiHomo/.github/workflows/ci.yml`
- **Dependencies:** T-018, T-034, T-050, T-072 (representative tests from each earlier phase must exist to be run)
- **Acceptance criteria:**
  1. Runs `shellcheck --shell=sh` across every file under `files/usr/lib/submihomo/`, `files/etc/init.d/`, `files/usr/bin/submihomo-ctl`, and `install/`, failing the build on any warning.
  2. Runs the fixture-driven subscription (T-040/T-041), config-generation (T-050/T-051), and RPC (T-034) test scripts against a containerized or SDK-emulated environment.
  3. Runs the headless-browser LuCI smoke test (T-072) against a test instance.
  4. The workflow fails (non-zero exit, red status) if any of the above fails, and completes in a bounded, CI-reasonable time (documented target: under 15 minutes).
- **Expected output:** A working CI pipeline enforcing project-wide acceptance criterion 7 ("all unit tests pass in CI").
- **Estimated complexity:** Complex

### T-094 — Write GitHub Actions Workflow for Package Build

- **Phase:** 16 — Release packaging
- **Purpose:** Automatically build both `.apk` packages against the real mipsel_24kc OpenWrt SDK on every push, catching build regressions immediately rather than only at release time.
- **Files affected:** `SubMiHomo/.github/workflows/build.yml`
- **Dependencies:** T-008, T-093
- **Acceptance criteria:**
  1. Downloads/caches the pinned OpenWrt 25+ SDK for `mipsel_24kc`, runs the Phase 2 compile steps (T-005/T-006 stanzas) exactly as a contributor would locally.
  2. Uploads the resulting `.apk` artifacts as workflow artifacts for inspection/download.
  3. Fails clearly and specifically if the build silently falls back to a host-architecture toolchain instead of genuinely cross-compiling for `mipsel_24kc` (guarding against the "false confidence" risk noted in `docs/ROADMAP.md` §2, Phase 16).
- **Expected output:** A working, architecture-faithful package-build CI job, enforcing project-wide acceptance criterion 8.
- **Estimated complexity:** Medium

### T-095 — Write GitHub Actions Release Workflow (Tag → Build → Sign → Publish)

- **Phase:** 16 — Release packaging
- **Purpose:** Fully automate the path from a git tag to a signed, published APK release.
- **Files affected:** `SubMiHomo/.github/workflows/release.yml`
- **Dependencies:** T-092, T-094
- **Acceptance criteria:**
  1. Triggers only on version tags matching a documented pattern (e.g., `v*.*.*`), never on ordinary pushes.
  2. Reuses the build steps from T-094, then signs the resulting `.apk` files using the private key restored from the CI secret established in T-092, then publishes both the signed packages and an updated `APKINDEX` to the project's package feed/repository host.
  3. A dry run against a non-production release-candidate tag/feed completes successfully with no changes to the real production feed, confirming the pipeline is safe to rehearse before a genuine release.
  4. The private signing key is never written to a log, artifact, or any world-readable location at any pipeline step (verified by inspecting workflow logs for accidental key material exposure).
- **Expected output:** A working, secure, one-tag release pipeline.
- **Estimated complexity:** Complex

### T-096 — Run Complete Regression Test Suite

- **Phase:** 16 — Release packaging
- **Purpose:** Execute every phase's exit criteria and every project-wide acceptance criterion in one final, end-to-end pass before tagging v1.0.0.
- **Files affected:** None (verification task; may consolidate prior ad hoc test scripts from T-008, T-013, T-018, T-022, T-034, T-040–T-042, T-050–T-051, T-054–T-055, T-058–T-059, T-064–T-065, T-072–T-073, T-078–T-079, T-084–T-086, T-091 into a single runnable regression script, e.g. `SubMiHomo/install/regression-test.sh`, for ongoing post-v1.0 use)
- **Dependencies:** T-093, T-094, T-095
- **Acceptance criteria:**
  1. All 16 phases' individually documented exit criteria (`docs/ROADMAP.md` §2) pass on a fresh install performed exclusively via the published one-command installer.
  2. All 10 project-wide acceptance criteria (`docs/ROADMAP.md` §6) are independently re-verified in this single end-to-end pass, not merely assumed from earlier phase-level testing.
  3. All 12 diagnostic checks (T-074) pass on the resulting installation.
  4. Any regression discovered here is triaged and fixed before proceeding to T-097/T-098 — this task does not complete until the suite is fully green.
- **Expected output:** A confirmed, fully working, release-candidate build of SubMiHomo.
- **Estimated complexity:** Complex

### T-097 — Final Documentation Review Pass

- **Phase:** 16 — Release packaging
- **Purpose:** Ensure every document in `docs/` accurately reflects the shipped v1.0.0 implementation, with no stale placeholders, TODOs, or contradictions between documents.
- **Files affected:** `SubMiHomo/README.md` and every file under `SubMiHomo/docs/` (review and correction, not wholesale rewrite)
- **Dependencies:** T-096
- **Acceptance criteria:**
  1. Every file path, function name, UCI option, and RPC method referenced anywhere in `docs/` matches the actual shipped implementation exactly (spot-checked against the real files under `files/`).
  2. No document contains an unresolved `TODO`, `FIXME`, or "not yet implemented" note describing v1.0.0-scoped functionality (post-v1.0 items are explicitly relocated to the "Post-Launch Considerations" section of `docs/ROADMAP.md` §9 instead of left dangling elsewhere).
  3. `README.md`'s one-command install instructions are tested verbatim (copy-pasted, not paraphrased) against a clean router as part of this review.
- **Expected output:** Documentation that is trustworthy as of the v1.0.0 tag.
- **Estimated complexity:** Medium

### T-098 — Tag v1.0.0 Release

- **Phase:** 16 — Release packaging
- **Purpose:** Formally mark the completion of the roadmap and trigger the automated release pipeline.
- **Files affected:** None (git tag operation only)
- **Dependencies:** T-096, T-097
- **Acceptance criteria:**
  1. A git tag `v1.0.0` is created on the exact commit that passed T-096's full regression suite and T-097's documentation review, with no further code changes after tagging.
  2. Pushing the tag triggers T-095's release workflow end-to-end with no manual intervention, resulting in a signed, published APK package.
  3. A router with zero prior SubMiHomo installation can run the published one-command installer against the live (non-dry-run) feed and reach a fully working, diagnostics-passing installation — the final, complete confirmation of every acceptance criterion in `docs/ROADMAP.md` §6.
- **Expected output:** The published, signed, publicly installable v1.0.0 release of SubMiHomo.
- **Estimated complexity:** Simple

---

## 17. Task Summary Table

| Phase | Task Range | Task Count | Combined Complexity Skew |
|---|---|---|---|
| 1 — Repository skeleton | T-001–T-004 | 4 | Simple |
| 2 — Package build system | T-005–T-008 | 4 | Medium |
| 3 — Core service | T-009–T-013 | 5 | Simple/Medium |
| 4 — procd integration | T-014–T-018 | 5 | Medium |
| 5 — UCI | T-019–T-022 | 4 | Medium |
| 6 — RPC | T-023–T-034 | 12 | Medium/Complex |
| 7 — Subscription manager | T-035–T-042 | 8 | Medium/Complex |
| 8 — Config generator | T-043–T-051 | 9 | Complex |
| 9 — DNS manager | T-052–T-055 | 4 | Simple |
| 10 — Routing manager | T-056–T-059 | 4 | Simple |
| 11 — Firewall manager | T-060–T-065 | 6 | Medium/Complex |
| 12 — LuCI frontend | T-066–T-073 | 8 | Complex |
| 13 — Diagnostics | T-074–T-079 | 6 | Medium/Complex |
| 14 — Installer | T-080–T-086 | 7 | Medium |
| 15 — Dashboard | T-087–T-091 | 5 | Medium |
| 16 — Release packaging | T-092–T-098 | 7 | Complex |
| **Total** | **T-001–T-098** | **98** | — |

Every file in the repository's final layout (per `docs/FILESYSTEM.md` §2) is created or modified by at least one task above; every module's line-count budget (§0.3) is explicitly tracked across the tasks that contribute to it; and every phase's roadmap-level exit criteria (`docs/ROADMAP.md` §2) is covered by at least one dedicated verification task in this document.
