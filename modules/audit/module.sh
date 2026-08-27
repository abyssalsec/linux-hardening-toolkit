#!/usr/bin/env bash

LHT_AUDIT_JOURNALD_CONF="${LHT_AUDIT_JOURNALD_CONF:-/etc/systemd/journald.conf}"
LHT_AUDIT_JOURNALD_DROPIN="${LHT_AUDIT_JOURNALD_DROPIN:-/etc/systemd/journald.conf.d}"
LHT_AUDIT_AUDITD_CONF="${LHT_AUDIT_AUDITD_CONF:-/etc/audit/auditd.conf}"

lht_audit_systemd_available() {
  command -v systemctl >/dev/null 2>&1 \
    && [[ -d /run/systemd/system ]]
}

lht_audit_service_active() {
  local unit="${1:?unit is required}"

  lht_audit_systemd_available || return 1

  systemctl is-active --quiet "$unit" 2>/dev/null
}

lht_audit_find_command() {
  local command_name="${1:?command name is required}"

  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
    return 0
  fi

  for path in \
    "/sbin/${command_name}" \
    "/usr/sbin/${command_name}"; do

    if [[ -x "$path" ]]; then
      printf '%s' "$path"
      return 0
    fi
  done

  return 1
}

lht_audit_journald_value() {
  local key="${1:?key is required}"
  local file=""
  local line=""
  local value=""

  local -a files=("$LHT_AUDIT_JOURNALD_CONF")

  if [[ -d "$LHT_AUDIT_JOURNALD_DROPIN" ]]; then
    while IFS= read -r file; do
      files+=("$file")
    done < <(
      find "$LHT_AUDIT_JOURNALD_DROPIN" \
        -maxdepth 1 \
        -type f \
        -name '*.conf' \
        -print \
        2>/dev/null | sort
    )
  fi

  for file in "${files[@]}"; do
    [[ -r "$file" ]] || continue

    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue

      if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^[:space:]#]+) ]]; then
        value="${BASH_REMATCH[1]}"
      fi
    done < "$file"
  done

  [[ -n "$value" ]] || return 1

  printf '%s' "$value"
}

lht_audit_conf_value() {
  local key="${1:?key is required}"

  [[ -r "$LHT_AUDIT_AUDITD_CONF" ]] || return 1

  local line=""
  local value=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^[:space:]#]+) ]]; then
      value="${BASH_REMATCH[1]}"
    fi
  done < "$LHT_AUDIT_AUDITD_CONF"

  [[ -n "$value" ]] || return 1

  printf '%s' "$value"
}

lht_audit_append_detail() {
  local current="${1-}"
  local item="${2-}"

  if [[ -z "$current" ]]; then
    printf '%s' "$item"
  else
    printf '%s; %s' "$current" "$item"
  fi
}

lht_check_logging_journald() {
  if ! lht_audit_systemd_available; then
    lht_result \
      "SKIP" \
      "systemd-journald state could not be evaluated" \
      "systemd is not the active service manager"
    return 0
  fi

  if lht_audit_service_active "systemd-journald.service"; then
    lht_result \
      "PASS" \
      "systemd-journald is active" \
      "systemd-journald.service is running"
  else
    lht_result \
      "FAIL" \
      "systemd-journald is not active" \
      "systemd-journald.service is not running"
  fi
}

