#!/usr/bin/env bash

LHT_SSH_COLLECTION_ATTEMPTED=0
LHT_SSH_COLLECTION_STATUS=""
LHT_SSH_COLLECTION_MESSAGE=""
LHT_SSHD_BINARY=""
LHT_SSH_SETTING_VALUE=""

declare -Ag LHT_SSH_EFFECTIVE_CONFIG=()

lht_ssh_find_sshd() {
  local candidate=""

  if command -v sshd >/dev/null 2>&1; then
    command -v sshd
    return 0
  fi

  for candidate in /usr/sbin/sshd /usr/local/sbin/sshd /sbin/sshd; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

lht_ssh_collect_effective_config() {
  if (( LHT_SSH_COLLECTION_ATTEMPTED == 1 )); then
    return 0
  fi

  LHT_SSH_COLLECTION_ATTEMPTED=1
  LHT_SSH_COLLECTION_STATUS=""
  LHT_SSH_COLLECTION_MESSAGE=""
  LHT_SSH_DUMP_MODE=""
  LHT_SSH_EFFECTIVE_CONFIG=()

  if ! LHT_SSHD_BINARY="$(lht_ssh_find_sshd)"; then
    LHT_SSH_COLLECTION_STATUS="not-installed"
    LHT_SSH_COLLECTION_MESSAGE="OpenSSH server executable was not found"
    return 0
  fi

  local output=""
  local command_rc=0
  local first_line=""

  #
  # Prefer sshd -G.
  #
  # -G prints the effective configuration without requiring host-key
  # validation. However, the current process must still be able to
  # read every configuration file referenced through Include.
  #
  if output="$(LC_ALL=C "$LHT_SSHD_BINARY" -G 2>&1)"; then
    LHT_SSH_DUMP_MODE="-G"

  else
    command_rc=$?
    first_line="${output%%$'\n'*}"

    if [[ -z "$first_line" ]]; then
      first_line="no diagnostic output"
    fi

    #
    # A configuration snippet may intentionally be unreadable by an
    # unprivileged user. Do not ignore it and do not attempt to parse
    # an incomplete configuration.
    #
    if (( EUID != 0 )) && [[ "$output" == *"Permission denied"* ]]; then
      LHT_SSH_COLLECTION_STATUS="requires-privilege"
      LHT_SSH_COLLECTION_MESSAGE="OpenSSH configuration contains files that are not readable by the current user. Re-run the SSH audit with elevated privileges. Diagnostic: ${first_line}"
      return 0
    fi

    #
    # Compatibility fallback for old OpenSSH implementations where
    # configuration dump mode (-G) may not be available.
    #
    # -T may require access to private host keys, so only use it when
    # the toolkit is already running as root.
    #
    if (( EUID == 0 )); then
      if output="$(LC_ALL=C "$LHT_SSHD_BINARY" -T 2>&1)"; then
        LHT_SSH_DUMP_MODE="-T"
      else
        command_rc=$?
        first_line="${output%%$'\n'*}"

        if [[ -z "$first_line" ]]; then
          first_line="no diagnostic output"
        fi

        LHT_SSH_COLLECTION_STATUS="error"
        LHT_SSH_COLLECTION_MESSAGE="Unable to obtain effective OpenSSH configuration. Diagnostic: ${first_line}"
        return 0
      fi
    else
      LHT_SSH_COLLECTION_STATUS="error"
      LHT_SSH_COLLECTION_MESSAGE="sshd -G failed with exit code ${command_rc}: ${first_line}"
      return 0
    fi
  fi

  local line=""
  local key=""
  local value=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue

    key="${line%%[[:space:]]*}"

    if [[ "$key" == "$line" ]]; then
      continue
    fi

    value="${line#"$key"}"
    value="$(lht_trim "$value")"
    key="${key,,}"

    [[ "$key" =~ ^[a-z0-9]+$ ]] || continue
    [[ -n "$value" ]] || continue

    LHT_SSH_EFFECTIVE_CONFIG["$key"]="$value"
  done <<< "$output"

  if (( ${#LHT_SSH_EFFECTIVE_CONFIG[@]} == 0 )); then
    LHT_SSH_COLLECTION_STATUS="error"
    LHT_SSH_COLLECTION_MESSAGE="sshd ${LHT_SSH_DUMP_MODE} returned no parseable configuration settings"
    return 0
  fi

  LHT_SSH_COLLECTION_STATUS="ok"
  LHT_SSH_COLLECTION_MESSAGE="Effective OpenSSH configuration collected successfully"
}

lht_ssh_require_effective_config() {
  lht_ssh_collect_effective_config

  case "$LHT_SSH_COLLECTION_STATUS" in
    ok)
      return 0
      ;;

    not-installed)
      lht_result \
        "SKIP" \
        "OpenSSH server is not installed" \
        "$LHT_SSH_COLLECTION_MESSAGE"
      return 1
      ;;

    requires-privilege)
      lht_result \
        "SKIP" \
        "SSH audit requires elevated read access" \
        "$LHT_SSH_COLLECTION_MESSAGE"
      return 1
      ;;

    error)
      lht_result \
        "SKIP" \
        "Effective SSH configuration is unavailable" \
        "See ssh.config-effective; ${LHT_SSH_COLLECTION_MESSAGE}"
      return 1
      ;;

    *)
      lht_result \
        "ERROR" \
        "Unexpected SSH collection state" \
        "State: ${LHT_SSH_COLLECTION_STATUS:-unset}"
      return 1
      ;;
  esac
}

