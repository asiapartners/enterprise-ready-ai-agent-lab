#!/usr/bin/env bash
# =============================================================================
# scripts/lib/common.sh — shared bash helpers
#
# Source this file from other scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=lib/common.sh
#   source "$SCRIPT_DIR/lib/common.sh"
#
# Provides:
#   - Coloured status helpers: pass / warn / fail / info / title
#   - is_interactive       — returns 0 if stdin is a TTY
#   - require_env VAR ...  — fail fast if any env var is empty
#   - require_cmd CMD ...  — fail fast if a command isn't on PATH
#   - mask_secret VALUE    — print first 4 chars + ***
#   - confirm "prompt"     — y/N prompt; auto-yes when CONFIRM_YES=1
#   - dry_run_echo CMD...  — echoes the command when AZ_DRY_RUN=1, else runs it
#   - detect_os            — sets OS_FAMILY (linux|macos|windows) and PKG_MGR
# =============================================================================

# Idempotent guard — allow sourcing multiple times safely
if [[ -n "${_OPENCLAW_COMMON_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_OPENCLAW_COMMON_SH_LOADED=1

# ─── Colours (disabled when not a TTY or NO_COLOR set) ───────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'
  GREY=$'\033[0;90m'
  NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; GREY=''; NC=''
fi

# ─── Status helpers (write to stderr; stdout reserved for machine output) ────
pass()  { printf '%s✔%s  %s\n' "$GREEN"  "$NC" "$*" >&2; }
warn()  { printf '%s⚠%s  %s\n' "$YELLOW" "$NC" "$*" >&2; }
fail()  { printf '%s✖%s  %s\n' "$RED"    "$NC" "$*" >&2; exit 1; }
info()  { printf '%s→%s  %s\n' "$CYAN"   "$NC" "$*" >&2; }
debug() { [[ -n "${DEBUG:-}" ]] && printf '%s•%s  %s\n' "$GREY" "$NC" "$*" >&2 || true; }
title() {
  printf '\n%s═══════════════════════════════════════════%s\n'   "$CYAN" "$NC" >&2
  printf '  %s\n' "$*" >&2
  printf '%s═══════════════════════════════════════════%s\n'     "$CYAN" "$NC" >&2
}

# ─── Predicates ──────────────────────────────────────────────────────────────
is_interactive() {
  [[ -t 0 && -t 1 && -z "${CI:-}" ]]
}

# require_env VAR1 VAR2 ...  — fails if any are empty/unset
require_env() {
  local missing=()
  local v
  for v in "$@"; do
    if [[ -z "${!v:-}" ]]; then
      missing+=("$v")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Required environment variables not set: ${missing[*]}"
  fi
}

# require_cmd CMD1 CMD2 ...  — fails if any are not on PATH
require_cmd() {
  local missing=()
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Required commands not found on PATH: ${missing[*]}"
  fi
}

# mask_secret VALUE  — print "abcd***" so logs don't expose secrets
mask_secret() {
  local v="${1:-}"
  if [[ -z "$v" ]]; then
    printf '(empty)'
  elif (( ${#v} <= 4 )); then
    printf '***'
  else
    printf '%s***' "${v:0:4}"
  fi
}

# confirm "Are you sure?"  — y/N, default N. CONFIRM_YES=1 auto-accepts.
confirm() {
  local prompt="${1:-Continue?}"
  if [[ "${CONFIRM_YES:-0}" == "1" ]]; then
    info "$prompt → auto-yes (CONFIRM_YES=1)"
    return 0
  fi
  if ! is_interactive; then
    fail "Refusing to prompt in non-interactive mode. Set CONFIRM_YES=1 to bypass."
  fi
  local reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# dry_run_echo cmd args...  — echo when AZ_DRY_RUN=1, else execute
dry_run_echo() {
  if [[ "${AZ_DRY_RUN:-0}" == "1" ]]; then
    printf '%s[dry-run]%s ' "$YELLOW" "$NC" >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
  else
    "$@"
  fi
}

# detect_os  — sets OS_FAMILY=(linux|macos|windows) and PKG_MGR=(apt|dnf|brew|winget|unknown)
detect_os() {
  case "${OSTYPE:-$(uname -s)}" in
    linux*|Linux*)
      OS_FAMILY=linux
      if command -v apt-get >/dev/null 2>&1;       then PKG_MGR=apt
      elif command -v dnf     >/dev/null 2>&1;     then PKG_MGR=dnf
      elif command -v yum     >/dev/null 2>&1;     then PKG_MGR=yum
      else                                              PKG_MGR=unknown
      fi
      ;;
    darwin*|Darwin*)
      OS_FAMILY=macos
      if command -v brew >/dev/null 2>&1; then PKG_MGR=brew; else PKG_MGR=unknown; fi
      ;;
    msys*|cygwin*|mingw*|MINGW*|MSYS*|CYGWIN*)
      OS_FAMILY=windows
      if command -v winget >/dev/null 2>&1; then PKG_MGR=winget; else PKG_MGR=unknown; fi
      ;;
    *)
      OS_FAMILY=unknown
      PKG_MGR=unknown
      ;;
  esac
  export OS_FAMILY PKG_MGR
}

# repo_root  — print the absolute path of the repository root
repo_root() {
  git rev-parse --show-toplevel 2>/dev/null \
    || (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
}
