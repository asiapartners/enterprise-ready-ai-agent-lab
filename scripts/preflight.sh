#!/usr/bin/env bash
# =============================================================================
# preflight.sh — Prerequisites check for the Enterprise AI Agent Lab
#
# Usage:
#   ./scripts/preflight.sh            # check all phases
#   ./scripts/preflight.sh --phase 1  # check Phase 1 prerequisites only
#   ./scripts/preflight.sh --phase 2  # check Phase 1 + Phase 2 prerequisites
#   ./scripts/preflight.sh --fix      # attempt to install missing tools
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
PHASE=0        # 0 = all
FIX=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --fix)   FIX=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--phase <1|2|3>] [--fix]"
      echo ""
      echo "  --phase <N>   Only check prerequisites for phase N (and below)"
      echo "  --fix         Attempt to install missing tools via Homebrew or npm"
      exit 0
      ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

PASS=0
WARN=0
FAIL=0

check_pass() { echo -e "  ${GREEN}✅ $*${RESET}"; ((PASS++)) || true; }
check_warn() { echo -e "  ${YELLOW}⚠️  $*${RESET}"; ((WARN++)) || true; }
check_fail() { echo -e "  ${RED}❌ $*${RESET}"; ((FAIL++)) || true; }
section()    { echo -e "\n${BOLD}${CYAN}── $* ──${RESET}"; }

