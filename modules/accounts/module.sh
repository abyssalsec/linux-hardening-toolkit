#!/usr/bin/env bash

LHT_ACCOUNTS_PASSWD_COLLECTION_ATTEMPTED=0
LHT_ACCOUNTS_PASSWD_STATUS=""
LHT_ACCOUNTS_PASSWD_MESSAGE=""

LHT_ACCOUNTS_SHADOW_COLLECTION_ATTEMPTED=0
LHT_ACCOUNTS_SHADOW_STATUS=""
LHT_ACCOUNTS_SHADOW_MESSAGE=""

LHT_ACCOUNTS_LOGIN_DEFS_ATTEMPTED=0
LHT_ACCOUNTS_LOGIN_DEFS_STATUS=""
LHT_ACCOUNTS_LOGIN_DEFS_MESSAGE=""

LHT_ACCOUNTS_UID_MIN=1000
LHT_ACCOUNTS_PASS_MAX_DAYS=""
LHT_ACCOUNTS_PASS_MIN_DAYS=""
LHT_ACCOUNTS_PASS_WARN_AGE=""

declare -ag LHT_ACCOUNTS_PASSWD_USERS=()

declare -Ag LHT_ACCOUNTS_PASSWD_PASSWORD=()
declare -Ag LHT_ACCOUNTS_PASSWD_UID=()
declare -Ag LHT_ACCOUNTS_PASSWD_SHELL=()
declare -Ag LHT_ACCOUNTS_UID_USERS=()

declare -ag LHT_ACCOUNTS_SHADOW_USERS=()

declare -Ag LHT_ACCOUNTS_SHADOW_PASSWORD=()
declare -Ag LHT_ACCOUNTS_SHADOW_LAST_CHANGE=()
declare -Ag LHT_ACCOUNTS_SHADOW_MIN_DAYS=()
declare -Ag LHT_ACCOUNTS_SHADOW_MAX_DAYS=()
declare -Ag LHT_ACCOUNTS_SHADOW_WARN_DAYS=()

lht_accounts_append_detail() {
  local current="${1-}"
  local item="${2-}"

  if [[ -z "$current" ]]; then
    printf '%s' "$item"
  else
    printf '%s; %s' "$current" "$item"
  fi
}