lht_check_logging_persistence() {
  local storage=""

  storage="$(
    lht_audit_journald_value "Storage" || true
  )"

  case "${storage,,}" in
    persistent)
      lht_result \
        "PASS" \
        "Persistent systemd journal storage is configured" \
        "Storage=persistent"
      return 0
      ;;

    volatile)
      lht_result \
        "FAIL" \
        "systemd journal storage is volatile" \
        "Storage=volatile; logs are not retained across reboot"
      return 0
      ;;

    none)
      lht_result \
        "FAIL" \
        "systemd journal storage is disabled" \
        "Storage=none"
      return 0
      ;;

    auto|"")
      if [[ -d /var/log/journal ]]; then
        lht_result \
          "PASS" \
          "Persistent systemd journal storage is available" \
          "Storage=${storage:-auto(default)}; /var/log/journal exists"
      else
        lht_result \
          "WARN" \
          "systemd journal persistence is not guaranteed" \
          "Storage=${storage:-auto(default)}; /var/log/journal does not exist"
      fi
      return 0
      ;;

    *)
      lht_result \
        "WARN" \
        "systemd journal storage mode requires manual review" \
        "Storage=${storage}"
      ;;
  esac
}

lht_check_logging_syslog() {
  if lht_audit_service_active "rsyslog.service"; then
    lht_result \
      "PASS" \
      "rsyslog is active" \
      "rsyslog.service is running"
    return 0
  fi

  if lht_audit_service_active "syslog-ng.service"; then
    lht_result \
      "PASS" \
      "syslog-ng is active" \
      "syslog-ng.service is running"
    return 0
  fi

  if command -v rsyslogd >/dev/null 2>&1 \
    || command -v syslog-ng >/dev/null 2>&1; then

    lht_result \
      "WARN" \
      "A syslog daemon is installed but not active" \
      "Neither rsyslog.service nor syslog-ng.service is running"
    return 0
  fi

  lht_result \
    "WARN" \
    "No traditional syslog daemon is active" \
    "Persistent journald may be sufficient depending on the host role"
}

lht_check_logging_permissions() {
  local -a files=(
    "/var/log/auth.log"
    "/var/log/syslog"
    "/var/log/audit/audit.log"
  )

  local file=""
  local metadata=""
  local owner=""
  local group=""
  local mode=""
  local mode_decimal=0
  local checked=0
  local violations=""

  for file in "${files[@]}"; do
    [[ -e "$file" ]] || continue

    checked=$((checked + 1))

    if ! metadata="$(stat -c '%U|%G|%a' -- "$file" 2>/dev/null)"; then
      violations="$(
        lht_audit_append_detail \
          "$violations" \
          "${file}:stat-failed"
      )"
      continue
    fi

    IFS='|' read -r owner group mode <<< "$metadata"

    if [[ ! "$mode" =~ ^[0-7]{3,4}$ ]]; then
      violations="$(
        lht_audit_append_detail \
          "$violations" \
          "${file}:invalid-mode=${mode}"
      )"
      continue
    fi

    mode_decimal="$((8#$mode))"

    if [[ "$owner" != "root" && "$owner" != "syslog" ]]; then
      violations="$(
        lht_audit_append_detail \
          "$violations" \
          "${file}:owner=${owner}"
      )"
    fi

    if [[ "$group" != "root" \
      && "$group" != "adm" \
      && "$group" != "audit" ]]; then

      violations="$(
        lht_audit_append_detail \
          "$violations" \
          "${file}:group=${group}"
      )"
    fi

    if (( (mode_decimal & 8#0027) != 0 )); then
      violations="$(
        lht_audit_append_detail \
          "$violations" \
          "${file}:mode=${mode}"
      )"
    fi
  done

  if (( checked == 0 )); then
    lht_result \
      "SKIP" \
      "Log file permissions could not be evaluated" \
      "No supported log files were found"
    return 0
  fi

  if [[ -n "$violations" ]]; then
    lht_result \
      "FAIL" \
      "One or more security log files have unsafe metadata" \
      "$violations"
    return 0
  fi

  lht_result \
    "PASS" \
    "Security log file permissions are restrictive" \
    "checked=${checked}; no unsafe ownership or permission bits detected"
}

lht_check_auditd_available() {
  local auditctl=""

  if auditctl="$(lht_audit_find_command auditctl)"; then
    lht_result \
      "PASS" \
      "Linux audit userspace tools are available" \
      "auditctl=${auditctl}"
  else
    lht_result \
      "FAIL" \
      "Linux audit userspace tools are not installed" \
      "auditctl command was not found"
  fi
}

lht_check_auditd_active() {
  if ! lht_audit_find_command auditctl >/dev/null; then
    lht_result \
      "SKIP" \
      "auditd service state could not be evaluated" \
      "auditctl is not installed"
    return 0
  fi

  if lht_audit_service_active "auditd.service"; then
    lht_result \
      "PASS" \
      "auditd service is active" \
      "auditd.service is running"
  else
    lht_result \
      "FAIL" \
      "auditd service is not active" \
      "auditd.service is not running"
  fi
}

lht_check_auditd_kernel_status() {
  local auditctl=""

  if ! auditctl="$(lht_audit_find_command auditctl)"; then
    lht_result \
      "SKIP" \
      "Kernel audit status could not be evaluated" \
      "auditctl is not installed"
    return 0
  fi

  local output=""
  local enabled=""

  if ! output="$("$auditctl" -s 2>&1)"; then
    lht_result \
      "ERROR" \
      "Kernel audit status could not be queried" \
      "auditctl -s failed"
    return 0
  fi

  enabled="$(
    printf '%s\n' "$output" |
      awk '$1 == "enabled" {print $2; exit}'
  )"

  case "$enabled" in
    1|2)
      lht_result \
        "PASS" \
        "Linux kernel auditing is enabled" \
        "enabled=${enabled}"
      ;;

    0)
      lht_result \
        "FAIL" \
        "Linux kernel auditing is disabled" \
        "enabled=0"
      ;;

    *)
      lht_result \
        "ERROR" \
        "Linux kernel audit state could not be interpreted" \
        "enabled=${enabled:-unknown}"
      ;;
  esac
}

