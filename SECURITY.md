# Security Policy

SubMiHomo is an OpenWrt service that runs with elevated privileges (root) on a device mediating all LAN-to-WAN traffic. Security is a critical concern. This document describes how to report vulnerabilities responsibly and outlines the security architecture you should understand before deploying SubMiHomo.

## Reporting Security Vulnerabilities

If you discover a security vulnerability in SubMiHomo, **please do not open a public GitHub issue**. Instead, email security details to the maintainers at:

📧 **[submihomo-security@example.com]** (or contact via GitHub private security advisory)

Include:
- Description of the vulnerability
- Steps to reproduce (if applicable)
- Potential impact
- Suggested fix (if you have one)

We will acknowledge receipt within 48 hours and work toward a fix according to severity:

| Severity | Timeline |
|---|---|
| Critical | 24–48 hours to patch and release |
| High | 1 week to patch and release |
| Medium | 2 weeks to patch and release |
| Low | Next minor release cycle |

Once a patch is released, you may disclose the vulnerability publicly (with credit).

## Security Architecture Overview

SubMiHomo implements several layers of security control:

### Threat Model

See `docs/SECURITY.md` for a complete threat model. In brief:

- **Local network attacker**: Can reach LuCI and the Mihomo external controller; mitigated by a required controller secret and firewall rules
- **Remote/WAN attacker**: Cannot reach SubMiHomo services (fw4 does not expose them by default)
- **Compromised subscription provider**: Cannot execute arbitrary code; subscription content is validated and sandboxed to proxy rules
- **Physical attacker**: Can extract files from flash; treated as an accepted risk consistent with OpenWrt standards

### Security Controls

1. **Subscription validation**: YAML is parsed with `mihomo -t` before activation
2. **Privilege separation**: Mihomo runs as a dedicated non-root user where possible; initialization runs as root with minimal window
3. **Firewall integration**: fw4/nftables rules are managed automatically and reset on restart
4. **LuCI ACLs**: rpcd enforces role-based access control (see `docs/RPC.md`)
5. **Secret management**: Controller secret is read from `/etc/config/submihomo` (mode 0600) and not logged
6. **Dependency hardening**: No external runtime dependencies beyond OpenWrt standards (fw4, nftables, apk)

### Known Limitations and Acceptable Risks

- **Physical access**: Unencrypted configuration files on flash are readable by anyone with serial access or flash dumping tools (accepted risk consistent with OpenWrt)
- **DNS privacy**: DNS queries are intercepted and may be visible in logs depending on configuration (use encryption where available)
- **Proxy operator trust**: The chosen proxy provider has visibility into all proxied traffic content (inherent to proxy use)
- **IPv6**: Not currently supported; future versions may address this

## Supply Chain Security

### Dependencies

SubMiHomo depends on:
- **OpenWrt 25+** (firmware, fw4, nftables, apk, rpcd, procd, LuCI)
- **Mihomo** (binary core, downloaded at install time and verified by content)
- **Zashboard** (optional dashboard, downloaded at install time)

All are established, open-source projects with their own security processes.

### Package Integrity

APK packages are signed by the OpenWrt build system. Subscription files are validated with YAML schema and `mihomo -t`.

### Controller Secret

If you expose the external controller port (default 9090) to the internet or untrusted networks, **set a strong secret** in LuCI:

Settings → Controller Secret (required, min 8 characters, alphanumeric + symbols recommended)

Without this secret, any network-accessible device can query and control Mihomo.

## Testing and Audits

- Unit tests: `bash tests/unit/run_all.sh`
- Integration tests: `bash tests/integration/run_all.sh`
- System tests: `bash tests/system/run_all.sh`
- Static analysis: `shellcheck -x files/usr/lib/submihomo/*.sh`

See `docs/TESTING.md` and `docs/SECURITY.md` for comprehensive security architecture and testing details.

## Security Hardening Checklist

- [ ] Set a strong controller secret if exposing the Mihomo API
- [ ] Do not port-forward LuCI (port 80/443) or the controller (9090) to the WAN without strong authentication
- [ ] Keep OpenWrt firmware and packages up to date
- [ ] Use HTTPS (not HTTP) for LuCI access when possible
- [ ] Review subscription provider trustworthiness before configuring
- [ ] Enable debug logging only when troubleshooting (logs may include traffic metadata)
- [ ] Regularly check for security advisories in `docs/` and GitHub releases

## Security.md Reference

This is a summary. For deep technical details on security architecture, threat actors, attack surface analysis, and controls, see:

📖 [`docs/SECURITY.md`](docs/SECURITY.md)

---

**Thank you for helping keep SubMiHomo secure!**