lht_accounts_collect_passwd() {
  if (( LHT_ACCOUNTS_PASSWD_COLLECTION_ATTEMPTED == 1 )); then
    return 0
  fi

  LHT_ACCOUNTS_PASSWD_COLLECTION_ATTEMPTED=1

  LHT_ACCOUNTS_PASSWD_USERS=()
  LHT_ACCOUNTS_PASSWD_PASSWORD=()
  LHT_ACCOUNTS_PASSWD_UID=()
  LHT_ACCOUNTS_PASSWD_SHELL=()
  LHT_ACCOUNTS_UID_USERS=()

  if [[ ! -r /etc/passwd ]]; then
    LHT_ACCOUNTS_PASSWD_STATUS="error"
    LHT_ACCOUNTS_PASSWD_MESSAGE="/etc/passwd is not readable"
    return 0
  fi

  local name=""
  local password=""
  local uid=""
  local gid=""
  local gecos=""
  local home=""
  local shell=""
  local extra=""
  local line_number=0

  while IFS=: read -r \
    name password uid gid gecos home shell extra \
    || [[ -n "$name$password$uid$gid$gecos$home$shell$extra" ]]; do

    line_number=$((line_number + 1))

    if [[ -z "$name" ]] \
      || [[ ! "$uid" =~ ^[0-9]+$ ]] \
      || [[ ! "$gid" =~ ^[0-9]+$ ]] \
      || [[ -n "$extra" ]]; then

      LHT_ACCOUNTS_PASSWD_STATUS="error"
      LHT_ACCOUNTS_PASSWD_MESSAGE="Malformed /etc/passwd entry at line ${line_number}"
      return 0
    fi

    if [[ -n "${LHT_ACCOUNTS_PASSWD_UID[$name]+x}" ]]; then
      LHT_ACCOUNTS_PASSWD_STATUS="error"
      LHT_ACCOUNTS_PASSWD_MESSAGE="Duplicate account name '${name}' in /etc/passwd"
      return 0
    fi

    LHT_ACCOUNTS_PASSWD_USERS+=("$name")

    LHT_ACCOUNTS_PASSWD_PASSWORD["$name"]="$password"
    LHT_ACCOUNTS_PASSWD_UID["$name"]="$uid"
    LHT_ACCOUNTS_PASSWD_SHELL["$name"]="$shell"

    if [[ -n "${LHT_ACCOUNTS_UID_USERS[$uid]+x}" ]]; then
      LHT_ACCOUNTS_UID_USERS["$uid"]+=",${name}"
    else
      LHT_ACCOUNTS_UID_USERS["$uid"]="$name"
    fi
  done < /etc/passwd

  if (( ${#LHT_ACCOUNTS_PASSWD_USERS[@]} == 0 )); then
    LHT_ACCOUNTS_PASSWD_STATUS="error"
    LHT_ACCOUNTS_PASSWD_MESSAGE="/etc/passwd contains no account entries"
    return 0
  fi

  LHT_ACCOUNTS_PASSWD_STATUS="ok"
  LHT_ACCOUNTS_PASSWD_MESSAGE="Local passwd database collected successfully"
}

lht_accounts_require_passwd() {
  lht_accounts_collect_passwd

  if [[ "$LHT_ACCOUNTS_PASSWD_STATUS" == "ok" ]]; then
    return 0
  fi

  lht_result \
    "ERROR" \
    "Local account database is unavailable" \
    "$LHT_ACCOUNTS_PASSWD_MESSAGE"

  return 1
}

lht_accounts_collect_shadow() {
  if (( LHT_ACCOUNTS_SHADOW_COLLECTION_ATTEMPTED == 1 )); then
    return 0
  fi

  LHT_ACCOUNTS_SHADOW_COLLECTION_ATTEMPTED=1

  LHT_ACCOUNTS_SHADOW_USERS=()
  LHT_ACCOUNTS_SHADOW_PASSWORD=()
  LHT_ACCOUNTS_SHADOW_LAST_CHANGE=()
  LHT_ACCOUNTS_SHADOW_MIN_DAYS=()
  LHT_ACCOUNTS_SHADOW_MAX_DAYS=()
  LHT_ACCOUNTS_SHADOW_WARN_DAYS=()

  if [[ ! -e /etc/shadow ]]; then
    LHT_ACCOUNTS_SHADOW_STATUS="error"
    LHT_ACCOUNTS_SHADOW_MESSAGE="/etc/shadow does not exist"
    return 0
  fi

  if [[ ! -r /etc/shadow ]]; then
    if (( EUID == 0 )); then
      LHT_ACCOUNTS_SHADOW_STATUS="error"
      LHT_ACCOUNTS_SHADOW_MESSAGE="/etc/shadow is not readable by root"
    else
      LHT_ACCOUNTS_SHADOW_STATUS="requires-privilege"
      LHT_ACCOUNTS_SHADOW_MESSAGE="/etc/shadow is not readable by the current user"
    fi

    return 0
  fi

  local name=""
  local password=""
  local last_change=""
  local min_days=""
  local max_days=""
  local warn_days=""
  local inactive_days=""
  local expire_day=""
  local flag=""
  local extra=""
  local line_number=0

  while IFS=: read -r \
    name password last_change min_days max_days warn_days \
    inactive_days expire_day flag extra \
    || [[ -n "$name$password$last_change$min_days$max_days$warn_days$inactive_days$expire_day$flag$extra" ]]; do

    line_number=$((line_number + 1))

    if [[ -z "$name" ]] || [[ -n "$extra" ]]; then
      LHT_ACCOUNTS_SHADOW_STATUS="error"
      LHT_ACCOUNTS_SHADOW_MESSAGE="Malformed /etc/shadow entry at line ${line_number}"
      return 0
    fi

    if [[ -n "${LHT_ACCOUNTS_SHADOW_PASSWORD[$name]+x}" ]]; then
      LHT_ACCOUNTS_SHADOW_STATUS="error"
      LHT_ACCOUNTS_SHADOW_MESSAGE="Duplicate account name '${name}' in /etc/shadow"
      return 0
    fi

    LHT_ACCOUNTS_SHADOW_USERS+=("$name")

    LHT_ACCOUNTS_SHADOW_PASSWORD["$name"]="$password"
    LHT_ACCOUNTS_SHADOW_LAST_CHANGE["$name"]="$last_change"
    LHT_ACCOUNTS_SHADOW_MIN_DAYS["$name"]="$min_days"
    LHT_ACCOUNTS_SHADOW_MAX_DAYS["$name"]="$max_days"
    LHT_ACCOUNTS_SHADOW_WARN_DAYS["$name"]="$warn_days"
  done < /etc/shadow

  LHT_ACCOUNTS_SHADOW_STATUS="ok"
  LHT_ACCOUNTS_SHADOW_MESSAGE="Local shadow database collected successfully"
}

lht_accounts_require_shadow() {
  lht_accounts_collect_shadow

  case "$LHT_ACCOUNTS_SHADOW_STATUS" in
    ok)
      return 0
      ;;

    requires-privilege)
      lht_result \
        "SKIP" \
        "Shadow-backed account checks require elevated read access" \
        "${LHT_ACCOUNTS_SHADOW_MESSAGE}; re-run the account profile with elevated privileges for complete results"

      return 1
      ;;

    error)
      lht_result \
        "ERROR" \
        "Local shadow database is unavailable" \
        "$LHT_ACCOUNTS_SHADOW_MESSAGE"

      return 1
      ;;

    *)
      lht_result \
        "ERROR" \
        "Unexpected shadow collection state" \
        "State: ${LHT_ACCOUNTS_SHADOW_STATUS:-unset}"

      return 1
      ;;
  esac
}

