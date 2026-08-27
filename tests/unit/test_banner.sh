#!/usr/bin/env bash

set -uo pipefail

TEST_ROOT="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 || exit 1
  pwd -P
)"

# shellcheck source=tests/lib/testlib.sh
source "${TEST_ROOT}/tests/lib/testlib.sh"

lht_color_enabled() {
  return 1
}

# shellcheck source=lib/core/banner.sh
source "${TEST_ROOT}/lib/core/banner.sh"

COLUMNS=200

full_banner="$(lht_print_banner)"

assert_contains \
  "$full_banner" \
  "#ABSL Security Development Project" \
  "full banner contains ABSL branding"

assert_contains \
  "$full_banner" \
  "L   I   N   U   X" \
  "full banner contains toolkit title"

assert_contains \
  "$full_banner" \
  "H   A   R   D   E   N   I   N   G" \
  "full banner renders expanded toolkit title"

COLUMNS=40

compact_banner="$(lht_print_banner)"

assert_contains \
  "$compact_banner" \
  "#ABSL Security" \
  "narrow terminal uses compact ABSL banner"

assert_contains \
  "$compact_banner" \
  "Linux Hardening Toolkit" \
  "narrow terminal uses compact toolkit title"

finish_tests
