#!/usr/bin/env bash

lht_banner_terminal_width() {
  local width=""

  if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$COLUMNS"
    return 0
  fi

  if command -v tput >/dev/null 2>&1; then
    width="$(tput cols 2>/dev/null || true)"

    if [[ "$width" =~ ^[0-9]+$ ]]; then
      printf '%s' "$width"
      return 0
    fi
  fi

  printf '0'
}

lht_print_banner() {
  local bright_green=""
  local reset=""
  local terminal_width=""

  if lht_color_enabled; then
    bright_green=$'\033[92m'
    reset=$'\033[0m'
  fi

  terminal_width="$(lht_banner_terminal_width)"

  if (( terminal_width > 0 && terminal_width < 83 )); then
    printf '\n%s#ABSL Security%s\n' \
      "$bright_green" \
      "$reset"

    printf '%sLinux Hardening Toolkit%s\n\n' \
      "$bright_green" \
      "$reset"

    return 0
  fi

  printf '\n%s' "$bright_green"

  cat <<'BANNER'
   _  _      _    ____  ____  _      ____  _____ ____ _   _ ____  ___ _______   __
  _| || |_   / \  | __ )/ ___|| |    / ___|| ____/ ___| | | |  _ \|_ _|_   _\ \ / /
 |_  ..  _| / _ \ |  _ \\___ \| |    \___ \|  _|| |   | | | | |_) || |  | |  \ V /
 |_      _|/ ___ \| |_) |___) | |___  ___) | |__| |___| |_| |  _ < | |  | |   | |
   |_||_| /_/   \_\____/|____/|_____| |____/|_____\____|\___/|_| \_\___| |_|   |_|

-----------------------------------------------------------------------------------
L   I   N   U   X    H   A   R   D   E   N   I   N   G    T   O   O   L   K   I   T
-----------------------------------------------------------------------------------
                        #ABSL Security Development Project
BANNER

  printf '%s\n' "$reset"
}

lht_maybe_print_banner() {
  [[ "${LHT_NO_BANNER:-0}" != "1" ]] || return 0
  [[ -t 1 ]] || return 0

  case "${LHT_COMMAND:-}" in
    version)
      return 0
      ;;

    audit)
      [[ "${LHT_OUTPUT_FORMAT:-text}" == "text" ]] || return 0
      ;;
  esac

  lht_print_banner
}