lht_accounts_collect_login_defs() {
  if (( LHT_ACCOUNTS_LOGIN_DEFS_ATTEMPTED == 1 )); then
    return 0
  fi

  LHT_ACCOUNTS_LOGIN_DEFS_ATTEMPTED=1

  LHT_ACCOUNTS_UID_MIN=1000
  LHT_ACCOUNTS_PASS_MAX_DAYS=""
  LHT_ACCOUNTS_PASS_MIN_DAYS=""
  LHT_ACCOUNTS_PASS_WARN_AGE=""

  if [[ ! -r /etc/login.defs ]]; then
    LHT_ACCOUNTS_LOGIN_DEFS_STATUS="unavailable"
    LHT_ACCOUNTS_LOGIN_DEFS_MESSAGE="/etc/login.defs is not readable; UID_MIN fallback=1000"
    return 0
  fi

  local raw_line=""
  local line=""
  local key=""
  local value=""
  local uid_min_seen=0

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="$(lht_trim "$raw_line")"

    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    key="${line%%[[:space:]]*}"

    if [[ "$key" == "$line" ]]; then
      continue
    fi

    value="${line#"$key"}"
    value="$(lht_trim "$value")"

    case "$key" in
      UID_MIN)
        if [[ "$value" =~ ^[0-9]+$ ]]; then
          LHT_ACCOUNTS_UID_MIN="$value"
          uid_min_seen=1
        else
          LHT_ACCOUNTS_LOGIN_DEFS_STATUS="invalid"
          LHT_ACCOUNTS_LOGIN_DEFS_MESSAGE="Invalid UID_MIN value in /etc/login.defs: ${value}"
          return 0
        fi
        ;;

      PASS_MAX_DAYS)
        LHT_ACCOUNTS_PASS_MAX_DAYS="$value"
        ;;

      PASS_MIN_DAYS)
        LHT_ACCOUNTS_PASS_MIN_DAYS="$value"
        ;;

      PASS_WARN_AGE)
        LHT_ACCOUNTS_PASS_WARN_AGE="$value"
        ;;
    esac
  done < /etc/login.defs

  if (( uid_min_seen == 0 )); then
    LHT_ACCOUNTS_LOGIN_DEFS_STATUS="partial"
    LHT_ACCOUNTS_LOGIN_DEFS_MESSAGE="UID_MIN is not defined; fallback=1000"
  else
    LHT_ACCOUNTS_LOGIN_DEFS_STATUS="ok"
    LHT_ACCOUNTS_LOGIN_DEFS_MESSAGE="login.defs defaults collected successfully"
  fi
}

