# IMPLEMENTATION_PROMPT.md

> **This is not documentation. This is an execution prompt for the implementation engineer (human or AI agent) who will build SubMiHomo.**
> Read this file first. Then read every document it references, in the order listed, before writing a single line of code.

---

## 0. What You Are Building

**SubMiHomo** is an OpenWrt 25+ service package that wraps the **Mihomo** proxy core to deliver fully automatic, transparent, system-wide proxy routing. The product philosophy is one sentence, and it is non-negotiable:

> **Paste an HTTPS subscription URL. Click Apply. Everything else happens automatically.**

The end user never touches routing tables, nftables, ip rules, DNS configuration, or YAML. They see a subscription URL field, a handful of high-level toggles, and a status page. Every low-level networking concept is hidden behind SubMiHomo's automation.

You are the implementation engineer. **You do not redesign anything.** Every architectural decision has already been made and is recorded in the documents in `docs/`. Your job is to implement exactly what is specified — nothing more, nothing less, nothing different.

---

## 1. Required Reading (in this order)

Before writing any code, read every one of these documents in full. They are the complete, authoritative specification. If something you're about to build isn't described in these documents, **stop and re-read** — it is virtually certain the answer is already there.

1. `docs/ARCHITECTURE.md` — overall system design, philosophy, data flows, technology justifications
2. `docs/FILESYSTEM.md` — exact repository layout and installed filesystem layout
3. `docs/COMPONENTS.md` — every module's responsibilities, interfaces, dependencies
4. `docs/BOOT.md` — procd lifecycle, startup/shutdown sequencing, failure recovery
5. `docs/NETWORK.md` — TPROXY, nftables, policy routing, DNS packet flow (the technical heart of the project)
6. `docs/UCI.md` — complete configuration schema, validation, migration
7. `docs/SUBSCRIPTIONS.md` — subscription download, validation, merge, rollback
8. `docs/DASHBOARD.md` — Zashboard download, hosting, integration
9. `docs/RPC.md` — rpcd plugin, all 12 ubus methods, data contracts
10. `docs/LUCI.md` — all 5 LuCI JS pages, UX flows, RPC call patterns
11. `docs/LOGGING.md` — logging conventions, syslog usage
12. `docs/DIAGNOSTICS.md` — all 12 health checks
13. `docs/SECURITY.md` — threat model, permissions, secrets handling
14. `docs/INSTALL.md` — APK packaging, install/update/uninstall scripts
15. `docs/TESTING.md` — testing strategy across all 4 layers
16. `docs/ROADMAP.md` — the 16-phase build order with entry/exit criteria
17. `docs/TASKS.md` — the granular T-001…T-098 task breakdown you will execute

Every document cross-references the others using consistent terminology (file paths, function names, UCI option names, RPC method names, port numbers, fwmark values). If you ever find an apparent contradiction between two documents, **stop and flag it** rather than guessing — but this should not happen, as the documents were authored as a single consistent specification.

---

## 2. Non-Negotiable Technology Decisions

These decisions are final. Do not substitute, "improve," or add alternatives.

| Concern | Decision | Forbidden alternatives |
|---|---|---|
| Proxy core | Mihomo only | Xray, sing-box, any Clash derivative |
| Package manager | APK | opkg |
| Firewall | fw4 + nftables | iptables, iptables-legacy |
| Traffic interception | TPROXY (TCP+UDP) | REDIRECT, DNAT, TUN/TAP |
| Init system | procd | runit, systemd, custom daemonization |
| Frontend | LuCI JS (modern view framework) | LuCI CBI/classic Lua templates, a separate SPA, Vue/React build pipeline |
| RPC transport | rpcd Lua plugin over ubus | Direct shell exec from LuCI, a custom HTTP API, CGI scripts |
| DNS | dnsmasq forwarding to Mihomo DNS (127.0.0.1:1053) | Replacing dnsmasq, unbound, a second DNS daemon |
| Dashboard | Zashboard, served via Mihomo `external-ui` | Yacd, MetaCubeX dashboard, a custom UI |
| Config generation | POSIX shell + `awk`/`sed` template substitution | A YAML library, Python/Node.js tooling at runtime |
| IPv6 | Not supported (explicitly out of scope) | Any IPv6 handling |
| Shell dialect | POSIX `sh` (BusyBox ash compatible) | bash-isms, `[[ ]]`, arrays, `local` misuse beyond ash support |