lht_ssh_get_setting() {
  local key="${1:?setting name is required}"

  key="${key,,}"
  LHT_SSH_SETTING_VALUE=""

  if [[ -z "${LHT_SSH_EFFECTIVE_CONFIG[$key]+x}" ]]; then
    return 1
  fi

  LHT_SSH_SETTING_VALUE="${LHT_SSH_EFFECTIVE_CONFIG[$key]}"
  return 0
}

lht_ssh_check_exact_setting() {
  local key="${1:?setting name is required}"
  local expected="${2:?expected value is required}"
  local pass_message="${3:?pass message is required}"
  local mismatch_status="${4:?mismatch status is required}"
  local mismatch_message="${5:?mismatch message is required}"

  if ! lht_ssh_require_effective_config; then
    return 0
  fi

  if ! lht_ssh_get_setting "$key"; then
    lht_result \
      "ERROR" \
      "Required SSH setting is missing" \
      "sshd -T did not return '${key}'"
    return 0
  fi

  local actual="$LHT_SSH_SETTING_VALUE"

  if [[ "$actual" == "$expected" ]]; then
    lht_result \
      "PASS" \
      "$pass_message" \
      "${key}=${actual} (effective value)"
  else
    lht_result \
      "$mismatch_status" \
      "$mismatch_message" \
      "${key}=${actual}; expected ${expected}"
  fi
}

lht_check_ssh_config_effective() {
  lht_ssh_collect_effective_config

  case "$LHT_SSH_COLLECTION_STATUS" in
    ok)
      lht_result \
        "PASS" \
        "OpenSSH effective configuration is readable" \
        "${LHT_SSHD_BINARY} ${LHT_SSH_DUMP_MODE} returned ${#LHT_SSH_EFFECTIVE_CONFIG[@]} settings"
      ;;

    not-installed)
      lht_result \
        "SKIP" \
        "OpenSSH server is not installed" \
        "$LHT_SSH_COLLECTION_MESSAGE"
      ;;

    requires-privilege)
      lht_result \
        "SKIP" \
        "OpenSSH configuration requires elevated read access" \
        "$LHT_SSH_COLLECTION_MESSAGE"
      ;;

    error)
      lht_result \
        "ERROR" \
        "Unable to evaluate OpenSSH effective configuration" \
        "$LHT_SSH_COLLECTION_MESSAGE"
      ;;

    *)
      lht_result \
        "ERROR" \
        "Unexpected SSH collection state" \
        "State: ${LHT_SSH_COLLECTION_STATUS:-unset}"
      ;;
  esac
}

lht_check_ssh_root_login() {
  lht_ssh_check_exact_setting \
    "permitrootlogin" \
    "no" \
    "Direct SSH login as root is disabled" \
    "FAIL" \
    "Direct SSH login as root is not fully disabled"
}

lht_check_ssh_password_authentication() {
  lht_ssh_check_exact_setting \
    "passwordauthentication" \
    "no" \
    "SSH password authentication is disabled" \
    "FAIL" \
    "SSH password authentication is enabled"
}

lht_check_ssh_kbd_interactive_authentication() {
  lht_ssh_check_exact_setting \
    "kbdinteractiveauthentication" \
    "no" \
    "Keyboard-interactive authentication is disabled" \
    "FAIL" \
    "Keyboard-interactive authentication is enabled"
}

lht_check_ssh_empty_passwords() {
  lht_ssh_check_exact_setting \
    "permitemptypasswords" \
    "no" \
    "SSH login with empty passwords is disabled" \
    "FAIL" \
    "SSH login with empty passwords is permitted"
}

lht_check_ssh_pubkey_authentication() {
  lht_ssh_check_exact_setting \
    "pubkeyauthentication" \
    "yes" \
    "SSH public key authentication is enabled" \
    "FAIL" \
    "SSH public key authentication is disabled"
}