lht_accounts_shell_is_interactive() {
  local shell="${1-}"

  case "$shell" in
    */nologin|*/false|/bin/sync|/sbin/shutdown|/sbin/halt)
      return 1
      ;;

    *)
      return 0
      ;;
  esac
}

lht_check_accounts_local_database() {
  lht_accounts_collect_passwd

  if [[ "$LHT_ACCOUNTS_PASSWD_STATUS" == "ok" ]]; then
    lht_result \
      "PASS" \
      "Local account database is readable and parseable" \
      "/etc/passwd contains ${#LHT_ACCOUNTS_PASSWD_USERS[@]} account(s)"
  else
    lht_result \
      "ERROR" \
      "Local account database cannot be evaluated" \
      "$LHT_ACCOUNTS_PASSWD_MESSAGE"
  fi
}

lht_check_accounts_login_defs_defaults() {
  lht_accounts_collect_login_defs

  local max_days="${LHT_ACCOUNTS_PASS_MAX_DAYS:-unset}"
  local min_days="${LHT_ACCOUNTS_PASS_MIN_DAYS:-unset}"
  local warn_age="${LHT_ACCOUNTS_PASS_WARN_AGE:-unset}"

  local details="UID_MIN=${LHT_ACCOUNTS_UID_MIN}; PASS_MAX_DAYS=${max_days}; PASS_MIN_DAYS=${min_days}; PASS_WARN_AGE=${warn_age}. PASS_* values are account-creation defaults, not proof of current per-user enforcement."

  case "$LHT_ACCOUNTS_LOGIN_DEFS_STATUS" in
    ok)
      lht_result \
        "PASS" \
        "Local account defaults are readable" \
        "$details"
      ;;

    partial|unavailable)
      lht_result \
        "WARN" \
        "Local account defaults are only partially available" \
        "${LHT_ACCOUNTS_LOGIN_DEFS_MESSAGE}; ${details}"
      ;;

    invalid)
      lht_result \
        "FAIL" \
        "Local account defaults contain an invalid value" \
        "$LHT_ACCOUNTS_LOGIN_DEFS_MESSAGE"
      ;;

    *)
      lht_result \
        "ERROR" \
        "Unexpected login.defs collection state" \
        "State: ${LHT_ACCOUNTS_LOGIN_DEFS_STATUS:-unset}"
      ;;
  esac
}

lht_check_accounts_uid0_exclusive() {
  if ! lht_accounts_require_passwd; then
    return 0
  fi

  local user=""
  local uid0_users=""
  local root_uid="${LHT_ACCOUNTS_PASSWD_UID[root]-missing}"

  for user in "${LHT_ACCOUNTS_PASSWD_USERS[@]}"; do
    if [[ "${LHT_ACCOUNTS_PASSWD_UID[$user]}" == "0" ]]; then
      uid0_users="$(
        lht_accounts_append_detail \
          "$uid0_users" \
          "$user"
      )"
    fi
  done

  if [[ "$root_uid" != "0" ]]; then
    lht_result \
      "FAIL" \
      "The root account does not own UID 0" \
      "root UID=${root_uid}; UID 0 account(s): ${uid0_users:-none}"

  elif [[ "$uid0_users" != "root" ]]; then
    lht_result \
      "FAIL" \
      "Additional accounts have UID 0" \
      "UID 0 account(s): ${uid0_users}"

  else
    lht_result \
      "PASS" \
      "UID 0 is assigned exclusively to root" \
      "root:uid=0"
  fi
}