lht_check_auditd_rules() {
  local auditctl=""

  if ! auditctl="$(lht_audit_find_command auditctl)"; then
    lht_result \
      "SKIP" \
      "Audit rule configuration could not be evaluated" \
      "auditctl is not installed"
    return 0
  fi

  local output=""
  local count=0

  if ! output="$("$auditctl" -l 2>&1)"; then
    lht_result \
      "ERROR" \
      "Audit rules could not be queried" \
      "auditctl -l failed"
    return 0
  fi

  count="$(
    printf '%s\n' "$output" |
      awk '
        NF && $0 !~ /^[[:space:]]*No rules/ {
          count++
        }
        END {print count+0}
      '
  )"

  if (( count == 0 )); then
    lht_result \
      "FAIL" \
      "No active Linux audit rules were detected" \
      "auditctl -l returned no active rules"
    return 0
  fi

  lht_result \
    "PASS" \
    "Linux audit rules are active" \
    "rules=${count}"
}

lht_check_auditd_critical_paths() {
  local auditctl=""

  if ! auditctl="$(lht_audit_find_command auditctl)"; then
    lht_result \
      "SKIP" \
      "Critical-path audit coverage could not be evaluated" \
      "auditctl is not installed"
    return 0
  fi

  local output=""

  if ! output="$("$auditctl" -l 2>&1)"; then
    lht_result \
      "ERROR" \
      "Critical-path audit coverage could not be queried" \
      "auditctl -l failed"
    return 0
  fi

  if [[ -z "$(lht_trim "$output")" ]] \
    || grep -Eqi '^[[:space:]]*No rules' <<< "$output"; then

    lht_result \
      "SKIP" \
      "Critical-path audit coverage could not be evaluated" \
      "No active audit rules are configured"
    return 0
  fi

  local -a paths=(
    "/etc/passwd"
    "/etc/shadow"
    "/etc/sudoers"
    "/etc/ssh"
  )

  local path=""
  local covered=0
  local missing=""

  for path in "${paths[@]}"; do
    if grep -Fq -- "$path" <<< "$output"; then
      covered=$((covered + 1))
    else
      missing="$(
        lht_audit_append_detail \
          "$missing" \
          "$path"
      )"
    fi
  done

  if [[ -z "$missing" ]]; then
    lht_result \
      "PASS" \
      "Critical authentication and privilege paths are audited" \
      "covered=${covered}/${#paths[@]}"
  else
    lht_result \
      "WARN" \
      "Critical-path audit coverage requires manual review" \
      "covered=${covered}/${#paths[@]}; no direct rule reference found for ${missing}"
  fi
}

