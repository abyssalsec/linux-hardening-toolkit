#!/usr/bin/env bash

LHT_FIREWALL_COLLECTED=0
LHT_FIREWALL_BACKEND=""
LHT_FIREWALL_STATE="unknown"
LHT_FIREWALL_RULESET=""
LHT_FIREWALL_INPUT_POLICY="unknown"
LHT_FIREWALL_FORWARD_POLICY="unknown"

lht_firewall_nft_hook_policy() {
  local hook="${1:?hook is required}"
  local ruleset="${2-}"

  printf '%s\n' "$ruleset" | awk -v wanted_hook="$hook" '
    /^[[:space:]]*chain[[:space:]]+/ {
      in_chain=1
      has_hook=0
      explicit_policy=""
    }

    in_chain {
      if ($0 ~ ("hook[[:space:]]+" wanted_hook "([[:space:];]|$)")) {
        has_hook=1
      }

      if ($0 ~ /policy[[:space:]]+(accept|drop|reject)[[:space:]]*;/) {
        line=$0
        sub(/^.*policy[[:space:]]+/, "", line)
        sub(/[[:space:];].*$/, "", line)
        explicit_policy=tolower(line)
      }
    }

    in_chain && /^[[:space:]]*}/ {
      if (has_hook) {
        if (explicit_policy != "") {
          print explicit_policy
        } else {
          print "accept"
        }

        exit
      }

      in_chain=0
      has_hook=0
      explicit_policy=""
    }
  '
}

lht_firewall_use_ufw() {
  local output="${1-}"
  local state="${2:-unknown}"
  local default_line=""

  LHT_FIREWALL_BACKEND="ufw"
  LHT_FIREWALL_STATE="$state"
  LHT_FIREWALL_RULESET="$output"

  default_line="$(
    printf '%s\n' "$output" |
      awk -F': ' '/^Default:/ { print $2; exit }'
  )"

  if [[ "$default_line" =~ (deny|reject|allow)[[:space:]]+\(incoming\) ]]; then
    LHT_FIREWALL_INPUT_POLICY="${BASH_REMATCH[1]}"
  fi

  if [[ "$default_line" =~ (deny|reject|allow|disabled)[[:space:]]+\(routed\) ]]; then
    LHT_FIREWALL_FORWARD_POLICY="${BASH_REMATCH[1]}"
  fi
}

lht_firewall_use_firewalld() {
  local state="${1:-unknown}"
  local zones=""
  local zone=""
  local target=""
  local forward=""
  local input_policy="unknown"
  local forward_policy="disabled"

  LHT_FIREWALL_BACKEND="firewalld"
  LHT_FIREWALL_STATE="$state"

  if [[ "$state" != "active" ]]; then
    return 0
  fi

  zones="$(
    firewall-cmd --get-active-zones 2>/dev/null |
      awk '/^[^[:space:]]/ { print $1 }'
  )"

  if [[ -n "$zones" ]]; then
    input_policy="default"

    while IFS= read -r zone; do
      [[ -n "$zone" ]] || continue

      target="$(
        firewall-cmd --zone="$zone" --get-target 2>/dev/null |
          tr '[:upper:]' '[:lower:]'
      )"

      case "$target" in
        accept)
          input_policy="accept"
          ;;
        drop|reject)
          if [[ "$input_policy" != "accept" ]]; then
            input_policy="$target"
          fi
          ;;
        default|"")
          ;;
        *)
          input_policy="unknown"
          ;;
      esac

      forward="$(
        firewall-cmd --zone="$zone" --query-forward 2>/dev/null |
          tr '[:upper:]' '[:lower:]'
      )"

      if [[ "$forward" == "yes" ]]; then
        forward_policy="enabled"
      fi
    done <<< "$zones"
  fi

  LHT_FIREWALL_INPUT_POLICY="$input_policy"
  LHT_FIREWALL_FORWARD_POLICY="$forward_policy"
  LHT_FIREWALL_RULESET="$(
    firewall-cmd --list-all-zones 2>/dev/null || true
  )"
}

