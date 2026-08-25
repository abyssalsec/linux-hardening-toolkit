#!/usr/bin/env bash

LHT_SYSCTL_PROC_ROOT="${LHT_SYSCTL_PROC_ROOT:-/proc/sys}"
LHT_SYSCTL_VALUE=""

declare -Ag LHT_SYSCTL_CACHE_STATUS=()
declare -Ag LHT_SYSCTL_CACHE_VALUE=()
declare -Ag LHT_SYSCTL_CACHE_PATH=()

lht_sysctl_append_detail() {
  local current="${1-}"
  local item="${2-}"

  if [[ -z "$current" ]]; then
    printf '%s' "$item"
  else
    printf '%s; %s' "$current" "$item"
  fi
}

lht_sysctl_key_to_path() {
  local key="${1:?sysctl key is required}"

  printf '%s/%s' \
    "$LHT_SYSCTL_PROC_ROOT" \
    "${key//./\/}"
}

lht_sysctl_read() {
  local key="${1:?sysctl key is required}"

  LHT_SYSCTL_VALUE=""

  if [[ -n "${LHT_SYSCTL_CACHE_STATUS[$key]+x}" ]]; then
    if [[ "${LHT_SYSCTL_CACHE_STATUS[$key]}" == "ok" ]]; then
      LHT_SYSCTL_VALUE="${LHT_SYSCTL_CACHE_VALUE[$key]}"
      return 0
    fi

    return 1
  fi

  local path=""
  local value=""

  path="$(lht_sysctl_key_to_path "$key")"

  LHT_SYSCTL_CACHE_PATH["$key"]="$path"

  if [[ ! -e "$path" ]]; then
    LHT_SYSCTL_CACHE_STATUS["$key"]="missing"
    return 1
  fi

  if [[ ! -r "$path" ]]; then
    LHT_SYSCTL_CACHE_STATUS["$key"]="unreadable"
    return 1
  fi

  if ! value="$(cat -- "$path" 2>/dev/null)"; then
    LHT_SYSCTL_CACHE_STATUS["$key"]="error"
    return 1
  fi

  value="$(lht_trim "$value")"

  LHT_SYSCTL_CACHE_STATUS["$key"]="ok"
  LHT_SYSCTL_CACHE_VALUE["$key"]="$value"

  LHT_SYSCTL_VALUE="$value"

  return 0
}

lht_sysctl_unavailable_result() {
  local key="${1:?sysctl key is required}"

  local status="${LHT_SYSCTL_CACHE_STATUS[$key]:-unknown}"
  local path="${LHT_SYSCTL_CACHE_PATH[$key]:-unknown}"

  case "$status" in
    missing)
      lht_result \
        "SKIP" \
        "Kernel parameter is not available" \
        "${key} is not exposed by this kernel (${path})"
      ;;

    unreadable)
      lht_result \
        "SKIP" \
        "Kernel parameter is not readable" \
        "${key} cannot be read by the current process (${path})"
      ;;

    error)
      lht_result \
        "ERROR" \
        "Kernel parameter could not be read" \
        "${key}: read failed (${path})"
      ;;

    *)
      lht_result \
        "ERROR" \
        "Unexpected sysctl collection state" \
        "${key}: state=${status}"
      ;;
  esac
}

lht_sysctl_check_exact() {
  local key="${1:?sysctl key is required}"
  local expected="${2:?expected value is required}"
  local pass_message="${3:?pass message is required}"
  local fail_message="${4:?fail message is required}"

  if ! lht_sysctl_read "$key"; then
    lht_sysctl_unavailable_result "$key"
    return 0
  fi

  local actual="$LHT_SYSCTL_VALUE"

  if [[ "$actual" == "$expected" ]]; then
    lht_result \
      "PASS" \
      "$pass_message" \
      "${key}=${actual}"
  else
    lht_result \
      "FAIL" \
      "$fail_message" \
      "${key}=${actual}; expected ${expected}"
  fi
}

