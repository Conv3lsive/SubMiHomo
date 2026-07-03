# SubMiHomo RC1 Release Checklist

## Pre-release gates

- [x] Layer 1 static analysis passes (`tests/static/run_static.sh`)
- [x] Layer 2 unit tests pass (`tests/unit/run_all.sh` — 194/194)
- [x] Critical BusyBox `\s` / `grep -A` bug fixed and regression-tested
- [x] Module line-count budgets verified (`core.sh` ≤150, `config.sh` ≤200, `subscription.sh` ≤200, `dashboard.sh` ≤150)
- [x] Makefile statically validated (`tests/integration/validate_makefile.sh`)
- [ ] OpenWrt SDK build produces `submihomo` + `luci-app-submihomo` APKs (`tests/integration/sdk_build.sh`)
- [ ] Docker lifecycle harness passes (`tests/integration/docker_lifecycle.sh`)
- [ ] QEMU lifecycle harness passes (`tests/integration/qemu_lifecycle.sh`)
- [ ] On-device performance script run (`tests/integration/embedded_perf.sh`)
- [ ] Install/upgrade/reinstall/sysupgrade smoke test on target hardware
- [ ] Removal cleanup verified (no orphan files, cron entries, or processes)

## Versioning and tagging

- [ ] Update `PKG_VERSION` and `PKG_RELEASE` in `Makefile` if changed
- [ ] Update version references in `install/install.sh`, `install/update.sh`, and `install/uninstall.sh`
- [ ] Tag release: `git tag -a v1.0.0-rc1 -m "SubMiHomo 1.0.0 RC1"`
- [ ] Push tag to trigger CI release workflow

## Artifacts

- [ ] `submihomo_*.apk` for `mipsel_24kc`
- [ ] `luci-app-submihomo_*.apk` for `mipsel_24kc`
- [ ] APK signing key published at expected URL (`submihomo.pub`)
- [ ] Release notes summarizing fixes, test results, and known limitations

## Documentation

- [x] `docs/QA_REPORT.md`
- [x] `docs/TEST_RESULTS.md`
- [x] `docs/PASS_FAIL_MATRIX.md`
- [x] `docs/KNOWN_LIMITATIONS.md`
- [x] `docs/RELEASE_CHECKLIST.md`
- [x] `docs/CI_REPORT.md`
- [x] `docs/DOCKER_SETUP.md`
- [x] `docs/QEMU_SETUP.md`

## Post-release

- [ ] Monitor CI for SDK build failures
- [ ] Collect feedback from early adopters on mipsel_24kc hardware
- [ ] Address any blocker before final `v1.0.0`
