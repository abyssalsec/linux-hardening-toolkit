#!/usr/bin/env bash

LHT_COLOR_RED=$'\033[31m'
LHT_COLOR_GREEN=$'\033[32m'
LHT_COLOR_YELLOW=$'\033[33m'
LHT_COLOR_BLUE=$'\033[34m'
LHT_COLOR_CYAN=$'\033[36m'
LHT_COLOR_RESET=$'\033[0m'

lht_color_enabled() {
  [[ -t 1 ]] \
    && [[ "${LHT_NO_COLOR:-0}" != "1" ]] \
    && [[ -z "${NO_COLOR:-}" ]]
}

lht_log_info() {
  printf 'INFO: %s\n' "$*"
}

lht_log_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

lht_log_debug() {
  [[ "${LHT_VERBOSE:-0}" == "1" ]] || return 0

  printf 'DEBUG: %s\n' "$*" >&2
}

lht_die() {
  local message="${1:-Unexpected error}"
  local exit_code="${2:-1}"

  lht_log_error "$message"
  exit "$exit_code"
}

lht_print_status() {
  local status="${1:?status is required}"
  local check_id="${2:?check id is required}"
  local message="${3:?message is required}"

  local color=""
  local reset=""

  if lht_color_enabled; then
    reset="$LHT_COLOR_RESET"

    case "$status" in
      PASS)
        color="$LHT_COLOR_GREEN"
        ;;
      FAIL)
        color="$LHT_COLOR_RED"
        ;;
      WARN)
        color="$LHT_COLOR_YELLOW"
        ;;
      SKIP)
        color="$LHT_COLOR_CYAN"
        ;;
      ERROR)
        color="$LHT_COLOR_RED"
        ;;
    esac
  fi

  printf '%b[%-5s]%b %-28s %s\n' \
    "$color" \
    "$status" \
    "$reset" \
    "$check_id" \
    "$message"
}

lht_print_detail() {
  local message="${1-}"

  [[ -n "$message" ]] || return 0

  printf '        %s\n' "$message"
}
