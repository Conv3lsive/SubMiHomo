# SubMiHomo — Filesystem Reference

> **Audience**: Contributors, package maintainers, and operators deploying SubMiHomo on OpenWrt.
> **Scope**: Every file in the repository and on the installed router, its purpose, permissions, and the reasoning behind its location.
> **Version**: 1.0

---

## Table of Contents

1. [Overview](#1-overview)
2. [Repository Source Tree](#2-repository-source-tree)
   - 2.1 [Root Level](#21-root-level)
   - 2.2 [docs/ — Architecture Documents](#22-docs--architecture-documents)
   - 2.3 [files/etc/ — Configuration and Init](#23-filesetc--configuration-and-init)
   - 2.4 [files/usr/lib/ — Service Logic and RPC](#24-filesusrlib--service-logic-and-rpc)
   - 2.5 [files/usr/bin/ — CLI Tools](#25-filesusrbin--cli-tools)
   - 2.6 [files/usr/share/ — LuCI Menu and ACL](#26-filesusrshare--luci-menu-and-acl)
   - 2.7 [files/htdocs/ — LuCI Frontend Views](#27-filesshtdocs--luci-frontend-views)
   - 2.8 [install/ — Deployment Scripts](#28-install--deployment-scripts)
3. [Installed Filesystem Tree (OpenWrt Router)](#3-installed-filesystem-tree-openwrt-router)
   - 3.1 [/etc — Persistent Configuration](#31-etc--persistent-configuration)
   - 3.2 [/usr/lib — Service Libraries and RPC Plugin](#32-usrlib--service-libraries-and-rpc-plugin)
   - 3.3 [/usr/bin — CLI Tool](#33-usrbin--cli-tool)
   - 3.4 [/usr/share — Shared Data and UI Assets](#34-usrshare--shared-data-and-ui-assets)
   - 3.5 [/htdocs — LuCI Static Assets](#35-htdocs--luci-static-assets)
4. [Runtime-Created Paths](#4-runtime-created-paths)
   - 4.1 [/var/run/submihomo/ — Ephemeral Runtime State](#41-varrunsubmihomo--ephemeral-runtime-state)
   - 4.2 [/etc/submihomo/subscriptions/ — Persistent Subscription Storage](#42-etcsubmihomosubscriptions--persistent-subscription-storage)
   - 4.3 [/usr/share/submihomo/dashboard/ — Zashboard Assets](#43-ussharubmihomodashboard--zashboard-assets)
   - 4.4 [/etc/dnsmasq.d/submihomo.conf — DNS Injection](#44-etcdnsmasqdsubmihomoconf--dns-injection)
5. [File Permissions Table](#5-file-permissions-table)
6. [Path Choice Rationale — OpenWrt Conventions](#6-path-choice-rationale--openwrt-conventions)
7. [Persistent vs. Runtime Storage](#7-persistent-vs-runtime-storage)
8. [Flash Storage Impact](#8-flash-storage-impact)

---

## 1. Overview

SubMiHomo occupies three distinct filesystem namespaces:

1. **Repository** (`submihomo/` git root): The source tree that is also the OpenWrt package directory. Contains all files that will be installed plus the build system metadata, documentation, and deployment scripts.

2. **Installed (persistent)**: Files installed by APK onto the router's overlay filesystem (SquashFS + JFFS2). These survive reboots and firmware upgrades (overlay layer). Includes UCI config, init script, shell modules, LuCI assets, and templates.

3. **Runtime (ephemeral)**: Files created by the service at runtime. Divided into tmpfs paths (lost on reboot, intentionally) and persistent paths within `/etc/submihomo/` (survive reboots, contain user data such as subscription files).

The diagram below shows the three namespaces and how they relate:

```mermaid
flowchart TD
    subgraph REPO["Git Repository (submihomo/)"]
        RF[files/ — installed content]
        RD[docs/ — documentation]
        RI[install/ — deployment scripts]
        RM[Makefile — package build]
    end

    subgraph INSTALLED["Installed on Router (APK)"]
        subgraph PERSIST_INST["Overlay FS (persistent across reboots)"]
            ETC_I[/etc/config/submihomo\n/etc/init.d/submihomo\n/etc/submihomo/templates/]
            USR_I[/usr/lib/submihomo/\n/usr/lib/rpcd/submihomo\n/usr/bin/submihomo-ctl]
            SHR_I[/usr/share/luci/menu.d/\n/usr/share/rpcd/acl.d/]
            HTD_I[/htdocs/luci-static/resources/view/submihomo/]
        end
    end

    subgraph RUNTIME["Runtime State (created at service start)"]
        subgraph TMPFS["tmpfs /var/run — lost on reboot"]
            VAR_R[/var/run/submihomo/config.yaml\n/var/run/submihomo/mihomo.pid]
        end
        subgraph PERSIST_RT["Overlay FS — survives reboots"]
            ETC_R[/etc/submihomo/subscriptions/current.yaml\n/etc/submihomo/subscriptions/backup.yaml]
            SHR_R[/usr/share/submihomo/dashboard/]
        end
        subgraph DNSMASQ["dnsmasq config — recreated on each start"]
            DNS_R[/etc/dnsmasq.d/submihomo.conf]
        end
    end

    RF -->|apk install| INSTALLED
    INSTALLED -->|service start| RUNTIME
```

---

## 2. Repository Source Tree

The repository root (`submihomo/`) doubles as the OpenWrt package directory. The OpenWrt build system expects a `Makefile` at the root of the package directory and a `files/` subdirectory whose contents are installed verbatim to the target filesystem.

### 2.1 Root Level

```
submihomo/
├── Makefile
├── README.md
├── docs/
├── files/
└── install/
```

| File / Directory | Description |
|---|---|
| `Makefile` | OpenWrt package Makefile. Declares package metadata (name, version, description, dependencies), build instructions, and install targets. Uses the `PKG_INSTALL_DIR` mechanism to install files from `files/` to the target. Defines three packages: `mihomo` (upstream dep), `submihomo`, and `luci-app-submihomo`. |
| `README.md` | Project introduction, installation instructions, and quick-start guide for end users. Should reference the paste-URL-click-Apply philosophy without technical detail. |
| `docs/` | All architecture and reference documentation. See §2.2. |
| `files/` | All files installed to the router target. Subdirectory structure mirrors the target filesystem exactly. See §2.3–2.7. |
| `install/` | Standalone shell scripts for bootstrapping SubMiHomo on a running OpenWrt router without an existing package feed. See §2.8. |

### 2.2 docs/ — Architecture Documents

```
docs/
├── ARCHITECTURE.md
├── FILESYSTEM.md
└── (up to 18 total documents)
```

| File | Description |
|---|---|
| `docs/ARCHITECTURE.md` | System architecture, design philosophy, data flow diagrams, technology choices, and intentional omissions. (This document's companion.) |
| `docs/FILESYSTEM.md` | This document. Complete filesystem reference for repository and installed paths. |
| Additional docs | May include: `ROUTING.md`, `DNS.md`, `FIREWALL.md`, `SUBSCRIPTION.md`, `DASHBOARD.md`, `UCI.md`, `RPC-API.md`, `LUCI.md`, `SECURITY.md`, `INSTALL.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `TESTING.md`, `DIAGNOSTICS.md`, `SHELL-MODULES.md`, `PACKAGES.md`. |

Documentation lives in `docs/` rather than a wiki to keep it versioned alongside the code. This ensures that architecture documents describing a particular version of the software are always checkable by git hash.

### 2.3 files/etc/ — Configuration and Init

```
files/etc/
├── config/
│   └── submihomo
├── init.d/
│   └── submihomo
└── submihomo/
    └── templates/
        └── base.yaml.tmpl
```

#### `files/etc/config/submihomo`

The default UCI configuration file. This is the template that APK installs to `/etc/config/submihomo`. It contains the default values for all configurable options. If the user has already configured SubMiHomo, APK will not overwrite this file on upgrade (OpenWrt APK preserves conffiles).

The file defines two UCI sections:

- `config submihomo 'main'` — The primary options object. All service-level settings live here.
- `config bypass 'bypass'` — A list option section for user-defined bypass addresses.

Default values are chosen to be safe: service disabled (`enabled 0`), no subscription URL, fake-IP DNS mode, warning log level, no external controller secret, LAN access disabled, and a 24-hour subscription update interval. The default bypass list includes the three RFC 1918 ranges.

This file has mode **0600** on install because it is flagged as a conffile containing potentially sensitive data (subscription URL, controller secret).

#### `files/etc/init.d/submihomo`

The procd init script. This is the entry point for all service lifecycle operations. It is written in shell and follows the OpenWrt procd init script convention (`START`, `STOP` variables, `start_service()`, `stop_service()`, `reload_config()` functions).

Key properties defined in this file:

| Property | Value | Rationale |
|---|---|---|
| `START` | 95 | Must start after dnsmasq (60), firewall (19), and all network services (20) |
| `STOP` | 5 | Must stop before dnsmasq and network tear down |
| procd respawn | 5 attempts / 60s | Moderate recovery: restart on crash, but give up after repeated failures |
| Mihomo command | `mihomo -f /var/run/submihomo/config.yaml -d /var/run/submihomo` | Config file explicitly specified; working dir set to runtime directory |

The `start_service()` function executes in this order:
1. Source `core.sh` to load constants and helpers.
2. Call `config_generate()` from `config.sh` to build `config.yaml`.
3. Call `routing_setup()` from `routing.sh` to install ip rules and table 100.
4. Call `dns_setup()` from `dns.sh` to install dnsmasq forwarding config.
5. Call `firewall_setup()` from `firewall.sh` to install nftables table.
6. If `/usr/share/submihomo/dashboard/` is empty, call `dashboard_download()` from `dashboard.sh`.
7. Register Mihomo with procd via `procd_set_param`.

The `stop_service()` function executes in this order:
1. Call `firewall_teardown()` from `firewall.sh`.
2. Call `dns_teardown()` from `dns.sh`.
3. Call `routing_teardown()` from `routing.sh`.

Procd kills the Mihomo process before calling `stop_service()`.

This file has mode **0755** on install (executable, world-readable, standard for init scripts).

#### `files/etc/submihomo/templates/base.yaml.tmpl`

A YAML template that represents the non-subscription portions of the Mihomo config. It contains placeholder tokens (e.g., `@@PORT@@`, `@@DNS_MODE@@`, `@@LOG_LEVEL@@`) that `config.sh` replaces with UCI-derived values using `sed`. The template establishes the correct YAML structure and key ordering so that `config.sh` can append subscription blocks without needing to understand YAML structure deeply.

This file is installed to `/etc/submihomo/templates/` rather than `/var/run/submihomo/` because it is a static asset that never changes at runtime. Placing it under `/etc/submihomo/` keeps it on the persistent overlay filesystem where it survives reboots.

### 2.4 files/usr/lib/ — Service Logic and RPC Plugin

```
files/usr/lib/
├── rpcd/
│   └── submihomo
└── submihomo/
    ├── core.sh
    ├── config.sh
    ├── routing.sh
    ├── dns.sh
    ├── firewall.sh
    ├── subscription.sh
    └── dashboard.sh
```

#### `files/usr/lib/submihomo/core.sh`

The shared library sourced by all other shell modules and by the init script. Defines:

- **Constants**: Port numbers (`TPROXY_PORT=7891`, `MIXED_PORT=7890`, `DNS_PORT=1053`, `CTRL_PORT=9090`), fwmark values (`FWMARK_PROXY=1`, `FWMARK_BYPASS=255`), routing table number (`ROUTE_TABLE=100`), and filesystem paths.
- **UCI read helpers**: Functions like `submihomo_get_option(section, option, default)` that wrap `uci -q get submihomo.$section.$option` with a fallback default value. Named accessors such as `get_dns_mode()`, `get_log_level()`, `get_subscription_url()`, etc.
- **Logging helpers**: `log_info()`, `log_warn()`, `log_err()` — each calls `logger -t submihomo -p daemon.info/warn/err` to write to syslog. In debug mode, additionally writes to `/var/log/submihomo.log`.
- **Lock helpers**: `acquire_lock()` and `release_lock()` use a lockfile at `/var/run/submihomo/submihomo.lock` to prevent concurrent subscription updates or service restarts from racing.
- **Validation helpers**: `check_root()` (exit if not running as root), `check_mihomo_binary()` (verify `/usr/bin/mihomo` exists and is executable).

`core.sh` is placed in `/usr/lib/submihomo/` rather than `/usr/lib/` directly to namespace it away from other packages. It is not independently executable; it is always sourced.

#### `files/usr/lib/submihomo/config.sh`

Generates the final Mihomo config YAML at `/var/run/submihomo/config.yaml`. This is the most complex shell module. Its responsibilities:

1. Read all relevant UCI options via `core.sh` helpers.
2. Start with a copy of `base.yaml.tmpl`, replacing all `@@PLACEHOLDER@@` tokens with UCI-derived values using `sed`.
3. Read `/etc/submihomo/subscriptions/current.yaml` and extract three blocks:
   - The `proxies:` block: everything from the `proxies:` key to the next top-level key.
   - The `proxy-groups:` block: similarly extracted.
   - The `rules:` block: similarly extracted.
4. Build the DNS section YAML based on `dns_mode` UCI option. Fake-IP mode generates a different `dns:` block than real-IP (redir-host) mode.
5. Prepend SubMiHomo's bypass rules to the rules block.
6. Append `MATCH,PROXY` as the final rule in the rules block.
7. Assemble all sections in order and write to `/var/run/submihomo/config.yaml`.
8. Run `mihomo -t -f /var/run/submihomo/config.yaml` to validate the output before Mihomo is started. If validation fails, log an error and exit non-zero (which will abort the init script start sequence).

The use of `awk` for YAML block extraction is a deliberate architectural choice. The alternative — a Python or Lua YAML parser — would add a dependency that may not be available on minimal OpenWrt builds and would increase script startup time.

#### `files/usr/lib/submihomo/routing.sh`

Manages the two kernel constructs required for TPROXY to function. Exposes two functions:

**`routing_setup()`**:
```
ip route add local default dev lo table 100
ip rule add fwmark 1 lookup 100 pref 100
```
Checks whether the rule and route already exist before adding them (idempotent). Logs the actions via `core.sh`.

**`routing_teardown()`**:
```
ip rule del fwmark 1 lookup 100
ip route del local default dev lo table 100
```
Uses `ip rule show` and `ip route show table 100` to check existence before deletion. Failures are logged as warnings, not errors, because a missing rule during teardown is not harmful.

The routing table number 100 is defined as a constant in `core.sh`. This table is not named in `/etc/iproute2/rt_tables` by default; it is referenced only by number, which is sufficient for the `ip` command.

#### `files/usr/lib/submihomo/dns.sh`

Manages dnsmasq integration. Exposes two functions:

**`dns_setup()`**:
1. Writes `/etc/dnsmasq.d/submihomo.conf` with content `server=/#/127.0.0.1#1053`.
2. Sends SIGHUP to dnsmasq to trigger a config reload (`kill -HUP $(cat /var/run/dnsmasq/dnsmasq.pid)`).
3. Verifies that Mihomo's DNS listener will be active on port 1053 (waits up to 3 seconds).

**`dns_teardown()`**:
1. Removes `/etc/dnsmasq.d/submihomo.conf`.
2. Sends SIGHUP to dnsmasq to reload config (removing the forwarding rule).

The SIGHUP approach is used rather than `service dnsmasq reload` because the latter may trigger a dnsmasq restart on some OpenWrt versions, which would briefly interrupt DHCP service. SIGHUP causes dnsmasq to re-read its config without restarting.

#### `files/usr/lib/submihomo/firewall.sh`

Manages the nftables table `inet submihomo`. This is the most security-critical shell module. Exposes two functions:

**`firewall_setup()`**:
Builds an nftables ruleset string from constants and UCI bypass addresses, then applies it atomically via `nft -f -` (reading from stdin). The ruleset string is constructed in shell using `printf` to concatenate the hardcoded bypass ranges with any user-defined bypass addresses from UCI. The `nft -f -` approach allows the entire table to be defined in a single atomic operation; if any rule fails, the entire table is rolled back.

The nftables table includes:
- A named set `bypass_addr` containing all bypass CIDRs.
- A `PREROUTING` chain with hook `prerouting`, type `filter`, priority `mangle - 1`.
- An `OUTPUT` chain with hook `output`, type `route`, priority `mangle - 1`.

**`firewall_teardown()`**:
Executes `nft delete table inet submihomo`. This is a single atomic operation that removes all chains, rules, and sets in the table simultaneously.

#### `files/usr/lib/submihomo/subscription.sh`

Manages the subscription lifecycle. Exposes these functions:

- **`subscription_download(url)`**: Downloads to `/tmp/sub_download.yaml` using `wget` with the user-agent from UCI (`subscription_user_agent`). Uses `--timeout=30` and `--tries=2` for resilience.
- **`subscription_validate(file)`**: Checks that the file is non-empty, contains the string `proxies:`, and passes `mihomo -t -f <file>`. Returns 0 for valid, 1 for invalid.
- **`subscription_apply(file)`**: Moves existing `current.yaml` to `backup.yaml`, then moves the downloaded file to `current.yaml`.
- **`subscription_update()`**: Orchestrates download → validate → apply → restart.
- **`subscription_restore()`**: Moves `backup.yaml` back to `current.yaml` (for error recovery).
- **`subscription_schedule_set(hours)`**: Writes a crontab line to `/etc/crontabs/root` for the given interval. If hours is 0, removes the crontab line.
- **`subscription_schedule_remove()`**: Removes the SubMiHomo crontab line from `/etc/crontabs/root`.

The crontab entry format is: `0 */<hours> * * * /usr/lib/submihomo/subscription.sh update_cron`.

#### `files/usr/lib/submihomo/dashboard.sh`

Manages Zashboard download and update. Exposes:

- **`dashboard_download()`**: Calls the GitHub Releases API (`https://api.github.com/repos/Zephyruso/zashboard/releases/latest`), parses the JSON response to find the `dist.zip` asset URL, downloads it to `/tmp/zashboard_dist.zip`, extracts it to `/usr/share/submihomo/dashboard/`, and writes a version file `/usr/share/submihomo/dashboard/.version`.
- **`dashboard_get_version()`**: Reads and returns the content of `.version` if present.
- **`dashboard_is_present()`**: Returns 0 if the dashboard directory is non-empty, 1 otherwise.

JSON parsing of the GitHub API response uses `grep` and `sed` to extract the download URL, avoiding a `jq` dependency. This is sufficient because the GitHub Releases API response has a consistent structure.

#### `files/usr/lib/rpcd/submihomo`

The Lua rpcd plugin. rpcd (the OpenWrt RPC daemon) loads Lua plugins from `/usr/lib/rpcd/`. The plugin registers a set of methods under the `submihomo` object name.

Each method implementation:

| Method | Implementation approach |
|---|---|
| `status()` | Read PID file, call `ps` for uptime, read UCI for subscription URL and dns_mode, check port 7891 via `/proc/net/` |
| `start()` / `stop()` / `restart()` | Call `/etc/init.d/submihomo start/stop/restart` via `io.popen` |
| `update_subscription()` | Source `subscription.sh` functions via shell call |
| `get_config()` | Iterate all UCI options under `submihomo` config and return as JSON |
| `set_config(data)` | Write each supplied option to UCI via `uci set`, call `uci commit`, validate values |
| `get_logs(lines)` | Call `logread -l <lines>` and filter for `submihomo` tag |
| `run_diagnostics()` | Execute each of the 10 diagnostic checks sequentially, return structured results |
| `download_dashboard()` | Call `dashboard.sh` functions via shell |
| `get_proxies()` | HTTP GET to `http://127.0.0.1:9090/proxies` with Bearer token from UCI |
| `test_connection()` | `wget --spider` a test URL via proxy, measure elapsed time |

The plugin is not independently executable. rpcd loads it at startup and keeps it in memory. This means all Lua plugin calls incur no interpreter startup overhead.

### 2.5 files/usr/bin/ — CLI Tools

```
files/usr/bin/
└── submihomo-ctl
```

#### `files/usr/bin/submihomo-ctl`

A CLI management tool for operators who prefer the command line or who are managing headless routers without LuCI. It is a shell script that accepts subcommands:

| Subcommand | Action |
|---|---|
| `start` | Start the service |
| `stop` | Stop the service |
| `restart` | Restart the service |
| `status` | Print service status summary |
| `update-sub` | Trigger subscription update |
| `update-dashboard` | Download/update Zashboard |
| `set-url <url>` | Set subscription URL in UCI and trigger update |
| `diagnostics` | Run all diagnostic checks and print results |
| `logs [n]` | Print last n lines of SubMiHomo syslog entries |
| `version` | Print SubMiHomo and Mihomo versions |

The tool sources `core.sh` for shared constants and helpers, and delegates to the appropriate shell module functions or init script calls. It is placed in `/usr/bin/` (in PATH) so operators can run `submihomo-ctl status` without specifying a path.

### 2.6 files/usr/share/ — LuCI Menu and ACL

```
files/usr/share/
├── luci/
│   └── menu.d/
│       └── luci-app-submihomo.json
└── rpcd/
    └── acl.d/
        └── luci-app-submihomo.json
```

#### `files/usr/share/luci/menu.d/luci-app-submihomo.json`

A JSON file that registers SubMiHomo in the LuCI navigation menu. The LuCI JS framework scans `/usr/share/luci/menu.d/` at runtime to build the sidebar navigation tree. This file creates a top-level menu entry "SubMiHomo" with child entries for each view:

| Menu Entry | View | Path |
|---|---|---|
| Overview | `overview.js` | `/submihomo/overview` |
| Subscription | `subscription.js` | `/submihomo/subscription` |
| Settings | `settings.js` | `/submihomo/settings` |
| Proxies | `proxies.js` | `/submihomo/proxies` |
| Logs | `logs.js` | `/submihomo/logs` |

This file follows the LuCI menu.d JSON schema: `title`, `order`, `action` (type `view`, `view` pointing to the JS module path), and optional `depends` for permission gating.

#### `files/usr/share/rpcd/acl.d/luci-app-submihomo.json`

An rpcd ACL file that declares which RPC methods are accessible to which user roles. rpcd reads all files in `/usr/share/rpcd/acl.d/` at startup to build its permission table.

The ACL structure:

```json
{
  "luci-user": {
    "description": "Read-only SubMiHomo access",
    "read": {
      "ubus": {
        "submihomo": ["status", "get_config", "get_logs", "get_proxies",
                      "run_diagnostics", "test_connection"]
      }
    }
  },
  "luci-admin": {
    "description": "Full SubMiHomo access",
    "read": { "ubus": { "submihomo": ["*"] } },
    "write": { "ubus": { "submihomo": ["*"] } }
  }
}
```

This ensures that a logged-in user without admin privileges can view the service status and logs but cannot change configuration, restart the service, or update the subscription.

### 2.7 files/htdocs/ — LuCI Frontend Views

```
files/htdocs/
└── luci-static/
    └── resources/
        └── view/
            └── submihomo/
                ├── overview.js
                ├── subscription.js
                ├── settings.js
                ├── proxies.js
                └── logs.js
```

All LuCI JS view files are installed to `/htdocs/luci-static/resources/view/submihomo/`. The LuCI JS framework's module loader resolves `view/submihomo/<name>` to this path.

#### `overview.js`

The primary dashboard page. Displays:
- A status card showing whether the service is running, the Mihomo version, PID, and uptime.
- An enable/disable toggle that calls `start()` or `stop()` via RPC.
- Quick stats: active subscription URL (truncated), DNS mode, last subscription update timestamp.
- A "Run Diagnostics" button that calls `run_diagnostics()` and renders results in a table.

Makes RPC calls to: `status`, `start`, `stop`, `run_diagnostics`.

#### `subscription.js`

Subscription management page. Displays:
- A text input for the subscription URL bound to the UCI `subscription_url` option.
- A dropdown for the update interval bound to `subscription_update_interval`.
- A "Save & Update Now" button that calls `set_config()` followed by `update_subscription()`.
- A status row showing last update time and whether the current subscription is valid.
- A text area showing the first few lines of `current.yaml` for verification.

Makes RPC calls to: `get_config`, `set_config`, `update_subscription`, `status`.

#### `settings.js`

General settings page. Displays a form for:
- DNS mode selector (fake-ip / redir-host).
- Log level selector (debug / info / warning / error / silent).
- External controller port (numeric input).
- External controller secret (password input).
- Allow LAN direct access toggle (enables mixed-port 7890).
- Custom bypass address list (dynamic list input).
- Dashboard repository (text input for GitHub repo path).
- User-agent string for subscription downloads.

On save, calls `set_config()` and optionally `restart()` if service-impacting settings changed.

Makes RPC calls to: `get_config`, `set_config`, `restart`.

#### `proxies.js`

Proxy group viewer. Displays:
- A table of proxy groups retrieved from Mihomo's API via RPC.
- For each group: name, type (selector/fallback/url-test/load-balance), current selection, member proxies.
- For selector-type groups: a dropdown to switch the active proxy (calls Mihomo API PUT via RPC).
- Latency testing button per proxy.

This page directly reflects Mihomo's live state rather than UCI configuration. It is useful for operators who want to override the automatic proxy selection without restarting the service.

Makes RPC calls to: `get_proxies`, and a proxy-specific selector call.

#### `logs.js`

Log viewer page. Displays:
- A textarea showing the last N lines of SubMiHomo syslog entries.
- A line count selector (50 / 100 / 200 / 500).
- An auto-refresh toggle (polls every 5 seconds via RPC).
- A filter input to grep log lines client-side.

Makes RPC calls to: `get_logs`.

### 2.8 install/ — Deployment Scripts

```
install/
├── install.sh
├── update.sh
└── uninstall.sh
```

These scripts are not installed to the router by APK. They are run directly from the repository (or downloaded by the user) to bootstrap the APK feed on a router that does not yet have the feed configured.

#### `install/install.sh`

Bootstraps SubMiHomo on a fresh OpenWrt 25+ router. Steps:

1. Verify OpenWrt version is 25+ by reading `/etc/openwrt_release`.
2. Download and install the APK repository public key from GitHub Releases.
3. Add the SubMiHomo APK repository URL to `/etc/apk/repositories`.
4. Run `apk update`.
5. Run `apk add submihomo luci-app-submihomo`.
6. Enable the service: `/etc/init.d/submihomo enable`.
7. Start the service: `/etc/init.d/submihomo start`.
8. Print the LuCI URL and default credentials reminder.

#### `install/update.sh`

Updates SubMiHomo to the latest version:

1. Run `apk update`.
2. Run `apk upgrade submihomo luci-app-submihomo`.
3. Restart the service: `/etc/init.d/submihomo restart`.

#### `install/uninstall.sh`

Completely removes SubMiHomo:

1. Stop and disable the service.
2. Run `apk del submihomo luci-app-submihomo`.
3. Remove the APK repository entry from `/etc/apk/repositories`.
4. Remove the APK repository key.
5. Remove `/etc/submihomo/` (subscription data — with user confirmation prompt).
6. Remove `/usr/share/submihomo/` (Zashboard — downloaded at runtime).
7. Remove `/var/log/submihomo.log` if present.
8. Print confirmation.

The uninstall script prompts before deleting `/etc/submihomo/subscriptions/` because this directory contains the user's subscription data.

---

## 3. Installed Filesystem Tree (OpenWrt Router)

This section describes every path installed to the router by APK, in the order a system administrator would encounter them browsing the filesystem.

### 3.1 /etc — Persistent Configuration

```
/etc/
├── config/
│   └── submihomo               ← UCI config (mode 0600)
├── init.d/
│   └── submihomo               ← procd init script (mode 0755)
└── submihomo/
    └── templates/
        └── base.yaml.tmpl      ← Mihomo config template (mode 0644)
```

#### `/etc/config/submihomo`

The UCI configuration file. This is the user-editable configuration for the entire SubMiHomo service. It is a conffile: APK will not overwrite it during upgrades if the user has modified it. See the UCI schema section of ARCHITECTURE.md for the full option list.

**Mode**: 0600 — readable only by root. This is essential because the file may contain a subscription URL with embedded authentication tokens and an external controller secret. World-readable access would expose these credentials to any process running on the router.

**OpenWrt convention**: All UCI config files live in `/etc/config/`. The filename matches the UCI config name used in `uci get submihomo.*` commands.

#### `/etc/init.d/submihomo`

The procd init script. Registered with OpenWrt's init system via `update-rc.d` or the `enable` command. When enabled, symlinks are created in `/etc/rc.d/S95submihomo` (start) and `/etc/rc.d/K05submihomo` (stop).

**Mode**: 0755 — executable by root, readable by all. OpenWrt convention for init scripts.

**OpenWrt convention**: All procd-managed services have their init script in `/etc/init.d/`. The filename matches the service name used in `service submihomo start/stop/status` commands.

#### `/etc/submihomo/templates/base.yaml.tmpl`

The Mihomo YAML config template. Contains the static structure of the config file with placeholder tokens for UCI-derived values. This file is read by `config.sh` on every service start and every `reload_config` call.

**Mode**: 0644 — readable by all (no sensitive data in the template; it contains only structure and placeholder tokens, not actual values).

**Path rationale**: Placed under `/etc/submihomo/` as a package-owned subdirectory. The `/etc/submihomo/` directory tree is owned by the `submihomo` package. Placing the template here rather than `/usr/share/submihomo/` is a judgment call: `/etc/` is for host-specific configuration, and the template is part of the service's functional configuration layer (even if the user is not expected to edit it). Advanced users who want to customize the Mihomo config structure can edit this template.

### 3.2 /usr/lib — Service Libraries and RPC Plugin

```
/usr/lib/
├── rpcd/
│   └── submihomo               ← rpcd Lua plugin (mode 0755)
└── submihomo/
    ├── core.sh                 ← Shared library (mode 0644)
    ├── config.sh               ← Config generation (mode 0755)
    ├── routing.sh              ← ip rule/route management (mode 0755)
    ├── dns.sh                  ← dnsmasq integration (mode 0755)
    ├── firewall.sh             ← nftables management (mode 0755)
    ├── subscription.sh         ← Subscription management (mode 0755)
    └── dashboard.sh            ← Zashboard management (mode 0755)
```

#### `/usr/lib/rpcd/submihomo`

The rpcd Lua plugin. rpcd scans `/usr/lib/rpcd/` at startup for executable files and loads each as a plugin. The plugin filename `submihomo` becomes the ubus object name that LuCI calls as `submihomo.<method>`.

**Mode**: 0755 — must be executable for rpcd to load it. Readable by all (rpcd runs as root but the ACL file controls what callers can invoke).

**OpenWrt convention**: All rpcd plugins live in `/usr/lib/rpcd/`. The filename determines the ubus object namespace.

#### `/usr/lib/submihomo/core.sh`

**Mode**: 0644 — not directly executable. Always sourced by other scripts with `. /usr/lib/submihomo/core.sh`.

#### `/usr/lib/submihomo/config.sh`, `routing.sh`, `dns.sh`, `firewall.sh`, `subscription.sh`, `dashboard.sh`

**Mode**: 0755 — each module can be sourced by the init script or called directly from the CLI (e.g., `subscription.sh update_cron` is called by cron). Being executable allows direct invocation for testing or scripted calls from `submihomo-ctl`.

**Path rationale**: `/usr/lib/submihomo/` is the conventional location for non-binary package libraries on OpenWrt. The directory name matches the package name for clarity. Shell scripts placed here are not intended to be called directly by users; they are library code. The exception is `subscription.sh` and `dashboard.sh` which have a dual role as libraries (sourced) and direct executables (called by cron or CLI).

### 3.3 /usr/bin — CLI Tool

```
/usr/bin/
└── submihomo-ctl               ← CLI management tool (mode 0755)
```

#### `/usr/bin/submihomo-ctl`

The primary command-line interface for SubMiHomo. Placed in `/usr/bin/` so it is in `PATH` for all users, including root's interactive shell and SSH sessions.

**Mode**: 0755 — executable by all, but most operations require root (firewall changes, UCI writes).

**Path rationale**: `/usr/bin/` is used rather than `/usr/sbin/` because `submihomo-ctl status` and `submihomo-ctl logs` are legitimately useful to non-root users (they only read data). `/usr/sbin/` implies root-only tools; `/usr/bin/` is the correct location for tools that have mixed read/write permissions.

### 3.4 /usr/share — Shared Data and UI Assets

```
/usr/share/
├── luci/
│   └── menu.d/
│       └── luci-app-submihomo.json     ← LuCI menu registration (mode 0644)
└── rpcd/
    └── acl.d/
        └── luci-app-submihomo.json     ← rpcd ACL (mode 0644)
```

#### `/usr/share/luci/menu.d/luci-app-submihomo.json`

**Mode**: 0644 — read by LuCI at runtime; no sensitive data.

**OpenWrt convention**: All LuCI application menu registrations live in `/usr/share/luci/menu.d/`. The LuCI JS framework scans this directory to build the navigation tree dynamically. This avoids the need to edit any global LuCI config file when installing or removing an app.

#### `/usr/share/rpcd/acl.d/luci-app-submihomo.json`

**Mode**: 0644 — read by rpcd at startup; no sensitive data.

**OpenWrt convention**: All rpcd ACL definitions live in `/usr/share/rpcd/acl.d/`. rpcd loads all JSON files from this directory at startup. Each file can grant permissions to any number of roles.

### 3.5 /htdocs — LuCI Static Assets

```
/htdocs/
└── luci-static/
    └── resources/
        └── view/
            └── submihomo/
                ├── overview.js         ← Overview page (mode 0644)
                ├── subscription.js     ← Subscription page (mode 0644)
                ├── settings.js         ← Settings page (mode 0644)
                ├── proxies.js          ← Proxy group page (mode 0644)
                └── logs.js             ← Log viewer page (mode 0644)
```

**Mode**: 0644 for all JS files — served as static files by uhttpd to authenticated browser sessions.

**OpenWrt convention**: LuCI JS view files live in `/htdocs/luci-static/resources/view/<appname>/`. The LuCI JS module loader resolves `view/<appname>/<filename>` to this path. uhttpd serves the entire `/htdocs/` tree as static content under `/`. The LuCI application framework provides authenticated access control at the HTTP layer before serving these files.

Note: `/htdocs/` is on the overlay filesystem (flash). This is standard for LuCI apps on OpenWrt. The JS files are not particularly large (typically 5–20 KB each) and do not change at runtime.

---

## 4. Runtime-Created Paths

These paths do not exist in the repository and are not installed by APK. They are created by the service at runtime. Understanding them is essential for debugging and operations.

### 4.1 /var/run/submihomo/ — Ephemeral Runtime State

```
/var/run/submihomo/
├── config.yaml         ← Active Mihomo config (generated at service start)
├── mihomo.pid          ← Mihomo PID file (managed by procd)
└── submihomo.lock      ← Mutex lockfile (prevents concurrent operations)
```

On OpenWrt, `/var/` is a symlink to `/tmp/`, which is a tmpfs filesystem. Everything under `/var/run/submihomo/` lives in RAM and is lost on reboot. This is intentional.

#### `/var/run/submihomo/config.yaml`

The active Mihomo configuration file, generated fresh on every service start by `config.sh`. Contains the merged content of UCI settings and the subscription YAML. Sensitive data (external controller secret, proxy server credentials from subscription) may be present in this file.

**Created by**: `config.sh` during `start_service()`.
**Destroyed by**: Tmpfs reset on reboot; also deleted during `stop_service()` (optional, but clean).
**Mode**: 0600 — contains proxy credentials from subscription. Only root should read this file.

**Why tmpfs**: Generating this file from scratch on every start ensures it always reflects the current UCI configuration and the current subscription. There is no stale state from a previous run. It also avoids flash writes on every config regeneration, which is important for flash longevity on MIPS routers.

#### `/var/run/submihomo/mihomo.pid`

The PID file for the Mihomo process. Created and managed by procd when it spawns Mihomo. Used by `submihomo-ctl status` and the rpcd `status()` method to read Mihomo's PID.

**Created by**: procd when Mihomo is spawned.
**Destroyed by**: procd when Mihomo exits; tmpfs reset on reboot.
**Mode**: 0644.

#### `/var/run/submihomo/submihomo.lock`

A lockfile used by `core.sh`'s mutex helpers to prevent concurrent subscription updates, config regeneration, or service restarts from racing. The lock is acquired by writing the current PID to the file and released by deleting the file.

**Created by**: `core.sh` `acquire_lock()`.
**Destroyed by**: `core.sh` `release_lock()`; tmpfs reset on reboot.
**Mode**: 0644.

### 4.2 /etc/submihomo/subscriptions/ — Persistent Subscription Storage

```
/etc/submihomo/
└── subscriptions/
    ├── current.yaml    ← Active subscription YAML
    └── backup.yaml     ← Previous subscription (kept for rollback)
```

This directory lives under `/etc/` on the overlay filesystem (persistent across reboots). Subscription data is user data that must persist.

#### `/etc/submihomo/subscriptions/current.yaml`

The active subscription file. Downloaded from the user's subscription URL and validated before being placed here. This file is the source for the `proxies:`, `proxy-groups:`, and `rules:` sections in the generated `config.yaml`.

**Created by**: `subscription.sh` `subscription_apply()` on first update or install.
**Updated by**: Every successful subscription update.
**Mode**: 0600 — may contain proxy server hostnames and authentication credentials.

**Why /etc/submihomo/subscriptions/ and not /var/**: The subscription represents user data. Losing it on reboot would mean the service cannot start (no proxies configured). It must persist.

**Why not /etc/config/**: The subscription YAML is not a UCI file and is not managed by the UCI system. Placing it under `/etc/config/` would be a convention violation. `/etc/submihomo/` is the correct namespace for package-specific persistent data.

#### `/etc/submihomo/subscriptions/backup.yaml`

A copy of the previous `current.yaml`. Created atomically before each subscription update. Used to restore service in case a new subscription causes problems. Only one level of backup is maintained (the most recent previous version).

**Created by**: `subscription.sh` `subscription_apply()`, by moving the old `current.yaml`.
**Restored by**: `subscription.sh` `subscription_restore()` on failed updates.
**Mode**: 0600.

### 4.3 /usr/share/submihomo/dashboard/ — Zashboard Assets

```
/usr/share/submihomo/dashboard/
├── index.html
├── assets/
│   ├── index-*.js
│   └── index-*.css
└── .version                    ← Version tag written by dashboard.sh
```

The Zashboard dashboard static files, downloaded from GitHub Releases by `dashboard.sh`. Served by Mihomo at `http://router-ip:9090/ui` via the `external-ui` config directive.

**Created by**: `dashboard.sh` `dashboard_download()`, called automatically on first service start if directory is empty, or on demand via `submihomo-ctl update-dashboard`.
**Mode**: 0755 for directory, 0644 for all files.

**Why /usr/share/submihomo/dashboard/ and not /var/**: Dashboard assets are 2–5 MB of static files that would take 10–20 seconds to re-download on every boot over a WAN connection. Placing them on flash (persistent) avoids this latency and unnecessary GitHub API calls. The trade-off is flash space consumption.

**Why not served by uhttpd directly**: Mihomo's built-in static file server is used so that the dashboard and the Mihomo API share the same origin (host:9090). This avoids CORS issues when the dashboard JS makes API calls to `/api/*`.

### 4.4 /etc/dnsmasq.d/submihomo.conf — DNS Injection

```
/etc/dnsmasq.d/
└── submihomo.conf              ← Single-line dnsmasq upstream directive
```

A single-line file created on service start and removed on service stop. Its content is always:

```
server=/#/127.0.0.1#1053
```

**Created by**: `dns.sh` `dns_setup()`.
**Destroyed by**: `dns.sh` `dns_teardown()`.
**Mode**: 0644 — dnsmasq reads this as root; no sensitive data.

**Why /etc/dnsmasq.d/ and not a dnsmasq UCI option**: The dnsmasq UCI config on OpenWrt (`/etc/config/dhcp`) does not support a "forward all" directive in a way that can be cleanly added and removed without editing the main config. The `/etc/dnsmasq.d/` drop-in directory is the standard mechanism for packages to add dnsmasq configuration without touching the main config file. Removing this file and sending SIGHUP to dnsmasq is a completely reversible, clean operation.

**Note on /etc/ placement**: Although this file is under `/etc/`, it is ephemeral in function (removed on service stop). Its placement in `/etc/dnsmasq.d/` is dictated by dnsmasq's config loading mechanism, not by SubMiHomo's persistence requirements. This is a known architectural quirk; the file is effectively runtime state that lives in a persistent path.

---

## 5. File Permissions Table

The following table covers every file installed by APK plus all runtime-created paths.

| Path | Mode | Owner | Group | Notes |
|---|---|---|---|---|
| `/etc/config/submihomo` | 0600 | root | root | Contains credentials (conffile) |
| `/etc/init.d/submihomo` | 0755 | root | root | Executable init script |
| `/etc/submihomo/` | 0755 | root | root | Package directory |
| `/etc/submihomo/templates/` | 0755 | root | root | Template directory |
| `/etc/submihomo/templates/base.yaml.tmpl` | 0644 | root | root | No sensitive data |
| `/usr/lib/submihomo/` | 0755 | root | root | Library directory |
| `/usr/lib/submihomo/core.sh` | 0644 | root | root | Sourced, not executed directly |
| `/usr/lib/submihomo/config.sh` | 0755 | root | root | Executable (direct call + source) |
| `/usr/lib/submihomo/routing.sh` | 0755 | root | root | Executable |
| `/usr/lib/submihomo/dns.sh` | 0755 | root | root | Executable |
| `/usr/lib/submihomo/firewall.sh` | 0755 | root | root | Executable |
| `/usr/lib/submihomo/subscription.sh` | 0755 | root | root | Executable (cron + source) |
| `/usr/lib/submihomo/dashboard.sh` | 0755 | root | root | Executable |
| `/usr/lib/rpcd/submihomo` | 0755 | root | root | Must be executable for rpcd |
| `/usr/bin/submihomo-ctl` | 0755 | root | root | In PATH |
| `/usr/share/luci/menu.d/luci-app-submihomo.json` | 0644 | root | root | Static data |
| `/usr/share/rpcd/acl.d/luci-app-submihomo.json` | 0644 | root | root | Static data |
| `/htdocs/luci-static/resources/view/submihomo/overview.js` | 0644 | root | root | Served as static asset |
| `/htdocs/luci-static/resources/view/submihomo/subscription.js` | 0644 | root | root | Served as static asset |
| `/htdocs/luci-static/resources/view/submihomo/settings.js` | 0644 | root | root | Served as static asset |
| `/htdocs/luci-static/resources/view/submihomo/proxies.js` | 0644 | root | root | Served as static asset |
| `/htdocs/luci-static/resources/view/submihomo/logs.js` | 0644 | root | root | Served as static asset |
| `/var/run/submihomo/` | 0755 | root | root | Created at service start (tmpfs) |
| `/var/run/submihomo/config.yaml` | 0600 | root | root | Contains proxy credentials |
| `/var/run/submihomo/mihomo.pid` | 0644 | root | root | PID file |
| `/var/run/submihomo/submihomo.lock` | 0644 | root | root | Lockfile |
| `/etc/submihomo/subscriptions/` | 0700 | root | root | Contains credential data |
| `/etc/submihomo/subscriptions/current.yaml` | 0600 | root | root | Subscription data |
| `/etc/submihomo/subscriptions/backup.yaml` | 0600 | root | root | Subscription backup |
| `/usr/share/submihomo/` | 0755 | root | root | Created by dashboard.sh |
| `/usr/share/submihomo/dashboard/` | 0755 | root | root | Zashboard files |
| `/usr/share/submihomo/dashboard/.version` | 0644 | root | root | Version marker |
| `/etc/dnsmasq.d/submihomo.conf` | 0644 | root | root | Created/removed at runtime |

---

## 6. Path Choice Rationale — OpenWrt Conventions

OpenWrt follows the FHS (Filesystem Hierarchy Standard) with router-specific conventions. The following table explains why each directory was chosen.

| Directory | FHS / OpenWrt convention | SubMiHomo usage |
|---|---|---|
| `/etc/config/` | OpenWrt-specific: all UCI config files | `submihomo` UCI config |
| `/etc/init.d/` | Standard SysV/OpenWrt: init scripts | `submihomo` init script |
| `/etc/<package>/` | OpenWrt convention for package-specific config and data | Templates, subscription data |
| `/etc/dnsmasq.d/` | dnsmasq drop-in directory, OpenWrt standard | DNS forwarding directive |
| `/usr/lib/<package>/` | FHS: non-binary libraries for package | Shell module libraries |
| `/usr/lib/rpcd/` | OpenWrt-specific: rpcd plugin directory | Lua rpcd plugin |
| `/usr/bin/` | FHS: user-accessible binaries | `submihomo-ctl` CLI |
| `/usr/share/luci/menu.d/` | OpenWrt LuCI convention: menu registrations | LuCI menu entry |
| `/usr/share/rpcd/acl.d/` | OpenWrt rpcd convention: ACL definitions | rpcd ACL |
| `/htdocs/luci-static/resources/view/` | OpenWrt LuCI JS convention: view modules | LuCI JS pages |
| `/var/run/<package>/` | FHS: runtime state files (tmpfs on OpenWrt) | config.yaml, PID, lock |
| `/usr/share/<package>/` | FHS: package-specific read-only shared data | Zashboard dashboard |

### Special Case: `/etc/submihomo/subscriptions/`

This path sits in an interesting position. It is under `/etc/` (persistent configuration) but contains what is functionally user data (the subscription YAML). The FHS would suggest `/var/lib/<package>/` for persistent package state. However, on OpenWrt:

- `/var/` is tmpfs — persistent data cannot go here.
- `/usr/share/` is for read-only data — mutable subscription files should not go here.
- `/etc/<package>/` is the established OpenWrt convention for persistent package-specific data when `/var/lib/` is not available.

The `subscriptions/` subdirectory has mode 0700 (not just the files) so that a directory listing cannot expose filenames to non-root processes even if file permissions were somehow misconfigured.

### Special Case: `/usr/share/submihomo/dashboard/`

The Zashboard files are downloaded at runtime (not installed by APK), but stored in `/usr/share/`, which is conventionally for read-only installed data. This is acceptable because:

- The files are static assets that do not change at runtime (only updated by `dashboard.sh`).
- `/usr/share/` is on the overlay filesystem and is writable in practice on OpenWrt.
- The alternative (`/var/lib/submihomo/dashboard/`) would require a tmpfs path that loses files on reboot.
- Mihomo's `external-ui` directive requires a stable, persistent path.

---

## 7. Persistent vs. Runtime Storage

Understanding which storage tier holds which files is critical for reasoning about service behavior across reboots, power loss, and firmware upgrades.

```mermaid
flowchart TD
    subgraph FLASH["Flash (Overlay FS — persistent)"]
        F1[/etc/config/submihomo]
        F2[/etc/init.d/submihomo]
        F3[/etc/submihomo/templates/base.yaml.tmpl]
        F4[/etc/submihomo/subscriptions/current.yaml]
        F5[/etc/submihomo/subscriptions/backup.yaml]
        F6[/usr/lib/submihomo/*.sh]
        F7[/usr/lib/rpcd/submihomo]
        F8[/usr/bin/submihomo-ctl]
        F9[/usr/share/luci/menu.d/*.json]
        F10[/usr/share/rpcd/acl.d/*.json]
        F11[/usr/share/submihomo/dashboard/]
        F12[/htdocs/luci-static/resources/view/submihomo/*.js]
    end

    subgraph TMPFS["tmpfs /var = /tmp — lost on reboot"]
        T1[/var/run/submihomo/config.yaml]
        T2[/var/run/submihomo/mihomo.pid]
        T3[/var/run/submihomo/submihomo.lock]
    end

    subgraph VOLATILE["Volatile — ephemeral by design"]
        V1[/etc/dnsmasq.d/submihomo.conf\ncreated on start, removed on stop]
        V2[/tmp/sub_download.yaml\ntemporary download buffer]
        V3[/tmp/zashboard_dist.zip\ntemporary download buffer]
    end

    FLASH -->|"service start reads"| TMPFS
    TMPFS -->|"Mihomo reads config.yaml"| TMPFS
    FLASH -->|"dns_setup writes, dns_teardown removes"| VOLATILE
```

### Reboot Behavior

On reboot:

1. All tmpfs content (`/var/run/submihomo/`) is lost. This is intentional — the config is regenerated fresh on next start.
2. All flash content survives: UCI config, subscription files, shell modules, dashboard assets.
3. `/etc/dnsmasq.d/submihomo.conf` may or may not survive depending on whether a clean stop was performed. The `stop_service()` function removes it, but a hard power loss will leave it present. This is safe: dnsmasq will load it on boot and forward DNS to port 1053, but Mihomo is not yet running. dnsmasq will retry forwarding and eventually return SERVFAIL until the service starts. This is a known startup race; the START priority 95 ensures the service starts within seconds of boot.

### Firmware Upgrade Behavior

When OpenWrt firmware is upgraded:

- The base SquashFS layer is replaced.
- The JFFS2 overlay is preserved **only for conffiles** explicitly declared in the APK package.
- All installed package files are reinstalled from APK packages.
- `/etc/config/submihomo` is a conffile and is preserved.
- `/etc/submihomo/subscriptions/` is persistent data and survives if it is listed as preserved in the sysupgrade configuration.

Operators should add `/etc/submihomo/subscriptions/` to `/etc/sysupgrade.conf` to ensure subscription data survives firmware upgrades. The `install.sh` script should add this entry automatically.

---

## 8. Flash Storage Impact

Flash storage is a critical constraint on MIPS routers. The following table estimates the contribution of each SubMiHomo component to flash usage.

| Component | Path | Estimated Size | Notes |
|---|---|---|---|
| `mihomo` binary | `/usr/bin/mihomo` | 8–15 MB | Dominant cost; upstream package; MIPS build |
| Shell modules (all 7) | `/usr/lib/submihomo/` | 30–60 KB | Compressed in SquashFS |
| rpcd Lua plugin | `/usr/lib/rpcd/submihomo` | 10–20 KB | Lua source |
| Init script | `/etc/init.d/submihomo` | 5–10 KB | Shell |
| CLI tool | `/usr/bin/submihomo-ctl` | 5–10 KB | Shell |
| Config template | `/etc/submihomo/templates/base.yaml.tmpl` | 1–3 KB | YAML |
| UCI default config | `/etc/config/submihomo` | 1–2 KB | UCI text |
| LuCI JS views (5 files) | `/htdocs/luci-static/resources/view/submihomo/` | 20–60 KB | JS source |
| LuCI menu JSON | `/usr/share/luci/menu.d/` | < 1 KB | JSON |
| rpcd ACL JSON | `/usr/share/rpcd/acl.d/` | < 1 KB | JSON |
| **submihomo package total** | | **~80–170 KB** | Excluding Mihomo binary |
| **luci-app-submihomo package total** | | **~25–65 KB** | JS views + menu + ACL |
| **Zashboard dashboard** | `/usr/share/submihomo/dashboard/` | **2–5 MB** | Downloaded at runtime |
| **Subscription YAML** | `/etc/submihomo/subscriptions/` | **10–500 KB** | Depends on subscription size |

### Summary by Installation Profile

| Profile | Components | Approximate Flash Cost |
|---|---|---|
| Minimal (no LuCI, no dashboard) | mihomo + submihomo | 8.1–15.2 MB |
| Standard | mihomo + submihomo + luci-app-submihomo | 8.2–15.3 MB |
| Full (with Zashboard) | Standard + dashboard download | 10–21 MB |

### SquashFS Compression

OpenWrt packages are installed into the SquashFS overlay. Text files (shell scripts, JSON, YAML) compress extremely well under SquashFS's LZ4 or LZMA compression. The actual flash consumed by the SubMiHomo shell modules and JS views is likely 40–60% of their uncompressed size. The Mihomo binary compresses less aggressively (binaries typically achieve 50–70% compression).

### Flash Write Frequency

Flash longevity depends on write frequency. SubMiHomo minimizes writes to flash:

- **High-frequency writes are on tmpfs**: `config.yaml`, `mihomo.pid`, and the lockfile are all on tmpfs. No flash write occurs on service start/stop for these.
- **Subscription files on flash**: `/etc/submihomo/subscriptions/current.yaml` and `backup.yaml` are written on each subscription update. With a 24-hour update interval, this is at most one write per day — negligible for NAND flash rated at 100,000+ write cycles.
- **Dashboard files on flash**: `/usr/share/submihomo/dashboard/` is written only when `submihomo-ctl update-dashboard` is called manually, or when auto-update is triggered. This is infrequent.
- **dnsmasq config**: `/etc/dnsmasq.d/submihomo.conf` is written on service start and deleted on service stop. On a stable router, this is a small number of writes per day at most.

---

*End of FILESYSTEM.md*
