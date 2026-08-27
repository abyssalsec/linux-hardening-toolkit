#!/usr/bin/env bash

LHT_AUTH_PAM_DIR="${LHT_AUTH_PAM_DIR:-/etc/pam.d}"
LHT_AUTH_SECURITY_DIR="${LHT_AUTH_SECURITY_DIR:-/etc/security}"
LHT_AUTH_MIN_PASSWORD_LENGTH="${LHT_AUTH_MIN_PASSWORD_LENGTH:-12}"
LHT_AUTH_MIN_PASSWORD_HISTORY="${LHT_AUTH_MIN_PASSWORD_HISTORY:-5}"
LHT_AUTH_MAX_FAILED_ATTEMPTS="${LHT_AUTH_MAX_FAILED_ATTEMPTS:-5}"

LHT_AUTH_COLLECTED=0
LHT_AUTH_LAYOUT=""

declare -ag LHT_AUTH_AUTH_FILES=()
declare -ag LHT_AUTH_PASSWORD_FILES=()

lht_auth_collect_stack() {
  if (( LHT_AUTH_COLLECTED == 1 )); then
    return 0
  fi

  LHT_AUTH_COLLECTED=1

  if [[ -r "${LHT_AUTH_PAM_DIR}/common-auth" ]] \
    && [[ -r "${LHT_AUTH_PAM_DIR}/common-password" ]]; then

    LHT_AUTH_LAYOUT="debian"
    LHT_AUTH_AUTH_FILES=("${LHT_AUTH_PAM_DIR}/common-auth")
    LHT_AUTH_PASSWORD_FILES=("${LHT_AUTH_PAM_DIR}/common-password")
    return 0
  fi

  if [[ -r "${LHT_AUTH_PAM_DIR}/system-auth" ]] \
    || [[ -r "${LHT_AUTH_PAM_DIR}/password-auth" ]]; then

    LHT_AUTH_LAYOUT="rhel"

    if [[ -r "${LHT_AUTH_PAM_DIR}/system-auth" ]]; then
      LHT_AUTH_AUTH_FILES+=("${LHT_AUTH_PAM_DIR}/system-auth")
      LHT_AUTH_PASSWORD_FILES+=("${LHT_AUTH_PAM_DIR}/system-auth")
    fi

    if [[ -r "${LHT_AUTH_PAM_DIR}/password-auth" ]]; then
      LHT_AUTH_AUTH_FILES+=("${LHT_AUTH_PAM_DIR}/password-auth")
      LHT_AUTH_PASSWORD_FILES+=("${LHT_AUTH_PAM_DIR}/password-auth")
    fi
  fi
}

lht_auth_join_files() {
  local joined=""
  local file=""

  for file in "$@"; do
    if [[ -z "$joined" ]]; then
      joined="$file"
    else
      joined="${joined},${file}"
    fi
  done

  printf '%s' "$joined"
}

lht_auth_first_module_line() {
  local module_regex="${1:?module regex is required}"
  shift

  local file=""
  local line=""

  for file in "$@"; do
    [[ -r "$file" ]] || continue

    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$(lht_trim "$line")" ]] && continue

      if [[ "$line" =~ $module_regex ]]; then
        printf '%s' "$line"
        return 0
      fi
    done < "$file"
  done

  return 1
}

lht_auth_any_module_line() {
  local module_regex="${1:?module regex is required}"
  shift

  lht_auth_first_module_line "$module_regex" "$@" >/dev/null
}

lht_auth_extract_option() {
  local line="${1-}"
  local option="${2:?option name is required}"

  printf '%s\n' "$line" | awk -v wanted="$option" '
    {
      for (i = 1; i <= NF; i++) {
        prefix = wanted "="

        if (index($i, prefix) == 1) {
          value = substr($i, length(prefix) + 1)
        }
      }
    }

    END {
      if (value != "") {
        print value
      }
    }
  '
}

lht_auth_security_conf_value() {
  local base_name="${1:?configuration basename is required}"
  local key="${2:?configuration key is required}"

  local file=""
  local line=""
  local value=""
  local found=""
  local -a files=("${LHT_AUTH_SECURITY_DIR}/${base_name}")

  if [[ -d "${LHT_AUTH_SECURITY_DIR}/${base_name}.d" ]]; then
    while IFS= read -r file; do
      files+=("$file")
    done < <(
      find "${LHT_AUTH_SECURITY_DIR}/${base_name}.d" \
        -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort
    )
  fi

  for file in "${files[@]}"; do
    [[ -r "$file" ]] || continue

    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue

      if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^[:space:]#]+) ]]; then
        value="${BASH_REMATCH[1]}"
        found="$value"
      fi
    done < "$file"
  done

  [[ -n "$found" ]] || return 1
  printf '%s' "$found"
}