lht_sysctl_check_allowed() {
  local key="${1:?sysctl key is required}"
  local allowed_values="${2:?allowed values are required}"
  local pass_message="${3:?pass message is required}"
  local fail_message="${4:?fail message is required}"

  if ! lht_sysctl_read "$key"; then
    lht_sysctl_unavailable_result "$key"
    return 0
  fi

  local actual="$LHT_SYSCTL_VALUE"
  local value=""

  for value in $allowed_values; do
    if [[ "$actual" == "$value" ]]; then
      lht_result \
        "PASS" \
        "$pass_message" \
        "${key}=${actual}; accepted=${allowed_values}"
      return 0
    fi
  done

  lht_result \
    "FAIL" \
    "$fail_message" \
    "${key}=${actual}; accepted=${allowed_values}"
}

lht_sysctl_check_conf_zero() {
  local family="${1:?network family is required}"
  local setting="${2:?setting is required}"
  local pass_message="${3:?pass message is required}"
  local fail_message="${4:?fail message is required}"

  local conf_root="${LHT_SYSCTL_PROC_ROOT}/net/${family}/conf"

  if [[ ! -d "$conf_root" ]]; then
    lht_result \
      "SKIP" \
      "${family} network configuration is not available" \
      "${conf_root} does not exist"
    return 0
  fi

  local -a targets=(
    "all"
    "default"
  )

  local directory=""
  local target=""

  for directory in "$conf_root"/*; do
    [[ -d "$directory" ]] || continue

    target="${directory##*/}"

    case "$target" in
      all|default)
        continue
        ;;
    esac

    targets+=("$target")
  done

  local key=""
  local actual=""
  local violations=""
  local unavailable=""
  local checked=0

  for target in "${targets[@]}"; do
    key="net.${family}.conf.${target}.${setting}"

    if ! lht_sysctl_read "$key"; then
      unavailable="$(
        lht_sysctl_append_detail \
          "$unavailable" \
          "${target}:${LHT_SYSCTL_CACHE_STATUS[$key]:-unknown}"
      )"
      continue
    fi

    actual="$LHT_SYSCTL_VALUE"
    checked=$((checked + 1))

    if [[ "$actual" != "0" ]]; then
      violations="$(
        lht_sysctl_append_detail \
          "$violations" \
          "${target}=${actual}"
      )"
    fi
  done

  if [[ -n "$violations" ]]; then
    lht_result \
      "FAIL" \
      "$fail_message" \
      "${setting}: ${violations}"
    return 0
  fi

  if (( checked == 0 )); then
    lht_result \
      "SKIP" \
      "Network kernel parameter could not be evaluated" \
      "${family}.${setting}; unavailable=${unavailable:-all}"
    return 0
  fi

  if [[ -n "$unavailable" ]]; then
    lht_result \
      "WARN" \
      "Network kernel parameter was only partially evaluated" \
      "${setting}; unavailable=${unavailable}"
    return 0
  fi

  lht_result \
    "PASS" \
    "$pass_message" \
    "${setting}=0 for ${checked} ${family} configuration target(s)"
}

lht_check_sysctl_runtime() {
  if [[ ! -d "$LHT_SYSCTL_PROC_ROOT" ]]; then
    lht_result \
      "ERROR" \
      "Kernel sysctl interface is unavailable" \
      "${LHT_SYSCTL_PROC_ROOT} does not exist"
    return 0
  fi

  if [[ ! -r "$LHT_SYSCTL_PROC_ROOT" ]] \
    || [[ ! -x "$LHT_SYSCTL_PROC_ROOT" ]]; then

    lht_result \
      "ERROR" \
      "Kernel sysctl interface is inaccessible" \
      "${LHT_SYSCTL_PROC_ROOT} cannot be traversed"
    return 0
  fi

  lht_result \
    "PASS" \
    "Kernel sysctl runtime interface is available" \
    "Reading effective values from ${LHT_SYSCTL_PROC_ROOT}"
}

lht_check_kernel_aslr() {
  lht_sysctl_check_exact \
    "kernel.randomize_va_space" \
    "2" \
    "Full userspace ASLR is enabled" \
    "Full userspace ASLR is not enabled"
}

