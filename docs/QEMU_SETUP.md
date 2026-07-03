# QEMU Integration Setup

This document describes the QEMU-based integration harness for SubMiHomo. It boots a real OpenWrt x86_64 image and exercises the full service lifecycle in a virtual network environment. It must run on a Linux host with QEMU and either `guestmount` or loop-mount support; it cannot be executed in the macOS sandbox used for static/unit validation.

## What the harness verifies

- OpenWrt SDK package build for `x86_64`.
- Boot of an official OpenWrt snapshot image with two virtio-net interfaces (LAN + WAN).
- APK installation inside the VM.
- UCI configuration and subscription seeding.
- procd service start with real `mihomo` process.
- TPROXY routing rule and local route in table 100.
- nftables `submihomo` table created by `firewall.sh`.
- dnsmasq forwarding configuration (`/etc/dnsmasq.d/submihomo.conf`).
- rpcd `status` method responds.
- Failure recovery: killing `mihomo` is detected by procd and the process respawns.
- Reboot survival: after `reboot`, the service starts automatically because it is enabled.

## Prerequisites

- Linux host with KVM acceleration recommended (`qemu-system-x86_64`).
- `wget`, `gunzip`, `qemu-img`, `ssh-keygen`, `ssh`, `scp`.
- Either `guestmount`/`guestunmount` (libguestfs) or `sudo` + loop mount for injecting the SSH key.
- Network access to `downloads.openwrt.org`.

## Running the harness

```sh
cd /path/to/SubMiHomo
sh tests/integration/qemu_lifecycle.sh
```

Environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `SDK_URL` | OpenWrt snapshot x86_64 SDK | SDK tarball URL |
| `TARGET` | `x86_64` | Package architecture |
| `WORK_DIR` | `/tmp/submihomo-qemu` | Build, image, and key cache |
| `IMAGE_URL` | OpenWrt snapshot x86_64 ext4 combined image | VM image URL |
| `SSH_PORT` | `2222` | Host port forwarded to VM SSH |

## Network topology

QEMU is started with two `virtio-net-pci` adapters:

- `lan`: user netdev with `hostfwd=tcp::2222-:22` for host access.
- `wan`: second user netdev providing a separate virtual uplink.

Both interfaces are visible inside OpenWrt as `eth0` and `eth1`. The harness does not configure firewall zones; it only verifies that SubMiHomo's TPROXY/policy-routing rules are installed.

## How it works

1. `tests/integration/sdk_build.sh` builds `mihomo`, `submihomo`, and `luci-app-submihomo` APKs.
2. The OpenWrt image is downloaded, decompressed, resized, and an Ed25519 SSH key is injected into `/etc/dropbear/authorized_keys`.
3. QEMU boots the image with two network interfaces.
4. Once SSH is available, APKs and helper scripts are copied to `/apk`.
5. `tests/integration/qemu_helpers/vm_setup.sh` installs the APKs, seeds a subscription, configures UCI, enables and starts the service.
6. `tests/integration/qemu_helpers/vm_check.sh` verifies runtime state.
7. The harness kills `mihomo` and checks that procd respawns it.
8. The VM is rebooted and the runtime checks are run again.

## Limitations

- The harness uses the dummy `mihomo` package from `tests/integration/mihomo-dummy`. It validates CLI surface and procd integration but does not forward real proxy traffic.
- Real-world traffic capture through TPROXY is not performed; only rule presence is checked.
- The official OpenWrt snapshot image may not include all kernel modules required for TPROXY; the package dependencies (`kmod-nft-tproxy`, `nftables`) are installed by `apk`.

## Expected result

The script exits `0` and prints:

```
QEMU lifecycle integration: PASS
```