lht_check_accounts_duplicate_uids() {
  if ! lht_accounts_require_passwd; then
    return 0
  fi

  local user=""
  local uid=""
  local users_for_uid=""
  local duplicates=""

  declare -A reported_uids=()

  for user in "${LHT_ACCOUNTS_PASSWD_USERS[@]}"; do
    uid="${LHT_ACCOUNTS_PASSWD_UID[$user]}"
    users_for_uid="${LHT_ACCOUNTS_UID_USERS[$uid]}"

    [[ "$users_for_uid" == *,* ]] || continue
    [[ -z "${reported_uids[$uid]+x}" ]] || continue

    reported_uids["$uid"]=1

    duplicates="$(
      lht_accounts_append_detail \
        "$duplicates" \
        "uid=${uid} users=${users_for_uid}"
    )"
  done

  if [[ -n "$duplicates" ]]; then
    lht_result \
      "FAIL" \
      "Duplicate local UIDs were detected" \
      "$duplicates"
  else
    lht_result \
      "PASS" \
      "Local account UIDs are unique" \
      "No duplicate numeric UIDs detected in /etc/passwd"
  fi
}

lht_check_accounts_passwd_shadowing() {
  if ! lht_accounts_require_passwd; then
    return 0
  fi

  local user=""
  local field=""
  local empty_fields=""
  local unexpected_fields=""

  for user in "${LHT_ACCOUNTS_PASSWD_USERS[@]}"; do
    field="${LHT_ACCOUNTS_PASSWD_PASSWORD[$user]}"

    case "$field" in
      x|X)
        ;;

      "")
        empty_fields="$(
          lht_accounts_append_detail \
            "$empty_fields" \
            "$user"
        )"
        ;;

      !*|\**)
        ;;

      *)
        unexpected_fields="$(
          lht_accounts_append_detail \
            "$unexpected_fields" \
            "$user"
        )"
        ;;
    esac
  done

  if [[ -n "$empty_fields" ]] || [[ -n "$unexpected_fields" ]]; then
    local details=""

    if [[ -n "$empty_fields" ]]; then
      details="empty passwd field: ${empty_fields}"
    fi

    if [[ -n "$unexpected_fields" ]]; then
      details="$(
        lht_accounts_append_detail \
          "$details" \
          "non-shadowed or unexpected passwd field: ${unexpected_fields}"
      )"
    fi

    lht_result \
      "FAIL" \
      "Unsafe password fields were found in /etc/passwd" \
      "$details"
  else
    lht_result \
      "PASS" \
      "Local password hashes are not stored in /etc/passwd" \
      "All password fields use the shadow marker or an account-lock marker"
  fi
}

lht_check_accounts_system_shells() {
  if ! lht_accounts_require_passwd; then
    return 0
  fi

  lht_accounts_collect_login_defs

  local user=""
  local uid=""
  local shell=""
  local findings=""

  for user in "${LHT_ACCOUNTS_PASSWD_USERS[@]}"; do
    [[ "$user" == "root" ]] && continue

    uid="${LHT_ACCOUNTS_PASSWD_UID[$user]}"
    shell="${LHT_ACCOUNTS_PASSWD_SHELL[$user]}"

    if (( uid < LHT_ACCOUNTS_UID_MIN )) \
      && lht_accounts_shell_is_interactive "$shell"; then

      findings="$(
        lht_accounts_append_detail \
          "$findings" \
          "${user}(uid=${uid},shell=${shell:-<empty>})"
      )"
    fi
  done

  if [[ -n "$findings" ]]; then
    lht_result \
      "WARN" \
      "System accounts with potentially interactive shells were found" \
      "UID_MIN=${LHT_ACCOUNTS_UID_MIN}; review: ${findings}"
  else
    lht_result \
      "PASS" \
      "System accounts do not expose interactive login shells" \
      "Checked local accounts with UID < ${LHT_ACCOUNTS_UID_MIN}, excluding root"
  fi
}

