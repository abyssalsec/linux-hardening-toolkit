#!/usr/bin/env bash

LHT_FILESYSTEM_SCAN_PATHS="${LHT_FILESYSTEM_SCAN_PATHS:-/etc /usr /boot /opt /srv /var/www}"
LHT_FILESYSTEM_PRIVILEGED_PATHS="${LHT_FILESYSTEM_PRIVILEGED_PATHS:-/usr /opt /srv}"
LHT_FILESYSTEM_SSH_DIR="${LHT_FILESYSTEM_SSH_DIR:-/etc/ssh}"

lht_filesystem_append_detail() {
  local current="${1-}"
  local item="${2-}"

  if [[ -z "$current" ]]; then
    printf '%s' "$item"
  else
    printf '%s; %s' "$current" "$item"
  fi
}

lht_filesystem_existing_paths() {
  local raw_paths="${1-}"
  local path=""

  for path in $raw_paths; do
    [[ -e "$path" ]] || continue
    printf '%s\n' "$path"
  done
}

lht_filesystem_mode_decimal() {
  local mode="${1:?mode is required}"

  if [[ ! "$mode" =~ ^[0-7]{3,4}$ ]]; then
    return 1
  fi

  printf '%d' "$((8#$mode))"
}

lht_filesystem_check_sensitive_file() {
  local path="${1:?path is required}"
  local label="${2:?label is required}"
  local allowed_group_regex="${3:?allowed group regex is required}"
  local unsafe_mask="${4:?unsafe mask is required}"
  local missing_status="${5:-FAIL}"

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    lht_result \
      "$missing_status" \
      "${label} is not available" \
      "${path} does not exist"
    return 0
  fi

  if [[ -L "$path" ]]; then
    lht_result \
      "WARN" \
      "${label} is a symbolic link" \
      "${path} requires manual review"
    return 0
  fi

  if [[ ! -f "$path" ]]; then
    lht_result \
      "FAIL" \
      "${label} is not a regular file" \
      "${path}"
    return 0
  fi

  local metadata=""
  local owner=""
  local group=""
  local mode=""
  local mode_decimal=""
  local mask_decimal=""
  local violations=""

  if ! metadata="$(stat -c '%U|%G|%a' -- "$path" 2>/dev/null)"; then
    lht_result \
      "ERROR" \
      "${label} metadata could not be read" \
      "${path}: stat failed"
    return 0
  fi

  IFS='|' read -r owner group mode <<< "$metadata"

  if ! mode_decimal="$(lht_filesystem_mode_decimal "$mode")"; then
    lht_result \
      "ERROR" \
      "${label} has an invalid permission mode" \
      "${path}: mode=${mode}"
    return 0
  fi

  if ! mask_decimal="$(lht_filesystem_mode_decimal "$unsafe_mask")"; then
    lht_result \
      "ERROR" \
      "Filesystem audit has an invalid internal permission mask" \
      "mask=${unsafe_mask}"
    return 0
  fi

  if [[ "$owner" != "root" ]]; then
    violations="$(
      lht_filesystem_append_detail \
        "$violations" \
        "owner=${owner}"
    )"
  fi

  if [[ ! "$group" =~ $allowed_group_regex ]]; then
    violations="$(
      lht_filesystem_append_detail \
        "$violations" \
        "group=${group}"
    )"
  fi

  if (( (mode_decimal & mask_decimal) != 0 )); then
    violations="$(
      lht_filesystem_append_detail \
        "$violations" \
        "mode=${mode}"
    )"
  fi

  if [[ -n "$violations" ]]; then
    lht_result \
      "FAIL" \
      "${label} permissions are insecure" \
      "${path}: ${violations}"
    return 0
  fi

  lht_result \
    "PASS" \
    "${label} ownership and permissions are secure" \
    "${path}: owner=${owner}; group=${group}; mode=${mode}"
}

lht_check_filesystem_passwd_permissions() {
  lht_filesystem_check_sensitive_file \
    "/etc/passwd" \
    "/etc/passwd" \
    '^(root)$' \
    "0133" \
    "FAIL"
}

lht_check_filesystem_shadow_permissions() {
  lht_filesystem_check_sensitive_file \
    "/etc/shadow" \
    "/etc/shadow" \
    '^(root|shadow)$' \
    "0137" \
    "FAIL"
}