Ports, fwmarks, routing table numbers, and file paths are fixed exactly as specified in `docs/ARCHITECTURE.md` and `docs/NETWORK.md` (TPROXY=7891, Mixed=7890, DNS=1053, Controller=9090, fwmark 1 for intercepted traffic, fwmark 255/0xff for Mihomo's own traffic via `routing-mark: 255`, routing table 100 with `local default dev lo`). Do not renumber or relocate any of these.

---

## 3. Forbidden Practices

The following are explicitly forbidden anywhere in this codebase, with no exceptions:

- Rewriting or reinterpreting any architectural decision documented in `docs/`.
- Changing module boundaries described in `docs/COMPONENTS.md` (e.g., merging `dns.sh` and `routing.sh`, or splitting `core.sh` into multiple files).
- Changing any public interface/function signature described in `docs/COMPONENTS.md` or any RPC method contract described in `docs/RPC.md`.
- Introducing a new runtime dependency (a new package, a new binary, a new language runtime) that is not already named in `docs/INSTALL.md`'s dependency table, without first stopping and raising the question — this project's architecture is closed with respect to dependencies.
- Large monolithic files. Every module has a documented line-count budget in `docs/ROADMAP.md`/`docs/TASKS.md` — respect it. If a module is approaching its budget, that is a signal you have drifted from the intended scope, not a license to keep growing the file.
- Duplicated logic between modules. Shared behavior belongs in `core.sh` and is sourced, never copy-pasted.
- "Temporary" solutions, stub implementations, or placeholder logic of any kind.
- `TODO`, `FIXME`, "not yet implemented," "will add later," or any similar marker in shipped code. If a task's scope is incomplete, the task is not done — it does not ship partially.
- Incomplete error handling. Every external command invocation (`uci`, `nft`, `ip`, `wget`, `mihomo`, `dnsmasq`) must have its exit code checked and handled per the behavior documented in `docs/BOOT.md` and `docs/COMPONENTS.md`.
- Calling shell scripts directly from Lua/LuCI instead of going through the documented ubus/rpcd path (see `docs/RPC.md` §1–2).
- Polling loops or `sleep`-based synchronization where an event-driven or check-then-act approach is documented instead.
- Any IPv6-handling code path, however small.

---

## 4. Coding Standards

### Shell (`.sh` files, `/etc/init.d/submihomo`, `/usr/bin/submihomo-ctl`)

- POSIX `sh` syntax only, compatible with BusyBox `ash`. Test with `shellcheck --shell=sh`.
- Every module begins by sourcing `/usr/lib/submihomo/core.sh` for shared constants, logging, and UCI helpers. Never redefine a constant or logging function locally.
- No global mutable state beyond what `core.sh` defines as constants. Functions take arguments and return via exit codes / stdout, not shared variables set as a side effect (unless explicitly documented in `docs/COMPONENTS.md`).
- Every function has a single, clearly named responsibility matching its documented public interface in `docs/COMPONENTS.md` (e.g., `routing_setup()`, `routing_teardown()`, `config_generate()`).
- All setup functions (`routing_setup`, `dns_setup`, `firewall_setup`) must be **idempotent**: calling them twice in a row must not error or create duplicate state. All teardown functions must succeed even if the corresponding setup never ran.
- Logging must use the `log_debug`/`log_info`/`log_warn`/`log_error` functions from `core.sh` exactly as specified in `docs/LOGGING.md`. Never call `logger` directly from other modules.
- Respect the per-module line-count budgets listed in `docs/ROADMAP.md`/`docs/TASKS.md` conventions.

### Lua (`/usr/lib/rpcd/submihomo`)

- Implement exactly the 12 methods specified in `docs/RPC.md`, with exactly the input/output schemas documented there — no additional methods, no renamed fields.
- Use the OpenWrt-provided `uci` Lua binding for configuration access, not shelling out to the `uci` CLI, for performance on embedded CPUs.
- Every method must enforce the REDACTED behavior for `external_controller_secret` exactly as specified in `docs/RPC.md` and `docs/SECURITY.md`.
- Respect the documented per-method timeouts and ACL read/write classification (`docs/RPC.md` §5–6).

### LuCI JS (`/htdocs/luci-static/resources/view/submihomo/*.js`)

- Use the modern LuCI JS `view.extend()` framework and `rpc.declare()` for RPC calls, exactly as documented in `docs/LUCI.md`.
- No client-side framework beyond what LuCI JS already ships (no jQuery, no Vue, no React, no bundler).
- Every page must handle the loading / error / success states described in `docs/LUCI.md` — never assume an RPC call succeeds.
- Never call the Mihomo HTTP API directly from the browser. All Mihomo API access is proxied through the rpcd plugin (`get_proxies`, `test_connection`) per `docs/RPC.md` and `docs/LUCI.md`.

### Makefile / packaging

- Follow the `Package/submihomo` and `Package/luci-app-submihomo` definitions and dependency lists exactly as specified in `docs/INSTALL.md`.
- File installation destinations must match `docs/FILESYSTEM.md` exactly, including permission modes from the table in that document.

---

## 5. Repository Layout You Must Produce

Build exactly the tree documented in `docs/FILESYSTEM.md` §2 ("Complete repository source tree"). Do not add extra top-level directories. Do not rename any file. If you believe a file is missing from the specification, re-read `docs/FILESYSTEM.md` and `docs/COMPONENTS.md` fully before concluding that — it is far more likely the file is described and you have not found it yet.

---

## 6. Implementation Order — 16 Mandatory Phases

You must implement the project in the exact phase order defined in `docs/ROADMAP.md`, decomposed into the exact tasks defined in `docs/TASKS.md` (T-001 through T-098). **Do not skip ahead.** Each phase depends on the deliverables of every phase before it.

1. **Phase 1 — Repository skeleton** (T-001–T-004)
2. **Phase 2 — Package build system** (T-005–T-008)
3. **Phase 3 — Core service** (T-009–T-013)
4. **Phase 4 — procd integration** (T-014–T-018)
5. **Phase 5 — UCI** (T-019–T-022)
6. **Phase 6 — RPC** (T-023–T-034)
7. **Phase 7 — Subscription manager** (T-035–T-042)
8. **Phase 8 — Mihomo config generator** (T-043–T-051)
9. **Phase 9 — DNS manager** (T-052–T-055)
10. **Phase 10 — Routing manager** (T-056–T-059)
11. **Phase 11 — Firewall manager** (T-060–T-065)
12. **Phase 12 — LuCI frontend** (T-066–T-073)
13. **Phase 13 — Diagnostics** (T-074–T-079)
14. **Phase 14 — Installer** (T-080–T-086)
15. **Phase 15 — Dashboard** (T-087–T-091)
16. **Phase 16 — Release packaging** (T-092–T-098)

**Milestones** (from `docs/ROADMAP.md`):

- **M1 — Service skeleton** (after Phase 3): procd can start/stop an empty `submihomo` service.
- **M2 — Core working** (after Phase 8): a real subscription produces a valid Mihomo config that `mihomo -t` accepts.
- **M3 — Full feature** (after Phase 12): traffic is actually proxied end-to-end, LuCI is usable.
- **M4 — Production ready** (after Phase 16): installable, tested, signed, released.

### Phase-completion rule

**A phase is not complete until its exit criteria, as written in `docs/ROADMAP.md` §2 for that phase, are demonstrated — not merely code-reviewed.** For shell modules this means actually running them (on real OpenWrt 25+ hardware/QEMU, or the mocked test harness described in `docs/TESTING.md` where hardware is unavailable) and observing the documented result: a routing table appearing, an nftables table appearing, a config file validating with `mihomo -t`, an RPC method returning the documented JSON shape via `ubus call`, etc.

Do not proceed to the next phase until:
1. All tasks for the current phase (per `docs/TASKS.md`) meet their individual acceptance criteria.
2. The current phase's exit criteria (per `docs/ROADMAP.md`) are demonstrated.
3. `shellcheck --shell=sh` is clean on every shell file touched.
4. No regression exists in any previously completed phase's exit criteria (re-verify, don't assume).

