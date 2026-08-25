#!/usr/bin/env bash

declare -ag LHT_CHECK_IDS=()

declare -Ag LHT_CHECK_CATEGORY=()
declare -Ag LHT_CHECK_TITLE=()
declare -Ag LHT_CHECK_SEVERITY=()
declare -Ag LHT_CHECK_AUDIT_FN=()
declare -Ag LHT_CHECK_APPLY_FN=()

lht_check_exists() {
  local check_id="${1:?check id is required}"

  [[ -n "${LHT_CHECK_TITLE[$check_id]+x}" ]]
}

lht_register_check() {
  local check_id="${1:?check id is required}"
  local category="${2:?category is required}"
  local title="${3:?title is required}"
  local severity="${4:?severity is required}"
  local audit_function="${5:?audit function is required}"
  local apply_function="${6:-}"

  if [[ ! "$check_id" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
    lht_die "Invalid check id: ${check_id}"
  fi

  if [[ ! "$category" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
    lht_die "Invalid check category: ${category}"
  fi

  case "$severity" in
    info|low|medium|high|critical)
      ;;
    *)
      lht_die \
        "Invalid severity '${severity}' for check '${check_id}'"
      ;;
  esac

  if lht_check_exists "$check_id"; then
    lht_die "Duplicate check id registered: ${check_id}"
  fi

  if ! declare -F "$audit_function" >/dev/null 2>&1; then
    lht_die \
      "Audit function '${audit_function}' for '${check_id}' does not exist"
  fi

  if [[ -n "$apply_function" ]] \
    && ! declare -F "$apply_function" >/dev/null 2>&1; then
    lht_die \
      "Apply function '${apply_function}' for '${check_id}' does not exist"
  fi

  LHT_CHECK_IDS+=("$check_id")

  LHT_CHECK_CATEGORY["$check_id"]="$category"
  LHT_CHECK_TITLE["$check_id"]="$title"
  LHT_CHECK_SEVERITY["$check_id"]="$severity"
  LHT_CHECK_AUDIT_FN["$check_id"]="$audit_function"
  LHT_CHECK_APPLY_FN["$check_id"]="$apply_function"

  lht_log_debug "Registered check: ${check_id}"
}

lht_load_modules() {
  local module_dir=""
  local module_file=""
  local loaded_modules=0

  for module_dir in "$LHT_MODULES_DIR"/*; do
    [[ -d "$module_dir" ]] || continue

    module_file="${module_dir}/module.sh"

    [[ -f "$module_file" ]] || continue

    lht_log_debug "Loading module: ${module_file}"

    # shellcheck source=/dev/null
    source "$module_file"

    loaded_modules=$((loaded_modules + 1))
  done

  if (( loaded_modules == 0 )); then
    lht_die "No modules were found in ${LHT_MODULES_DIR}"
  fi

  if (( ${#LHT_CHECK_IDS[@]} == 0 )); then
    lht_die "Modules were loaded, but no checks were registered"
  fi

  lht_log_debug \
    "Loaded ${loaded_modules} module(s), ${#LHT_CHECK_IDS[@]} check(s)"
}
