#!/usr/bin/env bash
# =============================================================================
# scripts/install-azure-cli.sh — Install or upgrade the Azure CLI + extensions
#
# Usage:
#   bash scripts/install-azure-cli.sh [--upgrade] [--no-extensions] [--help]
#   pnpm run az:install
#
# Behaviour:
#   - Detects OS (Linux apt, macOS brew, Windows winget) and installs az.
#   - If az is already present:
#       * --upgrade   → upgrade in place
#       * (default)   → skip install, only ensure extensions
#   - Ensures these extensions are installed and current:
#       containerapp, bot-service, application-insights
#   - Idempotent: safe to re-run.
#
# Exit codes:
#   0  success
#   1  unsupported OS / missing package manager
#   2  install failed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

UPGRADE=0
INSTALL_EXTENSIONS=1
EXTENSIONS=(containerapp bot-service application-insights)

print_help() {
  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while (($#)); do
  case "$1" in
    --upgrade)        UPGRADE=1 ;;
    --no-extensions)  INSTALL_EXTENSIONS=0 ;;
    -h|--help)        print_help ;;
    *) fail "Unknown argument: $1 (try --help)" ;;
  esac
  shift
done

title "Azure CLI installer"

detect_os
info "Detected OS: $OS_FAMILY  (package manager: $PKG_MGR)"

install_linux_apt() {
  info "Installing Azure CLI via Microsoft apt repository..."
  require_cmd curl
  # Microsoft's official one-liner — pinned to /etc/apt/sources.list.d/azure-cli.sources
  if ! dry_run_echo bash -c 'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash'; then
    fail "Azure CLI install failed (apt). Check sudo permissions and network access."
  fi
}

install_linux_dnf() {
  info "Installing Azure CLI via Microsoft dnf/yum repository..."
  require_cmd curl
  fail "dnf/yum installer not implemented yet. See https://learn.microsoft.com/cli/azure/install-azure-cli-linux"
}

install_macos_brew() {
  info "Installing Azure CLI via Homebrew..."
  if [[ "$UPGRADE" == "1" ]]; then
    dry_run_echo brew update
    dry_run_echo brew upgrade azure-cli || dry_run_echo brew install azure-cli
  else
    dry_run_echo brew install azure-cli
  fi
}

install_windows_winget() {
  info "Installing Azure CLI via winget..."
  dry_run_echo winget install -e --id Microsoft.AzureCLI --silent --accept-source-agreements --accept-package-agreements
}

# ─── Install / upgrade ───────────────────────────────────────────────────────
if command -v az >/dev/null 2>&1; then
  CURRENT_VER="$(az --version 2>/dev/null | awk 'NR==1 {print $2}')"
  pass "Azure CLI already installed: $CURRENT_VER"
  if [[ "$UPGRADE" == "1" ]]; then
    info "Upgrading..."
    case "$OS_FAMILY:$PKG_MGR" in
      linux:apt)         install_linux_apt ;;
      linux:dnf|linux:yum) install_linux_dnf ;;
      macos:brew)        install_macos_brew ;;
      windows:winget)    install_windows_winget ;;
      *)                 warn "Don't know how to upgrade on $OS_FAMILY/$PKG_MGR — please upgrade manually." ;;
    esac
  fi
else
  case "$OS_FAMILY:$PKG_MGR" in
    linux:apt)            install_linux_apt ;;
    linux:dnf|linux:yum)  install_linux_dnf ;;
    macos:brew)           install_macos_brew ;;
    windows:winget)       install_windows_winget ;;
    macos:unknown)        fail "Homebrew not found. Install: https://brew.sh — then re-run this script." ;;
    windows:unknown)      fail "winget not found. Install App Installer from the Microsoft Store, or download az MSI: https://aka.ms/installazurecliwindows" ;;
    *)                    fail "Unsupported OS/package manager: $OS_FAMILY/$PKG_MGR. See https://learn.microsoft.com/cli/azure/install-azure-cli" ;;
  esac
  pass "Azure CLI installed: $(az --version 2>/dev/null | awk 'NR==1 {print $2}')"
fi

# ─── Extensions ──────────────────────────────────────────────────────────────
if [[ "$INSTALL_EXTENSIONS" == "1" ]]; then
  title "Azure CLI extensions"
  # Disable interactive extension-install prompts globally for this script
  dry_run_echo az config set extension.use_dynamic_install=yes_without_prompt >/dev/null

  for ext in "${EXTENSIONS[@]}"; do
    if az extension show --name "$ext" >/dev/null 2>&1; then
      info "Updating extension: $ext"
      dry_run_echo az extension update --name "$ext" >/dev/null || warn "Failed to update $ext (continuing)"
      pass "Extension up to date: $ext"
    else
      info "Installing extension: $ext"
      dry_run_echo az extension add --name "$ext" --yes >/dev/null \
        || fail "Failed to install extension: $ext"
      pass "Extension installed: $ext"
    fi
  done
else
  warn "Skipping extension install (--no-extensions)"
fi

title "Done"
pass "Azure CLI ready. Next: bash scripts/azure-login.sh"
