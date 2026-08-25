#!/usr/bin/env bash

if [[ -z "${LHT_ROOT_DIR:-}" ]]; then
  printf 'ERROR: LHT_ROOT_DIR is not defined\n' >&2
  return 1
fi

LHT_LIB_DIR="${LHT_ROOT_DIR}/lib"
LHT_MODULES_DIR="${LHT_ROOT_DIR}/modules"
LHT_PROFILES_DIR="${LHT_ROOT_DIR}/profiles"

# shellcheck source=lib/core/utils.sh
source "${LHT_LIB_DIR}/core/utils.sh"

# shellcheck source=lib/core/log.sh
source "${LHT_LIB_DIR}/core/log.sh"

# shellcheck source=lib/core/runtime.sh
source "${LHT_LIB_DIR}/core/runtime.sh"

# shellcheck source=lib/core/registry.sh
source "${LHT_LIB_DIR}/core/registry.sh"

# shellcheck source=lib/core/profile.sh
source "${LHT_LIB_DIR}/core/profile.sh"

# shellcheck source=lib/core/runner.sh
source "${LHT_LIB_DIR}/core/runner.sh"

lht_bootstrap_modules() {
  lht_assert_runtime
  lht_load_modules
}
