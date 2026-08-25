# Linux Hardening Toolkit

Linux Hardening Toolkit is a modular Bash-based security auditing and
hardening framework for Linux servers.

The project is designed to provide reproducible security checks,
controlled remediation, configuration backup and rollback, profiles,
reporting, and automation-friendly execution.

> Current version: v0.1.0

## Project status

v0.1 establishes the core architecture and read-only audit engine.

Implemented:

- modular check registry;
- profile-based check selection;
- standardized audit results;
- deterministic exit codes;
- verbose and colorless CLI output;
- dry-run execution context;
- runtime validation module.

Actual Linux security hardening modules are not implemented in v0.1 yet.

## Usage

```bash
chmod +x bin/linux-hardening-toolkit

./bin/linux-hardening-toolkit --help
./bin/linux-hardening-toolkit version
./bin/linux-hardening-toolkit list-checks
./bin/linux-hardening-toolkit audit
