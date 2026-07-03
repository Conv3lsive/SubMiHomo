# Contributing to SubMiHomo

Thank you for your interest in contributing to SubMiHomo! We welcome bug fixes, documentation improvements, and quality-of-life enhancements to our first stable release.

## Development Setup

### Prerequisites

- OpenWrt build environment (or Docker/QEMU for testing; see `docs/DOCKER_SETUP.md` and `docs/QEMU_SETUP.md`)
- Standard Unix tools: `bash`, `shellcheck`, `wget`, `git`
- Knowledge of POSIX shell, OpenWrt init scripts, UCI, nftables, and policy routing

### Getting Started

1. Clone the repository:
   ```sh
   git clone https://github.com/Conv3lsive/SubMiHomo.git
   cd SubMiHomo
   ```

2. Read the architecture documentation in order:
   ```
   docs/ARCHITECTURE.md
   docs/FILESYSTEM.md
   docs/COMPONENTS.md
   docs/BOOT.md
   docs/NETWORK.md
   docs/SECURITY.md
   ```

3. Familiarize yourself with the module structure under `files/usr/lib/submihomo/` and the test framework in `tests/`.

## Running Tests

SubMiHomo includes a comprehensive test suite covering unit, integration, and system testing:

```sh
# Run all unit tests
bash tests/unit/run_all.sh

# Run a specific test file
bash tests/unit/test_mihomo.sh

# Run integration tests (requires OpenWrt environment)
bash tests/integration/run_all.sh

# Run system tests (full deployment validation)
bash tests/system/run_all.sh
```

For detailed testing documentation, see `docs/TESTING.md`.

## Code Style and Quality

### Shell Code Standards

All shell scripts must comply with **POSIX shell** and **ShellCheck** (SC2086, SC2181, etc.):

1. No bash-isms: no `[[…]]`, no `${var//pattern/}`, no `<<<` redirects
2. Quote variables and command substitutions: `"$var"`, `"$(command)"`
3. Avoid unnecessary command substitutions; use `set -f; set -- $var; set +f` for word splitting
4. Use `if` and `then` for all conditionals; no implicit `&&` chains for error handling
5. Pre-declare functions at the top of scripts
6. Use descriptive variable names; avoid single letters except in loops

### Checking Code Style

Run ShellCheck on any shell script you modify:

```sh
shellcheck -x files/usr/lib/submihomo/*.sh
shellcheck -x files/etc/init.d/submihomo
```

### YAML and Templates

- Indentation: **2 spaces** (never tabs)
- Line length: keep under 100 columns where practical
- Comments: explain *why*, not *what*
- Template variables: use `{{ variable }}` syntax in `.tmpl` files

### Markdown Documentation

- Indentation: **2 spaces**
- Line wrapping: hard-wrap at **100 columns**
- Use headings consistently: `#` for title, `##` for sections, etc.
- Include a table of contents for documents over 20 lines

## Pull Request Process

1. **Create a feature branch** from `main`:
   ```sh
   git checkout -b fix/my-bug-name
   git checkout -b docs/add-new-guide
   ```

2. **Make focused, incremental commits** with clear messages:
   ```
   Fix: handle missing /etc/config/submihomo gracefully
   
   Previously, mihomo.sh would fail if the config file did not exist.
   Now we create it with defaults if necessary, matching the init script's
   behavior. Fixes #42.
   ```

3. **Run tests** before pushing:
   ```sh
   bash tests/unit/run_all.sh
   shellcheck -x files/usr/lib/submihomo/*.sh
   ```

4. **Submit a pull request** with:
   - Clear title: `Fix: …` or `Docs: …` or `Perf: …`
   - Description of the problem and solution
   - Link to any related issues (`Fixes #123`)
   - Confirmation that tests pass

5. **Respond to review feedback** promptly and in good faith.

## What We Accept

✅ **Bug fixes** (reproducible, with unit tests when possible)  
✅ **Documentation improvements** (grammar, clarity, new guides)  
✅ **Test improvements** (better coverage, faster tests)  
✅ **Performance enhancements** (measurable, with benchmarks)  
✅ **Security hardening** (with threat model analysis)  

## What We Don't Accept (v1.0.0 Release)

❌ **Major new features** (SubMiHomo is stable and feature-complete)  
❌ **Breaking changes** to UCI schema or config format  
❌ **New external dependencies** without strong justification  
❌ **Removal of documented features** without migration path  

For feature ideas beyond v1.0.0, open a GitHub discussion or see `docs/ROADMAP.md`.

## Reporting Security Issues

**Do not open a public issue for security vulnerabilities.** See `SECURITY.md` for responsible disclosure instructions.

## License

By contributing to SubMiHomo, you agree that your contributions will be licensed under the MIT License (see `LICENSE`).

## Questions?

- Check `docs/` for existing documentation
- Read through open/closed GitHub issues
- Join our discussions for community support

Thank you for helping make SubMiHomo better!
