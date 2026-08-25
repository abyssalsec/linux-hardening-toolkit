#!/usr/bin/env bash

lht_assert_runtime() {
  if (( BASH_VERSINFO[0] < 4 )); then
    lht_die \
      "Bash 4.0 or newer is required. Detected: ${BASH_VERSION}" \
      1
  fi

  local kernel_name=""

  kernel_name="$(uname -s 2>/dev/null || true)"

  if [[ "$kernel_name" != "Linux" ]]; then
    lht_die \
      "Linux Hardening Toolkit can audit Linux systems only. Detected kernel: ${kernel_name:-unknown}" \
      1
  fi
}
