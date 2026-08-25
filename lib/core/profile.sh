#!/usr/bin/env bash

LHT_PROFILE_DISPLAY_NAME=""
LHT_PROFILE_DESCRIPTION=""

declare -ag LHT_ENABLED_CHECKS=()

lht_profile_has_check() {
  local wanted_id="${1:?check id is required}"
  local enabled_id=""

  for enabled_id in "${LHT_ENABLED_CHECKS[@]}"; do
    if [[ "$enabled_id" == "$wanted_id" ]]; then
      return 0
    fi
  done

  return 1
}

lht_load_profile() {
  local requested_profile="${1:?profile name is required}"

  if ! lht_is_safe_name "$requested_profile"; then
    lht_die "Invalid profile name: ${requested_profile}"
  fi

  local profile_file="${LHT_PROFILES_DIR}/${requested_profile}.conf"

  if [[ ! -r "$profile_file" ]]; then
    lht_die "Profile not found or not readable: ${profile_file}"
  fi

  local profile_display_name=""
  local profile_description=""
  local enabled_checks_raw=""

  local raw_line=""
  local line=""
  local key=""
  local value=""

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    line="$(lht_trim "$raw_line")"

    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    if [[ "$line" != *=* ]]; then
      lht_die \
        "Invalid profile line in ${profile_file}: ${raw_line}"
    fi

    key="${line%%=*}"
    value="${line#*=}"

    key="$(lht_trim "$key")"
    value="$(lht_trim "$value")"

    case "$key" in
      name)
        profile_display_name="$value"
        ;;
      description)
        profile_description="$value"
        ;;
      enabled_checks)
        enabled_checks_raw="$value"
        ;;
      *)
        lht_die \
          "Unknown profile option '${key}' in ${profile_file}"
        ;;
    esac
  done < "$profile_file"

  if [[ -z "$profile_display_name" ]]; then
    profile_display_name="$requested_profile"
  fi

  if [[ -z "$enabled_checks_raw" ]]; then
    lht_die \
      "Profile '${requested_profile}' does not define enabled_checks"
  fi

  LHT_PROFILE_DISPLAY_NAME="$profile_display_name"
  LHT_PROFILE_DESCRIPTION="$profile_description"
  LHT_ENABLED_CHECKS=()

  local -a raw_check_ids=()
  local check_id=""
  local existing_id=""

  IFS=',' read -r -a raw_check_ids <<< "$enabled_checks_raw"

  for check_id in "${raw_check_ids[@]}"; do
    check_id="$(lht_trim "$check_id")"

    [[ -n "$check_id" ]] || continue

    if ! lht_check_exists "$check_id"; then
      lht_die \
        "Profile '${requested_profile}' references unknown check '${check_id}'"
    fi

    for existing_id in "${LHT_ENABLED_CHECKS[@]}"; do
      if [[ "$existing_id" == "$check_id" ]]; then
        lht_die \
          "Profile '${requested_profile}' contains duplicate check '${check_id}'"
      fi
    done

    LHT_ENABLED_CHECKS+=("$check_id")
  done

  if (( ${#LHT_ENABLED_CHECKS[@]} == 0 )); then
    lht_die \
      "Profile '${requested_profile}' contains no enabled checks"
  fi

  lht_log_debug \
    "Loaded profile '${requested_profile}' with ${#LHT_ENABLED_CHECKS[@]} check(s)"
}
