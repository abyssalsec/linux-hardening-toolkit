#!/usr/bin/env bash

LHT_UPDATES_COLLECTED=0
LHT_UPDATES_BACKEND=""
LHT_UPDATES_APT_DUMP=""

LHT_UPDATES_DNF_CONF="${LHT_UPDATES_DNF_CONF:-/etc/dnf/automatic.conf}"

lht_updates_collect() {
  if (( LHT_UPDATES_COLLECTED == 1 )); then
    return 0
  fi

  LHT_UPDATES_COLLECTED=1

  if command -v apt-config >/dev/null 2>&1 \
    && command -v apt-get >/dev/null 2>&1; then

    LHT_UPDATES_BACKEND="apt"
    LHT_UPDATES_APT_DUMP="$(apt-config dump 2>/dev/null || true)"
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    LHT_UPDATES_BACKEND="dnf"
    return 0
  fi

  LHT_UPDATES_BACKEND="unsupported"
}

lht_updates_systemd_available() {
  command -v systemctl >/dev/null 2>&1 \
    && [[ -d /run/systemd/system ]]
}

lht_updates_apt_value() {
  local key="${1:?APT configuration key is required}"
  local value=""

  lht_updates_collect

  [[ "$LHT_UPDATES_BACKEND" == "apt" ]] || return 1

  value="$(
    printf '%s\n' "$LHT_UPDATES_APT_DUMP" |
      awk -v wanted="$key" '
        $1 == wanted {
          value=$2
          gsub(/^"/, "", value)
          gsub(/";$/, "", value)
        }

        END {
          if (value != "") {
            print value
          }
        }
      '
  )"

  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

lht_updates_dnf_value() {
  local section="${1:?section is required}"
  local key="${2:?key is required}"

  [[ -r "$LHT_UPDATES_DNF_CONF" ]] || return 1

  local value=""

  value="$(
    awk \
      -v wanted_section="$section" \
      -v wanted_key="$key" '
        function trim(value) {
          sub(/^[[:space:]]+/, "", value)
          sub(/[[:space:]]+$/, "", value)
          return value
        }

        {
          line=trim($0)

          if (line == "" || line ~ /^[#;]/) {
            next
          }

          if (line ~ /^\[/) {
            current=line
            sub(/^\[/, "", current)
            sub(/\]$/, "", current)
            current=tolower(trim(current))
            next
          }

          if (current == tolower(wanted_section) && index(line, "=") > 0) {
            option=line
            sub(/=.*/, "", option)
            option=tolower(trim(option))

            if (option == tolower(wanted_key)) {
              result=line
              sub(/^[^=]*=/, "", result)
              result=trim(result)
            }
          }
        }

        END {
          if (result != "") {
            print result
          }
        }
      ' "$LHT_UPDATES_DNF_CONF"
  )"

  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

lht_updates_timer_state() {
  local unit="${1:?unit is required}"

  local enabled=""
  local active=""

  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  active="$(systemctl is-active "$unit" 2>/dev/null || true)"

  printf '%s|%s' "${enabled:-unknown}" "${active:-unknown}"
}

lht_check_updates_backend() {
  lht_updates_collect

  case "$LHT_UPDATES_BACKEND" in
    apt)
      lht_result \
        "PASS" \
        "APT automatic update backend detected" \
        "backend=apt"
      ;;

    dnf)
      lht_result \
        "PASS" \
        "DNF automatic update backend detected" \
        "backend=dnf"
      ;;

    *)
      lht_result \
        "SKIP" \
        "Supported automatic update backend was not detected" \
        "Currently supported backends: APT and DNF"
      ;;
  esac
}

lht_check_updates_automatic_tool() {
  lht_updates_collect

  case "$LHT_UPDATES_BACKEND" in
    apt)
      if command -v unattended-upgrade >/dev/null 2>&1; then
        lht_result \
          "PASS" \
          "APT unattended-upgrades is installed" \
          "unattended-upgrade command is available"
      else
        lht_result \
          "FAIL" \
          "APT unattended-upgrades is not installed" \
          "unattended-upgrade command was not found"
      fi
      ;;

    dnf)
      if command -v dnf-automatic >/dev/null 2>&1; then
        lht_result \
          "PASS" \
          "DNF automatic update tooling is installed" \
          "dnf-automatic command is available"
      else
        lht_result \
          "FAIL" \
          "DNF automatic update tooling is not installed" \
          "dnf-automatic command was not found"
      fi
      ;;

    *)
      lht_result \
        "SKIP" \
        "Automatic update tooling could not be evaluated" \
        "No supported package manager backend was detected"
      ;;
  esac
}