lht_auth_option_from_module_or_conf() {
  local module_regex="${1:?module regex is required}"
  local option="${2:?option name is required}"
  local conf_base="${3:?configuration basename is required}"
  shift 3

  local line=""
  local value=""

  if line="$(lht_auth_first_module_line "$module_regex" "$@")"; then
    value="$(lht_auth_extract_option "$line" "$option")"

    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  fi

  lht_auth_security_conf_value "$conf_base" "$option"
}

lht_check_auth_pam_stack() {
  lht_auth_collect_stack

  if [[ -z "$LHT_AUTH_LAYOUT" ]]; then
    lht_result \
      "WARN" \
      "Supported central PAM authentication stack was not detected" \
      "Checked Debian/Ubuntu common-* and RHEL-family system-auth/password-auth layouts"
    return 0
  fi

  lht_result \
    "PASS" \
    "Central PAM authentication stack detected" \
    "layout=${LHT_AUTH_LAYOUT}; auth=$(lht_auth_join_files "${LHT_AUTH_AUTH_FILES[@]}"); password=$(lht_auth_join_files "${LHT_AUTH_PASSWORD_FILES[@]}")"
}

lht_check_auth_null_passwords() {
  lht_auth_collect_stack

  if [[ -z "$LHT_AUTH_LAYOUT" ]]; then
    lht_result \
      "SKIP" \
      "PAM null-password policy could not be evaluated" \
      "No supported central PAM stack was detected"
    return 0
  fi

  local file=""
  local line=""
  local findings=""

  for file in "${LHT_AUTH_AUTH_FILES[@]}"; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue

      if [[ "$line" =~ pam_unix\.so ]] \
        && [[ " $line " =~ [[:space:]]nullok([[:space:]]|$) ]]; then

        if [[ -z "$findings" ]]; then
          findings="${file}: pam_unix.so nullok"
        else
          findings="${findings}; ${file}: pam_unix.so nullok"
        fi
      fi
    done < "$file"
  done

  if [[ -n "$findings" ]]; then
    lht_result \
      "FAIL" \
      "PAM permits null passwords" \
      "$findings"
  else
    lht_result \
      "PASS" \
      "PAM does not permit null passwords through pam_unix" \
      "No active pam_unix.so nullok option was found in the central authentication stack"
  fi
}

lht_check_auth_password_quality() {
  lht_auth_collect_stack

  if [[ -z "$LHT_AUTH_LAYOUT" ]]; then
    lht_result \
      "SKIP" \
      "PAM password quality policy could not be evaluated" \
      "No supported central PAM stack was detected"
    return 0
  fi

  local line=""

  if line="$(lht_auth_first_module_line 'pam_pwquality\.so' "${LHT_AUTH_PASSWORD_FILES[@]}")"; then
    lht_result \
      "PASS" \
      "PAM password quality enforcement is configured" \
      "module=pam_pwquality.so; ${line}"
    return 0
  fi

  if line="$(lht_auth_first_module_line 'pam_passwdqc\.so' "${LHT_AUTH_PASSWORD_FILES[@]}")"; then
    lht_result \
      "PASS" \
      "PAM password quality enforcement is configured" \
      "module=pam_passwdqc.so; ${line}"
    return 0
  fi

  lht_result \
    "FAIL" \
    "No supported PAM password quality module is active" \
    "Neither pam_pwquality.so nor pam_passwdqc.so was found in the central password stack"
}

lht_check_auth_password_min_length() {
  lht_auth_collect_stack

  if [[ -z "$LHT_AUTH_LAYOUT" ]]; then
    lht_result \
      "SKIP" \
      "Password minimum length could not be evaluated" \
      "No supported central PAM stack was detected"
    return 0
  fi

  if ! lht_auth_any_module_line 'pam_pwquality\.so' "${LHT_AUTH_PASSWORD_FILES[@]}"; then
    lht_result \
      "SKIP" \
      "Password minimum length could not be evaluated" \
      "pam_pwquality.so is not active in the central password stack"
    return 0
  fi

  local value=""

  if ! value="$(
    lht_auth_option_from_module_or_conf \
      'pam_pwquality\.so' \
      'minlen' \
      'pwquality.conf' \
      "${LHT_AUTH_PASSWORD_FILES[@]}"
  )"; then
    lht_result \
      "WARN" \
      "Password minimum length is not explicitly configured" \
      "pam_pwquality.so is active but no explicit minlen value was found"
    return 0
  fi

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    lht_result \
      "ERROR" \
      "Invalid PAM password minimum length value" \
      "minlen=${value}"
    return 0
  fi

  if (( value >= LHT_AUTH_MIN_PASSWORD_LENGTH )); then
    lht_result \
      "PASS" \
      "Password minimum length meets the toolkit baseline" \
      "minlen=${value}; required>=${LHT_AUTH_MIN_PASSWORD_LENGTH}"
  else
    lht_result \
      "FAIL" \
      "Password minimum length is below the toolkit baseline" \
      "minlen=${value}; required>=${LHT_AUTH_MIN_PASSWORD_LENGTH}"
  fi
}

