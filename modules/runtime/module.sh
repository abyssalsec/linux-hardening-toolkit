#!/usr/bin/env bash

lht_check_runtime_os_release() {
  if [[ -r "/etc/os-release" ]]; then
    lht_result \
      "PASS" \
      "Linux OS metadata is available" \
      "/etc/os-release is readable"
  else
    lht_result \
      "FAIL" \
      "Linux OS metadata is unavailable" \
      "/etc/os-release does not exist or cannot be read"
  fi
}

lht_check_runtime_procfs() {
  if [[ -r "/proc/self/status" ]]; then
    lht_result \
      "PASS" \
      "procfs is available" \
      "/proc/self/status is readable"
  else
    lht_result \
      "FAIL" \
      "procfs is unavailable" \
      "/proc/self/status does not exist or cannot be read"
  fi
}

lht_register_check \
  "runtime.os-release" \
  "runtime" \
  "Linux OS metadata available" \
  "info" \
  "lht_check_runtime_os_release"

lht_register_check \
  "runtime.procfs" \
  "runtime" \
  "procfs available" \
  "info" \
  "lht_check_runtime_procfs"
