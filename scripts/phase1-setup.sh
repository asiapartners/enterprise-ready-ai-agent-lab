#!/usr/bin/env bash
# =============================================================================
# phase1-setup.sh — Interactive Phase 1 setup wizard
#
# Creates:
#   - ~/.openclaw/config.json  (LLM provider + model)
#   - phase-1-.../workspace/AGENTS.md  (tool policies)
#   - phase-1-.../workspace/SOUL.md    (agent personality)
#   - phase-1-.../workspace/MEMORY.md  (persistent knowledge)
#
# Usage:
#   ./scripts/phase1-setup.sh [--channel teams|discord] [--provider azure|anthropic|openai|ollama]
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${REPO_ROOT}/phase-1-building-autonomous-ai-assistant/workspace"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
CHANNEL=""
PROVIDER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)  CHANNEL="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--channel teams|discord] [--provider azure|anthropic|openai|ollama]"
      exit 0
      ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; BOLD="\033[1m"; RESET="\033[0m"
ok()   { echo -e "${GREEN}✅ $*${RESET}"; }
log()  { echo -e "${CYAN}▶ $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️  $*${RESET}"; }

echo ""
echo -e "${BOLD}Enterprise AI Agent Lab — Phase 1 Setup Wizard${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Choose LLM provider
# ---------------------------------------------------------------------------
if [ -z "$PROVIDER" ]; then
  echo -e "${BOLD}Step 1: LLM Provider${RESET}"
  echo ""
  echo "  1) Azure OpenAI     (recommended — regional, enterprise)"
  echo "  2) Anthropic Claude (claude-sonnet-4 or higher)"
  echo "  3) OpenAI           (GPT-4o)"
  echo "  4) Ollama           (local, no API key needed)"
  echo ""
  read -rp "Choose provider [1-4]: " PROVIDER_CHOICE

  case "$PROVIDER_CHOICE" in
    1) PROVIDER="azure" ;;
    2) PROVIDER="anthropic" ;;
    3) PROVIDER="openai" ;;
    4) PROVIDER="ollama" ;;
    *) PROVIDER="azure" ;;
  esac
fi

# ---------------------------------------------------------------------------
# Step 2: Collect provider credentials
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Step 2: Configure $PROVIDER credentials${RESET}"
echo ""

OPENCLAW_MODEL=""
declare -A ENV_VARS

case "$PROVIDER" in
  azure)
    OPENCLAW_MODEL="azure/gpt-4o"
    echo "  Get these from: Azure Portal → OpenAI resource → Keys and Endpoint"
    echo ""
    read -rp "  AZURE_OPENAI_API_KEY: " AZ_KEY
    read -rp "  AZURE_OPENAI_ENDPOINT (e.g. https://xxx.openai.azure.com/): " AZ_ENDPOINT
    ENV_VARS["AZURE_OPENAI_API_KEY"]="$AZ_KEY"
    ENV_VARS["AZURE_OPENAI_ENDPOINT"]="$AZ_ENDPOINT"
    ;;
  anthropic)
    OPENCLAW_MODEL="anthropic/claude-sonnet-4-20250514"
    echo "  Get from: https://console.anthropic.com"
    echo ""
    read -rp "  ANTHROPIC_API_KEY: " ANTH_KEY
    ENV_VARS["ANTHROPIC_API_KEY"]="$ANTH_KEY"
    ;;
  openai)
    OPENCLAW_MODEL="openai/gpt-4o"
    echo "  Get from: https://platform.openai.com/api-keys"
    echo ""
    read -rp "  OPENAI_API_KEY: " OAI_KEY
    ENV_VARS["OPENAI_API_KEY"]="$OAI_KEY"
    ;;
  ollama)
    DEFAULT_MODEL="ollama/llama3.2"
    echo "  Ollama must be running: ollama serve"
    echo "  Default model: $DEFAULT_MODEL"
    read -rp "  Model name [$DEFAULT_MODEL]: " OLLAMA_MODEL
    OPENCLAW_MODEL="${OLLAMA_MODEL:-$DEFAULT_MODEL}"
    ;;