lht_check_updates_metadata_refresh() {
  lht_updates_collect

  case "$LHT_UPDATES_BACKEND" in
    apt)
      local value=""

      if ! value="$(
        lht_updates_apt_value \
          "APT::Periodic::Update-Package-Lists"
      )"; then

        lht_result \
          "FAIL" \
          "Automatic APT package index refresh is not configured" \
          "APT::Periodic::Update-Package-Lists is not set"
        return 0
      fi

      if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        lht_result \
          "ERROR" \
          "Automatic APT package index interval is invalid" \
          "APT::Periodic::Update-Package-Lists=${value}"
        return 0
      fi

      if (( value > 0 )); then
        lht_result \
          "PASS" \
          "Automatic APT package index refresh is enabled" \
          "APT::Periodic::Update-Package-Lists=${value}"
      else
        lht_result \
          "FAIL" \
          "Automatic APT package index refresh is disabled" \
          "APT::Periodic::Update-Package-Lists=${value}"
      fi
      ;;

    dnf)
      lht_result \
        "SKIP" \
        "DNF metadata refresh is not evaluated separately" \
        "DNF automatic transactions manage repository metadata as part of update execution"
      ;;

    *)
      lht_result \
        "SKIP" \
        "Automatic package metadata refresh could not be evaluated" \
        "No supported package manager backend was detected"
      ;;
  esac
}

lht_check_updates_auto_install() {
  lht_updates_collect

  case "$LHT_UPDATES_BACKEND" in
    apt)
      local value=""

      if ! value="$(
        lht_updates_apt_value \
          "APT::Periodic::Unattended-Upgrade"
      )"; then

        lht_result \
          "FAIL" \
          "Automatic APT package installation is not configured" \
          "APT::Periodic::Unattended-Upgrade is not set"
        return 0
      fi

      if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        lht_result \
          "ERROR" \
          "Automatic APT upgrade interval is invalid" \
          "APT::Periodic::Unattended-Upgrade=${value}"
        return 0
      fi

      if (( value > 0 )); then
        lht_result \
          "PASS" \
          "APT unattended package installation is enabled" \
          "APT::Periodic::Unattended-Upgrade=${value}"
      else
        lht_result \
          "FAIL" \
          "APT unattended package installation is disabled" \
          "APT::Periodic::Unattended-Upgrade=${value}"
      fi
      ;;

    dnf)
      local value=""

      if ! value="$(lht_updates_dnf_value commands apply_updates)"; then
        lht_result \
          "FAIL" \
          "DNF automatic package installation is not configured" \
          "${LHT_UPDATES_DNF_CONF}: commands.apply_updates is unavailable"
        return 0
      fi

      case "${value,,}" in
        yes|true|1)
          lht_result \
            "PASS" \
            "DNF automatic package installation is enabled" \
            "apply_updates=${value}"
          ;;

        no|false|0)
          lht_result \
            "FAIL" \
            "DNF automatic package installation is disabled" \
            "apply_updates=${value}"
          ;;

        *)
          lht_result \
            "ERROR" \
            "DNF automatic update setting is invalid" \
            "apply_updates=${value}"
          ;;
      esac
      ;;

    *)
      lht_result \
        "SKIP" \
        "Automatic package installation could not be evaluated" \
        "No supported package manager backend was detected"
      ;;
  esac
}