lht_check_auth_password_history() {
  lht_auth_collect_stack

  if [[ -z "$LHT_AUTH_LAYOUT" ]]; then
    lht_result \
      "SKIP" \
      "Password history policy could not be evaluated" \
      "No supported central PAM stack was detected"
    return 0
  fi

  local line=""
  local value=""
  local source=""

  if line="$(lht_auth_first_module_line 'pam_pwhistory\.so' "${LHT_AUTH_PASSWORD_FILES[@]}")"; then
    value="$(lht_auth_extract_option "$line" 'remember')"

    if [[ -n "$value" ]]; then
      source="pam_pwhistory.so option"
    elif value="$(lht_auth_security_conf_value 'pwhistory.conf' 'remember')"; then
      source="pwhistory.conf"
    else
      value="10"
      source="pam_pwhistory.so default"
    fi
  elif line="$(lht_auth_first_module_line 'pam_unix\.so' "${LHT_AUTH_PASSWORD_FILES[@]}")"; then
    value="$(lht_auth_extract_option "$line" 'remember')"

    if [[ -n "$value" ]]; then
      source="pam_unix.so remember option"
    else
      lht_result \
        "FAIL" \
        "Password history enforcement is not configured" \
        "pam_pwhistory.so is not active and pam_unix.so has no remember option"
      return 0
    fi
  else
    lht_result \
      "FAIL" \
      "Password history enforcement is not configured" \
      "No supported password-history mechanism was found in the central password stack"
    return 0
  fi

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    lht_result \
      "ERROR" \
      "Invalid password history value" \
      "remember=${value}; source=${source}"
    return 0
  fi

  if (( value >= LHT_AUTH_MIN_PASSWORD_HISTORY )); then
    lht_result \
      "PASS" \
      "Password history meets the toolkit baseline" \
      "remember=${value}; required>=${LHT_AUTH_MIN_PASSWORD_HISTORY}; source=${source}"
  else
    lht_result \
      "FAIL" \
      "Password history is below the toolkit baseline" \
      "remember=${value}; required>=${LHT_AUTH_MIN_PASSWORD_HISTORY}; source=${source}"
  fi
}

lht_check_auth_failed_login_lockout() {
  lht_auth_collect_stack

  if [[ -z "$LHT_AUTH_LAYOUT" ]]; then
    lht_result \
      "SKIP" \
      "Failed-login lockout could not be evaluated" \
      "No supported central PAM stack was detected"
    return 0
  fi

  if lht_auth_any_module_line 'pam_faillock\.so' "${LHT_AUTH_AUTH_FILES[@]}"; then
    lht_result \
      "PASS" \
      "PAM failed-login lockout is configured" \
      "pam_faillock.so is active in the central authentication stack"
    return 0
  fi

  if lht_auth_any_module_line 'pam_tally2\.so' "${LHT_AUTH_AUTH_FILES[@]}"; then
    lht_result \
      "WARN" \
      "Legacy PAM failed-login lockout is configured" \
      "pam_tally2.so is active; consider migrating to pam_faillock.so where supported"
    return 0
  fi

  lht_result \
    "FAIL" \
    "PAM failed-login lockout is not configured" \
    "pam_faillock.so was not found in the central authentication stack"
}