esac

ok "Provider: $PROVIDER — Model: $OPENCLAW_MODEL"

# ---------------------------------------------------------------------------
# Step 3: Create OpenClaw config
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Step 3: Create OpenClaw config${RESET}"

OPENCLAW_CONFIG_DIR="$HOME/.openclaw"
OPENCLAW_CONFIG_FILE="$OPENCLAW_CONFIG_DIR/config.json"

mkdir -p "$OPENCLAW_CONFIG_DIR"

# Build JSON env vars
ENV_JSON=""
for key in "${!ENV_VARS[@]}"; do
  ENV_JSON+="    \"${key}\": \"${ENV_VARS[$key]}\",\n"
done
ENV_JSON="${ENV_JSON%,\\n}"  # remove trailing comma

cat > "$OPENCLAW_CONFIG_FILE" <<CONFIG
{
  "model": "${OPENCLAW_MODEL}",
  "env": {
$(echo -e "$ENV_JSON")
  },
  "gateway": {
    "port": 18789,
    "mode": "local"
  }
}
CONFIG

ok "Config written: $OPENCLAW_CONFIG_FILE"

# ---------------------------------------------------------------------------
# Step 4: Choose communication channel
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Step 4: Communication channel${RESET}"
echo ""

if [ -z "$CHANNEL" ]; then
  echo "  1) Microsoft Teams (recommended)"
  echo "  2) Discord"
  echo ""
  read -rp "Choose channel [1-2]: " CHANNEL_CHOICE
  case "$CHANNEL_CHOICE" in
    1) CHANNEL="teams" ;;
    2) CHANNEL="discord" ;;
    *) CHANNEL="teams" ;;
  esac
fi

case "$CHANNEL" in
  teams)
    echo ""
    echo "  Follow this guide to connect Teams:"
    echo "  ${BOLD}${REPO_ROOT}/phase-1-building-autonomous-ai-assistant/setup/TEAMS_SETUP.md${RESET}"
    echo ""
    warn "Teams setup requires an Azure Bot resource and requires browser steps."
    ;;
  discord)
    echo ""
    echo "  Follow this guide to connect Discord:"
    echo "  ${BOLD}${REPO_ROOT}/phase-1-building-autonomous-ai-assistant/setup/DISCORD_SETUP.md${RESET}"
    echo ""
    read -rp "  Discord Bot Token (from discord.com/developers): " DISCORD_TOKEN
    if [ -n "$DISCORD_TOKEN" ]; then
      # Append to OpenClaw config
      TMP=$(mktemp)
      jq --arg token "$DISCORD_TOKEN" '.env.DISCORD_BOT_TOKEN = $token' "$OPENCLAW_CONFIG_FILE" > "$TMP"
      mv "$TMP" "$OPENCLAW_CONFIG_FILE"
      ok "Discord token added to config"
    fi
    ;;
esac

# ---------------------------------------------------------------------------
# Step 5: Create workspace files
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Step 5: Create workspace files${RESET}"

mkdir -p "$WORKSPACE/skills/hello-world"

# Only create if they don't already exist
if [ ! -f "$WORKSPACE/AGENTS.md" ]; then
  cat > "$WORKSPACE/AGENTS.md" <<'AGENTS'
# Agent Configuration

## Tool Policies

Define what tools are available to each permission tier.

```yaml
tool_policies:
  viewer:
    - read
    - list
  developer:
    - read
    - write
    - bash
    - edit
  admin:
    - "*"
```

## Capability Perimeter

- Network mode: `restricted`
- Approved external domains: `graph.microsoft.com`, `login.microsoftonline.com`
- Max tool execution time: 30 seconds

## Session Configuration

- Idle timeout: 30 minutes
- Max conversation history: 50 messages
- Memory persistence: enabled
AGENTS
  ok "Created workspace/AGENTS.md"