lht_check_updates_security_scope() {
  lht_updates_collect

  case "$LHT_UPDATES_BACKEND" in
    apt)
      local origins=""

      origins="$(
        printf '%s\n' "$LHT_UPDATES_APT_DUMP" |
          grep -Ei \
            '^Unattended-Upgrade::(Allowed-Origins|Origins-Pattern)' \
          || true
      )"

      if [[ -z "$origins" ]]; then
        lht_result \
          "FAIL" \
          "Unattended APT update origins are not configured" \
          "No Allowed-Origins or Origins-Pattern configuration was found"
        return 0
      fi

      if grep -Eqi 'security' <<< "$origins"; then
        local security_origins=""

        security_origins="$(
          printf '%s\n' "$origins" |
            grep -Ei 'security' |
            head -n 6 |
            paste -sd ';' -
        )"

        lht_result \
          "PASS" \
          "APT unattended upgrades include security repositories" \
          "${security_origins}"
      else
        lht_result \
          "FAIL" \
          "APT unattended upgrades do not explicitly include security repositories" \
          "Configured unattended origins contain no security origin"
      fi
      ;;

    dnf)
      local value=""

      if ! value="$(lht_updates_dnf_value commands upgrade_type)"; then
        lht_result \
          "WARN" \
          "DNF automatic update scope could not be determined" \
          "${LHT_UPDATES_DNF_CONF}: commands.upgrade_type is unavailable"
        return 0
      fi

      case "${value,,}" in
        security)
          lht_result \
            "PASS" \
            "DNF automatic updates are scoped to security updates" \
            "upgrade_type=${value}"
          ;;

        default)
          lht_result \
            "WARN" \
            "DNF automatic updates use the default update scope" \
            "upgrade_type=${value}; security updates should be included, but the scope is broader than security-only"
          ;;

        *)
          lht_result \
            "WARN" \
            "DNF automatic update scope requires manual review" \
            "upgrade_type=${value}"
          ;;
      esac
      ;;

    *)
      lht_result \
        "SKIP" \
        "Automatic security update scope could not be evaluated" \
        "No supported package manager backend was detected"
      ;;
  esac
}

lht_check_updates_scheduler() {
  lht_updates_collect

  if ! lht_updates_systemd_available; then
    lht_result \
      "SKIP" \
      "Automatic update scheduler could not be evaluated" \
      "systemd is not the active service manager"
    return 0
  fi

  case "$LHT_UPDATES_BACKEND" in
    apt)
      local unit=""
      local state=""
      local enabled=""
      local active=""
      local findings=""

      for unit in \
        "apt-daily.timer" \
        "apt-daily-upgrade.timer"; do

        state="$(lht_updates_timer_state "$unit")"
        IFS='|' read -r enabled active <<< "$state"

        if [[ "$enabled" != "enabled" \
          && "$enabled" != "enabled-runtime" ]]; then

          if [[ -z "$findings" ]]; then
            findings="${unit}:enabled=${enabled},active=${active}"
          else
            findings="${findings}; ${unit}:enabled=${enabled},active=${active}"
          fi

          continue
        fi

        if [[ "$active" != "active" ]]; then
          if [[ -z "$findings" ]]; then
            findings="${unit}:enabled=${enabled},active=${active}"
          else
            findings="${findings}; ${unit}:enabled=${enabled},active=${active}"
          fi
        fi
      done

      if [[ -n "$findings" ]]; then
        lht_result \
          "FAIL" \
          "APT automatic update timers are not fully active" \
          "$findings"
      else
        lht_result \
          "PASS" \
          "APT automatic update timers are enabled and active" \
          "apt-daily.timer=enabled/active; apt-daily-upgrade.timer=enabled/active"
      fi
      ;;

    dnf)
      local unit=""
      local state=""
      local enabled=""
      local active=""
      local found=0
      local healthy=0
      local details=""

      for unit in \
        "dnf-automatic-install.timer" \
        "dnf-automatic.timer" \
        "dnf5-automatic.timer"; do

        state="$(lht_updates_timer_state "$unit")"
        IFS='|' read -r enabled active <<< "$state"

        if [[ "$enabled" == "unknown" \
          && "$active" == "unknown" ]]; then
          continue
        fi

        if [[ "$enabled" == "not-found" \
          || "$active" == "not-found" ]]; then
          continue
        fi

        found=$((found + 1))

        if [[ -z "$details" ]]; then
          details="${unit}:enabled=${enabled},active=${active}"
        else
          details="${details}; ${unit}:enabled=${enabled},active=${active}"
        fi

        if [[ "$active" == "active" ]] \
          && [[ "$enabled" == "enabled" \
            || "$enabled" == "enabled-runtime" ]]; then

          healthy=$((healthy + 1))
        fi
      done

      if (( healthy > 0 )); then
        lht_result \
          "PASS" \
          "DNF automatic update scheduler is enabled and active" \
          "$details"
      elif (( found > 0 )); then
        lht_result \
          "FAIL" \
          "DNF automatic update timer is not fully active" \
          "$details"
      else
        lht_result \
          "FAIL" \
          "DNF automatic update timer was not found" \
          "Checked dnf-automatic-install.timer, dnf-automatic.timer, and dnf5-automatic.timer"
      fi
      ;;

    *)
      lht_result \
        "SKIP" \
        "Automatic update scheduler could not be evaluated" \
        "No supported package manager backend was detected"
      ;;
  esac
}