lht_check_ssh_max_auth_tries() {
  if ! lht_ssh_require_effective_config; then
    return 0
  fi

  if ! lht_ssh_get_setting "maxauthtries"; then
    lht_result \
      "ERROR" \
      "Required SSH setting is missing" \
      "sshd -T did not return 'maxauthtries'"
    return 0
  fi

  local actual="$LHT_SSH_SETTING_VALUE"

  if [[ ! "$actual" =~ ^[0-9]+$ ]]; then
    lht_result \
      "ERROR" \
      "Invalid effective MaxAuthTries value" \
      "maxauthtries=${actual}"
    return 0
  fi

  if (( actual <= 4 )); then
    lht_result \
      "PASS" \
      "SSH authentication attempts are limited" \
      "maxauthtries=${actual}; baseline requires <=4"
  else
    lht_result \
      "FAIL" \
      "SSH allows too many authentication attempts" \
      "maxauthtries=${actual}; baseline requires <=4"
  fi
}

lht_check_ssh_permit_user_environment() {
  lht_ssh_check_exact_setting \
    "permituserenvironment" \
    "no" \
    "SSH user-controlled environment processing is disabled" \
    "FAIL" \
    "SSH user-controlled environment processing is enabled"
}

lht_ssh_check_forwarding_setting() {
  local key="${1:?setting name is required}"
  local feature_name="${2:?feature name is required}"

  if ! lht_ssh_require_effective_config; then
    return 0
  fi

  if lht_ssh_get_setting "disableforwarding" \
    && [[ "$LHT_SSH_SETTING_VALUE" == "yes" ]]; then
    lht_result \
      "PASS" \
      "${feature_name} is disabled" \
      "disableforwarding=yes"
    return 0
  fi

  if ! lht_ssh_get_setting "$key"; then
    lht_result \
      "ERROR" \
      "Required SSH setting is missing" \
      "sshd -T did not return '${key}'"
    return 0
  fi

  local actual="$LHT_SSH_SETTING_VALUE"

  if [[ "$actual" == "no" ]]; then
    lht_result \
      "PASS" \
      "${feature_name} is disabled" \
      "${key}=${actual} (effective value)"
  else
    lht_result \
      "WARN" \
      "${feature_name} is enabled" \
      "${key}=${actual}; verify that forwarding is required for this server"
  fi
}

lht_check_ssh_x11_forwarding() {
  lht_ssh_check_forwarding_setting \
    "x11forwarding" \
    "SSH X11 forwarding"
}

lht_check_ssh_agent_forwarding() {
  lht_ssh_check_forwarding_setting \
    "allowagentforwarding" \
    "SSH agent forwarding"
}

lht_check_ssh_tcp_forwarding() {
  lht_ssh_check_forwarding_setting \
    "allowtcpforwarding" \
    "SSH TCP forwarding"
}

lht_register_check \
  "ssh.config-effective" \
  "ssh" \
  "OpenSSH effective configuration can be evaluated" \
  "high" \
  "lht_check_ssh_config_effective"

lht_register_check \
  "ssh.root-login" \
  "ssh" \
  "Direct SSH root login disabled" \
  "high" \
  "lht_check_ssh_root_login"

lht_register_check \
  "ssh.password-authentication" \
  "ssh" \
  "SSH password authentication disabled" \
  "high" \
  "lht_check_ssh_password_authentication"

lht_register_check \
  "ssh.kbd-interactive-authentication" \
  "ssh" \
  "Keyboard-interactive SSH authentication disabled" \
  "medium" \
  "lht_check_ssh_kbd_interactive_authentication"

lht_register_check \
  "ssh.empty-passwords" \
  "ssh" \
  "SSH empty-password logins disabled" \
  "critical" \
  "lht_check_ssh_empty_passwords"

lht_register_check \
  "ssh.pubkey-authentication" \
  "ssh" \
  "SSH public key authentication enabled" \
  "medium" \
  "lht_check_ssh_pubkey_authentication"

lht_register_check \
  "ssh.max-auth-tries" \
  "ssh" \
  "SSH authentication attempts limited" \
  "medium" \
  "lht_check_ssh_max_auth_tries"

lht_register_check \
  "ssh.permit-user-environment" \
  "ssh" \
  "SSH user environment processing disabled" \
  "medium" \
  "lht_check_ssh_permit_user_environment"

lht_register_check \
  "ssh.x11-forwarding" \
  "ssh" \
  "SSH X11 forwarding disabled" \
  "low" \
  "lht_check_ssh_x11_forwarding"

lht_register_check \
  "ssh.agent-forwarding" \
  "ssh" \
  "SSH agent forwarding reviewed" \
  "low" \
  "lht_check_ssh_agent_forwarding"

lht_register_check \
  "ssh.tcp-forwarding" \
  "ssh" \
  "SSH TCP forwarding reviewed" \
  "low" \
  "lht_check_ssh_tcp_forwarding"
