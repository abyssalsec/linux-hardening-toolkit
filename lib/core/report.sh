#!/usr/bin/env bash

declare -ag LHT_AUDIT_RESULT_IDS=()
declare -Ag LHT_AUDIT_RESULT_STATUS=()
declare -Ag LHT_AUDIT_RESULT_SUMMARY=()
declare -Ag LHT_AUDIT_RESULT_DETAILS=()

LHT_AUDIT_PASS_COUNT=0
LHT_AUDIT_FAIL_COUNT=0
LHT_AUDIT_WARN_COUNT=0
LHT_AUDIT_SKIP_COUNT=0
LHT_AUDIT_ERROR_COUNT=0
LHT_AUDIT_EXIT_CODE=0
LHT_AUDIT_GENERATED_AT=""

lht_reset_audit_report() {
  LHT_AUDIT_RESULT_IDS=()
  LHT_AUDIT_RESULT_STATUS=()
  LHT_AUDIT_RESULT_SUMMARY=()
  LHT_AUDIT_RESULT_DETAILS=()

  LHT_AUDIT_PASS_COUNT=0
  LHT_AUDIT_FAIL_COUNT=0
  LHT_AUDIT_WARN_COUNT=0
  LHT_AUDIT_SKIP_COUNT=0
  LHT_AUDIT_ERROR_COUNT=0
  LHT_AUDIT_EXIT_CODE=0
  LHT_AUDIT_GENERATED_AT=""
}

lht_record_audit_result() {
  local check_id="${1:?check id is required}"
  local status="${2:?result status is required}"
  local summary="${3:?result summary is required}"
  local details="${4:-}"

  LHT_AUDIT_RESULT_IDS+=("$check_id")
  LHT_AUDIT_RESULT_STATUS["$check_id"]="$status"
  LHT_AUDIT_RESULT_SUMMARY["$check_id"]="$summary"
  LHT_AUDIT_RESULT_DETAILS["$check_id"]="$details"

  case "$status" in
    PASS)  LHT_AUDIT_PASS_COUNT=$((LHT_AUDIT_PASS_COUNT + 1)) ;;
    FAIL)  LHT_AUDIT_FAIL_COUNT=$((LHT_AUDIT_FAIL_COUNT + 1)) ;;
    WARN)  LHT_AUDIT_WARN_COUNT=$((LHT_AUDIT_WARN_COUNT + 1)) ;;
    SKIP)  LHT_AUDIT_SKIP_COUNT=$((LHT_AUDIT_SKIP_COUNT + 1)) ;;
    ERROR) LHT_AUDIT_ERROR_COUNT=$((LHT_AUDIT_ERROR_COUNT + 1)) ;;
    *)
      lht_die "Invalid audit result status while recording: ${status}"
      ;;
  esac
}

lht_finalize_audit_report() {
  if (( LHT_AUDIT_ERROR_COUNT > 0 )); then
    LHT_AUDIT_EXIT_CODE=1
  elif (( LHT_AUDIT_FAIL_COUNT > 0 )); then
    LHT_AUDIT_EXIT_CODE=2
  else
    LHT_AUDIT_EXIT_CODE=0
  fi
}

lht_json_escape() {
  local value="${1-}"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\b'/\\b}"
  value="${value//$'\f'/\\f}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\a'/\\u0007}"
  value="${value//$'\v'/\\u000b}"
  value="${value//$'\e'/\\u001b}"

  printf '%s' "$value"
}