---

## 7. Quality Requirements

- **Single Responsibility Principle** at the file and function level — every module documented in `docs/COMPONENTS.md` does exactly one thing.
- **Loose coupling, high cohesion** — modules communicate only through their documented public interfaces (function calls with defined arguments/return codes, or RPC method calls with defined JSON schemas), never through incidental shared state.
- **No architectural debt** — if you find yourself wanting to defer a decision, stop. The decision has already been made in `docs/`. Find it and implement it.
- **Idempotency** everywhere state is created (routing, firewall, DNS config) — see `docs/BOOT.md` and `docs/NETWORK.md` for exact idempotency requirements.
- **Complete cleanup** — everything `firewall_setup`, `routing_setup`, and `dns_setup` create must be fully reversible by their corresponding teardown functions, verified by the integration tests in `docs/TESTING.md`.
- **Fail loud, fail safe** — a module that cannot complete its job must log a clear error (per `docs/LOGGING.md`) and cause the service to refuse to start in a half-configured state (per `docs/BOOT.md`'s failure-handling sections), never silently continue with partial setup.

---

## 8. Testing Requirements

Follow `docs/TESTING.md` exactly. You are required to produce and pass all four testing layers before a phase or the project as a whole is considered done:

1. **Unit tests** (`tests/unit/`) — shell function tests with mocked `uci`/`nft`/`ip`/`logger`/`wget`/`mihomo`.
2. **Integration tests** (`tests/integration/`) — real `nft`/`ip` invocations in a Linux container/namespace, a mock HTTPS subscription server.
3. **System tests** — full smoke test on QEMU OpenWrt (or real mipsel_24kc hardware if available), covering both DNS modes, subscription update, and dashboard download.
4. **Build tests** (GitHub Actions) — OpenWrt SDK package build, APK structure and permission verification, unit test execution in CI.

Every task in `docs/TASKS.md` includes explicit, testable acceptance criteria — treat them as your test specification. A task is not complete until its acceptance criteria pass, demonstrated (not assumed).

---

## 9. Acceptance Criteria for the Complete Project (v1.0.0)

Reproduced from `docs/ROADMAP.md` — the project is not done until **all** of the following are true:

1. A fresh OpenWrt 25+ router can be set up with **one command** (`docs/INSTALL.md`'s `install.sh`).
2. After pasting a subscription URL in LuCI and clicking Apply, all LAN traffic is transparently proxied with zero further user configuration.
3. Disabling the service completely removes every routing, DNS, and firewall change it made (verified by diagnostics and integration tests).
4. Subscription auto-updates work correctly on the user-configured schedule.
5. Zashboard is reachable and displays correct, live proxy data from Mihomo.
6. All 12 diagnostic checks (`docs/DIAGNOSTICS.md`) pass on a correctly functioning installation.
7. All automated tests (all four layers) pass in CI.
8. The package installs cleanly, with no errors, on mipsel_24kc.
9. The service auto-starts correctly after a router reboot.
10. `apk upgrade` on the packages preserves the user's existing UCI configuration and subscription data.

---

## 10. What To Do If You Get Stuck

- If a detail seems missing: re-read the relevant document section fully. The specification is intentionally exhaustive; the answer is very likely present.
- If two documents seem to genuinely conflict: stop, do not guess, and report the specific conflicting statements (document name + section) rather than picking one arbitrarily.
- If you believe a documented design is technically unworkable on OpenWrt 25+/mipsel_24kc: stop, document the specific technical blocker with evidence (e.g., a command that fails, a missing kernel module), and report it rather than silently substituting your own design.
- You are never authorized to invent new architecture to fill a perceived gap. Every architectural question this project has was already answered during the design phase captured in `docs/`.

---

## 11. Final Note

This specification was written so that two independent engineers, given only the documents in `docs/` and this prompt, would produce nearly identical implementations. That is the bar. Build exactly what is specified, in the specified order, validated at each step, and SubMiHomo will deliver on its founding promise: **paste a subscription, click Apply, and everything else happens automatically.**
