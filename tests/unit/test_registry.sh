#!/usr/bin/env bash

set -uo pipefail

TEST_ROOT="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 || exit 1
  pwd -P
)"

# shellcheck source=tests/lib/testlib.sh
source "${TEST_ROOT}/tests/lib/testlib.sh"

lht_die() {
  local message="${1:?message is required}"
  local rc="${2:-1}"

  printf 'ERROR: %s\n' "$message" >&2
  exit "$rc"
}

lht_log_debug() {
  :
}

test_audit_function() {
  :
}

test_apply_function() {
  :
}

# shellcheck source=lib/core/registry.sh
source "${TEST_ROOT}/lib/core/registry.sh"

lht_register_check \
  "test.registry" \
  "test" \
  "Registry test check" \
  "high" \
  "test_audit_function"

assert_eq \
  "1" \
  "${#LHT_CHECK_IDS[@]}" \
  "registry stores registered check"

assert_eq \
  "test" \
  "${LHT_CHECK_CATEGORY[test.registry]}" \
  "registry stores check category"

assert_eq \
  "Registry test check" \
  "${LHT_CHECK_TITLE[test.registry]}" \
  "registry stores check title"

assert_eq \
  "high" \
  "${LHT_CHECK_SEVERITY[test.registry]}" \
  "registry stores check severity"

assert_eq \
  "test_audit_function" \
  "${LHT_CHECK_AUDIT_FN[test.registry]}" \
  "registry stores audit function"

assert_eq \
  "" \
  "${LHT_CHECK_APPLY_FN[test.registry]}" \
  "remediation is optional"

lht_register_check \
  "test.remediation" \
  "test" \
  "Remediation test check" \
  "medium" \
  "test_audit_function" \
  "test_apply_function"

assert_eq \
  "test_apply_function" \
  "${LHT_CHECK_APPLY_FN[test.remediation]}" \
  "registry stores remediation function"

if (
  lht_register_check \
    "test.registry" \
    "test" \
    "Duplicate" \
    "high" \
    "test_audit_function"
) >/dev/null 2>&1; then
  test_fail "registry rejects duplicate check IDs"
else
  test_pass "registry rejects duplicate check IDs"
fi

if (
  lht_register_check \
    "INVALID CHECK" \
    "test" \
    "Invalid ID" \
    "high" \
    "test_audit_function"
) >/dev/null 2>&1; then
  test_fail "registry rejects invalid check IDs"
else
  test_pass "registry rejects invalid check IDs"
fi

if (
  lht_register_check \
    "test.invalid-severity" \
    "test" \
    "Invalid severity" \
    "extreme" \
    "test_audit_function"
) >/dev/null 2>&1; then
  test_fail "registry rejects invalid severity"
else
  test_pass "registry rejects invalid severity"
fi

finish_tests