lht_check_accounts_shadow_access() {
  lht_accounts_collect_shadow

  case "$LHT_ACCOUNTS_SHADOW_STATUS" in
    ok)
      lht_result \
        "PASS" \
        "Shadow account data is available for audit" \
        "/etc/shadow contains ${#LHT_ACCOUNTS_SHADOW_USERS[@]} account(s) visible to the current process"
      ;;

    requires-privilege)
      lht_result \
        "SKIP" \
        "Shadow account data requires elevated read access" \
        "${LHT_ACCOUNTS_SHADOW_MESSAGE}; the toolkit does not invoke sudo automatically"
      ;;

    error)
      lht_result \
        "ERROR" \
        "Shadow account data cannot be evaluated" \
        "$LHT_ACCOUNTS_SHADOW_MESSAGE"
      ;;

    *)
      lht_result \
        "ERROR" \
        "Unexpected shadow collection state" \
        "State: ${LHT_ACCOUNTS_SHADOW_STATUS:-unset}"
      ;;
  esac
}

lht_check_accounts_empty_passwords() {
  if ! lht_accounts_require_shadow; then
    return 0
  fi

  local user=""
  local empty_passwords=""

  for user in "${LHT_ACCOUNTS_SHADOW_USERS[@]}"; do
    if [[ -z "${LHT_ACCOUNTS_SHADOW_PASSWORD[$user]}" ]]; then
      empty_passwords="$(
        lht_accounts_append_detail \
          "$empty_passwords" \
          "$user"
      )"
    fi
  done

  if [[ -n "$empty_passwords" ]]; then
    lht_result \
      "FAIL" \
      "Accounts with empty shadow password fields were detected" \
      "Accounts: ${empty_passwords}"
  else
    lht_result \
      "PASS" \
      "No empty shadow password fields were detected" \
      "Checked ${#LHT_ACCOUNTS_SHADOW_USERS[@]} local shadow account(s)"
  fi
}

lht_check_accounts_password_aging_consistency() {
  if ! lht_accounts_require_shadow; then
    return 0
  fi

  local user=""
  local min_days=""
  local max_days=""
  local warn_days=""
  local findings=""

  for user in "${LHT_ACCOUNTS_SHADOW_USERS[@]}"; do
    min_days="${LHT_ACCOUNTS_SHADOW_MIN_DAYS[$user]}"
    max_days="${LHT_ACCOUNTS_SHADOW_MAX_DAYS[$user]}"
    warn_days="${LHT_ACCOUNTS_SHADOW_WARN_DAYS[$user]}"

    if [[ -n "$min_days" ]] \
      && [[ ! "$min_days" =~ ^-?[0-9]+$ ]]; then

      findings="$(
        lht_accounts_append_detail \
          "$findings" \
          "${user}: invalid min=${min_days}"
      )"

      continue
    fi

    if [[ -n "$max_days" ]] \
      && [[ ! "$max_days" =~ ^-?[0-9]+$ ]]; then

      findings="$(
        lht_accounts_append_detail \
          "$findings" \
          "${user}: invalid max=${max_days}"
      )"

      continue
    fi

    if [[ -n "$warn_days" ]] \
      && [[ ! "$warn_days" =~ ^-?[0-9]+$ ]]; then

      findings="$(
        lht_accounts_append_detail \
          "$findings" \
          "${user}: invalid warn=${warn_days}"
      )"

      continue
    fi

    if [[ -n "$min_days" ]] \
      && [[ -n "$max_days" ]] \
      && (( min_days >= 0 && max_days >= 0 && min_days > max_days )); then

      findings="$(
        lht_accounts_append_detail \
          "$findings" \
          "${user}: min=${min_days}>max=${max_days}"
      )"
    fi

    if [[ -n "$warn_days" ]] \
      && [[ -n "$max_days" ]] \
      && (( warn_days >= 0 && max_days >= 0 && warn_days > max_days )); then

      findings="$(
        lht_accounts_append_detail \
          "$findings" \
          "${user}: warn=${warn_days}>max=${max_days}"
      )"
    fi
  done

  if [[ -n "$findings" ]]; then
    lht_result \
      "FAIL" \
      "Inconsistent password-aging metadata was detected" \
      "$findings"
  else
    lht_result \
      "PASS" \
      "Password-aging metadata is internally consistent" \
      "No invalid min/max/warning relationships detected in /etc/shadow"
  fi
}