lht_check_auditd_config() {
  if ! lht_audit_find_command auditctl >/dev/null; then
    lht_result \
      "SKIP" \
      "auditd log handling policy could not be evaluated" \
      "auditctl is not installed"
    return 0
  fi

  if [[ ! -r "$LHT_AUDIT_AUDITD_CONF" ]]; then
    lht_result \
      "SKIP" \
      "auditd configuration file is unavailable" \
      "${LHT_AUDIT_AUDITD_CONF} is not readable"
    return 0
  fi

  local disk_full=""
  local disk_error=""
  local admin_space=""
  local findings=""

  disk_full="$(lht_audit_conf_value disk_full_action || true)"
  disk_error="$(lht_audit_conf_value disk_error_action || true)"
  admin_space="$(lht_audit_conf_value admin_space_left_action || true)"

  if [[ "${disk_full,,}" == "ignore" ]]; then
    findings="$(
      lht_audit_append_detail \
        "$findings" \
        "disk_full_action=${disk_full}"
    )"
  fi

  if [[ "${disk_error,,}" == "ignore" ]]; then
    findings="$(
      lht_audit_append_detail \
        "$findings" \
        "disk_error_action=${disk_error}"
    )"
  fi

  if [[ "${admin_space,,}" == "ignore" ]]; then
    findings="$(
      lht_audit_append_detail \
        "$findings" \
        "admin_space_left_action=${admin_space}"
    )"
  fi

  if [[ -n "$findings" ]]; then
    lht_result \
      "FAIL" \
      "auditd failure handling contains unsafe ignore actions" \
      "$findings"
    return 0
  fi

  lht_result \
    "PASS" \
    "auditd log failure handling is configured" \
    "disk_full_action=${disk_full:-default}; disk_error_action=${disk_error:-default}; admin_space_left_action=${admin_space:-default}"
}

lht_register_check \
  "logging.journald" \
  "logging" \
  "systemd-journald active" \
  "high" \
  "lht_check_logging_journald"

lht_register_check \
  "logging.persistence" \
  "logging" \
  "Persistent journal storage configured" \
  "high" \
  "lht_check_logging_persistence"

lht_register_check \
  "logging.syslog" \
  "logging" \
  "Traditional syslog service reviewed" \
  "medium" \
  "lht_check_logging_syslog"

lht_register_check \
  "logging.permissions" \
  "logging" \
  "Security log file permissions restrictive" \
  "high" \
  "lht_check_logging_permissions"

lht_register_check \
  "auditd.available" \
  "audit" \
  "Linux audit userspace available" \
  "high" \
  "lht_check_auditd_available"

lht_register_check \
  "auditd.active" \
  "audit" \
  "auditd service active" \
  "high" \
  "lht_check_auditd_active"

lht_register_check \
  "auditd.kernel-status" \
  "audit" \
  "Kernel auditing enabled" \
  "high" \
  "lht_check_auditd_kernel_status"

lht_register_check \
  "auditd.rules" \
  "audit" \
  "Linux audit rules configured" \
  "high" \
  "lht_check_auditd_rules"

lht_register_check \
  "auditd.critical-paths" \
  "audit" \
  "Critical security paths audited" \
  "medium" \
  "lht_check_auditd_critical_paths"

lht_register_check \
  "auditd.config" \
  "audit" \
  "auditd failure handling reviewed" \
  "medium" \
  "lht_check_auditd_config"
