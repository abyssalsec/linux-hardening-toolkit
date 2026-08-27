#!/usr/bin/env bash

LHT_SERVICES_ACTIVE_UNITS=""
LHT_SERVICES_PROCESS_LIST=""
LHT_SERVICES_COLLECTED=0

lht_services_append_detail() {
  local current="${1-}"
  local item="${2-}"

  if [[ -z "$current" ]]; then
    printf '%s' "$item"
  else
    printf '%s; %s' "$current" "$item"
  fi
}

lht_services_systemd_available() {
  command -v systemctl >/dev/null 2>&1 \
    && [[ -d /run/systemd/system ]]
}

lht_services_collect() {
  if (( LHT_SERVICES_COLLECTED == 1 )); then
    return 0
  fi

  LHT_SERVICES_COLLECTED=1

  if lht_services_systemd_available; then
    LHT_SERVICES_ACTIVE_UNITS="$(
      systemctl list-units \
        --type=service \
        --type=socket \
        --state=active \
        --no-legend \
        --no-pager \
        2>/dev/null || true
    )"
  fi

  if command -v ps >/dev/null 2>&1; then
    LHT_SERVICES_PROCESS_LIST="$(
      ps -eo comm= 2>/dev/null || true
    )"
  fi
}

lht_services_active_unit_matches() {
  local regex="${1:?regex is required}"

  lht_services_collect

  [[ -n "$LHT_SERVICES_ACTIVE_UNITS" ]] || return 1

  printf '%s\n' "$LHT_SERVICES_ACTIVE_UNITS" |
    awk '{print $1}' |
    grep -Eiq "$regex"
}

lht_services_process_matches() {
  local regex="${1:?regex is required}"

  lht_services_collect

  [[ -n "$LHT_SERVICES_PROCESS_LIST" ]] || return 1

  printf '%s\n' "$LHT_SERVICES_PROCESS_LIST" |
    grep -Eiq "$regex"
}

lht_services_matching_units() {
  local regex="${1:?regex is required}"

  lht_services_collect

  printf '%s\n' "$LHT_SERVICES_ACTIVE_UNITS" |
    awk '{print $1}' |
    grep -Ei "$regex" |
    sort -u |
    paste -sd ',' - || true
}

lht_services_matching_processes() {
  local regex="${1:?regex is required}"

  lht_services_collect

  printf '%s\n' "$LHT_SERVICES_PROCESS_LIST" |
    grep -Ei "$regex" |
    sort -u |
    paste -sd ',' - || true
}

lht_services_inetd_legacy_entries() {
  local file="/etc/inetd.conf"

  [[ -r "$file" ]] || return 1

  awk '
    /^[[:space:]]*#/ {
      next
    }

    NF == 0 {
      next
    }

    $1 ~ /^(telnet|shell|login|exec|rsh|rlogin|rexec)$/ {
      print $1
    }
  ' "$file"
}

lht_check_services_systemd_runtime() {
  if ! command -v systemctl >/dev/null 2>&1; then
    lht_result \
      "SKIP" \
      "systemd service manager is not available" \
      "systemctl command was not found"
    return 0
  fi

  if [[ ! -d /run/systemd/system ]]; then
    lht_result \
      "SKIP" \
      "systemd is not the active service manager" \
      "/run/systemd/system is not available"
    return 0
  fi

  if ! systemctl list-units \
    --type=service \
    --no-legend \
    --no-pager \
    >/dev/null 2>&1; then

    lht_result \
      "ERROR" \
      "systemd service state could not be queried" \
      "systemctl list-units failed"
    return 0
  fi

  lht_result \
    "PASS" \
    "systemd service state is available" \
    "Active and failed service units can be audited"
}

lht_check_services_failed_units() {
  if ! lht_services_systemd_available; then
    lht_result \
      "SKIP" \
      "Failed systemd services could not be evaluated" \
      "systemd is not available"
    return 0
  fi

  local output=""
  local count=0
  local sample=""

  if ! output="$(
    systemctl list-units \
      --type=service \
      --state=failed \
      --no-legend \
      --no-pager \
      2>/dev/null
  )"; then
    lht_result \
      "ERROR" \
      "Failed systemd services could not be queried" \
      "systemctl failed while collecting failed units"
    return 0
  fi

  count="$(
    printf '%s\n' "$output" |
      awk 'NF { count++ } END { print count+0 }'
  )"

  if (( count == 0 )); then
    lht_result \
      "PASS" \
      "No failed systemd services were detected" \
      "failed=0"
    return 0
  fi

  sample="$(
    printf '%s\n' "$output" |
      awk 'NF {print $1}' |
      head -n 8 |
      paste -sd ',' -
  )"

  lht_result \
    "WARN" \
    "One or more systemd services are in failed state" \
    "failed=${count}; units=${sample:-unknown}"
}

