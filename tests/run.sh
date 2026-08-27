#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 || exit 1
  pwd -P
)"

cd "$ROOT_DIR" || exit 1

failures=0

printf '== Syntax checks ==\n'

while IFS= read -r file; do
  if bash -n "$file"; then
    printf '[PASS] %s\n' "$file"
  else
    printf '[FAIL] %s\n' "$file" >&2
    failures=$((failures + 1))
  fi
done < <(
  find bin lib modules tests \
    -type f \
    \( -name '*.sh' -o -path 'bin/linux-hardening-toolkit' \) \
    -print |
    sort
)

printf '\n== Unit tests ==\n'

for test_file in tests/unit/test_*.sh; do
  printf '\n--- %s ---\n' "$test_file"

  if bash "$test_file"; then
    :
  else
    failures=$((failures + 1))
  fi
done

printf '\n== Integration tests ==\n'

for test_file in tests/integration/test_*.sh; do
  printf '\n--- %s ---\n' "$test_file"

  if bash "$test_file"; then
    :
  else
    failures=$((failures + 1))
  fi
done

printf '\n== Test suite summary ==\n'

if (( failures > 0 )); then
  printf 'FAILED: %d test suite(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'PASS: all test suites completed successfully\n'
exit 0
