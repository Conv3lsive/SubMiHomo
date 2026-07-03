# Docker Integration Setup

This document describes the Docker-based integration harness for SubMiHomo. It is intended to run on a Linux host with Docker; it cannot be executed in the macOS sandbox used for static/unit validation.

## What the harness verifies

- OpenWrt SDK package build for `x86_64` (produces `mihomo`, `submihomo`, and `luci-app-submihomo` APKs).
- Installation of the APKs inside an `openwrt/rootfs` container.
- UCI configuration and subscription seeding.
- procd service start/stop.
- rpcd `status` and `set_config` calls.
- Package uninstall and cleanup verification (no orphan files, cron entries, or running processes).

## Prerequisites

- Docker with privileged container support.
- `wget`, `tar` with zstd support, and standard build tools for the SDK step.
- Network access to `downloads.openwrt.org` and Docker Hub.

## Running the harness

```sh
cd /path/to/SubMiHomo
sh tests/integration/docker_lifecycle.sh
```

Environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `SDK_URL` | OpenWrt snapshot x86_64 SDK | URL of the OpenWrt SDK tarball |
| `TARGET` | `x86_64` | Package architecture |
| `WORK_DIR` | `/tmp/submihomo-docker` | Build and cache directory |
| `OPENWRT_IMAGE` | `openwrt/rootfs:x86_64-openwrt-snapshot` | Container image |
| `CONTAINER_NAME` | `submihomo-test` | Docker container name |

## How it works

1. `tests/integration/sdk_build.sh` downloads the SDK, registers the SubMiHomo feed and a dummy `mihomo` dependency, and builds all three APKs.
2. A privileged OpenWrt rootfs container is started with the APK directory and helper scripts bind-mounted.
3. `tests/integration/docker_helpers/container_setup.sh` runs inside the container:
   - Replaces `nft` and `ip` with no-op stubs (the container kernel lacks netfilter/policy-routing).
   - Creates `/etc/dnsmasq.d`.
   - Installs the APKs with `apk add --allow-untrusted`.
   - Seeds a minimal subscription fixture.
   - Configures UCI.
4. The harness starts the service, checks that the dummy `mihomo` process is running, and calls rpcd methods.
5. The service is stopped, packages are removed, and the harness asserts that no SubMiHomo files, cron entries, or processes remain.

## Limitations

- TPROXY/nftables/fw4/policy-routing are **not** functionally tested because the container shares the host kernel and lacks the required netfilter modules.
- The dummy `mihomo` binary only validates CLI surface and sleeps; no real proxy traffic is forwarded.
- DNS hijack is configured but dnsmasq may not be present in the minimal rootfs; the init script logs a warning and continues.

## Expected result

The script exits `0` and prints:

```
Docker lifecycle integration: PASS
```
