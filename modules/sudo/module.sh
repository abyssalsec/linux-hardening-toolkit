#!/usr/bin/env bash

LHT_SUDO_COLLECTION_ATTEMPTED=0
LHT_SUDO_STATUS=""
LHT_SUDO_MESSAGE=""
LHT_SUDO_BINARY=""
LHT_VISUDO_BINARY=""

LHT_SUDOERS_FILE="/etc/sudoers"
LHT_SUDOERS_DIR="/etc/sudoers.d"

declare -ag LHT_SUDO_INCLUDE_FILES=()

lht_sudo_find_binary() {
  local command_name="${1:?command name is required}"
  shift

  local candidate=""

  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
    return 0
  fi

  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

lht_sudo_collect_runtime() {
  if (( LHT_SUDO_COLLECTION_ATTEMPTED == 1 )); then
    return 0
  fi

  LHT_SUDO_COLLECTION_ATTEMPTED=1
  LHT_SUDO_STATUS=""
  LHT_SUDO_MESSAGE=""
  LHT_SUDO_BINARY=""
  LHT_VISUDO_BINARY=""
  LHT_SUDO_INCLUDE_FILES=()

  LHT_SUDO_BINARY="$(
    lht_sudo_find_binary \
      sudo \
      /usr/bin/sudo \
      /bin/sudo \
      || true
  )"

  LHT_VISUDO_BINARY="$(
    lht_sudo_find_binary \
      visudo \
      /usr/sbin/visudo \
      /sbin/visudo \
      || true
  )"

  if [[ -z "$LHT_SUDO_BINARY" ]] \
    && [[ -z "$LHT_VISUDO_BINARY" ]]; then

    LHT_SUDO_STATUS="not-installed"
    LHT_SUDO_MESSAGE="sudo and visudo executables were not found"
    return 0
  fi

  if [[ -z "$LHT_VISUDO_BINARY" ]]; then
    LHT_SUDO_STATUS="partial"
    LHT_SUDO_MESSAGE="sudo is installed but visudo was not found"
    return 0
  fi

  if [[ -d "$LHT_SUDOERS_DIR" ]] \
    && [[ -r "$LHT_SUDOERS_DIR" ]] \
    && [[ -x "$LHT_SUDOERS_DIR" ]]; then

    local path=""

    while IFS= read -r -d '' path; do
      LHT_SUDO_INCLUDE_FILES+=("$path")
    done < <(
      find "$LHT_SUDOERS_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type f \
        -print0 \
        2>/dev/null
    )
  fi

  LHT_SUDO_STATUS="ok"
  LHT_SUDO_MESSAGE="sudo runtime collected successfully"
}

lht_sudo_require_runtime() {
  lht_sudo_collect_runtime

  case "$LHT_SUDO_STATUS" in
    ok)
      return 0
      ;;

    not-installed)
      lht_result \
        "SKIP" \
        "sudo is not installed" \
        "$LHT_SUDO_MESSAGE"
      return 1
      ;;

    partial)
      lht_result \
        "SKIP" \
        "sudo configuration validator is unavailable" \
        "$LHT_SUDO_MESSAGE"
      return 1
      ;;

    *)
      lht_result \
        "ERROR" \
        "Unexpected sudo runtime state" \
        "State: ${LHT_SUDO_STATUS:-unset}"
      return 1
      ;;
  esac
}

lht_sudo_stat() {
  local format="${1:?format is required}"
  local path="${2:?path is required}"

  stat -Lc "$format" "$path" 2>/dev/null
}