lht_emit_json_report() {
  local dry_run_json="false"
  local total="${#LHT_AUDIT_RESULT_IDS[@]}"
  local index=0
  local check_id=""
  local remediation_json="false"

  if [[ "${LHT_DRY_RUN:-0}" == "1" ]]; then
    dry_run_json="true"
  fi

  printf '{\n'
  printf '  "schema_version": "1",\n'
  printf '  "tool": {\n'
  printf '    "name": "%s",\n' \
    "$(lht_json_escape 'Linux Hardening Toolkit')"
  printf '    "version": "%s"\n' \
    "$(lht_json_escape "$LHT_VERSION")"
  printf '  },\n'

  printf '  "audit": {\n'
  printf '    "profile_id": "%s",\n' \
    "$(lht_json_escape "$LHT_PROFILE_NAME")"
  printf '    "profile_name": "%s",\n' \
    "$(lht_json_escape "$LHT_PROFILE_DISPLAY_NAME")"
  printf '    "description": "%s",\n' \
    "$(lht_json_escape "$LHT_PROFILE_DESCRIPTION")"
  printf '    "mode": "audit",\n'
  printf '    "read_only": true,\n'
  printf '    "dry_run": %s,\n' "$dry_run_json"
  printf '    "generated_at": "%s"\n' \
    "$(lht_json_escape "$LHT_AUDIT_GENERATED_AT")"
  printf '  },\n'

  printf '  "summary": {\n'
  printf '    "pass": %d,\n' "$LHT_AUDIT_PASS_COUNT"
  printf '    "fail": %d,\n' "$LHT_AUDIT_FAIL_COUNT"
  printf '    "warn": %d,\n' "$LHT_AUDIT_WARN_COUNT"
  printf '    "skip": %d,\n' "$LHT_AUDIT_SKIP_COUNT"
  printf '    "error": %d,\n' "$LHT_AUDIT_ERROR_COUNT"
  printf '    "exit_code": %d\n' "$LHT_AUDIT_EXIT_CODE"
  printf '  },\n'

  printf '  "checks": [\n'

  for (( index = 0; index < total; index++ )); do
    check_id="${LHT_AUDIT_RESULT_IDS[$index]}"
    remediation_json="false"

    if [[ -n "${LHT_CHECK_APPLY_FN[$check_id]-}" ]]; then
      remediation_json="true"
    fi

    printf '    {\n'
    printf '      "id": "%s",\n' \
      "$(lht_json_escape "$check_id")"
    printf '      "category": "%s",\n' \
      "$(lht_json_escape "${LHT_CHECK_CATEGORY[$check_id]}")"
    printf '      "severity": "%s",\n' \
      "$(lht_json_escape "${LHT_CHECK_SEVERITY[$check_id]}")"
    printf '      "title": "%s",\n' \
      "$(lht_json_escape "${LHT_CHECK_TITLE[$check_id]}")"
    printf '      "status": "%s",\n' \
      "$(lht_json_escape "${LHT_AUDIT_RESULT_STATUS[$check_id]}")"
    printf '      "message": "%s",\n' \
      "$(lht_json_escape "${LHT_AUDIT_RESULT_SUMMARY[$check_id]}")"
    printf '      "details": "%s",\n' \
      "$(lht_json_escape "${LHT_AUDIT_RESULT_DETAILS[$check_id]}")"
    printf '      "remediation_available": %s\n' \
      "$remediation_json"

    if (( index + 1 < total )); then
      printf '    },\n'
    else
      printf '    }\n'
    fi
  done

  printf '  ]\n'
  printf '}\n'
}

lht_write_json_report() {
  local output_path="${LHT_OUTPUT_PATH:-}"
  local output_dir=""
  local output_base=""
  local temp_path=""

  if [[ -z "$output_path" || "$output_path" == "-" ]]; then
    lht_emit_json_report
    return 0
  fi

  if [[ -d "$output_path" ]]; then
    lht_die "Output path is a directory: ${output_path}"
  fi

  output_dir="$(dirname -- "$output_path")"
  output_base="$(basename -- "$output_path")"

  if [[ ! -d "$output_dir" ]]; then
    lht_die "Output directory does not exist: ${output_dir}"
  fi

  if [[ ! -w "$output_dir" ]]; then
    lht_die "Output directory is not writable: ${output_dir}"
  fi

  if ! temp_path="$(
    mktemp "${output_dir}/.${output_base}.tmp.XXXXXX"
  )"; then
    lht_die "Could not create temporary report file in ${output_dir}"
  fi

  if ! chmod 600 "$temp_path"; then
    rm -f -- "$temp_path"
    lht_die "Could not secure temporary report file: ${temp_path}"
  fi

  if ! lht_emit_json_report > "$temp_path"; then
    rm -f -- "$temp_path"
    lht_die "Could not write JSON report: ${output_path}"
  fi

  if ! mv -f -- "$temp_path" "$output_path"; then
    rm -f -- "$temp_path"
    lht_die "Could not finalize JSON report: ${output_path}"
  fi
}
