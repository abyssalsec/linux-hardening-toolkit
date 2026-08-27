#!/usr/bin/env bash

set -uo pipefail

TEST_ROOT="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 || exit 1
  pwd -P
)"

cd "$TEST_ROOT" || exit 1

# shellcheck source=tests/lib/testlib.sh
source "${TEST_ROOT}/tests/lib/testlib.sh"

expected_version="$(<VERSION)"

actual_version="$(
  ./bin/linux-hardening-toolkit --version
)"

assert_eq \
  "$expected_version" \
  "$actual_version" \
  "--version matches VERSION file"

help_output="$(
  ./bin/linux-hardening-toolkit --help
)"

assert_contains \
  "$help_output" \
  "Usage:" \
  "help displays usage"

assert_contains \
  "$help_output" \
  "--format FORMAT" \
  "help documents output format"

assert_contains \
  "$help_output" \
  "--output PATH" \
  "help documents report output path"

set +e

invalid_output="$(
  ./bin/linux-hardening-toolkit \
    --format yaml \
    audit 2>&1
)"
invalid_rc=$?

set -e

assert_eq \
  "1" \
  "$invalid_rc" \
  "unsupported format returns exit code 1"

assert_contains \
  "$invalid_output" \
  "Unsupported output format" \
  "unsupported format reports useful error"

set +e

invalid_output="$(
  ./bin/linux-hardening-toolkit \
    --output /tmp/lht-invalid.json \
    audit 2>&1
)"
invalid_rc=$?

set -e

assert_eq \
  "1" \
  "$invalid_rc" \
  "--output without JSON returns exit code 1"

catalog="$(
  ./bin/linux-hardening-toolkit \
    --profile default \
    list-checks
)"

assert_contains \
  "$catalog" \
  "CHECK ID" \
  "list-checks prints catalog header"

assert_contains \
  "$catalog" \
  "ssh.root-login" \
  "list-checks contains registered SSH checks"

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

json_report="${temp_dir}/updates.json"

set +e

./bin/linux-hardening-toolkit \
  --profile updates \
  --format json \
  --output "$json_report" \
  audit

audit_rc=$?

set -e

if [[ "$audit_rc" == "0" || "$audit_rc" == "2" ]]; then
  test_pass "JSON audit completes without execution error"
else
  test_fail \
    "JSON audit completes without execution error (rc=${audit_rc})"
fi

assert_file_exists \
  "$json_report" \
  "CLI writes requested JSON report"

report_mode="$(stat -c '%a' "$json_report")"

assert_eq \
  "600" \
  "$report_mode" \
  "CLI JSON report uses mode 0600"

if python3 - "$json_report" "$audit_rc" <<'PY'
import json
import sys

path = sys.argv[1]
process_rc = int(sys.argv[2])

with open(path, encoding="utf-8") as f:
    report = json.load(f)

assert report["schema_version"] == "1"
assert report["audit"]["profile_id"] == "updates"
assert report["summary"]["exit_code"] == process_rc
assert isinstance(report["checks"], list)
assert len(report["checks"]) > 0

required = {
    "id",
    "category",
    "severity",
    "title",
    "status",
    "message",
    "details",
    "remediation_available",
}

for check in report["checks"]:
    assert required.issubset(check)
PY
then
  test_pass "CLI JSON report satisfies integration expectations"
else
  test_fail "CLI JSON report satisfies integration expectations"
fi

set +e

text_output="$(
  ./bin/linux-hardening-toolkit \
    --profile updates \
    audit 2>&1
)"

text_rc=$?

set -e

if [[ "$text_rc" == "0" || "$text_rc" == "2" ]]; then
  test_pass "text audit completes without execution error"
else
  test_fail \
    "text audit completes without execution error (rc=${text_rc})"
fi

assert_contains \
  "$text_output" \
  "Linux Hardening Toolkit v${expected_version}" \
  "text renderer prints toolkit version"

assert_contains \
  "$text_output" \
  "Summary: PASS=" \
  "text renderer prints audit summary"


set +e

no_banner_help="$(
  ./bin/linux-hardening-toolkit \
    --no-banner \
    --help 2>&1
)"

no_banner_rc=$?

set -e

assert_eq \
  "0" \
  "$no_banner_rc" \
  "--no-banner is accepted by CLI"

assert_contains \
  "$no_banner_help" \
  "--no-banner" \
  "help documents --no-banner"

finish_tests
