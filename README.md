# Linux Hardening Toolkit

Linux Hardening Toolkit is a modular Bash-based security auditing and
hardening framework for Linux servers.

The project is designed to provide reproducible security checks,
controlled remediation, configuration backup and rollback, profiles,
reporting, and automation-friendly execution.

> Current version: v0.2.0

## Project status

v0.2 provides the core read-only audit framework and the first
production security audit module for OpenSSH.

Implemented:

- modular check registry;
- profile-based check selection;
- standardized audit results;
- deterministic exit codes;
- verbose and colorless CLI output;
- dry-run execution context;
- runtime validation;
- OpenSSH effective configuration collection;
- OpenSSH security baseline checks.

Configuration remediation is not implemented yet.

## Usage

```bash
chmod +x bin/linux-hardening-toolkit

./bin/linux-hardening-toolkit --help
./bin/linux-hardening-toolkit version
./bin/linux-hardening-toolkit list-checks
./bin/linux-hardening-toolkit audit
```

Verbose audit:

```bash
./bin/linux-hardening-toolkit --verbose audit
```

Disable colors:

```bash
./bin/linux-hardening-toolkit --no-color audit
```

Run only the OpenSSH profile:

```bash
./bin/linux-hardening-toolkit \
  --profile ssh-server \
  audit
```

## Architecture

The CLI acts as an orchestration layer.

Security functionality is implemented by independent modules that
register checks with the core registry.

Each check has:

- a stable check ID;
- a category;
- a title;
- a severity;
- an audit function;
- an optional remediation function.

Example registration:

```bash
lht_register_check \
  "example.security-check" \
  "example" \
  "Example security check" \
  "high" \
  "lht_check_example" \
  "lht_apply_example"
```

Audit functions return standardized results:

- `PASS`
- `FAIL`
- `WARN`
- `SKIP`
- `ERROR`

This model allows future audit and remediation functionality to share
the same module metadata and profiles.

## OpenSSH audit

The OpenSSH module evaluates the effective server configuration instead
of relying on direct text matching against `/etc/ssh/sshd_config`.

The module collects configuration using:

```bash
sshd -T
```

The result is cached for the duration of the audit and consumed by
individual security checks.

Current checks:

- effective configuration availability;
- direct root login;
- password authentication;
- keyboard-interactive authentication;
- empty-password authentication;
- public key authentication;
- maximum authentication attempts;
- user-controlled environment processing;
- X11 forwarding;
- SSH agent forwarding;
- TCP forwarding.

The default SSH baseline assumes a server intended to use public-key
authentication rather than password authentication.

Some functionality, such as TCP forwarding and agent forwarding, may be
legitimate operational requirements. These checks therefore produce
warnings instead of automatically treating enabled forwarding as a
security failure.

### Conditional OpenSSH configuration

v0.2 evaluates the global effective OpenSSH configuration.

Conditional configuration based on `Match` blocks may depend on user,
source address, destination address, hostname, and other connection
context. Context-specific `Match` analysis is not implemented yet and
is not claimed by this version.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | Command completed successfully and no failed checks were found |
| `1` | Toolkit, runtime, or check execution error |
| `2` | Audit completed successfully but one or more checks failed |

Warnings do not change the process exit code to `2`.

## Profiles

Profiles determine which registered checks are enabled.

Profiles are parsed as configuration data and are not executed as shell
code.

Included profiles:

### default

General Linux server baseline.

```bash
./bin/linux-hardening-toolkit audit
```

### ssh-server

OpenSSH-specific audit.

```bash
./bin/linux-hardening-toolkit \
  --profile ssh-server \
  audit
```

## Security baseline

Linux Hardening Toolkit does not claim official CIS certification or
official conformance with any third-party security benchmark.

Security checks implemented by the project represent documented,
generally accepted Linux and service-hardening practices.

Checks should clearly distinguish between:

- definite baseline violations;
- environment-dependent security decisions;
- unavailable or non-applicable functionality;
- audit execution errors.

## Requirements

- Linux
- Bash 4.0 or newer

The audit framework does not require root privileges globally.

Some system configuration may not be readable or evaluable by an
unprivileged account. In such cases the toolkit reports the limitation
instead of silently guessing the effective configuration.

## Roadmap

Planned areas include:

- users and authentication policy;
- sudo policy;
- kernel and sysctl;
- firewall;
- filesystem permissions;
- unnecessary services;
- audit and logging;
- automatic security updates;
- configuration remediation;
- backup and rollback;
- machine-readable reports;
- Ansible integration;
- automated testing;
- CI workflows.

## License

MIT
