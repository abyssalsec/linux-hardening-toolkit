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

LHT_VERSION="test-version"
LHT_PROFILE_NAME="test"
LHT_PROFILE_DISPLAY_NAME="Test profile"
LHT_PROFILE_DESCRIPTION="Test audit profile"
LHT_DRY_RUN=0
LHT_OUTPUT_PATH=""

declare -Ag LHT_CHECK_CATEGORY=()
declare -Ag LHT_CHECK_TITLE=()
declare -Ag LHT_CHECK_SEVERITY=()
declare -Ag LHT_CHECK_APPLY_FN=()

LHT_CHECK_CATEGORY["test.pass"]="test"
LHT_CHECK_TITLE["test.pass"]="Passing check"
LHT_CHECK_SEVERITY["test.pass"]="low"
LHT_CHECK_APPLY_FN["test.pass"]=""

LHT_CHECK_CATEGORY["test.fail"]="test"
LHT_CHECK_TITLE["test.fail"]="Failing check"
LHT_CHECK_SEVERITY["test.fail"]="high"
LHT_CHECK_APPLY_FN["test.fail"]=""

# shellcheck source=lib/core/report.sh
source "${TEST_ROOT}/lib/core/report.sh"

lht_reset_audit_report

LHT_AUDIT_GENERATED_AT="2026-01-01T00:00:00Z"

lht_record_audit_result \
  "test.pass" \
  "PASS" \
  "Everything is fine" \
  "value=1"

lht_record_audit_result \
  "test.fail" \
  "FAIL" \
  'Quote " and backslash \ test' \
  $'line one\nline two'

lht_finalize_audit_report

assert_eq \
  "1" \
  "$LHT_AUDIT_PASS_COUNT" \
  "report counts PASS results"

assert_eq \
  "1" \
  "$LHT_AUDIT_FAIL_COUNT" \
  "report counts FAIL results"

assert_eq \
  "0" \
  "$LHT_AUDIT_ERROR_COUNT" \
  "report starts without execution errors"

assert_eq \
  "2" \
  "$LHT_AUDIT_EXIT_CODE" \
  "FAIL result produces audit exit code 2"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

LHT_OUTPUT_PATH="${temp_dir}/report.json"

lht_write_json_report

assert_file_exists \
  "$LHT_OUTPUT_PATH" \
  "JSON report file is created"

mode="$(stat -c '%a' "$LHT_OUTPUT_PATH")"

assert_eq \
  "600" \
  "$mode" \
  "JSON report file uses mode 0600"

if python3 - "$LHT_OUTPUT_PATH" <<'PY'
import json
import sys

path = sys.argv[1]

with open(path, encoding="utf-8") as f:
    report = json.load(f)

assert report["schema_version"] == "1"
assert report["tool"]["version"] == "test-version"
assert report["audit"]["profile_id"] == "test"
assert report["summary"]["pass"] == 1
assert report["summary"]["fail"] == 1
assert report["summary"]["error"] == 0
assert report["summary"]["exit_code"] == 2

assert len(report["checks"]) == 2

failed = report["checks"][1]

assert failed["id"] == "test.fail"
assert failed["severity"] == "high"
assert failed["status"] == "FAIL"
assert failed["message"] == 'Quote " and backslash \\ test'
assert failed["details"] == "line one\nline two"
assert failed["remediation_available"] is False
PY
then
  test_pass "JSON report is valid and preserves structured data"
else
  test_fail "JSON report is valid and preserves structured data"
fi

lht_reset_audit_report

lht_record_audit_result \
  "test.pass" \
  "ERROR" \
  "Execution failure" \
  "test error"

lht_finalize_audit_report

assert_eq \
  "1" \
  "$LHT_AUDIT_EXIT_CODE" \
  "ERROR result takes precedence with exit code 1"

finish_tests