lht_check_filesystem_group_permissions() {
  lht_filesystem_check_sensitive_file \
    "/etc/group" \
    "/etc/group" \
    '^(root)$' \
    "0133" \
    "FAIL"
}

lht_check_filesystem_gshadow_permissions() {
  lht_filesystem_check_sensitive_file \
    "/etc/gshadow" \
    "/etc/gshadow" \
    '^(root|shadow)$' \
    "0137" \
    "SKIP"
}

lht_check_filesystem_root_home() {
  local path="/root"

  if [[ ! -d "$path" ]]; then
    lht_result \
      "SKIP" \
      "Root home directory is not available" \
      "${path} does not exist"
    return 0
  fi

  local metadata=""
  local owner=""
  local group=""
  local mode=""
  local mode_decimal=""

  if ! metadata="$(stat -c '%U|%G|%a' -- "$path" 2>/dev/null)"; then
    lht_result \
      "ERROR" \
      "Root home directory metadata could not be read" \
      "${path}: stat failed"
    return 0
  fi

  IFS='|' read -r owner group mode <<< "$metadata"

  if ! mode_decimal="$(lht_filesystem_mode_decimal "$mode")"; then
    lht_result \
      "ERROR" \
      "Root home directory has an invalid permission mode" \
      "${path}: mode=${mode}"
    return 0
  fi

  if [[ "$owner" != "root" ]]; then
    lht_result \
      "FAIL" \
      "Root home directory has an unexpected owner" \
      "${path}: owner=${owner}; group=${group}; mode=${mode}"
    return 0
  fi

  if (( (mode_decimal & 8#0077) != 0 )); then
    lht_result \
      "FAIL" \
      "Root home directory is accessible by non-root users" \
      "${path}: owner=${owner}; group=${group}; mode=${mode}; expected no group/other permissions"
    return 0
  fi

  lht_result \
    "PASS" \
    "Root home directory permissions are restrictive" \
    "${path}: owner=${owner}; group=${group}; mode=${mode}"
}

lht_check_filesystem_ssh_host_keys() {
  local file=""
  local metadata=""
  local owner=""
  local group=""
  local mode=""
  local mode_decimal=""
  local count=0
  local violations=""

  for file in "${LHT_FILESYSTEM_SSH_DIR}"/ssh_host_*_key; do
    [[ -e "$file" || -L "$file" ]] || continue

    count=$((count + 1))

    if [[ -L "$file" ]]; then
      violations="$(
        lht_filesystem_append_detail \
          "$violations" \
          "${file}:symlink"
      )"
      continue
    fi

    if ! metadata="$(stat -c '%U|%G|%a' -- "$file" 2>/dev/null)"; then
      violations="$(
        lht_filesystem_append_detail \
          "$violations" \
          "${file}:stat-failed"
      )"
      continue
    fi

    IFS='|' read -r owner group mode <<< "$metadata"

    if ! mode_decimal="$(lht_filesystem_mode_decimal "$mode")"; then
      violations="$(
        lht_filesystem_append_detail \
          "$violations" \
          "${file}:invalid-mode=${mode}"
      )"
      continue
    fi

    if [[ "$owner" != "root" ]] \
      || (( (mode_decimal & 8#0177) != 0 )); then

      violations="$(
        lht_filesystem_append_detail \
          "$violations" \
          "${file}:owner=${owner},group=${group},mode=${mode}"
      )"
    fi
  done

  if (( count == 0 )); then
    lht_result \
      "SKIP" \
      "SSH private host keys were not found" \
      "No ${LHT_FILESYSTEM_SSH_DIR}/ssh_host_*_key files were detected"
    return 0
  fi

  if [[ -n "$violations" ]]; then
    lht_result \
      "FAIL" \
      "One or more SSH private host keys have insecure metadata" \
      "$violations"
    return 0
  fi

  lht_result \
    "PASS" \
    "SSH private host key permissions are restrictive" \
    "checked=${count}; owner=root; no group/other access"
}

lht_check_filesystem_world_writable_files() {
  local -a roots=()
  local path=""

  while IFS= read -r path; do
    [[ -n "$path" ]] && roots+=("$path")
  done < <(
    lht_filesystem_existing_paths \
      "$LHT_FILESYSTEM_SCAN_PATHS"
  )

  if (( ${#roots[@]} == 0 )); then
    lht_result \
      "SKIP" \
      "World-writable file scan has no applicable paths" \
      "No configured filesystem scan paths exist"
    return 0
  fi

  local output=""
  local count=0
  local sample=""

  if ! output="$(
    find "${roots[@]}" \
      -xdev \
      -type f \
      -perm -0002 \
      -print \
      2>/dev/null
  )"; then
    lht_result \
      "ERROR" \
      "World-writable file scan could not be completed" \
      "find failed while scanning system paths"
    return 0
  fi

  count="$(
    printf '%s\n' "$output" |
      awk 'NF { count++ } END { print count+0 }'
  )"

  if (( count == 0 )); then
    lht_result \
      "PASS" \
      "No world-writable files were found in sensitive system paths" \
      "scanned=$(lht_filesystem_join_paths "${roots[@]}")"
    return 0
  fi

  sample="$(
    printf '%s\n' "$output" |
      head -n 8 |
      paste -sd ',' -
  )"

  lht_result \
    "FAIL" \
    "World-writable files were found in sensitive system paths" \
    "count=${count}; sample=${sample}"
}

lht_filesystem_join_paths() {
  local joined=""
  local path=""

  for path in "$@"; do
    if [[ -z "$joined" ]]; then
      joined="$path"
    else
      joined="${joined},${path}"
    fi
  done

  printf '%s' "$joined"
}

lht_check_filesystem_world_writable_dirs() {
  local -a roots=()
  local path=""

  for path in /tmp /var/tmp; do
    [[ -d "$path" ]] && roots+=("$path")
  done

  while IFS= read -r path; do
    [[ -n "$path" ]] && roots+=("$path")
  done < <(
    lht_filesystem_existing_paths \
      "$LHT_FILESYSTEM_SCAN_PATHS"
  )

  if (( ${#roots[@]} == 0 )); then
    lht_result \
      "SKIP" \
      "World-writable directory scan has no applicable paths" \
      "No configured filesystem scan paths exist"
    return 0
  fi

  local output=""
  local count=0
  local sample=""

  if ! output="$(
    find "${roots[@]}" \
      -xdev \
      -type d \
      -perm -0002 \
      ! -perm -1000 \
      -print \
      2>/dev/null
  )"; then
    lht_result \
      "ERROR" \
      "World-writable directory scan could not be completed" \
      "find failed while scanning system paths"
    return 0
  fi

  count="$(
    printf '%s\n' "$output" |
      awk 'NF { count++ } END { print count+0 }'
  )"

  if (( count == 0 )); then
    lht_result \
      "PASS" \
      "World-writable directories use sticky-bit protection" \
      "No world-writable directory without sticky bit was found"
    return 0
  fi

  sample="$(
    printf '%s\n' "$output" |
      head -n 8 |
      paste -sd ',' -
  )"

  lht_result \
    "FAIL" \
    "World-writable directories without sticky bit were found" \
    "count=${count}; sample=${sample}"
}

lht_check_filesystem_unowned_files() {
  local -a roots=()
  local path=""

  while IFS= read -r path; do
    [[ -n "$path" ]] && roots+=("$path")
  done < <(
    lht_filesystem_existing_paths \
      "$LHT_FILESYSTEM_SCAN_PATHS"
  )

  if (( ${#roots[@]} == 0 )); then
    lht_result \
      "SKIP" \
      "Unowned file scan has no applicable paths" \
      "No configured filesystem scan paths exist"
    return 0
  fi

  local output=""
  local count=0
  local sample=""

  if ! output="$(
    find "${roots[@]}" \
      -xdev \
      \( -nouser -o -nogroup \) \
      -print \
      2>/dev/null
  )"; then
    lht_result \
      "ERROR" \
      "Unowned file scan could not be completed" \
      "find failed while scanning system paths"
    return 0
  fi

  count="$(
    printf '%s\n' "$output" |
      awk 'NF { count++ } END { print count+0 }'
  )"

  if (( count == 0 )); then
    lht_result \
      "PASS" \
      "No unowned files or directories were found in sensitive paths" \
      "All scanned objects resolve to known users and groups"
    return 0
  fi

  sample="$(
    printf '%s\n' "$output" |
      head -n 8 |
      paste -sd ',' -
  )"

  lht_result \
    "FAIL" \
    "Unowned files or directories were found in sensitive paths" \
    "count=${count}; sample=${sample}"
}

lht_check_filesystem_privileged_files() {
  local -a roots=()
  local path=""

  while IFS= read -r path; do
    [[ -n "$path" ]] && roots+=("$path")
  done < <(
    lht_filesystem_existing_paths \
      "$LHT_FILESYSTEM_PRIVILEGED_PATHS"
  )

  if (( ${#roots[@]} == 0 )); then
    lht_result \
      "SKIP" \
      "SUID/SGID executable inventory has no applicable paths" \
      "No configured privileged-file scan paths exist"
    return 0
  fi

  local output=""
  local file=""
  local metadata=""
  local owner=""
  local group=""
  local mode=""
  local count=0
  local unexpected=""
  local sample=""

  if ! output="$(
    find "${roots[@]}" \
      -xdev \
      -type f \
      \( -perm -4000 -o -perm -2000 \) \
      -print \
      2>/dev/null
  )"; then
    lht_result \
      "ERROR" \
      "SUID/SGID executable inventory could not be completed" \
      "find failed while scanning privileged executable paths"
    return 0
  fi

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue

    count=$((count + 1))

    if ! metadata="$(stat -c '%U|%G|%a' -- "$file" 2>/dev/null)"; then
      unexpected="$(
        lht_filesystem_append_detail \
          "$unexpected" \
          "${file}:stat-failed"
      )"
      continue
    fi

    IFS='|' read -r owner group mode <<< "$metadata"

    if [[ "$owner" != "root" ]]; then
      unexpected="$(
        lht_filesystem_append_detail \
          "$unexpected" \
          "${file}:owner=${owner},group=${group},mode=${mode}"
      )"
    fi
  done <<< "$output"

  sample="$(
    printf '%s\n' "$output" |
      head -n 8 |
      paste -sd ',' -
  )"

  if [[ -n "$unexpected" ]]; then
    lht_result \
      "WARN" \
      "Non-root-owned SUID/SGID executables require manual review" \
      "${unexpected}"
    return 0
  fi

  lht_result \
    "PASS" \
    "SUID/SGID executable inventory was collected" \
    "count=${count}; all detected privileged executables are root-owned; sample=${sample:-none}"
}

lht_register_check \
  "filesystem.passwd-permissions" \
  "filesystem" \
  "/etc/passwd permissions secure" \
  "high" \
  "lht_check_filesystem_passwd_permissions"

lht_register_check \
  "filesystem.shadow-permissions" \
  "filesystem" \
  "/etc/shadow permissions secure" \
  "critical" \
  "lht_check_filesystem_shadow_permissions"

lht_register_check \
  "filesystem.group-permissions" \
  "filesystem" \
  "/etc/group permissions secure" \
  "medium" \
  "lht_check_filesystem_group_permissions"

lht_register_check \
  "filesystem.gshadow-permissions" \
  "filesystem" \
  "/etc/gshadow permissions secure" \
  "high" \
  "lht_check_filesystem_gshadow_permissions"

lht_register_check \
  "filesystem.root-home" \
  "filesystem" \
  "Root home directory permissions restrictive" \
  "high" \
  "lht_check_filesystem_root_home"

lht_register_check \
  "filesystem.ssh-host-keys" \
  "filesystem" \
  "SSH private host key permissions restrictive" \
  "critical" \
  "lht_check_filesystem_ssh_host_keys"

lht_register_check \
  "filesystem.world-writable-files" \
  "filesystem" \
  "Sensitive system paths contain no world-writable files" \
  "high" \
  "lht_check_filesystem_world_writable_files"

lht_register_check \
  "filesystem.world-writable-dirs" \
  "filesystem" \
  "World-writable directories use sticky-bit protection" \
  "high" \
  "lht_check_filesystem_world_writable_dirs"

lht_register_check \
  "filesystem.unowned-files" \
  "filesystem" \
  "Sensitive system paths contain no unowned objects" \
  "medium" \
  "lht_check_filesystem_unowned_files"

lht_register_check \
  "filesystem.privileged-files" \
  "filesystem" \
  "SUID/SGID executable inventory reviewed" \
  "medium" \
  "lht_check_filesystem_privileged_files"
