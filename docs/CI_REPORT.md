# SubMiHomo CI Report

## Recommended CI pipeline

The repository is designed to be validated by a multi-stage CI pipeline. The following stages are recommended for GitHub Actions, GitLab CI, or any comparable runner.

### Stage 1 — Static analysis

```sh
sh tests/static/run_static.sh
```

Expected result: `LAYER 1 STATIC ANALYSIS: PASS`

Tools required: `shellcheck`, `shfmt`, `lua`/`luac`, `jq`, `node`, `python3` + `pyyaml`.

### Stage 2 — Unit tests

```sh
sh tests/unit/run_all.sh
```

Expected result: `OVERALL RESULT: 194 passed, 0 failed`

Tools required: POSIX shell, `dash` (optional, for regression test), `python3`.

### Stage 3 — Makefile validation

```sh
sh tests/integration/validate_makefile.sh
```

Expected result: `Makefile static validation: PASS`

### Stage 4 — OpenWrt SDK build

Run on a Linux runner with `wget`, `tar` + zstd, and build essentials.

```sh
sh tests/integration/sdk_build.sh
```

Expected artifacts:

- `bin/packages/<arch>/submihomo/mihomo-*.apk`
- `bin/packages/<arch>/submihomo/submihomo-*.apk`
- `bin/packages/<arch>/submihomo/luci-app-submihomo-*.apk`

Default target: `mipsel_24kc` (ramips/mt7621). Override with `TARGET` and `SDK_URL`.

### Stage 5 — Docker lifecycle

Run on a Linux runner with Docker privileged mode.

```sh
sh tests/integration/docker_lifecycle.sh
```

Expected result: `Docker lifecycle integration: PASS`

### Stage 6 — QEMU lifecycle

Run on a Linux runner with QEMU and KVM acceleration.

```sh
sh tests/integration/qemu_lifecycle.sh
```

Expected result: `QEMU lifecycle integration: PASS`

### Stage 7 — Embedded performance (manual / device farm)

Run on a real OpenWrt device after installing the release APKs.

```sh
sh tests/integration/embedded_perf.sh
```

## CI status for this validation session

| Stage | Runner | Status |
|-------|--------|--------|
| Static analysis | macOS ARM64 sandbox | PASS |
| Unit tests | macOS ARM64 sandbox | PASS |
| Makefile validation | macOS ARM64 sandbox | PASS |
| SDK build | Not available | PENDING |
| Docker lifecycle | Not available | PENDING |
| QEMU lifecycle | Not available | PENDING |
| Embedded performance | Not available | PENDING |

## Notes

- The `.gitignore` in this repository intentionally ignores `docs/` and `.github/workflows/`. If CI workflows are desired, the repository owner should update `.gitignore` and add workflow files under `.github/workflows/`.
- The SDK, Docker, and QEMU stages are I/O and CPU intensive; runners should have at least 4 cores, 8 GB RAM, and 20 GB disk.
- The dummy `mihomo` package (`tests/integration/mihomo-dummy`) is intended only for CI integration tests and must not be published to production feeds.
