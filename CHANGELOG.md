# Changelog

All notable changes to Linux Hardening Toolkit are documented in this file.

## 1.0.1 - 2026-08-27

### Added

- interactive `#ABSL Security` startup branding
- large ASCII banner for wide terminals
- compact banner fallback for narrow terminals
- `--no-banner` CLI option
- automated banner unit tests
- CLI coverage for the new banner option

### Behavior

- JSON output remains free from startup branding
- redirected and piped output remains free from startup branding
- version output remains machine-readable
- startup branding does not affect audit result or exit-code semantics

## 1.0.0 - 2026-08-27

Initial stable release.

### Security auditing

- 96 checks in the default Linux server profile
- 11 built-in audit profiles
- OpenSSH server security auditing
- local account and password metadata auditing
- sudo policy and configuration integrity auditing
- kernel and sysctl runtime auditing
- host firewall and network exposure auditing
- PAM and password authentication auditing
- sensitive filesystem permission auditing
- service and network daemon exposure auditing
- Linux audit subsystem and security logging auditing
- automatic security update auditing

### Reporting

- human-readable terminal output
- `PASS`, `FAIL`, `WARN`, `SKIP`, and `ERROR` result states
- deterministic exit-code contract
- machine-readable JSON reports
- JSON schema versioning
- atomic report-file generation
- restrictive report permissions

### Engineering

- modular check registry
- profile-driven execution
- Bash syntax validation
- ShellCheck static analysis
- unit tests
- CLI integration tests
- JSON report validation
- GitHub Actions continuous integration

### Safety

- audit-only execution
- no automatic remediation
- no claim of official CIS certification or third-party benchmark compliance