lht_check_kernel_kptr_restrict() {
  lht_sysctl_check_allowed \
    "kernel.kptr_restrict" \
    "1 2" \
    "Kernel pointer exposure is restricted" \
    "Kernel pointer exposure is insufficiently restricted"
}

lht_check_kernel_dmesg_restrict() {
  lht_sysctl_check_exact \
    "kernel.dmesg_restrict" \
    "1" \
    "Unprivileged kernel log access is restricted" \
    "Unprivileged users may read kernel log messages"
}

lht_check_kernel_ptrace_scope() {
  lht_sysctl_check_allowed \
    "kernel.yama.ptrace_scope" \
    "1 2 3" \
    "Process tracing is restricted by Yama" \
    "Yama permits classic same-user ptrace behaviour"
}

lht_check_fs_protected_hardlinks() {
  lht_sysctl_check_exact \
    "fs.protected_hardlinks" \
    "1" \
    "Hardlink protection is enabled" \
    "Hardlink protection is disabled"
}

lht_check_fs_protected_symlinks() {
  lht_sysctl_check_exact \
    "fs.protected_symlinks" \
    "1" \
    "Symlink protection is enabled" \
    "Symlink protection is disabled"
}

lht_check_fs_protected_fifos() {
  lht_sysctl_check_allowed \
    "fs.protected_fifos" \
    "1 2" \
    "FIFO protection is enabled" \
    "FIFO protection is disabled"
}

lht_check_fs_protected_regular() {
  lht_sysctl_check_allowed \
    "fs.protected_regular" \
    "1 2" \
    "Regular-file protection is enabled" \
    "Regular-file protection is disabled"
}

lht_check_net_ipv4_accept_redirects() {
  lht_sysctl_check_conf_zero \
    "ipv4" \
    "accept_redirects" \
    "IPv4 ICMP redirects are not accepted" \
    "IPv4 ICMP redirect acceptance is enabled"
}

lht_check_net_ipv4_send_redirects() {
  lht_sysctl_check_conf_zero \
    "ipv4" \
    "send_redirects" \
    "IPv4 ICMP redirect sending is disabled" \
    "IPv4 ICMP redirect sending is enabled"
}

lht_check_net_ipv4_accept_source_route() {
  lht_sysctl_check_conf_zero \
    "ipv4" \
    "accept_source_route" \
    "IPv4 source routing is disabled" \
    "IPv4 source routing is enabled"
}

lht_check_net_ipv4_rp_filter() {
  local conf_root="${LHT_SYSCTL_PROC_ROOT}/net/ipv4/conf"

  if [[ ! -d "$conf_root" ]]; then
    lht_result \
      "SKIP" \
      "IPv4 reverse-path filtering is unavailable" \
      "${conf_root} does not exist"
    return 0
  fi

  local all_key="net.ipv4.conf.all.rp_filter"

  if ! lht_sysctl_read "$all_key"; then
    lht_sysctl_unavailable_result "$all_key"
    return 0
  fi

  local all_value="$LHT_SYSCTL_VALUE"

  if [[ ! "$all_value" =~ ^[012]$ ]]; then
    lht_result \
      "ERROR" \
      "Invalid global reverse-path filter value" \
      "${all_key}=${all_value}"
    return 0
  fi

  local -a targets=("default")

  local directory=""
  local target=""

  for directory in "$conf_root"/*; do
    [[ -d "$directory" ]] || continue

    target="${directory##*/}"

    case "$target" in
      all|default|lo)
        continue
        ;;
    esac

    targets+=("$target")
  done

  local key=""
  local interface_value=""
  local effective_value=0
  local violations=""
  local invalid=""
  local unavailable=""
  local checked=0

  for target in "${targets[@]}"; do
    key="net.ipv4.conf.${target}.rp_filter"

    if ! lht_sysctl_read "$key"; then
      unavailable="$(
        lht_sysctl_append_detail \
          "$unavailable" \
          "${target}:${LHT_SYSCTL_CACHE_STATUS[$key]:-unknown}"
      )"
      continue
    fi

    interface_value="$LHT_SYSCTL_VALUE"

    if [[ ! "$interface_value" =~ ^[012]$ ]]; then
      invalid="$(
        lht_sysctl_append_detail \
          "$invalid" \
          "${target}=${interface_value}"
      )"
      continue
    fi

    checked=$((checked + 1))

    if (( all_value > interface_value )); then
      effective_value="$all_value"
    else
      effective_value="$interface_value"
    fi

    if (( effective_value < 1 )); then
      violations="$(
        lht_sysctl_append_detail \
          "$violations" \
          "${target}:all=${all_value},local=${interface_value},effective=${effective_value}"
      )"
    fi
  done

  if [[ -n "$invalid" ]]; then
    lht_result \
      "ERROR" \
      "Invalid IPv4 reverse-path filtering values were detected" \
      "$invalid"
    return 0
  fi

  if [[ -n "$violations" ]]; then
    lht_result \
      "FAIL" \
      "IPv4 reverse-path filtering is disabled for one or more interfaces" \
      "$violations"
    return 0
  fi

  if (( checked == 0 )); then
    lht_result \
      "SKIP" \
      "IPv4 reverse-path filtering could not be evaluated" \
      "No applicable interface values were readable"
    return 0
  fi

  if [[ -n "$unavailable" ]]; then
    lht_result \
      "WARN" \
      "IPv4 reverse-path filtering was only partially evaluated" \
      "Unavailable: ${unavailable}"
    return 0
  fi

  lht_result \
    "PASS" \
    "IPv4 reverse-path filtering is enabled" \
    "Checked default plus ${checked} applicable configuration target(s); effective mode is strict or loose"
}