lht_check_updates_reboot_required() {
  lht_updates_collect

  case "$LHT_UPDATES_BACKEND" in
    apt)
      local marker=""

      for marker in \
        "/run/reboot-required" \
        "/var/run/reboot-required"; do

        if [[ -e "$marker" ]]; then
          local packages=""

          if [[ -r "${marker}.pkgs" ]]; then
            packages="$(
              head -n 8 "${marker}.pkgs" 2>/dev/null |
                paste -sd ',' -
            )"
          fi

          lht_result \
            "WARN" \
            "A system reboot is required to complete installed updates" \
            "marker=${marker}; packages=${packages:-unavailable}"
          return 0
        fi
      done

      lht_result \
        "PASS" \
        "No pending reboot marker was detected" \
        "No /run/reboot-required marker exists"
      ;;

    dnf)
      lht_result \
        "SKIP" \
        "Pending reboot state is not evaluated for DNF systems" \
        "No portable reboot-required marker is available for this backend"
      ;;

    *)
      lht_result \
        "SKIP" \
        "Pending reboot state could not be evaluated" \
        "No supported package manager backend was detected"
      ;;
  esac
}

lht_register_check \
  "updates.backend" \
  "updates" \
  "Automatic update backend detected" \
  "info" \
  "lht_check_updates_backend"

lht_register_check \
  "updates.automatic-tool" \
  "updates" \
  "Automatic update tooling installed" \
  "high" \
  "lht_check_updates_automatic_tool"

lht_register_check \
  "updates.metadata-refresh" \
  "updates" \
  "Automatic package metadata refresh configured" \
  "medium" \
  "lht_check_updates_metadata_refresh"

lht_register_check \
  "updates.auto-install" \
  "updates" \
  "Automatic package installation enabled" \
  "high" \
  "lht_check_updates_auto_install"

lht_register_check \
  "updates.security-scope" \
  "updates" \
  "Automatic updates include security updates" \
  "critical" \
  "lht_check_updates_security_scope"

lht_register_check \
  "updates.scheduler" \
  "updates" \
  "Automatic update scheduler active" \
  "high" \
  "lht_check_updates_scheduler"

lht_register_check \
  "updates.reboot-required" \
  "updates" \
  "Pending update reboot state reviewed" \
  "medium" \
  "lht_check_updates_reboot_required"