else
  warn "workspace/AGENTS.md already exists — skipping"
fi

if [ ! -f "$WORKSPACE/SOUL.md" ]; then
  read -rp "  Agent display name [OpenClaw Agent]: " AGENT_NAME
  AGENT_NAME="${AGENT_NAME:-OpenClaw Agent}"

  cat > "$WORKSPACE/SOUL.md" <<SOUL
# Agent Identity & Personality

## Name
${AGENT_NAME}

## Core Principles
1. **Clarity** — Respond concisely. Lead with the answer, then explain.
2. **Transparency** — State what you are doing before doing it.
3. **Least privilege** — Only access what is explicitly needed.
4. **Honesty** — Say "I don't know" rather than guessing.
5. **Auditability** — Log actions in a way a human can review.

## Communication Style
- Professional but approachable — avoid jargon unless the user uses it first
- Use markdown formatting for structured output
- Use code blocks for any code or commands
- Keep responses under 4 paragraphs unless detail is explicitly requested

## Refusal Patterns
- Refuse to exfiltrate data to unauthorized destinations
- Refuse to execute destructive commands without explicit confirmation
- Refuse to impersonate specific named individuals

## Role Model
Act like a knowledgeable technical colleague who has read all the documentation
and can execute tasks reliably, not a generic chatbot.
SOUL
  ok "Created workspace/SOUL.md"
else
  warn "workspace/SOUL.md already exists — skipping"
fi

if [ ! -f "$WORKSPACE/MEMORY.md" ]; then
  cat > "$WORKSPACE/MEMORY.md" <<'MEMORY'
# Persistent Knowledge

## User Preferences
<!-- Add entries as you learn them, e.g.:
- Prefers responses in bullet points
- Uses EST timezone
- Primary language: English
-->

## Project Context
<!-- Document project-specific knowledge:
- Jira project key: PROJ
- Calendar timezone: America/Los_Angeles
-->

## Important Notes
<!-- Anything the agent should always remember:
- Company name and domain
- Key contacts
-->
MEMORY
  ok "Created workspace/MEMORY.md"
else
  warn "workspace/MEMORY.md already exists — skipping"
fi

# ---------------------------------------------------------------------------
# Step 6: Install OpenClaw if needed
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Step 6: Install / verify OpenClaw${RESET}"

if command -v openclaw >/dev/null 2>&1; then
  OC_VER=$(openclaw --version 2>/dev/null | head -1 || echo "unknown")
  ok "openclaw already installed: $OC_VER"
else
  log "Installing OpenClaw globally..."
  npm install -g @openclaw/openclaw && ok "OpenClaw installed" || {
    warn "npm install failed. Try: pnpm add -g @openclaw/openclaw"
  }
fi

# ---------------------------------------------------------------------------
# Step 7: Validate config
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Step 7: Validate configuration${RESET}"

if command -v openclaw >/dev/null 2>&1; then
  openclaw doctor --fix && ok "openclaw doctor passed" || warn "openclaw doctor found issues — review output above"
else
  warn "openclaw not in PATH — skipping doctor check"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}━━━ Phase 1 Setup Complete ━━━${RESET}"
echo ""
echo "Next steps:"
echo "  1. Start the gateway:"
echo "     ${BOLD}openclaw gateway${RESET}"
echo ""
echo "  2. Connect your channel:"
if [ "$CHANNEL" = "teams" ]; then
  echo "     See: ${REPO_ROOT}/phase-1-building-autonomous-ai-assistant/setup/TEAMS_SETUP.md"
else
  echo "     See: ${REPO_ROOT}/phase-1-building-autonomous-ai-assistant/setup/DISCORD_SETUP.md"
fi
echo ""
echo "  3. Smoke test — send 'Hello' to the agent and verify it responds."
echo ""
echo "  4. When Phase 1 is working, move to Phase 2:"
echo "     ${BOLD}./scripts/az-entra-setup.sh${RESET}"