lht_check_net_ipv4_icmp_broadcast_ignore() {
  lht_sysctl_check_exact \
    "net.ipv4.icmp_echo_ignore_broadcasts" \
    "1" \
    "IPv4 broadcast ICMP echo requests are ignored" \
    "IPv4 broadcast ICMP echo requests are not ignored"
}

lht_check_net_ipv4_icmp_bogus_errors_ignore() {
  lht_sysctl_check_exact \
    "net.ipv4.icmp_ignore_bogus_error_responses" \
    "1" \
    "Bogus IPv4 ICMP error responses are ignored" \
    "Bogus IPv4 ICMP error responses are not ignored"
}

lht_check_net_ipv4_tcp_syncookies() {
  lht_sysctl_check_exact \
    "net.ipv4.tcp_syncookies" \
    "1" \
    "TCP SYN cookies are enabled" \
    "TCP SYN cookies are disabled"
}

lht_check_net_ipv6_accept_redirects() {
  lht_sysctl_check_conf_zero \
    "ipv6" \
    "accept_redirects" \
    "IPv6 redirects are not accepted" \
    "IPv6 redirect acceptance is enabled"
}

lht_check_net_forwarding() {
  local ipv4_status="unsupported"
  local ipv6_status="unsupported"
  local enabled=""

  if lht_sysctl_read "net.ipv4.ip_forward"; then
    ipv4_status="$LHT_SYSCTL_VALUE"

    if [[ "$ipv4_status" != "0" ]] \
      && [[ "$ipv4_status" != "1" ]]; then

      lht_result \
        "ERROR" \
        "Invalid IPv4 forwarding value" \
        "net.ipv4.ip_forward=${ipv4_status}"
      return 0
    fi

    if [[ "$ipv4_status" == "1" ]]; then
      enabled="$(
        lht_sysctl_append_detail \
          "$enabled" \
          "IPv4"
      )"
    fi
  fi

  if lht_sysctl_read "net.ipv6.conf.all.forwarding"; then
    ipv6_status="$LHT_SYSCTL_VALUE"

    if [[ "$ipv6_status" != "0" ]] \
      && [[ "$ipv6_status" != "1" ]]; then

      lht_result \
        "ERROR" \
        "Invalid IPv6 forwarding value" \
        "net.ipv6.conf.all.forwarding=${ipv6_status}"
      return 0
    fi

    if [[ "$ipv6_status" == "1" ]]; then
      enabled="$(
        lht_sysctl_append_detail \
          "$enabled" \
          "IPv6"
      )"
    fi
  fi

  if [[ "$ipv4_status" == "unsupported" ]] \
    && [[ "$ipv6_status" == "unsupported" ]]; then

    lht_result \
      "SKIP" \
      "IP forwarding state is unavailable" \
      "Neither IPv4 nor IPv6 forwarding parameters were readable"
    return 0
  fi

  if [[ -n "$enabled" ]]; then
    lht_result \
      "WARN" \
      "IP forwarding is enabled" \
      "Enabled families: ${enabled}. Verify that routing is intentional for this host role."
  else
    lht_result \
      "PASS" \
      "IP forwarding is disabled" \
      "IPv4=${ipv4_status}; IPv6=${ipv6_status}"
  fi
}

