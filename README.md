# Linux Hardening Toolkit

Linux Hardening Toolkit is a modular Bash-based security auditing and
hardening framework for Linux servers.

The project is designed to provide reproducible security checks,
controlled remediation, configuration backup and rollback, profiles,
reporting, and automation-friendly execution.

> Current version: v0.5.0

## Project status

v0.3 provides a read-only modular security audit framework covering
runtime validation, OpenSSH configuration, and local Linux account
security.

Implemented:

- modular check registry;
- profile-based check selection;
- standardized audit results;
- deterministic exit codes;
- verbose and colorless CLI output;
- dry-run execution context;
- privilege-aware checks;
- runtime validation;
- OpenSSH effective configuration audit;
- local account integrity audit;
- local password metadata audit;
- Linux kernel runtime security audit;
- IPv4/IPv6 sysctl security audit;
- effective reverse-path filtering analysis;
- sudo policy syntax and configuration integrity audit.
Configuration remediation is not implemented yet.

## Usage

Make the CLI executable:

```bash
chmod +x bin/linux-hardening-toolkit
```

Show help:

```bash
./bin/linux-hardening-toolkit --help
```

Run the default audit:

```bash
./bin/linux-hardening-toolkit audit
```

Run with additional diagnostic details:

```bash
./bin/linux-hardening-toolkit \
  --verbose \
  audit
```

Run a complete privileged host audit:

```bash
sudo ./bin/linux-hardening-toolkit \
  --verbose \
  audit
```

Disable ANSI colors:

```bash
./bin/linux-hardening-toolkit \
  --no-color \
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

Example:

```bash
lht_register_check \
  "example.security-check" \
  "example" \
  "Example security check" \
  "high" \
  "lht_check_example" \
  "lht_apply_example"
```

Audit functions return one of:

- `PASS`
- `FAIL`
- `WARN`
- `SKIP`
- `ERROR`

The same module registry is designed to support future audit and
remediation functionality without duplicating check metadata.

## Privilege model

The toolkit does not require root privileges globally.

Checks that can safely operate as an unprivileged user do so.

Checks requiring access to protected configuration or credential
metadata return `SKIP` when the current process does not have enough
privileges.

The toolkit never invokes `sudo` automatically.

For the most complete system audit, the administrator may explicitly
run:

```bash
sudo ./bin/linux-hardening-toolkit audit
```

## OpenSSH audit

The OpenSSH module evaluates the effective server configuration instead
of relying on direct text matching against `/etc/ssh/sshd_config`.

The module prefers:

```bash
sshd -G
```

This avoids requiring private host-key validation while obtaining the
effective OpenSSH configuration.

The current process must still be able to read the complete OpenSSH
configuration, including files referenced through `Include`.

If configuration snippets are not readable, affected SSH checks are
reported as `SKIP` and a privileged audit is recommended.

Current checks include:

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

### Conditional OpenSSH configuration

v0.3 evaluates the global effective OpenSSH configuration.

Context-specific evaluation of every possible `Match` condition is not
yet implemented and is not claimed by the project.

## Local account audit

The accounts module audits local host identities stored in:

```text
/etc/passwd
/etc/shadow
/etc/login.defs
```

The module intentionally does not treat LDAP, Active Directory, SSSD,
or other external NSS identities as local host accounts.

Current checks include:

- local account database integrity;
- exclusive ownership of UID 0 by root;
- duplicate numeric UIDs;
- password shadowing;
- system account login shells;
- empty shadow password fields;
- password-aging metadata consistency;
- future password-change dates;
- account creation defaults from `login.defs`.

### Shadow access

`/etc/shadow` contains protected password and aging information.

When it is not readable by the current process, shadow-backed checks are
reported as `SKIP`.

For complete account results:

```bash
sudo ./bin/linux-hardening-toolkit \
  --profile accounts \
  --verbose \
  audit
```

### Password aging policy

The toolkit does not currently enforce arbitrary periodic password
rotation such as a universal 30-, 60-, or 90-day expiration period.

Values including:

```text
PASS_MAX_DAYS
PASS_MIN_DAYS
PASS_WARN_AGE
```

are collected as account-creation defaults and audit context.

Existing per-account aging metadata is evaluated independently from
`/etc/shadow`.

A future configurable policy layer may allow organizations to explicitly
select stricter password-aging requirements when required by their own
security policy or compliance environment.

## sudo policy audit

The sudo module evaluates sudo configuration integrity without attempting
to implement a custom sudoers parser.

Native policy validation is performed with:

```bash
visudo -c

## Profiles

Profiles determine which registered checks are enabled.

Profile configuration is parsed as data and is never executed as shell
code.

Included profiles:

### default

General Linux server baseline:

```bash
./bin/linux-hardening-toolkit audit
```

### ssh-server

OpenSSH-specific audit:

```bash
./bin/linux-hardening-toolkit \
  --profile ssh-server \
  audit
```

### kernel

Linux kernel and network runtime security audit:

```bash
./bin/linux-hardening-toolkit \
  --profile kernel \
  audit

### accounts

Local account and password metadata audit:

```bash
./bin/linux-hardening-toolkit \
  --profile accounts \
  audit
```

For complete shadow-backed results:

```bash
sudo ./bin/linux-hardening-toolkit \
  --profile accounts \
  audit
```

### sudo

sudo policy and configuration integrity audit:

```bash
sudo ./bin/linux-hardening-toolkit \
  --profile sudo \
  audit

### firewall

Host firewall and network exposure audit:

```bash
sudo ./bin/linux-hardening-toolkit \
  --profile firewall \
  audit

The firewall audit detects supported host firewall backends including UFW,
firewalld, nftables, and iptables.

It evaluates whether host firewall filtering is active, reviews default
inbound and forwarding policies where possible, inspects the active ruleset,
and inventories network services listening on wildcard addresses.

Container-managed forwarding rules, such as Docker nftables chains, are not
treated as evidence that the host itself has an active inbound firewall
policy.

### auth

PAM and password authentication policy audit:

```bash
sudo ./bin/linux-hardening-toolkit \
  --profile auth \
  audit
```

The authentication audit detects the central PAM stack and reviews
null-password authentication, password quality enforcement, minimum password
length, password history, failed-login lockout policy, and password hashing.

Debian/Ubuntu common-* PAM layouts and RHEL-family system-auth/password-auth
layouts are supported. Checks distinguish between definite policy violations,
unavailable controls, and settings that require manual review.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | Command completed successfully and no failed checks were found |
| `1` | Toolkit, runtime, or check execution error |
| `2` | Audit completed successfully but one or more checks failed |

Warnings and skipped checks do not change the process exit code to `2`.

## Security baseline

Linux Hardening Toolkit does not claim official CIS certification or
official conformance with any third-party security benchmark.

Checks implemented by the project represent documented Linux security
practices and explicitly distinguish between:

- definite security baseline violations;
- environment-dependent security decisions;
- insufficient audit privileges;
- unavailable or non-applicable functionality;
- audit execution errors.

## Requirements

- Linux
- Bash 4.0 or newer

## Roadmap

Planned security domains and capabilities include:

- sudo policy;
- kernel and sysctl;
- filesystem permissions;
- unnecessary services;
- audit and logging;
- automatic security updates;
- remediation;
- configuration backup;
- rollback;
- machine-readable reports;
- Ansible integration;
- automated testing;
- GitHub Actions.

## License

MIT