lht_firewall_use_nftables() {
  local ruleset="${1-}"
  local state="${2:-unknown}"
  local policy=""

  LHT_FIREWALL_BACKEND="nftables"
  LHT_FIREWALL_STATE="$state"
  LHT_FIREWALL_RULESET="$ruleset"

  policy="$(lht_firewall_nft_hook_policy "input" "$ruleset")"
  [[ -n "$policy" ]] && LHT_FIREWALL_INPUT_POLICY="$policy"

  policy="$(lht_firewall_nft_hook_policy "forward" "$ruleset")"
  [[ -n "$policy" ]] && LHT_FIREWALL_FORWARD_POLICY="$policy"
}

lht_firewall_use_iptables() {
  local ruleset="${1-}"
  local state="${2:-unknown}"
  local policy=""

  LHT_FIREWALL_BACKEND="iptables"
  LHT_FIREWALL_STATE="$state"
  LHT_FIREWALL_RULESET="$ruleset"

  policy="$(
    printf '%s\n' "$ruleset" |
      awk '$1 == "-P" && $2 == "INPUT" { print tolower($3); exit }'
  )"

  [[ -n "$policy" ]] && LHT_FIREWALL_INPUT_POLICY="$policy"

  policy="$(
    printf '%s\n' "$ruleset" |
      awk '$1 == "-P" && $2 == "FORWARD" { print tolower($3); exit }'
  )"

  [[ -n "$policy" ]] && LHT_FIREWALL_FORWARD_POLICY="$policy"
}

lht_firewall_collect() {
  if (( LHT_FIREWALL_COLLECTED == 1 )); then
    return 0
  fi

  LHT_FIREWALL_COLLECTED=1

  local output=""
  local candidate_backend=""
  local candidate_output=""

  #
  # Prefer high-level firewall managers when active.
  #

  if command -v ufw >/dev/null 2>&1; then
    if output="$(ufw status verbose 2>&1)"; then
      if grep -Eqi '^Status:[[:space:]]*active' <<< "$output"; then
        lht_firewall_use_ufw "$output" "active"
        return 0
      fi

      if grep -Eqi '^Status:[[:space:]]*inactive' <<< "$output"; then
        candidate_backend="ufw"
        candidate_output="$output"
      fi
    fi
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    if output="$(firewall-cmd --state 2>/dev/null)"; then
      if [[ "$(lht_trim "$output")" == "running" ]]; then
        lht_firewall_use_firewalld "active"
        return 0
      fi
    elif [[ -z "$candidate_backend" ]]; then
      candidate_backend="firewalld"
    fi
  fi

  #
  # Native nftables.
  #

  if command -v nft >/dev/null 2>&1; then
    if output="$(nft list ruleset 2>&1)"; then
      if grep -Eq \
        'hook[[:space:]]+input([[:space:];]|$)' \
        <<< "$output"; then

        lht_firewall_use_nftables "$output" "active"
        return 0
      fi

      if [[ -z "$candidate_backend" ]]; then
        candidate_backend="nftables"
        candidate_output="$output"
      fi
    fi
  fi

  #
  # Legacy/direct iptables.
  #

  if command -v iptables >/dev/null 2>&1; then
    if output="$(iptables -S 2>&1)"; then
      if grep -Eq '^-A[[:space:]]+INPUT([[:space:]]|$)' <<< "$output" ||
        grep -Eq \
          '^-P[[:space:]]+INPUT[[:space:]]+(DROP|REJECT)([[:space:]]|$)' \
          <<< "$output"; then

        lht_firewall_use_iptables "$output" "active"
        return 0
      fi

      if [[ -z "$candidate_backend" ]]; then
        candidate_backend="iptables"
        candidate_output="$output"
      fi
    fi
  fi

  #
  # A firewall implementation exists, but no active filtering was found.
  #

  case "$candidate_backend" in
    ufw)
      lht_firewall_use_ufw "$candidate_output" "inactive"
      ;;

    firewalld)
      lht_firewall_use_firewalld "inactive"
      ;;

    nftables)
      lht_firewall_use_nftables "$candidate_output" "inactive"
      ;;

    iptables)
      lht_firewall_use_iptables "$candidate_output" "inactive"
      ;;

    *)
      LHT_FIREWALL_BACKEND="none"
      LHT_FIREWALL_STATE="inactive"
      ;;
  esac
}

