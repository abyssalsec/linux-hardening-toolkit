#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
  pwd -P
)"

cd "$ROOT_DIR"

if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'ERROR: shellcheck is not installed\n' >&2
  exit 1
fi

mapfile -t files < <(
  find \
    bin \
    lib \
    modules \
    scripts \
    tests \
    -type f \
    \( -name '*.sh' -o -path 'bin/linux-hardening-toolkit' \) \
    -print |
    sort
)

if (( ${#files[@]} == 0 )); then
  printf 'ERROR: no shell files were found\n' >&2
  exit 1
fi

printf 'ShellCheck: %d file(s)\n' "${#files[@]}"

shellcheck -x "${files[@]}"

printf 'ShellCheck: PASS\n'