lht_sudo_mode_has_group_write() {
  local mode="${1:?mode is required}"

  local group_digit="${mode: -2:1}"

  (( (10#$group_digit & 2) != 0 ))
}

lht_sudo_mode_has_other_write() {
  local mode="${1:?mode is required}"

  local other_digit="${mode: -1}"

  (( (10#$other_digit & 2) != 0 ))
}

lht_sudo_mode_is_dangerously_writable() {
  local mode="${1:?mode is required}"

  if lht_sudo_mode_has_group_write "$mode"; then
    return 0
  fi

  if lht_sudo_mode_has_other_write "$mode"; then
    return 0
  fi

  return 1
}

lht_sudo_append_detail() {
  local current="${1-}"
  local item="${2-}"

  if [[ -z "$current" ]]; then
    printf '%s' "$item"
  else
    printf '%s; %s' "$current" "$item"
  fi
}

lht_check_sudo_available() {
  lht_sudo_collect_runtime

  case "$LHT_SUDO_STATUS" in
    ok)
      lht_result \
        "PASS" \
        "sudo and visudo are available" \
        "sudo=${LHT_SUDO_BINARY:-not-found}; visudo=${LHT_VISUDO_BINARY}"
      ;;

    partial)
      lht_result \
        "WARN" \
        "sudo installation is incomplete for policy auditing" \
        "$LHT_SUDO_MESSAGE"
      ;;

    not-installed)
      lht_result \
        "SKIP" \
        "sudo is not installed" \
        "$LHT_SUDO_MESSAGE"
      ;;

    *)
      lht_result \
        "ERROR" \
        "Unexpected sudo runtime state" \
        "State: ${LHT_SUDO_STATUS:-unset}"
      ;;
  esac
}

lht_check_sudo_config_validation() {
  if ! lht_sudo_require_runtime; then
    return 0
  fi

  local output=""
  local rc=0
  local first_line=""

  if output="$(
    LC_ALL=C \
      "$LHT_VISUDO_BINARY" \
      -c \
      2>&1
  )"; then

    lht_result \
      "PASS" \
      "sudo policy passes native validation" \
      "${LHT_VISUDO_BINARY} -c completed successfully"

    return 0
  fi

  rc=$?
  first_line="${output%%$'\n'*}"

  [[ -n "$first_line" ]] \
    || first_line="no diagnostic output"

  if (( EUID != 0 )) \
    && [[ "$output" == *"Permission denied"* ]]; then

    lht_result \
      "SKIP" \
      "sudo policy validation requires elevated read access" \
      "${first_line}; re-run the sudo profile with elevated privileges"

    return 0
  fi

  lht_result \
    "FAIL" \
    "sudo policy failed native validation" \
    "visudo exit=${rc}; ${first_line}"
}

lht_check_sudo_main_owner() {
  if [[ ! -e "$LHT_SUDOERS_FILE" ]]; then
    lht_result \
      "SKIP" \
      "Main sudoers file does not exist" \
      "$LHT_SUDOERS_FILE was not found"
    return 0
  fi

  local uid=""
  local gid=""

  if ! uid="$(lht_sudo_stat '%u' "$LHT_SUDOERS_FILE")" \
    || ! gid="$(lht_sudo_stat '%g' "$LHT_SUDOERS_FILE")"; then

    lht_result \
      "ERROR" \
      "Unable to inspect sudoers ownership" \
      "stat failed for ${LHT_SUDOERS_FILE}"
    return 0
  fi

  if [[ "$uid" == "0" ]]; then
    lht_result \
      "PASS" \
      "Main sudoers file is owned by root" \
      "${LHT_SUDOERS_FILE}: uid=${uid} gid=${gid}"
  else
    lht_result \
      "FAIL" \
      "Main sudoers file is not owned by root" \
      "${LHT_SUDOERS_FILE}: uid=${uid} gid=${gid}"
  fi
}

lht_check_sudo_main_permissions() {
  if [[ ! -e "$LHT_SUDOERS_FILE" ]]; then
    lht_result \
      "SKIP" \
      "Main sudoers file does not exist" \
      "$LHT_SUDOERS_FILE was not found"
    return 0
  fi

  local mode=""

  if ! mode="$(lht_sudo_stat '%a' "$LHT_SUDOERS_FILE")"; then
    lht_result \
      "ERROR" \
      "Unable to inspect sudoers permissions" \
      "stat failed for ${LHT_SUDOERS_FILE}"
    return 0
  fi

  if lht_sudo_mode_is_dangerously_writable "$mode"; then
    lht_result \
      "FAIL" \
      "Main sudoers file has unsafe write permissions" \
      "${LHT_SUDOERS_FILE}: mode=${mode}"
  else
    lht_result \
      "PASS" \
      "Main sudoers file is protected from non-owner modification" \
      "${LHT_SUDOERS_FILE}: mode=${mode}"
  fi
}

lht_check_sudo_includes_integrity() {
  lht_sudo_collect_runtime

  if [[ ! -d "$LHT_SUDOERS_DIR" ]]; then
    lht_result \
      "SKIP" \
      "sudoers include directory is not present" \
      "$LHT_SUDOERS_DIR was not found"
    return 0
  fi

  if [[ ! -r "$LHT_SUDOERS_DIR" ]] \
    || [[ ! -x "$LHT_SUDOERS_DIR" ]]; then

    if (( EUID != 0 )); then
      lht_result \
        "SKIP" \
        "sudoers include directory requires elevated access" \
        "$LHT_SUDOERS_DIR cannot be inspected by the current user"
    else
      lht_result \
        "ERROR" \
        "sudoers include directory cannot be inspected" \
        "$LHT_SUDOERS_DIR is inaccessible to root"
    fi

    return 0
  fi

  local path=""
  local uid=""
  local mode=""
  local findings=""

  for path in "${LHT_SUDO_INCLUDE_FILES[@]}"; do
    uid="$(lht_sudo_stat '%u' "$path" || true)"
    mode="$(lht_sudo_stat '%a' "$path" || true)"

    if [[ -z "$uid" ]] || [[ -z "$mode" ]]; then
      findings="$(
        lht_sudo_append_detail \
          "$findings" \
          "${path}: unable-to-stat"
      )"

      continue
    fi

    if [[ "$uid" != "0" ]]; then
      findings="$(
        lht_sudo_append_detail \
          "$findings" \
          "${path}: owner-uid=${uid}"
      )"
    fi

    if lht_sudo_mode_is_dangerously_writable "$mode"; then
      findings="$(
        lht_sudo_append_detail \
          "$findings" \
          "${path}: mode=${mode}"
      )"
    fi
  done

  if [[ -n "$findings" ]]; then
    lht_result \
      "FAIL" \
      "Unsafe sudoers include files were detected" \
      "$findings"
  else
    lht_result \
      "PASS" \
      "sudoers include files have protected ownership and write permissions" \
      "Inspected ${#LHT_SUDO_INCLUDE_FILES[@]} regular file(s) in ${LHT_SUDOERS_DIR}"
  fi
}