lht_check_services_network_listeners() {
  if ! command -v ss >/dev/null 2>&1; then
    lht_result \
      "SKIP" \
      "Network listener inventory could not be collected" \
      "The ss command is not available"
    return 0
  fi

  local output=""
  local total=""
  local exposed=""
  local sample=""

  if ! output="$(ss -H -lntup 2>/dev/null)"; then
    lht_result \
      "ERROR" \
      "Network listener inventory could not be collected" \
      "ss -H -lntup failed"
    return 0
  fi

  if ! total="$(
    printf '%s\n' "$output" |
      awk 'NF { count++ } END { print count+0 }'
  )"; then
    lht_result \
      "ERROR" \
      "Network listener inventory could not be evaluated" \
      "Failed to count listening sockets"
    return 0
  fi

  if ! exposed="$(
    printf '%s\n' "$output" |
      awk '
        NF {
          addr=$5
          if (addr !~ /^127\./ && addr !~ /^\[::1\]:/ && addr !~ /^::1:/ &&
              !($1 == "udp" && (addr ~ /:68$/ || addr ~ /:546$/))) {
            count++
          }
        }
        END { print count+0 }
      '
  )"; then
    lht_result \
      "ERROR" \
      "Network listener exposure could not be evaluated" \
      "Failed to classify listening socket addresses"
    return 0
  fi

  if ! sample="$(
    printf '%s\n' "$output" |
      awk '
        NF {
          addr=$5
          if (addr !~ /^127\./ && addr !~ /^\[::1\]:/ && addr !~ /^::1:/ &&
              !($1 == "udp" && (addr ~ /:68$/ || addr ~ /:546$/))) {
            line=$0
            gsub(/[[:space:]]+/, " ", line)
            print line
          }
        }
      ' |
      head -n 6 |
      paste -sd ';' -
  )"; then
    lht_result \
      "ERROR" \
      "Network listener exposure could not be evaluated" \
      "Failed to build listener inventory"
    return 0
  fi

  if (( exposed == 0 )); then
    lht_result \
      "PASS" \
      "No non-loopback network listeners were detected" \
      "listeners=${total}"
    return 0
  fi

  lht_result \
    "WARN" \
    "Network services are listening beyond loopback interfaces" \
    "listeners=${total}; non-loopback=${exposed}; sample=${sample:-unavailable}"
}

lht_check_services_insecure_remote() {
  lht_services_collect

  local unit_regex='^(telnet|telnetd|rsh|rshd|rlogin|rlogind|rexec|rexecd)(@[^[:space:]]+)?\.(service|socket)$'
  local process_regex='^(in\.)?(telnetd|rshd|rlogind|rexecd)$'

  local units=""
  local processes=""
  local inetd=""
  local findings=""

  units="$(lht_services_matching_units "$unit_regex")"
  processes="$(lht_services_matching_processes "$process_regex")"
  inetd="$(
    lht_services_inetd_legacy_entries 2>/dev/null |
      paste -sd ',' - || true
  )"

  if [[ -n "$units" ]]; then
    findings="$(
      lht_services_append_detail \
        "$findings" \
        "units=${units}"
    )"
  fi

  if [[ -n "$processes" ]]; then
    findings="$(
      lht_services_append_detail \
        "$findings" \
        "processes=${processes}"
    )"
  fi

  if [[ -n "$inetd" ]]; then
    findings="$(
      lht_services_append_detail \
        "$findings" \
        "inetd=${inetd}"
    )"
  fi

  if [[ -n "$findings" ]]; then
    lht_result \
      "FAIL" \
      "Insecure legacy remote-access services are active" \
      "${findings}. Telnet and r-services transmit authentication or session data without modern transport security."
    return 0
  fi

  lht_result \
    "PASS" \
    "No active Telnet or r-services were detected" \
    "Checked active systemd units, processes, and /etc/inetd.conf"
}

