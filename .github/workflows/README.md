# GitHub Actions CI/CD Workflows

This document describes the automated CI/CD pipelines for SubMiHomo.

## Overview

SubMiHomo uses two GitHub Actions workflows:

1. **CI Workflow** (`.github/workflows/ci.yml`) — Runs on every push and pull request
2. **Release Workflow** (`.github/workflows/release.yml`) — Runs when a git tag is pushed

## Phase 4: CI Workflow

**File:** `.github/workflows/ci.yml`

**Trigger:** Automatically runs on:
- Every push to `main`, `develop`, and `feature/**` branches
- Every pull request to `main`

**Jobs:**

### `lint-and-test` Job

Runs linting and testing in a single job on `ubuntu-latest`.

#### Steps:

1. **Checkout code** — Fetches the repository
2. **Install tools** — Installs `shellcheck` and `shfmt` from APT
3. **ShellCheck analysis** — Checks shell scripts for common errors
   - Runs on: `files/`, `install/`, `tests/` directories
   - Severity: warning and errors only
   - Excludes: `SC1091` (source unavailable), `SC2181` (explicit exit codes)
   - Fails fast on first error
4. **shfmt formatting check** — Verifies shell script formatting
   - 4-space indentation (`-i 4`)
   - Reports formatting violations
   - Fails fast on first issue
5. **Syntax verification** — Runs `sh -n` on all shell files
   - Checks for syntax errors without execution
6. **Unit tests** — Runs all 194 tests
   - Command: `bash tests/unit/run_all.sh`
   - Must pass 100% to proceed
7. **CI status report** — Prints summary (always runs, even on failure)

**Expected Duration:** ~2-3 minutes

**Success Criteria:**
- All ShellCheck checks pass
- All shfmt formatting checks pass
- All syntax checks pass
- All 194 unit tests pass

## Phase 5: Release Workflow

**File:** `.github/workflows/release.yml`

**Trigger:** Automatically runs when a git tag matching `v*` is pushed

```bash
git tag v1.0.0
git push origin v1.0.0
```

**Jobs:** Three sequential jobs with dependencies

### Job 1: `validate`

**Name:** Validate & Test

**Outputs:**
- `version` — Extracted semantic version (e.g., `1.0.0`)
- `is_prerelease` — `true` if version contains `rc`, `alpha`, or `beta`

**Steps:**

1. **Checkout at tag** — Fetches code at the exact tag
2. **Extract version from tag**
   - Removes `v` prefix: `v1.0.0` → `1.0.0`
   - Detects pre-release status (contains `rc`/`alpha`/`beta`)
3. **Install tools** — ShellCheck and shfmt
4. **Run CI checks (ShellCheck)** — Full shell analysis with same exclusions
5. **Run CI checks (shfmt)** — Format verification
6. **Run unit tests** — All 194 tests must pass
7. **Validate CHANGELOG.md** — Checks if version section exists
   - Warning (not fatal) if version not found; uses latest entry as fallback

**Fails fast:** On first failure, stops entire workflow

### Job 2: `build` (Parallel multi-architecture)

**Name:** Build APK Packages

**Runs after:** `validate` job completes successfully

**Strategy:** Build for 4 architectures in parallel:
- `arm` (32-bit ARM)
- `aarch64` (64-bit ARM)
- `x86_64` (64-bit x86)
- `mips` (MIPS router SoCs)

**Steps per architecture:**

1. **Checkout at tag**
2. **Cache OpenWrt SDK** — Caches per-architecture SDK to speed up rebuilds
3. **Download OpenWrt SDK**
   - Uses OpenWrt 25.05.0 official releases
   - Maps target to correct download URL
   - Non-fatal if download fails (continues with fallback)
4. **Build APK packages**
   - In full production: `make -C . -j$(nproc)`
   - Outputs to `bin/{arch}/submihomo.apk` and `bin/{arch}/luci-app-submihomo.apk`
5. **Upload build artifacts** — Uploads APKs as GitHub Actions artifacts
   - Retention: 1 day (for release step to download)

**Notes:**
- Builds run in parallel, completing ~20-30 minutes total
- SDK downloads cached, so repeats are faster
- Non-critical failures (SDK download) don't block release

### Job 3: `publish`

**Name:** Publish Release

**Runs after:** Both `validate` and `build` complete

**Steps:**

1. **Checkout code** — Latest code (for CHANGELOG.md parsing)
2. **Download all artifacts** — Retrieves APKs built in Job 2
3. **Generate release notes**
   - Attempts to extract version section from `CHANGELOG.md`
   - Fallback: Uses latest changelog entry if version not found
   - Saves to `release_notes.txt`