lht_check_accounts_password_change_dates() {
  if ! lht_accounts_require_shadow; then
    return 0
  fi

  local today_days=$(( $(date -u +%s) / 86400 ))
  local user=""
  local last_change=""
  local findings=""

  for user in "${LHT_ACCOUNTS_SHADOW_USERS[@]}"; do
    last_change="${LHT_ACCOUNTS_SHADOW_LAST_CHANGE[$user]}"

    [[ -n "$last_change" ]] || continue

    if [[ ! "$last_change" =~ ^-?[0-9]+$ ]]; then
      findings="$(
        lht_accounts_append_detail \
          "$findings" \
          "${user}: invalid last-change=${last_change}"
      )"

      continue
    fi

    if (( last_change > today_days )); then
      findings="$(
        lht_accounts_append_detail \
          "$findings" \
          "${user}: last-change-day=${last_change} today=${today_days}"
      )"
    fi
  done

  if [[ -n "$findings" ]]; then
    lht_result \
      "FAIL" \
      "Invalid future password-change dates were detected" \
      "$findings"
  else
    lht_result \
      "PASS" \
      "Password-change dates are plausible" \
      "No local shadow account has a last password change date in the future"
  fi
}

lht_register_check \
  "accounts.local-database" \
  "accounts" \
  "Local account database readable and parseable" \
  "high" \
  "lht_check_accounts_local_database"

lht_register_check \
  "accounts.login-defs-defaults" \
  "accounts" \
  "Local account creation defaults visible" \
  "info" \
  "lht_check_accounts_login_defs_defaults"

lht_register_check \
  "accounts.uid0-exclusive" \
  "accounts" \
  "UID 0 assigned exclusively to root" \
  "critical" \
  "lht_check_accounts_uid0_exclusive"

lht_register_check \
  "accounts.duplicate-uids" \
  "accounts" \
  "Local numeric UIDs are unique" \
  "high" \
  "lht_check_accounts_duplicate_uids"

lht_register_check \
  "accounts.passwd-shadowing" \
  "accounts" \
  "Password hashes not stored in /etc/passwd" \
  "critical" \
  "lht_check_accounts_passwd_shadowing"

lht_register_check \
  "accounts.system-shells" \
  "accounts" \
  "System account login shells reviewed" \
  "medium" \
  "lht_check_accounts_system_shells"

lht_register_check \
  "accounts.shadow-access" \
  "accounts" \
  "Shadow data available for privileged audit" \
  "info" \
  "lht_check_accounts_shadow_access"

lht_register_check \
  "accounts.empty-passwords" \
  "accounts" \
  "No empty local password fields" \
  "critical" \
  "lht_check_accounts_empty_passwords"

lht_register_check \
  "accounts.password-aging-consistency" \
  "accounts" \
  "Password-aging metadata internally consistent" \
  "medium" \
  "lht_check_accounts_password_aging_consistency"

lht_register_check \
  "accounts.password-change-dates" \
  "accounts" \
  "Password-change dates are plausible" \
  "medium" \
  "lht_check_accounts_password_change_dates"