try_install() {
  local tool="$1"; local brew_name="${2:-$1}"; local npm_name="${3:-}"
  if $FIX; then
    if command -v brew >/dev/null 2>&1; then
      echo "    Installing $tool via Homebrew..."
      brew install "$brew_name" 2>&1 | tail -1
    elif [ -n "$npm_name" ] && command -v npm >/dev/null 2>&1; then
      echo "    Installing $tool via npm..."
      npm install -g "$npm_name"
    else
      echo "    Cannot auto-install $tool (no Homebrew or npm found)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Phase 1 prerequisites
# ---------------------------------------------------------------------------
check_phase1() {
  section "Phase 1 Prerequisites"

  # Node.js v22+
  if command -v node >/dev/null 2>&1; then
    NODE_VER=$(node --version | sed 's/v//')
    NODE_MAJOR="${NODE_VER%%.*}"
    if [ "$NODE_MAJOR" -ge 22 ]; then
      check_pass "Node.js $NODE_VER"
    else
      check_fail "Node.js $NODE_VER — need v22+. Install: https://nodejs.org"
      try_install "node" "node@22"
    fi
  else
    check_fail "Node.js not installed. Install v22+: https://nodejs.org"
    try_install "node" "node@22"
  fi

  # npm or pnpm
  if command -v pnpm >/dev/null 2>&1; then
    check_pass "pnpm $(pnpm --version)"
  elif command -v npm >/dev/null 2>&1; then
    check_warn "npm found but pnpm preferred. Install: npm install -g pnpm"
  else
    check_fail "No package manager found (npm/pnpm)"
  fi

  # Docker
  if command -v docker >/dev/null 2>&1; then
    DOCKER_VER=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    check_pass "Docker $DOCKER_VER"
    # Check Docker daemon is running
    if docker info >/dev/null 2>&1; then
      check_pass "Docker daemon running"
    else
      check_warn "Docker is installed but the daemon is not running. Start Docker Desktop."
    fi
  else
    check_fail "Docker not installed. Install Docker Desktop: https://docs.docker.com/get-docker/"
    try_install "docker" "docker"
  fi

  # Docker Compose
  if docker compose version >/dev/null 2>&1; then
    check_pass "Docker Compose (plugin)"
  elif command -v docker-compose >/dev/null 2>&1; then
    check_warn "docker-compose (v1) found. Prefer Docker Compose v2 plugin."
  else
    check_fail "Docker Compose not found"
  fi

  # OpenClaw
  if command -v openclaw >/dev/null 2>&1; then
    OC_VER=$(openclaw --version 2>/dev/null | head -1 || echo "unknown")
    check_pass "openclaw $OC_VER"
  else
    check_warn "OpenClaw CLI not installed. Will install when running phase1-setup.sh"
    echo "    To install now: npm install -g @openclaw/openclaw"
  fi
}

# ---------------------------------------------------------------------------
# Phase 2 prerequisites
# ---------------------------------------------------------------------------
check_phase2() {
  section "Phase 2 Prerequisites"

  # Azure CLI
  if command -v az >/dev/null 2>&1; then
    AZ_VER=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || az --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    AZ_MAJOR="${AZ_VER%%.*}"
    AZ_MINOR=$(echo "$AZ_VER" | cut -d. -f2)
    if [ "$AZ_MAJOR" -gt 2 ] || ([ "$AZ_MAJOR" -eq 2 ] && [ "$AZ_MINOR" -ge 60 ]); then
      check_pass "Azure CLI $AZ_VER"
    else
      check_warn "Azure CLI $AZ_VER — recommend ≥ 2.60. Upgrade: brew upgrade azure-cli"
    fi

    # Check login status
    AZ_ACCOUNT=$(az account show --query '{sub:name,tenant:tenantId}' -o tsv 2>/dev/null || echo "")
    if [ -n "$AZ_ACCOUNT" ]; then
      SUB=$(az account show --query name -o tsv)
      TENANT=$(az account show --query tenantId -o tsv)
      check_pass "az logged in — subscription: $SUB"
      check_pass "Tenant ID: $TENANT"
    else
      check_warn "Azure CLI not logged in. Run: az login"
    fi
  else
    check_fail "Azure CLI not installed. Install: brew install azure-cli  |  https://learn.microsoft.com/cli/azure/install-azure-cli"
    try_install "azure-cli" "azure-cli"
  fi

  # jq
  if command -v jq >/dev/null 2>&1; then
    check_pass "jq $(jq --version)"
  else
    check_fail "jq not installed. Install: brew install jq"
    try_install "jq" "jq"
  fi

  # curl
  if command -v curl >/dev/null 2>&1; then
    check_pass "curl $(curl --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  else
    check_fail "curl not installed"
  fi

  # SSH key
  if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    check_pass "SSH key: ~/.ssh/id_ed25519.pub"
  elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    check_pass "SSH key: ~/.ssh/id_rsa.pub"
  else
    check_warn "No SSH public key found. Generate one: ssh-keygen -t ed25519 -C 'openclaw-deploy'"
  fi

  # Optional tools — only needed for the composable path (TEAMS_COPILOT_INTEGRATION.md)
  # Path A (gateway-as-hub) and Path B (SDK-standalone) need these; the openclaw-a365
  # plugin path does not. We surface them as warnings, not failures.

  # Dev Tunnels CLI — exposes localhost:3978 for Azure Bot during development
  if command -v devtunnel >/dev/null 2>&1; then
    check_pass "Dev Tunnels CLI: $(devtunnel --version 2>&1 | head -1)"
  else
    check_warn "Dev Tunnels CLI not installed (only needed for the composable Pattern A/B path)."
    echo "    Install: npm install -g @microsoft/dev-tunnels-cli"
    echo "    Skip if you only deploy the openclaw-a365 plugin to an Azure VM."
  fi

  # Agent 365 CLI — required for AI-guided setup and 'a365 setup all' / 'a365 publish'
  if command -v a365 >/dev/null 2>&1; then
    A365_VER=$(a365 --version 2>/dev/null | head -1 || echo "unknown")
    check_pass "Agent 365 CLI: $A365_VER"
  else
    check_warn "Agent 365 CLI not installed (needed for Tier 1 Register / Tier 4 AI Teammate)."
    echo "    Install: dotnet tool install -g Microsoft.Agent365.CLI"
    echo "    Or: npm install -g @microsoft/agent365-cli"
    echo "    Skip if you stay on direct Graph + manual Entra setup."
  fi

  # .NET SDK — needed if installing the Agent 365 CLI via dotnet tool, or building .NET samples
  if command -v dotnet >/dev/null 2>&1; then
    DOTNET_VER=$(dotnet --version 2>/dev/null | head -1 || echo "unknown")
    DOTNET_MAJOR="${DOTNET_VER%%.*}"
    if [ -n "$DOTNET_MAJOR" ] && [ "$DOTNET_MAJOR" -ge 8 ] 2>/dev/null; then
      check_pass ".NET SDK $DOTNET_VER"
    else
      check_warn ".NET SDK $DOTNET_VER — recommend 8.0+ (only needed for 'dotnet tool install -g Microsoft.Agent365.CLI')"
    fi
  else
    check_warn ".NET SDK not installed (needed only if installing Agent 365 CLI via 'dotnet tool install' or building .NET samples)."
    echo "    Install: see https://dot.net (8.0+)"
  fi

  # .env file
  ENV_PATH="phase-2-tool-integration-capability-perimeters/a365-plugin/.env"
  if [ -f "$ENV_PATH" ]; then
    # Check for empty required values
    MISSING=()
    for var in A365_APP_ID A365_APP_PASSWORD A365_TENANT_ID AA_INSTANCE_ID AGENT_IDENTITY OWNER OWNER_AAD_ID; do
      val=$(grep -E "^${var}=" "$ENV_PATH" | cut -d= -f2- | tr -d '"' || echo "")
      if [ -z "$val" ] || [[ "$val" == *"your-"* ]] || [[ "$val" == *"yourtenant"* ]]; then
        MISSING+=("$var")
      fi
    done
    if [ ${#MISSING[@]} -eq 0 ]; then
      check_pass ".env file found and required fields populated"
    else
      check_warn ".env exists but missing: ${MISSING[*]}"
      echo "    Run: ./scripts/az-entra-setup.sh to populate these values"
    fi
  else
    check_warn ".env not found at $ENV_PATH"
    echo "    Run: cp ${ENV_PATH%.env}.env.example ${ENV_PATH}"
    echo "    Then: ./scripts/az-entra-setup.sh"
  fi
}

# ---------------------------------------------------------------------------
# Phase 3 prerequisites
# ---------------------------------------------------------------------------
check_phase3() {
  section "Phase 3 Prerequisites"

  # Check Phase 2 deployment is verified
  ENV_PATH="phase-2-tool-integration-capability-perimeters/a365-plugin/.env"
  if [ -f "$ENV_PATH" ]; then
    DATAVERSE_URL=$(grep -E "^DATAVERSE_URL=" "$ENV_PATH" | cut -d= -f2- | tr -d '"' || echo "")
    if [ -n "$DATAVERSE_URL" ] && [[ "$DATAVERSE_URL" != *"yourtenant"* ]]; then
      check_pass "DATAVERSE_URL configured: $DATAVERSE_URL"
    else
      check_warn "DATAVERSE_URL not set — needed for Phase 3 shared memory"
      echo "    Add to .env: DATAVERSE_URL=https://yourtenant.crm.dynamics.com"
    fi

    APPINSIGHTS=$(grep -E "^APPLICATIONINSIGHTS_CONNECTION_STRING=" "$ENV_PATH" | cut -d= -f2- | tr -d '"' || echo "")
    if [ -n "$APPINSIGHTS" ]; then
      check_pass "Application Insights connection string configured"
    else
      check_warn "APPLICATIONINSIGHTS_CONNECTION_STRING not set — needed for distributed tracing"
    fi
  else
    check_warn "Phase 2 .env not found — complete Phase 2 first"
  fi

  # Bicep CLI (for Phase 3 infra)
  if az bicep version >/dev/null 2>&1; then
    BICEP_VER=$(az bicep version --query 'bicepVersion' -o tsv 2>/dev/null || az bicep version 2>&1 | head -1)
    check_pass "Bicep CLI $BICEP_VER"
  else
    check_warn "Bicep CLI not installed. Install: az bicep install"
  fi
}

# ---------------------------------------------------------------------------
# Run checks
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Enterprise AI Agent Lab — Prerequisites Check${RESET}"
echo -e "Phase: ${PHASE:-all}"
echo ""

case "$PHASE" in
  1)   check_phase1 ;;
  2)   check_phase1; check_phase2 ;;
  3)   check_phase1; check_phase2; check_phase3 ;;
  0|*) check_phase1; check_phase2; check_phase3 ;;
esac

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}━━━ Summary ━━━${RESET}"
echo -e "  ${GREEN}Passed${RESET}: $PASS"
[ "$WARN" -gt 0 ] && echo -e "  ${YELLOW}Warnings${RESET}: $WARN"
[ "$FAIL" -gt 0 ] && echo -e "  ${RED}Failed${RESET}: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}❌ Fix the failures above before proceeding.${RESET}"
  if ! $FIX; then
    echo "   Tip: re-run with --fix to attempt automatic installation"
  fi
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  Warnings found — review before deploying to production.${RESET}"
  exit 0
else
  echo -e "${GREEN}✅ All checks passed. Ready to deploy.${RESET}"
  exit 0
fi
