# SubMiHomo

**Paste a subscription. Click Apply. Everything else happens automatically.**

SubMiHomo is an OpenWrt 25+ service that wraps the [Mihomo](https://github.com/MetaCubeX/mihomo) proxy core to deliver fully automatic, transparent, system-wide proxy routing — with the simplicity of Podkop, powered by Mihomo instead of sing-box.

The user never touches routing tables, nftables, `ip rule`, or DNS configuration. They paste an HTTPS subscription URL into LuCI, click Apply, and every device on the LAN is transparently proxied. DNS (Fake-IP or Real-IP), TPROXY interception, policy routing, and firewall rules are all configured and torn down automatically.

## Status

**v1.0.0-rc1 — First Release Candidate**

SubMiHomo is fully implemented as an OpenWrt package with LuCI, rpcd, procd, UCI-driven Mihomo configuration, transparent routing helpers, and managed Mihomo core installation. Phase 1 improvements have been completed, including enhanced error handling, graceful degradation, atomic configuration updates, and comprehensive security hardening. All tests are passing and the project is ready for community testing before v1.0.0 stable release.

For release notes and roadmap, see [`CHANGELOG.md`](CHANGELOG.md).

## Target Platform

| | |
|---|---|
| OS | OpenWrt 25+ |
| Package manager | APK |
| Firewall | fw4 + nftables |
| CPU architecture | Detected at install/update time |
| Frontend | LuCI JS |
| Proxy core | Mihomo (only) |
| Dashboard | Zashboard |
| IPv6 | Not supported |

## Installation

Run this on your OpenWrt 25+ router:

```sh
sh <(wget -qO- https://raw.githubusercontent.com/Conv3lsive/SubMiHomo/main/install/install.sh)
```

After installation, open **LuCI → Services → SubMiHomo**, paste your subscription URL, and click Apply.

See [`docs/INSTALL.md`](docs/INSTALL.md) for installer, updater, and uninstaller documentation.

## Documentation

| Document | Contents |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | System design, philosophy, and high-level diagrams |
| [`docs/COMPONENTS.md`](docs/COMPONENTS.md) | Module responsibilities, interfaces, and lifecycle |
| [`docs/NETWORK.md`](docs/NETWORK.md) | TPROXY, nftables, policy routing, and DNS flow |
| [`docs/UCI.md`](docs/UCI.md) | UCI schema, defaults, validation, and migration |
| [`docs/SUBSCRIPTIONS.md`](docs/SUBSCRIPTIONS.md) | Subscription download, validation, and rollback |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Threat model, permissions, and security architecture |
| [`docs/INSTALL.md`](docs/INSTALL.md) | APK repository and install/update/uninstall scripts |
| [`docs/TESTING.md`](docs/TESTING.md) | Unit, integration, and system test strategy |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Feature roadmap and future milestones |

## Community

- **Contributing**: See [`CONTRIBUTING.md`](CONTRIBUTING.md) for development setup, testing, and pull request guidelines.
- **Code of Conduct**: Please read our [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). We are committed to fostering an inclusive, respectful community.
- **Security**: Report vulnerabilities responsibly using [`SECURITY.md`](SECURITY.md). Do not open public issues for security concerns.

## License

MIT License. See [`LICENSE`](LICENSE) for full text.