lht_check_firewall_backend() {
  lht_firewall_collect

  if [[ "$LHT_FIREWALL_BACKEND" == "none" ]]; then
    lht_result \
      "WARN" \
      "No supported host firewall backend was detected" \
      "Checked UFW, firewalld, nftables, and iptables"
    return 0
  fi

  lht_result \
    "PASS" \
    "Host firewall backend detected" \
    "backend=${LHT_FIREWALL_BACKEND}; state=${LHT_FIREWALL_STATE}"
}

lht_check_firewall_active() {
  lht_firewall_collect

  if [[ "$LHT_FIREWALL_STATE" == "active" ]]; then
    lht_result \
      "PASS" \
      "Host firewall filtering is active" \
      "backend=${LHT_FIREWALL_BACKEND}"
  else
    lht_result \
      "FAIL" \
      "Host firewall filtering is not active" \
      "backend=${LHT_FIREWALL_BACKEND}; state=${LHT_FIREWALL_STATE}"
  fi
}

lht_check_firewall_default_input() {
  lht_firewall_collect

  if [[ "$LHT_FIREWALL_STATE" != "active" ]]; then
    lht_result \
      "SKIP" \
      "Default inbound firewall policy cannot be evaluated" \
      "Firewall is not active"
    return 0
  fi

  case "$LHT_FIREWALL_INPUT_POLICY" in
    deny|drop|reject|default)
      lht_result \
        "PASS" \
        "Default inbound firewall policy is restrictive" \
        "backend=${LHT_FIREWALL_BACKEND}; policy=${LHT_FIREWALL_INPUT_POLICY}"
      ;;

    allow|accept)
      lht_result \
        "FAIL" \
        "Default inbound firewall policy permits unsolicited traffic" \
        "backend=${LHT_FIREWALL_BACKEND}; policy=${LHT_FIREWALL_INPUT_POLICY}"
      ;;

    *)
      lht_result \
        "WARN" \
        "Default inbound firewall policy requires manual review" \
        "backend=${LHT_FIREWALL_BACKEND}; policy=${LHT_FIREWALL_INPUT_POLICY}"
      ;;
  esac
}

lht_check_firewall_default_forward() {
  lht_firewall_collect

  if [[ "$LHT_FIREWALL_STATE" != "active" ]]; then
    lht_result \
      "SKIP" \
      "Default forwarding firewall policy cannot be evaluated" \
      "Firewall is not active"
    return 0
  fi

  case "$LHT_FIREWALL_FORWARD_POLICY" in
    deny|drop|reject|disabled)
      lht_result \
        "PASS" \
        "Default forwarding policy is restrictive" \
        "backend=${LHT_FIREWALL_BACKEND}; policy=${LHT_FIREWALL_FORWARD_POLICY}"
      ;;

    allow|accept|enabled)
      lht_result \
        "WARN" \
        "Firewall forwarding is permissive or enabled" \
        "backend=${LHT_FIREWALL_BACKEND}; policy=${LHT_FIREWALL_FORWARD_POLICY}. Verify that routing is intentional for this host role."
      ;;

    *)
      lht_result \
        "WARN" \
        "Default forwarding policy requires manual review" \
        "backend=${LHT_FIREWALL_BACKEND}; policy=${LHT_FIREWALL_FORWARD_POLICY}"
      ;;
  esac
}

