# SubMiHomo Known Limitations

## Environment constraints of this validation

The release-validation work was performed in a macOS ARM64 sandbox with the following tools missing:

- Docker
- QEMU / `qemu-system-mipsel`
- OpenWrt SDK
- BusyBox ash (macOS `/bin/sh` is GNU bash 3.2)

Consequently, Layers 3–5 and on-device performance measurements are delivered as fully reproducible automation scripts and documentation, but are marked **pending execution** in the test reports.

## Functional limitations

### TPROXY / nftables

- The package depends on `kmod-nft-tproxy`, `nftables`, `firewall4`, and `ip-full`. If the running kernel lacks `nft_tproxy` or the required netfilter modules, `firewall_setup` will fail and the service will not start. This is expected behavior and is surfaced as a clear log error.
- IPv6 transparent proxy is not implemented; the generated config sets `ipv6: false`.

### DNS hijack

- `dns_setup` writes a forwarding directive to `/etc/dnsmasq.d/submihomo.conf`. If dnsmasq is not installed or the include directory is absent, the function logs an error and returns non-zero, causing service startup to abort. The Docker harness creates this directory explicitly because the minimal OpenWrt rootfs does not include dnsmasq.

### Dashboard download

- `dashboard_download` fetches the latest GitHub release of `Zephyruso/zashboard` (configurable via UCI). The download is non-blocking at service startup; failure does not prevent the proxy from starting.
- GitHub API rate limiting may cause dashboard installation to fail on hosts without authentication.

### Subscription update

- `subscription_update` requires a reachable HTTPS subscription URL. Offline operation is only possible if `/etc/submihomo/subscriptions/current.yaml` is seeded manually.
- Hot-reload via the Mihomo REST API is best-effort; if it fails, the new config is applied on the next service restart.

### Architecture / packaging

- Prebuilt APKs are targeted at `mipsel_24kc` (ramips/mt7621). Other architectures require building from source with the OpenWrt SDK.
- The integration harnesses use `x86_64` because official OpenWrt x86_64 images and SDK are readily available for Docker/QEMU; this is a test convenience, not a primary target.

### Dummy Mihomo dependency

- `tests/integration/mihomo-dummy` provides a no-op `mihomo` binary used only for integration testing. It satisfies package dependencies and allows procd lifecycle verification, but it does not forward traffic or perform real proxy operations.

## Not in scope

- Real-world throughput / latency benchmarking.
- Multi-WAN or policy-based routing beyond the single TPROXY redirect.
- Mihomo rule-provider / external proxy-provider runtime validation.
- LuCI UI end-to-end browser automation.