lht_check_sudo_include_filenames() {
  if [[ ! -d "$LHT_SUDOERS_DIR" ]]; then
    lht_result \
      "SKIP" \
      "sudoers include directory is not present" \
      "$LHT_SUDOERS_DIR was not found"
    return 0
  fi

  if [[ ! -r "$LHT_SUDOERS_DIR" ]] \
    || [[ ! -x "$LHT_SUDOERS_DIR" ]]; then

    lht_result \
      "SKIP" \
      "sudoers include filenames cannot be inspected" \
      "$LHT_SUDOERS_DIR is inaccessible to the current user"

    return 0
  fi

  local path=""
  local filename=""
  local findings=""

  while IFS= read -r -d '' path; do
    filename="${path##*/}"

    if [[ "$filename" == *"."* ]] \
      || [[ "$filename" == *"~" ]]; then

      findings="$(
        lht_sudo_append_detail \
          "$findings" \
          "$filename"
      )"
    fi
  done < <(
    find "$LHT_SUDOERS_DIR" \
      -mindepth 1 \
      -maxdepth 1 \
      -type f \
      -print0 \
      2>/dev/null
  )

  if [[ -n "$findings" ]]; then
    lht_result \
      "WARN" \
      "Potentially ignored sudoers include filenames were found" \
      "Review files containing '.' or ending in '~': ${findings}"
  else
    lht_result \
      "PASS" \
      "sudoers include filenames are compatible with includedir processing" \
      "No regular filenames containing '.' or ending in '~' were detected"
  fi
}