lht_check_auth_lockout_policy() {
  lht_auth_collect_stack

  if [[ -z "$LHT_AUTH_LAYOUT" ]]; then
    lht_result \
      "SKIP" \
      "Failed-login lockout policy could not be evaluated" \
      "No supported central PAM stack was detected"
    return 0
  fi

  if ! lht_auth_any_module_line 'pam_faillock\.so' "${LHT_AUTH_AUTH_FILES[@]}"; then
    lht_result \
      "SKIP" \
      "Failed-login lockout policy could not be evaluated" \
      "pam_faillock.so is not active in the central authentication stack"
    return 0
  fi

  local deny=""
  local unlock_time=""

  deny="$(
    lht_auth_option_from_module_or_conf \
      'pam_faillock\.so' \
      'deny' \
      'faillock.conf' \
      "${LHT_AUTH_AUTH_FILES[@]}" || true
  )"

  unlock_time="$(
    lht_auth_option_from_module_or_conf \
      'pam_faillock\.so' \
      'unlock_time' \
      'faillock.conf' \
      "${LHT_AUTH_AUTH_FILES[@]}" || true
  )"

  [[ -n "$deny" ]] || deny="3"
  [[ -n "$unlock_time" ]] || unlock_time="600"

  if [[ ! "$deny" =~ ^[0-9]+$ ]] || [[ ! "$unlock_time" =~ ^[0-9]+$ ]]; then
    lht_result \
      "ERROR" \
      "Invalid PAM failed-login lockout configuration" \
      "deny=${deny}; unlock_time=${unlock_time}"
    return 0
  fi

  if (( deny < 1 || deny > LHT_AUTH_MAX_FAILED_ATTEMPTS )); then
    lht_result \
      "FAIL" \
      "Failed-login attempt threshold is outside the toolkit baseline" \
      "deny=${deny}; required=1-${LHT_AUTH_MAX_FAILED_ATTEMPTS}; unlock_time=${unlock_time}"
    return 0
  fi

  if (( unlock_time == 0 || unlock_time <= 900 )); then
    lht_result \
      "PASS" \
      "Failed-login lockout policy meets the toolkit baseline" \
      "deny=${deny}; unlock_time=${unlock_time}"
  else
    lht_result \
      "WARN" \
      "Failed-login lockout duration requires operational review" \
      "deny=${deny}; unlock_time=${unlock_time}. Long lockouts may create availability risk."
  fi
}

lht_check_auth_password_hashing() {
  lht_auth_collect_stack

  if [[ -z "$LHT_AUTH_LAYOUT" ]]; then
    lht_result \
      "SKIP" \
      "PAM password hashing policy could not be evaluated" \
      "No supported central PAM stack was detected"
    return 0
  fi

  local line=""

  if ! line="$(lht_auth_first_module_line 'pam_unix\.so' "${LHT_AUTH_PASSWORD_FILES[@]}")"; then
    lht_result \
      "SKIP" \
      "PAM password hashing policy could not be evaluated" \
      "pam_unix.so was not found in the central password stack"
    return 0
  fi

  if [[ " $line " =~ [[:space:]](yescrypt|gost_yescrypt)([[:space:]]|$) ]]; then
    lht_result \
      "PASS" \
      "Modern password hashing is configured" \
      "algorithm=${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ " $line " =~ [[:space:]]sha512([[:space:]]|$) ]]; then
    lht_result \
      "PASS" \
      "Strong password hashing is configured" \
      "algorithm=sha512"
    return 0
  fi

  if [[ " $line " =~ [[:space:]](sha256|blowfish)([[:space:]]|$) ]]; then
    lht_result \
      "WARN" \
      "Password hashing algorithm should be reviewed" \
      "algorithm=${BASH_REMATCH[1]}; prefer yescrypt where supported"
    return 0
  fi

  if [[ " $line " =~ [[:space:]](md5|bigcrypt|des)([[:space:]]|$) ]]; then
    lht_result \
      "FAIL" \
      "Weak password hashing algorithm is configured" \
      "algorithm=${BASH_REMATCH[1]}"
    return 0
  fi

  lht_result \
    "WARN" \
    "Password hashing algorithm is not explicit in the PAM stack" \
    "pam_unix.so is active but no recognized hashing option was found"
}

lht_register_check \
  "auth.pam-stack" \
  "authentication" \
  "Central PAM authentication stack detected" \
  "info" \
  "lht_check_auth_pam_stack"

lht_register_check \
  "auth.null-passwords" \
  "authentication" \
  "PAM null-password authentication disabled" \
  "high" \
  "lht_check_auth_null_passwords"

lht_register_check \
  "auth.password-quality" \
  "authentication" \
  "PAM password quality enforcement configured" \
  "high" \
  "lht_check_auth_password_quality"

lht_register_check \
  "auth.password-min-length" \
  "authentication" \
  "Password minimum length reviewed" \
  "high" \
  "lht_check_auth_password_min_length"

lht_register_check \
  "auth.password-history" \
  "authentication" \
  "Password history enforcement configured" \
  "medium" \
  "lht_check_auth_password_history"

lht_register_check \
  "auth.failed-login-lockout" \
  "authentication" \
  "Failed-login lockout configured" \
  "high" \
  "lht_check_auth_failed_login_lockout"

lht_register_check \
  "auth.lockout-policy" \
  "authentication" \
  "Failed-login lockout policy reviewed" \
  "medium" \
  "lht_check_auth_lockout_policy"

lht_register_check \
  "auth.password-hashing" \
  "authentication" \
  "Password hashing policy reviewed" \
  "high" \
  "lht_check_auth_password_hashing"