lht_check_firewall_ruleset() {
  lht_firewall_collect

  if [[ "$LHT_FIREWALL_STATE" != "active" ]]; then
    lht_result \
      "SKIP" \
      "Firewall ruleset inspection was skipped" \
      "Firewall is not active"
    return 0
  fi

  if [[ -n "$(lht_trim "$LHT_FIREWALL_RULESET")" ]]; then
    lht_result \
      "PASS" \
      "Active firewall ruleset is readable" \
      "backend=${LHT_FIREWALL_BACKEND}"
  else
    lht_result \
      "WARN" \
      "Active firewall ruleset could not be inspected" \
      "backend=${LHT_FIREWALL_BACKEND}"
  fi
}

lht_check_firewall_listeners() {
  if ! command -v ss >/dev/null 2>&1; then
    lht_result \
      "SKIP" \
      "Listening network services could not be inventoried" \
      "The ss command is not available"
    return 0
  fi

  local output=""
  local listener_count=""
  local wildcard_count=""
  local wildcard_endpoints=""

  if ! output="$(ss -H -lntu 2>/dev/null)"; then
    lht_result \
      "ERROR" \
      "Listening network services could not be inventoried" \
      "ss -H -lntu failed"
    return 0
  fi

  if ! listener_count="$(
    printf '%s\n' "$output" |
      awk 'NF { count++ } END { print count+0 }'
  )"; then
    lht_result \
      "ERROR" \
      "Listening network services could not be evaluated" \
      "Failed to count listening sockets"
    return 0
  fi

  if ! wildcard_count="$(
    printf '%s\n' "$output" |
      awk '
        NF {
          addr=$5
          if (addr ~ /^(0\.0\.0\.0:|\[::\]:|\*:|:::)/) {
            count++
          }
        }
        END { print count+0 }
      '
  )"; then
    lht_result \
      "ERROR" \
      "Listening network services could not be evaluated" \
      "Failed to inspect wildcard listeners"
    return 0
  fi

  if ! wildcard_endpoints="$(
    printf '%s\n' "$output" |
      awk '
        NF {
          addr=$5
          if (addr ~ /^(0\.0\.0\.0:|\[::\]:|\*:|:::)/) {
            print $1 ":" addr
          }
        }
      ' |
      sort -u |
      head -n 8 |
      paste -sd ',' -
  )"; then
    lht_result \
      "ERROR" \
      "Listening network services could not be evaluated" \
      "Failed to build wildcard listener inventory"
    return 0
  fi

  if (( wildcard_count > 0 )); then
    lht_result \
      "WARN" \
      "Network services are listening on wildcard addresses" \
      "listeners=${listener_count}; wildcard=${wildcard_count}; endpoints=${wildcard_endpoints:-unknown}. Verify exposure against the intended firewall policy."
  else
    lht_result \
      "PASS" \
      "No wildcard network listeners were detected" \
      "listeners=${listener_count}"
  fi
}

lht_register_check \
  "firewall.backend" \
  "firewall" \
  "Host firewall backend detected" \
  "info" \
  "lht_check_firewall_backend"

lht_register_check \
  "firewall.active" \
  "firewall" \
  "Host firewall filtering active" \
  "high" \
  "lht_check_firewall_active"

lht_register_check \
  "firewall.default-input" \
  "firewall" \
  "Default inbound firewall policy restrictive" \
  "high" \
  "lht_check_firewall_default_input"

lht_register_check \
  "firewall.default-forward" \
  "firewall" \
  "Default forwarding firewall policy reviewed" \
  "medium" \
  "lht_check_firewall_default_forward"

lht_register_check \
  "firewall.ruleset" \
  "firewall" \
  "Active firewall ruleset readable" \
  "medium" \
  "lht_check_firewall_ruleset"

lht_register_check \
  "firewall.listeners" \
  "firewall" \
  "Listening network services reviewed" \
  "info" \
  "lht_check_firewall_listeners"