lht_check_sudo_config_writability() {
  local findings=""

  if [[ -e "$LHT_SUDOERS_FILE" ]]; then
    local main_uid=""
    local main_mode=""

    main_uid="$(lht_sudo_stat '%u' "$LHT_SUDOERS_FILE" || true)"
    main_mode="$(lht_sudo_stat '%a' "$LHT_SUDOERS_FILE" || true)"

    if [[ "$main_uid" != "0" ]]; then
      findings="$(
        lht_sudo_append_detail \
          "$findings" \
          "${LHT_SUDOERS_FILE}: owner=${main_uid:-unknown}"
      )"
    fi

    if [[ -n "$main_mode" ]] \
      && lht_sudo_mode_is_dangerously_writable "$main_mode"; then

      findings="$(
        lht_sudo_append_detail \
          "$findings" \
          "${LHT_SUDOERS_FILE}: mode=${main_mode}"
      )"
    fi
  fi

  if [[ -d "$LHT_SUDOERS_DIR" ]]; then
    local dir_uid=""
    local dir_mode=""

    dir_uid="$(lht_sudo_stat '%u' "$LHT_SUDOERS_DIR" || true)"
    dir_mode="$(lht_sudo_stat '%a' "$LHT_SUDOERS_DIR" || true)"

    if [[ "$dir_uid" != "0" ]]; then
      findings="$(
        lht_sudo_append_detail \
          "$findings" \
          "${LHT_SUDOERS_DIR}: owner=${dir_uid:-unknown}"
      )"
    fi

    if [[ -n "$dir_mode" ]] \
      && lht_sudo_mode_is_dangerously_writable "$dir_mode"; then

      findings="$(
        lht_sudo_append_detail \
          "$findings" \
          "${LHT_SUDOERS_DIR}: mode=${dir_mode}"
      )"
    fi
  fi

  if [[ -n "$findings" ]]; then
    lht_result \
      "FAIL" \
      "sudo policy paths expose unsafe modification permissions" \
      "$findings"
  else
    lht_result \
      "PASS" \
      "sudo policy paths are protected from unsafe modification" \
      "Main sudoers file and include directory ownership/write permissions are protected"
  fi
}

lht_register_check \
  "sudo.available" \
  "sudo" \
  "sudo policy tooling available" \
  "info" \
  "lht_check_sudo_available"

lht_register_check \
  "sudo.config-validation" \
  "sudo" \
  "sudo policy passes native validation" \
  "critical" \
  "lht_check_sudo_config_validation"

lht_register_check \
  "sudo.main-owner" \
  "sudo" \
  "Main sudoers file owned by root" \
  "critical" \
  "lht_check_sudo_main_owner"

lht_register_check \
  "sudo.main-permissions" \
  "sudo" \
  "Main sudoers file protected from unsafe writes" \
  "critical" \
  "lht_check_sudo_main_permissions"

lht_register_check \
  "sudo.includes-integrity" \
  "sudo" \
  "sudoers include files protected" \
  "critical" \
  "lht_check_sudo_includes_integrity"

lht_register_check \
  "sudo.includes-filenames" \
  "sudo" \
  "sudoers include filenames reviewed" \
  "medium" \
  "lht_check_sudo_include_filenames"

lht_register_check \
  "sudo.config-writability" \
  "sudo" \
  "sudo policy paths protected from modification" \
  "critical" \
  "lht_check_sudo_config_writability"
