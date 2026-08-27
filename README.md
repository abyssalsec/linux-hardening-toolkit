# Linux Hardening Toolkit

[![CI](https://github.com/abyssalsec/linux-hardening-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/abyssalsec/linux-hardening-toolkit/actions/workflows/ci.yml)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-4EAA25.svg)

A profile-driven, read-only Linux security auditing toolkit written in Bash.

Linux Hardening Toolkit evaluates the effective security state of a Linux
host, classifies findings with explicit result semantics, and can produce
both human-readable terminal output and structured JSON reports.

Version 1.0.0 includes **96 checks in the default server profile** across
OpenSSH, local accounts, sudo, kernel/sysctl, host firewall, PAM,
filesystem permissions, exposed services, audit/logging, and automatic
security updates.

## Highlights

- 96 checks in the default Linux server baseline
- 11 built-in audit profiles
- read-only audit execution
- modular check registry and profile system
- explicit `PASS`, `FAIL`, `WARN`, `SKIP`, and `ERROR` states
- deterministic process exit codes
- structured JSON reports
- atomic report-file generation with restrictive permissions
- ShellCheck static analysis
- automated unit and integration tests
- GitHub Actions continuous integration

## Quick start

Clone the repository:

```bash
git clone https://github.com/abyssalsec/linux-hardening-toolkit.git
cd linux-hardening-toolkit
```

Run the default audit:

```bash
sudo ./bin/linux-hardening-toolkit audit
```

Run a specific profile:

```bash
sudo ./bin/linux-hardening-toolkit \
  --profile ssh-server \
  audit
```

List all registered checks:

```bash
./bin/linux-hardening-toolkit list-checks
```

Show the installed version:

```bash
./bin/linux-hardening-toolkit --version
```

## Result model

Every executed check produces one of five result states:

| Status | Meaning |
| --- | --- |
| `PASS` | The evaluated security control satisfies the toolkit baseline |
| `FAIL` | A definite baseline violation was detected |
| `WARN` | A condition requires review but is not universally insecure |
| `SKIP` | The check is unavailable, not applicable, or cannot be evaluated in the current environment |
| `ERROR` | The check itself could not execute successfully |

This distinction is intentional. Environment-dependent configuration is not
automatically classified as a vulnerability, and unavailable functionality
is not silently treated as a pass.

## Profiles

Profiles define which registered checks are executed for a particular audit.

| Profile | Checks | Purpose |
| --- | ---: | --- |
| `default` | 96 | Complete Linux server security baseline |
| `accounts` | 10 | Local account and password metadata |
| `audit` | 10 | Linux audit subsystem and security logging |
| `auth` | 8 | PAM and password authentication policy |
| `filesystem` | 10 | Sensitive file ownership and permissions |
| `firewall` | 6 | Host firewall and network exposure |
| `kernel` | 18 | Kernel and network runtime hardening |
| `services` | 7 | Network listeners and unnecessary services |
| `ssh-server` | 11 | OpenSSH server security |
| `sudo` | 7 | sudo policy syntax and configuration integrity |
| `updates` | 7 | Automatic security updates and package maintenance |

Example:

```bash
sudo ./bin/linux-hardening-toolkit \
  --profile firewall \
  audit
```

## Audited security domains

### OpenSSH

The OpenSSH audit evaluates effective server configuration rather than only
parsing individual configuration files.

Checks include controls such as:

- root login
- password authentication
- keyboard-interactive authentication
- empty passwords
- public-key authentication
- maximum authentication attempts
- user environment
- X11 forwarding
- agent forwarding
- TCP forwarding

Conditional OpenSSH configuration is handled through the effective
configuration reported by the OpenSSH server where available.

### Local accounts

Account checks evaluate `/etc/passwd`, `/etc/shadow`, UID consistency,
password database integrity, login shells, empty passwords, password aging,
and password-change metadata.

Shadow-dependent checks distinguish unavailable privilege from a definite
security failure.

### sudo

The sudo profile evaluates:

- sudo availability
- configuration syntax
- ownership
- permissions
- include-directory integrity
- include-file naming
- configuration writability

### Kernel and sysctl

Runtime kernel checks inspect the effective state exposed through `/proc/sys`.

Coverage includes:

- ASLR
- kernel pointer restrictions
- kernel log restrictions
- ptrace policy
- protected links and files
- IPv4 and IPv6 redirect handling
- source routing
- reverse-path filtering
- ICMP hardening
- TCP SYN cookies
- IP forwarding

### Host firewall

Firewall auditing detects common Linux firewall backends and distinguishes a
real host input policy from container-specific forwarding rules.

Supported detection includes:

- UFW
- firewalld
- nftables
- iptables

The profile also reviews default policy, ruleset availability, forwarding,
and exposed network listeners.

### PAM and authentication

Authentication auditing reviews the PAM stack and password policy controls,
including:

- null passwords
- password quality
- minimum password length
- password history
- failed-login lockout
- lockout policy
- password hashing

### Filesystem permissions

Filesystem auditing reviews sensitive Linux files and selected filesystem
trees for:

- ownership
- permissions
- SSH host-key protection
- world-writable files
- world-writable directories
- unowned files
- privileged SUID/SGID files

The scanner intentionally avoids treating every privileged binary as a
vulnerability.

### Services and exposure

Service checks evaluate:

- failed systemd units
- network listeners
- insecure remote-access services
- legacy file-transfer services
- discovery and RPC services
- inetd-style service managers

Normal client-side DHCP sockets are not classified as exposed services.

### Audit and logging

The logging profile reviews:

- systemd-journald
- persistent journal storage
- syslog
- log-file permissions
- auditd availability
- auditd runtime state
- kernel audit state
- loaded audit rules
- critical-path coverage
- auditd configuration

Dependent auditd checks are skipped when the audit subsystem is unavailable
rather than producing misleading secondary failures.

### Automatic security updates

The updates profile reviews automatic package maintenance and security update
configuration.

APT-based Debian and Ubuntu systems are fully evaluated for:

- unattended-upgrades
- package metadata refresh
- unattended installation
- security repository scope
- systemd update timers
- pending reboot state

DNF-based systems are also detected and evaluated where equivalent controls
are available.

## Command-line interface

```text
linux-hardening-toolkit [options] <command>
```

Commands:

```text
audit
list-checks
version
help
```

Common options:

```text
--profile NAME
--format text|json
--output PATH
--dry-run
--no-color
-v, --verbose
-h, --help
--version
```

The `audit` command is always read-only.

`--dry-run` is part of the execution context for future mutating operations
and does not make the current audit mode more or less destructive.

## Human-readable output

The default renderer is designed for interactive terminal use.

Example:

```text
[PASS ] updates.backend          APT automatic update backend detected
[PASS ] updates.automatic-tool   APT unattended-upgrades is installed
[PASS ] updates.metadata-refresh Automatic APT package index refresh is enabled
...
Summary: PASS=7 FAIL=0 WARN=0 SKIP=0 ERROR=0
```

Use `--verbose` to display additional details for successful checks:

```bash
sudo ./bin/linux-hardening-toolkit \
  --profile updates \
  --verbose \
  audit
```

## Machine-readable JSON reports

Audit results can be emitted as structured JSON:

```bash
./bin/linux-hardening-toolkit \
  --profile default \
  --format json \
  audit
```

Write the JSON report directly to a file:

```bash
./bin/linux-hardening-toolkit \
  --profile default \
  --format json \
  --output report.json \
  audit
```

Report files are generated atomically and use restrictive `0600`
permissions.

The JSON document contains:

- schema version
- toolkit version
- profile metadata
- generation timestamp
- audit mode
- result counters
- process-equivalent exit code
- metadata and result data for every executed check

Example check object:

```json
{
  "id": "ssh.root-login",
  "category": "ssh",
  "severity": "high",
  "title": "SSH root login disabled",
  "status": "FAIL",
  "message": "SSH root login is permitted",
  "details": "permitrootlogin=yes",
  "remediation_available": false
}
```

The current report schema version is `1`.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | Audit completed without failed checks or execution errors |
| `1` | Toolkit, runtime, output, or check execution error |
| `2` | Audit completed successfully but one or more checks failed |

`ERROR` takes precedence over `FAIL`.

Warnings and skipped checks do not independently change the process exit code
to `2`.

This makes the toolkit suitable for automation and CI pipelines without
conflating security findings with execution failures.

## Architecture

The project separates runtime infrastructure from individual security
domains.

```text
linux-hardening-toolkit/
├── bin/
│   └── linux-hardening-toolkit
├── lib/
│   └── core/
│       ├── bootstrap.sh
│       ├── log.sh
│       ├── profile.sh
│       ├── registry.sh
│       ├── report.sh
│       ├── runner.sh
│       ├── runtime.sh
│       └── utils.sh
├── modules/
│   ├── accounts/
│   ├── audit/
│   ├── auth/
│   ├── filesystem/
│   ├── firewall/
│   ├── runtime/
│   ├── services/
│   ├── ssh/
│   ├── sudo/
│   ├── sysctl/
│   └── updates/
├── profiles/
├── scripts/
│   └── lint.sh
├── tests/
│   ├── integration/
│   ├── lib/
│   ├── unit/
│   └── run.sh
└── VERSION
```

Modules register checks with the core registry.

A registered check contains:

- unique check ID
- category
- title
- severity
- audit function
- optional future remediation function

Profiles select registered check IDs without duplicating their implementation.

The runner executes the selected checks, normalizes their results, records
summary state, and passes the collected audit data to the requested output
renderer.

## Privilege model

The toolkit does not automatically elevate privileges.

Some checks can run as an unprivileged user while others require access to
root-owned configuration or security metadata.

For a complete server audit, run:

```bash
sudo ./bin/linux-hardening-toolkit audit
```

When insufficient privilege prevents a meaningful evaluation, checks are
designed to distinguish that state from a confirmed security violation.

## Security baseline

Linux Hardening Toolkit does **not** claim official CIS certification,
CIS Benchmark conformance, or certification against another third-party
security standard.

The implemented checks represent explicit Linux security practices and the
toolkit intentionally distinguishes between:

- definite baseline violations
- environment-dependent security decisions
- insufficient audit privileges
- unavailable or non-applicable functionality
- audit execution errors

The toolkit is an auditing aid, not a substitute for system-specific threat
modeling, architecture review, or organizational security policy.

## Requirements

Runtime:

- Linux
- Bash 4.0 or newer

Individual checks may inspect native system tools and services when they are
available.

Development and test tooling:

- Python 3
- ShellCheck

## Testing

Run the complete test suite:

```bash
./tests/run.sh
```

The test infrastructure includes:

- Bash syntax validation
- registry unit tests
- result and report unit tests
- JSON serialization tests
- report permission tests
- CLI integration tests
- CLI validation tests
- exit-code verification
- text-renderer verification

## Static analysis

Run ShellCheck across the project:

```bash
./scripts/lint.sh
```

The lint script analyzes the executable, core libraries, security modules,
test code, and development scripts.

## Continuous integration

GitHub Actions runs two independent jobs on pushes and pull requests:

```text
ShellCheck
Test Suite
```

The separation makes static-analysis failures and behavioral test failures
independently visible in CI.

## Version 1.0 scope

Version 1.0 is intentionally **audit-only**.

Automatic remediation is not performed.

This keeps the initial stable release focused on predictable security
assessment, explicit finding semantics, and safe execution on real Linux
systems.

## Roadmap

Possible post-1.0 development areas include:

- controlled remediation workflows
- pre-change configuration backup
- rollback support
- Ansible integration
- broader distribution-specific coverage
- additional security domains
- expanded automated test fixtures
- report schema evolution

## License

Released under the MIT License.

See [LICENSE](LICENSE).