lht_check_services_file_transfer() {
  lht_services_collect

  local unit_regex='^(vsftpd|proftpd|pure-ftpd|tftp|tftpd|tftpd-hpa|atftpd)(@[^[:space:]]+)?\.(service|socket)$'
  local process_regex='^(vsftpd|proftpd|pure-ftpd|in\.tftpd|tftpd|atftpd)$'

  local units=""
  local processes=""
  local findings=""

  units="$(lht_services_matching_units "$unit_regex")"
  processes="$(lht_services_matching_processes "$process_regex")"

  if [[ -n "$units" ]]; then
    findings="$(
      lht_services_append_detail \
        "$findings" \
        "units=${units}"
    )"
  fi

  if [[ -n "$processes" ]]; then
    findings="$(
      lht_services_append_detail \
        "$findings" \
        "processes=${processes}"
    )"
  fi

  if [[ -z "$findings" ]]; then
    lht_result \
      "PASS" \
      "No active FTP or TFTP server services were detected" \
      "No known FTP/TFTP server unit or process is active"
    return 0
  fi

  lht_result \
    "WARN" \
    "FTP or TFTP server services require security review" \
    "${findings}. Verify that cleartext or unauthenticated file-transfer protocols are required for this host role."
}

lht_check_services_discovery_rpc() {
  lht_services_collect

  local unit_regex='^(rpcbind|avahi-daemon)(@[^[:space:]]+)?\.(service|socket)$'
  local process_regex='^(rpcbind|avahi-daemon)$'

  local units=""
  local processes=""
  local findings=""

  units="$(lht_services_matching_units "$unit_regex")"
  processes="$(lht_services_matching_processes "$process_regex")"

  if [[ -n "$units" ]]; then
    findings="$(
      lht_services_append_detail \
        "$findings" \
        "units=${units}"
    )"
  fi

  if [[ -n "$processes" ]]; then
    findings="$(
      lht_services_append_detail \
        "$findings" \
        "processes=${processes}"
    )"
  fi

  if [[ -z "$findings" ]]; then
    lht_result \
      "PASS" \
      "No RPC binder or multicast discovery daemon is active" \
      "rpcbind and avahi-daemon were not detected"
    return 0
  fi

  lht_result \
    "WARN" \
    "Network discovery or RPC services increase host attack surface" \
    "${findings}. Verify that these services are required for the intended server role."
}

lht_check_services_inetd() {
  lht_services_collect

  local unit_regex='^(xinetd|inetd|openbsd-inetd)\.(service|socket)$'
  local process_regex='^(xinetd|inetd)$'

  local units=""
  local processes=""
  local findings=""

  units="$(lht_services_matching_units "$unit_regex")"
  processes="$(lht_services_matching_processes "$process_regex")"

  if [[ -n "$units" ]]; then
    findings="$(
      lht_services_append_detail \
        "$findings" \
        "units=${units}"
    )"
  fi

  if [[ -n "$processes" ]]; then
    findings="$(
      lht_services_append_detail \
        "$findings" \
        "processes=${processes}"
    )"
  fi

  if [[ -z "$findings" ]]; then
    lht_result \
      "PASS" \
      "No inetd-style superserver is active" \
      "inetd and xinetd were not detected"
    return 0
  fi

  lht_result \
    "WARN" \
    "An inetd-style service superserver is active" \
    "${findings}. Review every service exposed through the superserver configuration."
}

lht_register_check \
  "services.systemd-runtime" \
  "services" \
  "systemd service state available" \
  "info" \
  "lht_check_services_systemd_runtime"

lht_register_check \
  "services.failed-units" \
  "services" \
  "Failed system services reviewed" \
  "medium" \
  "lht_check_services_failed_units"

lht_register_check \
  "services.network-listeners" \
  "services" \
  "Network service exposure reviewed" \
  "medium" \
  "lht_check_services_network_listeners"

lht_register_check \
  "services.insecure-remote" \
  "services" \
  "Legacy remote-access services disabled" \
  "critical" \
  "lht_check_services_insecure_remote"

lht_register_check \
  "services.file-transfer" \
  "services" \
  "FTP and TFTP services reviewed" \
  "medium" \
  "lht_check_services_file_transfer"

lht_register_check \
  "services.discovery-rpc" \
  "services" \
  "Discovery and RPC services reviewed" \
  "medium" \
  "lht_check_services_discovery_rpc"

lht_register_check \
  "services.inetd" \
  "services" \
  "inetd-style superservers reviewed" \
  "high" \
  "lht_check_services_inetd"
