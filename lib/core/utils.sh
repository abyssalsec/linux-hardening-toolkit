#!/usr/bin/env bash

lht_trim() {
  local value="${1-}"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"

  printf '%s' "$value"
}

lht_is_safe_name() {
  local value="${1-}"

  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]
}
