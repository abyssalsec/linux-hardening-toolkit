#!/usr/bin/env bash

TESTS_RUN=0
TESTS_FAILED=0

test_pass() {
  local message="${1:?message is required}"

  TESTS_RUN=$((TESTS_RUN + 1))
  printf '[PASS] %s\n' "$message"
}

test_fail() {
  local message="${1:?message is required}"

  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))

  printf '[FAIL] %s\n' "$message" >&2
}

assert_eq() {
  local expected="${1-}"
  local actual="${2-}"
  local message="${3:?message is required}"

  if [[ "$actual" == "$expected" ]]; then
    test_pass "$message"
  else
    test_fail \
      "${message} (expected='${expected}', actual='${actual}')"
  fi
}

assert_contains() {
  local haystack="${1-}"
  local needle="${2-}"
  local message="${3:?message is required}"

  if [[ "$haystack" == *"$needle"* ]]; then
    test_pass "$message"
  else
    test_fail \
      "${message} (missing='${needle}')"
  fi
}

assert_file_exists() {
  local path="${1:?path is required}"
  local message="${2:?message is required}"

  if [[ -f "$path" ]]; then
    test_pass "$message"
  else
    test_fail "${message} (missing=${path})"
  fi
}

finish_tests() {
  printf '\nTests: %d, Failed: %d\n' \
    "$TESTS_RUN" \
    "$TESTS_FAILED"

  if (( TESTS_FAILED > 0 )); then
    return 1
  fi

  return 0
}
