# Changelog

All notable changes to SubMiHomo are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0-rc1] — 2026-07-04 (Release Candidate 1)

### Overview

SubMiHomo v1.0.0-rc1 is the first public release candidate of the OpenWrt 25+ Mihomo proxy service wrapper. This release delivers a fully automatic, transparent, system-wide proxy routing solution with a simple LuCI web interface. Audit is complete, and the project is ready for community testing before v1.0.0 stable.

### Added

- **Complete OpenWrt service package** with transparent TPROXY interception, DNS hijacking, policy routing, and automatic firewall management
- **LuCI web interface** for configuration and monitoring (JavaScript frontend, rpcd backend)
- **Subscription management** with download, validation (YAML schema + Mihomo validation), merge, and automatic refresh scheduling
- **Mihomo proxy core** integration with automatic detection of CPU architecture and managed installation
- **Zashboard integration** (optional): web dashboard for traffic analysis and configuration, installed and updated automatically
- **External controller API** on port 9090 with secret-based authentication and LAN-only access by default
- **Policy routing** via nftables and iproute2 for selective proxy bypass
- **DNS hijacking** with Fake-IP and Real-IP mode support, automatic `/etc/resolv.conf` rewriting
- **Health checks** and automatic recovery: procd monitors Mihomo process, logs all startup/shutdown events
- **UCI configuration schema** with validation, migration, and default fallback behavior
- **Comprehensive documentation** covering architecture, components, network design, security model, and operations (17 reference documents)
- **Test suite** with unit, integration, and system tests

### Features (Phase 1 Improvements)

- **Enhanced mihomo.sh** with improved error handling, exit codes, and logging
- **Graceful degradation** if Mihomo crashes or subscription refresh fails
- **Template-based configuration** for proxy groups and policy rules
- **Atomic subscription activation** (validate before swap, keep previous on rollback)
- **Secure secret storage** in `/etc/config/submihomo` with mode 0600
- **Firewall rule cleanup** on stop, package remove, and crash recovery
- **Debug mode** for troubleshooting with verbose logging to syslog

### Security

- **Threat model analysis** covering local, remote, compromised subscription, and physical attack scenarios
- **Privilege separation** where possible; Mihomo runs as non-root during normal operation
- **Subscription validation** with YAML schema enforcement and Mihomo syntax checking before activation
- **YAML injection prevention** via strict template boundaries and parameterized configuration
- **Secret management** with automatic generation, secure storage, and no logging
- **Firewall isolation** by default (WAN-facing listeners blocked by fw4)
- **rpcd ACL enforcement** for LuCI operations

See [`SECURITY.md`](SECURITY.md) and [`docs/SECURITY.md`](docs/SECURITY.md) for complete security architecture and threat model.

### Known Limitations

- **IPv6**: Not supported in v1.0.0-rc1; listed as future enhancement
- **External controller exposure**: If exposed to untrusted networks, requires a strong secret (minimum 8 characters, alphanumeric + symbols recommended)
- **Physical storage**: Configuration files are unencrypted on flash (accepted risk consistent with OpenWrt)
- **Proxy provider trust**: Proxy operator has visibility into all proxied traffic content (inherent to proxy design)

### Documentation

Complete documentation set available in `docs/`:

1. **ARCHITECTURE.md** — System design, philosophy, and high-level diagrams
2. **FILESYSTEM.md** — Repository and installed filesystem layout
3. **COMPONENTS.md** — Module responsibilities, interfaces, and lifecycle
4. **BOOT.md** — procd lifecycle and startup order
5. **NETWORK.md** — TPROXY, nftables, policy routing, and DNS flow
6. **UCI.md** — UCI schema, defaults, validation, and migration
7. **SUBSCRIPTIONS.md** — Download, validation, merge, and refresh scheduling
8. **DASHBOARD.md** — Zashboard integration and installation
9. **RPC.md** — rpcd/ubus methods, ACLs, and data contracts
10. **LUCI.md** — LuCI page structure and frontend/backend communication
11. **LOGGING.md** — Logging system and syslog conventions
12. **DIAGNOSTICS.md** — Health checks, self-tests, and recovery
13. **SECURITY.md** — Threat model, controls, and vulnerability reporting
14. **INSTALL.md** — APK repository and install/update/uninstall scripts
15. **TESTING.md** — Unit, integration, and system test strategy
16. **ROADMAP.md** — 16-phase development plan
17. **TASKS.md** — Granular task breakdown (T-001–T-098)

### Testing

- Unit tests: `bash tests/unit/run_all.sh`
- Integration tests: `bash tests/integration/run_all.sh`
- System tests: `bash tests/system/run_all.sh`
- Static analysis: `shellcheck -x files/usr/lib/submihomo/*.sh`

All tests passing. See `docs/TESTING.md` for details.

### Installation

Install from a release build or build from source:

```sh
# One-step install (OpenWrt 25+)
sh <(wget -qO- https://raw.githubusercontent.com/Conv3lsive/SubMiHomo/main/install/install.sh)
```

See [`docs/INSTALL.md`](docs/INSTALL.md) for full installation, update, and uninstall procedures.

### Roadmap to v1.0.0 Stable

Before v1.0.0 stable release:

- ✅ Code review and audit (complete)
- ⏳ Community testing and feedback (RC phase)
- ⏳ Bug fixes for reported issues
- ⏳ Documentation polish
- ⏳ Release and publish

For v1.0.1 and beyond, see `docs/ROADMAP.md`.

### Contributing

Please see [`CONTRIBUTING.md`](CONTRIBUTING.md) for guidelines on bug reports, feature suggestions, and pull requests.

### Security Reporting

For security vulnerabilities, see [`SECURITY.md`](SECURITY.md). Do not open public issues for security concerns.

### License

MIT License. See [`LICENSE`](LICENSE).

---

## Unreleased

No changes currently staged.