4. **List and verify artifacts** — Reports APK counts found
5. **Create GitHub Release** (using `softprops/action-gh-release@v1`)
   - Tag name and semantic version
   - Release notes from `CHANGELOG.md`
   - Uploads all APK artifacts
   - Pre-release flag: `true` if version contains `rc`, `alpha`, or `beta`
   - Draft: `false` (immediately published)
6. **Summary** — Prints release completion details

**Output:**
- GitHub Release created with:
  - Name: `SubMiHomo {version}`
  - Body: Release notes from CHANGELOG.md
  - Artifacts: `submihomo.apk` and `luci-app-submihomo.apk` for each architecture
  - Pre-release badge if applicable

**Expected Duration:** ~35-45 minutes total (validate: 3 min, build: 30 min parallel, publish: 2 min)

---

## Environment & Prerequisites

### GitHub Actions Runner

- **OS:** Ubuntu 22.04 LTS (via `ubuntu-latest`)
- **Packages installed via APT:** `shellcheck`, `shfmt`, `python3`
- **Disk space:** ~5 GB available (for SDK caches)

### Required Repository Settings

1. **Push protection** (recommended): Require CI to pass before merge
   - Settings → Branches → Add rule for `main`
   - Require status checks to pass before merging
   - Select: `CI — Code Quality & Testing`

2. **Release permissions:** Default (GITHUB_TOKEN has write access)

### Optional Enhancements

To enable actual OpenWrt SDK builds in `build` job:

1. Pre-install OpenWrt SDK in a container image (reduces build time from 30 min → 5 min)
2. Cache compiled binaries between releases
3. Sign APK packages with private key stored in GitHub Secrets
4. Upload APKs to a custom APK repository

---

## Workflow Status & Monitoring

### CI Workflow Status

- Check latest run: **Actions → CI — Code Quality & Testing → Latest run**
- Branch protection: Prevents merge if CI fails
- PR badges: GitHub automatically shows status in pull requests

### Release Workflow Status

- Check release run: **Actions → Release — Build & Publish → Latest run**
- GitHub Releases: **Releases → Latest**
- Direct tag: `git tag -l` shows all created tags

---

## Troubleshooting

### CI Workflow Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| ShellCheck error (SC*) | Shell syntax/style issue | Run locally: `shellcheck -S warning file.sh` |
| shfmt formatting | Indentation mismatch | Run: `shfmt -i 4 -w file.sh` |
| Unit test failure | Test regression | Run: `bash tests/unit/run_all.sh` locally |

### Release Workflow Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Version not in CHANGELOG | Forgot to update changelog | Add `## [1.0.0]` section to CHANGELOG.md |
| SDK download fails | Network/URL issue | Non-fatal; release still published (empty artifacts) |
| Release not published | Insufficient permissions | Check GitHub token in repository secrets |

---

## Example Usage

### Trigger CI

```bash
# Trigger on push
git push origin main

# Trigger on PR
git push origin feature/my-feature
# Create pull request on GitHub
```

### Trigger Release

```bash
# Create release candidate
git tag v1.0.0-rc1
git push origin v1.0.0-rc1
# Workflow runs → publishes pre-release on GitHub

# Create stable release
git tag v1.0.0
git push origin v1.0.0
# Workflow runs → publishes release on GitHub
```

---

## Workflow Files Statistics

| Workflow | File | Lines | Jobs | Steps |
|----------|------|-------|------|-------|
| CI | `.github/workflows/ci.yml` | 115 | 1 | 7 |
| Release | `.github/workflows/release.yml` | 256 | 3 | 18 |
| **Total** | | **371** | **4** | **25** |

---

## Integration with Development

### Branch Strategy

- **`main`** — Production releases; must pass CI; tag from here
- **`develop`** — Integration branch; must pass CI before PR
- **`feature/**`** — Feature branches; must pass CI before PR to develop

### Pre-commit

Consider local pre-commit checks to avoid failed CI:

```bash
# Before committing
shellcheck --severity=warning files/usr/lib/submihomo/*.sh
shfmt -d -i 4 files/usr/lib/submihomo/*.sh
bash tests/unit/run_all.sh
```

### Release Process

1. Update `CHANGELOG.md` with new version section
2. Commit changes: `git commit -m "Release v1.0.0"`
3. Create tag: `git tag v1.0.0`
4. Push tag: `git push origin v1.0.0`
5. Monitor: **Actions → Release — Build & Publish**
6. Verify: **Releases → v1.0.0**

---

## Security Considerations

- **GITHUB_TOKEN:** Automatically provided; no manual setup needed
- **APK signing:** Not implemented (add to `build` job if needed)
- **SDK caching:** Public, cached locally; no secrets exposed
- **Artifact retention:** 1 day; cleaned automatically

---

Generated for SubMiHomo Phases 4 & 5 CI/CD
