# Changelog

All notable changes to Linux Hardening Toolkit are documented in this file.

## 1.0.0 - 2026-08-27

Initial stable release.

### Security auditing

- 96 checks in the default Linux server profile
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
- PASS, FAIL, WARN, SKIP, and ERROR result states
- deterministic exit-code contract
- machine-readable JSON reports
- JSON schema versioning
- atomic report-file creation
- restrictive report permissions

### Engineering

- modular check registry
- profile-driven execution
- unit tests
- CLI integration tests
- JSON validation tests
- ShellCheck static analysis
- GitHub Actions continuous integration
