#!/usr/bin/env bash
# =============================================================================
# setup.sh — Local development environment setup for openclaw-agent365
#
# Usage:
#   bash scripts/setup.sh
#   # or after pnpm setup:
#   pnpm run setup
#
# What it does:
#   1. Checks required tool versions (Node 24+, pnpm 9+, Docker, Azure CLI)
#   2. Installs npm dependencies
#   3. Copies .env.example → .env (if .env doesn't exist)
#   4. Initialises pre-commit hooks
#   5. Runs an initial typecheck + lint
#   6. Prompts next steps
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass()  { echo -e "${GREEN}✔${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
fail()  { echo -e "${RED}✖${NC}  $*"; exit 1; }
info()  { echo -e "${CYAN}→${NC}  $*"; }
title() { echo -e "\n${CYAN}═══════════════════════════════════════════${NC}"; echo -e "  $*"; echo -e "${CYAN}═══════════════════════════════════════════${NC}"; }

# ─── 1. Tool version checks ──────────────────────────────────────────────────
title "openclaw-agent365 — Dev Setup"
info "Checking required tools..."

# Node.js ≥ 24
if command -v node &>/dev/null; then
  NODE_VER=$(node --version | sed 's/v//')
  NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 24 ]; then
    pass "Node.js $NODE_VER"
  else
    fail "Node.js 24+ required (found $NODE_VER). Install via: nvm install 24"
  fi
else
  fail "Node.js not found. Install via: https://nodejs.org or nvm"
fi

# pnpm ≥ 9
if command -v pnpm &>/dev/null; then
  PNPM_VER=$(pnpm --version)
  PNPM_MAJOR=$(echo "$PNPM_VER" | cut -d. -f1)
  if [ "$PNPM_MAJOR" -ge 9 ]; then
    pass "pnpm $PNPM_VER"
  else
    warn "pnpm 9+ recommended (found $PNPM_VER). Upgrade: corepack prepare pnpm@latest --activate"
  fi
else
  info "pnpm not found — installing via corepack..."
  corepack enable && corepack prepare pnpm@latest --activate
  pass "pnpm installed"
fi

# Docker (optional but recommended)
if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
  pass "Docker $DOCKER_VER"
else
  warn "Docker not found (optional for local dev, required for container builds)"
fi

# Azure CLI (optional)
if command -v az &>/dev/null; then
  AZ_VER=$(az --version 2>/dev/null | head -1 | awk '{print $2}')
  pass "Azure CLI $AZ_VER"
else
  warn "Azure CLI not found (optional, required for Azure deployments): https://aka.ms/install-azure-cli"
fi

# k6 (optional, for load tests)
if command -v k6 &>/dev/null; then
  K6_VER=$(k6 version | awk '{print $3}')
  pass "k6 $K6_VER"
else
  warn "k6 not found (optional, for load tests): https://k6.io/docs/get-started/installation/"
fi

# ─── 2. Install dependencies ─────────────────────────────────────────────────
title "Installing dependencies"
pnpm install
pass "Dependencies installed"

# ─── 3. Environment file ─────────────────────────────────────────────────────
title "Environment configuration"
if [ -f .env ]; then
  pass ".env already exists — skipping copy"
else
  cp .env.example .env
  pass "Copied .env.example → .env"
  warn "Fill in .env with your actual values before running the agent"
  echo ""
  echo "  Required values to fill:"
  echo "    A365_APP_ID          — from Azure App Registration"
  echo "    A365_APP_PASSWORD    — from Azure App Registration (use Key Vault in prod)"
  echo "    A365_TENANT_ID       — your Azure AD tenant GUID"
  echo "    AA_INSTANCE_ID       — from Agent 365 registration"
  echo "    AGENT_IDENTITY       — agent's Entra ID UPN (e.g. agent@contoso.com)"
  echo "    OWNER                — your Entra ID UPN"
  echo "    OWNER_AAD_ID         — your Entra ID object GUID"
  echo "    ANTHROPIC_API_KEY    — from console.anthropic.com (or other LLM key)"
  echo ""
fi

# ─── 4. Pre-commit hooks ─────────────────────────────────────────────────────
title "Pre-commit hooks"
if command -v pre-commit &>/dev/null; then
  pre-commit install
  pass "pre-commit hooks installed"
  # Initialise detect-secrets baseline if not present
  if [ ! -f .secrets.baseline ] && command -v detect-secrets &>/dev/null; then
    detect-secrets scan > .secrets.baseline
    pass "Created .secrets.baseline"
  fi
else
  warn "pre-commit not found — skipping hook installation"
  warn "Install: pip install pre-commit detect-secrets"
fi

# ─── 5. Type check + lint ─────────────────────────────────────────────────────
title "Typecheck + lint"
if pnpm run typecheck; then
  pass "TypeScript: no errors"
else
  warn "TypeScript errors found — fix before committing"
fi

if pnpm run lint 2>/dev/null; then
  pass "ESLint: no warnings"
else
  warn "ESLint warnings found — run 'pnpm run lint' for details"
fi

# ─── 6. Build verification ────────────────────────────────────────────────────
title "Build"
if pnpm run build; then
  pass "Build successful → dist/"
else
  fail "Build failed — check TypeScript errors above"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
title "Setup complete"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Fill in .env with your values (see above)"
echo "  2. Start local dev server:"
echo "       pnpm run dev"
echo ""
echo "  3. In a separate terminal, start ngrok (for Teams tunnel):"
echo "       ngrok http 3978"
echo ""
echo "  4. Register the Bot Framework endpoint in Azure:"
echo "       https://<ngrok-url>/api/messages"
echo ""
echo "  5. Run tests:"
echo "       pnpm test"
echo ""
echo "  See docs/architecture.md for the full lab phases."
echo ""
