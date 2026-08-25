#!/usr/bin/env bash

LHT_RESULT_STATUS=""
LHT_RESULT_SUMMARY=""
LHT_RESULT_DETAILS=""

lht_reset_result() {
  LHT_RESULT_STATUS=""
  LHT_RESULT_SUMMARY=""
  LHT_RESULT_DETAILS=""
}

lht_result() {
  local status="${1:?result status is required}"
  local summary="${2:?result summary is required}"
  local details="${3:-}"

  status="${status^^}"

  case "$status" in
    PASS|FAIL|WARN|SKIP|ERROR)
      ;;
    *)
      lht_die "Invalid check result status: ${status}"
      ;;
  esac

  LHT_RESULT_STATUS="$status"
  LHT_RESULT_SUMMARY="$summary"
  LHT_RESULT_DETAILS="$details"
}

lht_print_audit_header() {
  printf '\n'
  printf 'Linux Hardening Toolkit v%s\n' "$LHT_VERSION"
  printf 'Profile: %s\n' "$LHT_PROFILE_DISPLAY_NAME"
  printf 'Mode: audit (read-only)\n'

  if [[ "${LHT_DRY_RUN:-0}" == "1" ]]; then
    printf 'Dry-run: enabled\n'
  fi

  if [[ -n "$LHT_PROFILE_DESCRIPTION" ]]; then
    printf 'Description: %s\n' "$LHT_PROFILE_DESCRIPTION"
  fi

  printf '\n'
}

lht_run_audit() {
  local pass_count=0
  local fail_count=0
  local warn_count=0
  local skip_count=0
  local error_count=0

  local check_id=""
  local audit_function=""
  local check_rc=0

  lht_print_audit_header

  for check_id in "${LHT_ENABLED_CHECKS[@]}"; do
    audit_function="${LHT_CHECK_AUDIT_FN[$check_id]}"

    lht_reset_result

    if "$audit_function"; then
      check_rc=0
    else
      check_rc=$?
    fi

    if (( check_rc != 0 )); then
      lht_result \
        "ERROR" \
        "Check execution failed" \
        "Function '${audit_function}' returned exit code ${check_rc}"
    elif [[ -z "$LHT_RESULT_STATUS" ]]; then
      lht_result \
        "ERROR" \
        "Check returned no result" \
        "Function '${audit_function}' did not call lht_result"
    fi

    case "$LHT_RESULT_STATUS" in
      PASS)
        pass_count=$((pass_count + 1))
        ;;
      FAIL)
        fail_count=$((fail_count + 1))
        ;;
      WARN)
        warn_count=$((warn_count + 1))
        ;;
      SKIP)
        skip_count=$((skip_count + 1))
        ;;
      ERROR)
        error_count=$((error_count + 1))
        ;;
    esac

    lht_print_status \
      "$LHT_RESULT_STATUS" \
      "$check_id" \
      "$LHT_RESULT_SUMMARY"

    if [[ -n "$LHT_RESULT_DETAILS" ]]; then
      if [[ "${LHT_VERBOSE:-0}" == "1" ]] \
        || [[ "$LHT_RESULT_STATUS" != "PASS" ]]; then
        lht_print_detail "$LHT_RESULT_DETAILS"
      fi
    fi
  done

  printf '\n'
  printf 'Summary: PASS=%d FAIL=%d WARN=%d SKIP=%d ERROR=%d\n' \
    "$pass_count" \
    "$fail_count" \
    "$warn_count" \
    "$skip_count" \
    "$error_count"

  if (( error_count > 0 )); then
    return 1
  fi

  if (( fail_count > 0 )); then
    return 2
  fi

  return 0
}

lht_print_check_catalog() {
  local check_id=""
  local enabled=""
  local remediation=""

  printf '\n'
  printf '%-28s %-12s %-9s %-8s %-11s %s\n' \
    "CHECK ID" \
    "CATEGORY" \
    "SEVERITY" \
    "ENABLED" \
    "REMEDIATION" \
    "TITLE"

  printf '%-28s %-12s %-9s %-8s %-11s %s\n' \
    "----------------------------" \
    "------------" \
    "---------" \
    "--------" \
    "-----------" \
    "-----"

  for check_id in "${LHT_CHECK_IDS[@]}"; do
    enabled="no"
    remediation="no"

    if lht_profile_has_check "$check_id"; then
      enabled="yes"
    fi

    if [[ -n "${LHT_CHECK_APPLY_FN[$check_id]}" ]]; then
      remediation="yes"
    fi

    printf '%-28s %-12s %-9s %-8s %-11s %s\n' \
      "$check_id" \
      "${LHT_CHECK_CATEGORY[$check_id]}" \
      "${LHT_CHECK_SEVERITY[$check_id]}" \
      "$enabled" \
      "$remediation" \
      "${LHT_CHECK_TITLE[$check_id]}"
  done

  printf '\n'
}