lht_register_check \
  "sysctl.runtime" \
  "sysctl" \
  "Kernel sysctl runtime interface available" \
  "high" \
  "lht_check_sysctl_runtime"

lht_register_check \
  "kernel.aslr" \
  "kernel" \
  "Full userspace ASLR enabled" \
  "high" \
  "lht_check_kernel_aslr"

lht_register_check \
  "kernel.kptr-restrict" \
  "kernel" \
  "Kernel pointer exposure restricted" \
  "high" \
  "lht_check_kernel_kptr_restrict"

lht_register_check \
  "kernel.dmesg-restrict" \
  "kernel" \
  "Unprivileged kernel log access restricted" \
  "medium" \
  "lht_check_kernel_dmesg_restrict"

lht_register_check \
  "kernel.ptrace-scope" \
  "kernel" \
  "Process tracing restricted" \
  "high" \
  "lht_check_kernel_ptrace_scope"

lht_register_check \
  "fs.protected-hardlinks" \
  "filesystem" \
  "Hardlink protection enabled" \
  "high" \
  "lht_check_fs_protected_hardlinks"

lht_register_check \
  "fs.protected-symlinks" \
  "filesystem" \
  "Symlink protection enabled" \
  "high" \
  "lht_check_fs_protected_symlinks"

lht_register_check \
  "fs.protected-fifos" \
  "filesystem" \
  "FIFO protection enabled" \
  "medium" \
  "lht_check_fs_protected_fifos"

lht_register_check \
  "fs.protected-regular" \
  "filesystem" \
  "Regular-file protection enabled" \
  "medium" \
  "lht_check_fs_protected_regular"

lht_register_check \
  "net.ipv4.accept-redirects" \
  "network" \
  "IPv4 ICMP redirects disabled" \
  "high" \
  "lht_check_net_ipv4_accept_redirects"

lht_register_check \
  "net.ipv4.send-redirects" \
  "network" \
  "IPv4 ICMP redirect sending disabled" \
  "medium" \
  "lht_check_net_ipv4_send_redirects"

lht_register_check \
  "net.ipv4.accept-source-route" \
  "network" \
  "IPv4 source routing disabled" \
  "high" \
  "lht_check_net_ipv4_accept_source_route"

lht_register_check \
  "net.ipv4.rp-filter" \
  "network" \
  "IPv4 reverse-path filtering enabled" \
  "medium" \
  "lht_check_net_ipv4_rp_filter"

lht_register_check \
  "net.ipv4.icmp-broadcast-ignore" \
  "network" \
  "IPv4 broadcast ICMP echo ignored" \
  "medium" \
  "lht_check_net_ipv4_icmp_broadcast_ignore"

lht_register_check \
  "net.ipv4.icmp-bogus-errors-ignore" \
  "network" \
  "Bogus IPv4 ICMP errors ignored" \
  "low" \
  "lht_check_net_ipv4_icmp_bogus_errors_ignore"

lht_register_check \
  "net.ipv4.tcp-syncookies" \
  "network" \
  "TCP SYN cookies enabled" \
  "medium" \
  "lht_check_net_ipv4_tcp_syncookies"

lht_register_check \
  "net.ipv6.accept-redirects" \
  "network" \
  "IPv6 redirects disabled" \
  "high" \
  "lht_check_net_ipv6_accept_redirects"

lht_register_check \
  "net.forwarding" \
  "network" \
  "IP forwarding reviewed" \
  "medium" \
  "lht_check_net_forwarding"
