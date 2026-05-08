#!/usr/bin/env bash
# =============================================================================
# az-entra-setup.sh — Phase 2 Azure / Entra credential setup via Azure CLI
#
# Automates all portal steps in setup/AZURE_ENTRA_SETUP.md that can be done
# via CLI. One step (Step 4: AA Instance ID) still requires the M365 Agents
# portal — the script pauses and guides you through it.
#
# Usage:
#   cd phase-2-tool-integration-capability-perimeters/a365-plugin
#   ../../scripts/az-entra-setup.sh [--dry-run] [--env-file .env]
#
# Outputs:
#   - Prints all generated .env values
#   - Writes to .env.generated (safe — does NOT overwrite your .env)
#
# Requirements:
#   - az CLI ≥ 2.60 (brew install azure-cli)
#   - jq (brew install jq)
#   - Global Administrator or Application Administrator + User Administrator role
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
DRY_RUN=false
ENV_FILE=".env.generated"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --env-file)   ENV_FILE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--env-file <path>]"
      echo ""
      echo "  --dry-run      Print commands but don't execute them"
      echo "  --env-file     Output file for generated env vars (default: .env.generated)"
      exit 0
      ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

log()  { echo -e "${CYAN}▶ $*${RESET}"; }
ok()   { echo -e "${GREEN}✅ $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️  $*${RESET}"; }
err()  { echo -e "${RED}❌ $*${RESET}"; exit 1; }
step() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

run() {
  if $DRY_RUN; then
    echo -e "${YELLOW}[dry-run]${RESET} $*"
  else
    eval "$*"
  fi
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
step "Preflight checks"

command -v az  >/dev/null 2>&1 || err "az CLI not installed. Install: brew install azure-cli  |  https://learn.microsoft.com/cli/azure/install-azure-cli"
command -v jq  >/dev/null 2>&1 || err "jq not installed. Install: brew install jq"

az account show >/dev/null 2>&1 || {
  warn "Not logged in to Azure. Running az login..."
  az login
}

TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
DEPLOYER_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo "unknown")
DEPLOYER_OID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")

echo ""
echo "  Subscription : $SUBSCRIPTION_NAME"
echo "  Tenant ID    : $TENANT_ID"
echo "  Logged in as : $DEPLOYER_UPN"
echo ""

if $DRY_RUN; then
  warn "DRY RUN mode — no resources will be created"
fi

# ---------------------------------------------------------------------------
# Step 1: Agentic User
# ---------------------------------------------------------------------------
step "Step 1 — Create the Agentic User"

# Derive tenant domain from deployer UPN
TENANT_DOMAIN="${DEPLOYER_UPN#*@}"
DEFAULT_AGENT_UPN="agent@${TENANT_DOMAIN}"

echo -e "Default agent UPN: ${BOLD}${DEFAULT_AGENT_UPN}${RESET}"
read -rp "Agent UPN [press Enter to accept default or type a custom one]: " INPUT_AGENT_UPN
AGENT_IDENTITY="${INPUT_AGENT_UPN:-$DEFAULT_AGENT_UPN}"

# Check if user already exists
EXISTING_USER=$(az ad user show --id "$AGENT_IDENTITY" --query id -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_USER" ]; then
  ok "Agent user already exists: $AGENT_IDENTITY (Object ID: $EXISTING_USER)"
  AGENT_OBJECT_ID="$EXISTING_USER"
else
  log "Creating agent user $AGENT_IDENTITY..."

  # Generate a secure temp password (never used — FIC handles auth)
  TEMP_PW="Oc$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9!@#' | head -c 14)!"

  if ! $DRY_RUN; then
    az ad user create \
      --display-name "OpenClaw Agent" \
      --user-principal-name "$AGENT_IDENTITY" \
      --password "$TEMP_PW" \
      --force-change-password-next-sign-in false \
      --job-title "Autonomous Agent" \
      --department "AI Agents" \
      -o none

    AGENT_OBJECT_ID=$(az ad user show --id "$AGENT_IDENTITY" --query id -o tsv)
    ok "Agent user created: $AGENT_IDENTITY (Object ID: $AGENT_OBJECT_ID)"
  else
    echo "[dry-run] Would create user: $AGENT_IDENTITY"
    AGENT_OBJECT_ID="<would-be-created>"
  fi

  echo ""
  warn "ACTION REQUIRED: Assign a Microsoft 365 license to $AGENT_IDENTITY"
  echo "  Portal: https://admin.microsoft.com → Users → Active users → $AGENT_IDENTITY → Licenses"
  echo "  Or run (if you have M365 PowerShell):"
  echo "    Set-MgUserLicense -UserId $AGENT_IDENTITY -AddLicenses @{SkuId='...'} -RemoveLicenses @()"
  echo ""
  read -rp "Press Enter once you have assigned the license (or Enter to skip for now)..." _
fi

# ---------------------------------------------------------------------------
# Step 2: App Registration (Bot identity)
# ---------------------------------------------------------------------------
step "Step 2 — App Registration (Bot identity)"

APP_DISPLAY_NAME="openclaw-a365-bot"

# Check if app already exists
EXISTING_APP=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP" ] && [ "$EXISTING_APP" != "null" ]; then
  ok "App registration already exists: $APP_DISPLAY_NAME (App ID: $EXISTING_APP)"
  A365_APP_ID="$EXISTING_APP"
else
  log "Creating app registration: $APP_DISPLAY_NAME..."

  if ! $DRY_RUN; then
    A365_APP_ID=$(az ad app create \
      --display-name "$APP_DISPLAY_NAME" \
      --sign-in-audience AzureADMyOrg \
      --query appId -o tsv)
    ok "App registration created. App ID: $A365_APP_ID"
  else
    echo "[dry-run] Would create app registration: $APP_DISPLAY_NAME"
    A365_APP_ID="<would-be-created>"
  fi
fi

# ---------------------------------------------------------------------------
# Step 2b: Client secret
# ---------------------------------------------------------------------------
log "Creating client secret for $APP_DISPLAY_NAME..."

if ! $DRY_RUN; then
  SECRET_RESULT=$(az ad app credential reset \
    --id "$A365_APP_ID" \
    --append \
    --display-name "phase-2-dev" \
    --end-date "$(date -v+1y '+%Y-%m-%d' 2>/dev/null || date -d '+1 year' '+%Y-%m-%d')" \
    -o json 2>/dev/null || \
    # Fallback: try without --end-date flag version differences
    az ad app credential reset \
      --id "$A365_APP_ID" \
      --append \
      -o json)

  A365_APP_PASSWORD=$(echo "$SECRET_RESULT" | jq -r '.password')
  ok "Client secret created (valid 1 year)"
else
  echo "[dry-run] Would create client secret"
  A365_APP_PASSWORD="<would-be-generated>"
fi

# ---------------------------------------------------------------------------
# Step 2c: API Permissions (Microsoft Graph)
# ---------------------------------------------------------------------------
log "Adding Microsoft Graph application permissions..."

GRAPH_API_ID="00000003-0000-0000-c000-000000000000"

# Dynamically resolve permission GUIDs from the Microsoft Graph service principal
get_graph_app_role_id() {
  local perm_name="$1"
  az ad sp show --id "$GRAPH_API_ID" \
    --query "appRoles[?value=='${perm_name}'].id | [0]" -o tsv 2>/dev/null || echo ""
}

PERM_CALENDARS=$(get_graph_app_role_id "Calendars.ReadWrite.Shared")
PERM_MAIL=$(get_graph_app_role_id "Mail.Send.Shared")
PERM_USER=$(get_graph_app_role_id "User.Read.All")

# Validate we got the IDs
for name_id in "Calendars.ReadWrite.Shared:$PERM_CALENDARS" "Mail.Send.Shared:$PERM_MAIL" "User.Read.All:$PERM_USER"; do
  pname="${name_id%%:*}"
  pid="${name_id##*:}"
  if [ -z "$pid" ]; then
    warn "Could not resolve permission ID for $pname. Will need to add manually in portal."
  else
    log "  $pname → $pid"
  fi
done

if ! $DRY_RUN; then
  PERMS=""
  [ -n "$PERM_CALENDARS" ] && PERMS="$PERMS ${PERM_CALENDARS}=Role"
  [ -n "$PERM_MAIL" ]      && PERMS="$PERMS ${PERM_MAIL}=Role"
  [ -n "$PERM_USER" ]      && PERMS="$PERMS ${PERM_USER}=Role"

  if [ -n "$PERMS" ]; then
    # shellcheck disable=SC2086
    az ad app permission add \
      --id "$A365_APP_ID" \
      --api "$GRAPH_API_ID" \
      --api-permissions $PERMS \
      -o none
    ok "Graph permissions added"

    log "Granting admin consent (requires Global Admin or Application Admin)..."
    az ad app permission admin-consent --id "$A365_APP_ID" -o none && \
      ok "Admin consent granted" || \
      warn "Admin consent failed — grant manually: Azure Portal → App registrations → $APP_DISPLAY_NAME → API permissions → Grant admin consent"
  else
    warn "No permission IDs resolved. Add Graph permissions manually in the portal."
  fi
else
  echo "[dry-run] Would add Graph permissions: Calendars.ReadWrite.Shared, Mail.Send.Shared, User.Read.All"
fi

# ---------------------------------------------------------------------------
# Step 3: Federated Identity Credentials (placeholder — needs AA_INSTANCE_ID)
# ---------------------------------------------------------------------------
step "Step 3 — Federated Identity Credentials (FIC)"

echo ""
echo "  FIC binds the bot identity (A365_APP_ID) to the agent's AA Instance ID."
echo "  The Subject of the FIC MUST match the AA_INSTANCE_ID exactly."
echo ""
echo "  We will create the FIC credential AFTER you complete Step 4 (AA Instance ID)."
echo ""

# ---------------------------------------------------------------------------
# Step 4: Register the Autonomous Agent (PORTAL REQUIRED)
# ---------------------------------------------------------------------------
step "Step 4 — Register Autonomous Agent (PORTAL REQUIRED)"

echo ""
echo -e "${YELLOW}  This step cannot be automated — it requires the Microsoft 365 Agents portal.${RESET}"
echo ""
echo -e "  1. Go to: ${BOLD}https://admin.microsoft.com${RESET}"
echo "     → Settings → Integrated Apps → (or search 'Agents')"
echo "     → Register autonomous agent"
echo ""
echo "  2. Fill in:"
echo "     • Agent UPN:       $AGENT_IDENTITY"
echo "     • App ID:          $A365_APP_ID"
echo "     • Display name:    OpenClaw Agent"
echo ""
echo "  3. Copy the 'AA Instance ID' (GUID format) from the result."
echo ""
echo -e "  Reference: ${BOLD}https://learn.microsoft.com/en-us/microsoft-agent-365/developer/registration${RESET}"
echo ""
read -rp "Paste the AA_INSTANCE_ID here: " AA_INSTANCE_ID

if [ -z "$AA_INSTANCE_ID" ]; then
  warn "AA_INSTANCE_ID not provided. You must add it to .env manually before the container will start."
  AA_INSTANCE_ID="<REPLACE_WITH_AA_INSTANCE_ID>"
fi

# ---------------------------------------------------------------------------
# Step 3 (continued): Create the FIC now that we have AA_INSTANCE_ID
# ---------------------------------------------------------------------------
step "Step 3 (continued) — Create FIC with AA_INSTANCE_ID as Subject"

log "Creating federated identity credential..."

FIC_PARAMS=$(cat <<JSON
{
  "name": "aa-instance-fic",
  "issuer": "api://AzureAdTokenExchange",
  "subject": "${AA_INSTANCE_ID}",
  "audiences": ["api://AzureAdTokenExchange"],
  "description": "FIC for OpenClaw autonomous agent — T2 token exchange"
}
JSON
)

if ! $DRY_RUN && [ "$AA_INSTANCE_ID" != "<REPLACE_WITH_AA_INSTANCE_ID>" ]; then
  # Check if FIC already exists
  EXISTING_FIC=$(az ad app federated-credential list --id "$A365_APP_ID" \
    --query "[?name=='aa-instance-fic'].id | [0]" -o tsv 2>/dev/null || echo "")

  if [ -n "$EXISTING_FIC" ] && [ "$EXISTING_FIC" != "null" ]; then
    log "FIC already exists. Deleting and recreating with new subject..."
    az ad app federated-credential delete --id "$A365_APP_ID" --federated-credential-id "$EXISTING_FIC" -o none
  fi

  az ad app federated-credential create \
    --id "$A365_APP_ID" \
    --parameters "$FIC_PARAMS" \
    -o none
  ok "FIC created — Subject: $AA_INSTANCE_ID"
else
  echo "[dry-run or missing AA_INSTANCE_ID] Would create FIC with subject: $AA_INSTANCE_ID"
fi

# ---------------------------------------------------------------------------
# Step 5: Capture OWNER values from current az login
# ---------------------------------------------------------------------------
step "Step 5 — Capture Owner Identity"

OWNER="$DEPLOYER_UPN"
OWNER_AAD_ID="$DEPLOYER_OID"

echo "  OWNER      : $OWNER"
echo "  OWNER_AAD_ID: $OWNER_AAD_ID"
echo ""
read -rp "Use your logged-in user as OWNER? [Y/n]: " CONFIRM_OWNER
if [[ "${CONFIRM_OWNER:-Y}" =~ ^[Nn] ]]; then
  read -rp "Enter OWNER UPN: " OWNER
  OWNER_AAD_ID=$(az ad user show --id "$OWNER" --query id -o tsv 2>/dev/null || echo "")
  if [ -z "$OWNER_AAD_ID" ]; then
    warn "Could not resolve AAD ID for $OWNER. Enter it manually."
    read -rp "Enter OWNER_AAD_ID: " OWNER_AAD_ID
  fi
fi

ok "Owner: $OWNER ($OWNER_AAD_ID)"

# ---------------------------------------------------------------------------
# Step 6: Calendar sharing reminder
# ---------------------------------------------------------------------------
step "Step 6 — Calendar Sharing (ACTION REQUIRED)"

echo ""
echo -e "${YELLOW}  Share your calendar with the agent user:${RESET}"
echo ""
echo "  1. Open Outlook Web App (https://outlook.office.com) as $OWNER"
echo "  2. Calendar → right-click your calendar → Sharing and permissions"
echo "  3. Add: $AGENT_IDENTITY   Permission: Can edit"
echo "  4. Save. Wait ~5 min."
echo ""
read -rp "Press Enter once calendar sharing is configured (or skip for now)..." _

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
step "Output — Generated .env values"

OUTPUT=$(cat <<EOF
# =============================================================================
# Generated by scripts/az-entra-setup.sh on $(date)
# Copy these values into your .env file
# =============================================================================

# Microsoft Agent 365 credentials
A365_APP_ID=${A365_APP_ID}
A365_APP_PASSWORD=${A365_APP_PASSWORD}
A365_TENANT_ID=${TENANT_ID}

# Autonomous Agent instance
AA_INSTANCE_ID=${AA_INSTANCE_ID}

# Identity
AGENT_IDENTITY=${AGENT_IDENTITY}
OWNER=${OWNER}
OWNER_AAD_ID=${OWNER_AAD_ID}

# Azure OpenAI (fill these in from Azure Portal → OpenAI resource)
AZURE_OPENAI_API_KEY=
AZURE_OPENAI_ENDPOINT=
EOF
)

echo ""
echo "$OUTPUT"
echo ""

if ! $DRY_RUN; then
  echo "$OUTPUT" > "$ENV_FILE"
  ok "Values written to: $ENV_FILE"
  echo ""
  echo "Next steps:"
  echo "  1. Fill in AZURE_OPENAI_API_KEY and AZURE_OPENAI_ENDPOINT in $ENV_FILE"
  echo "  2. Copy values to your .env: cat $ENV_FILE >> .env  (or merge manually)"
  echo "  3. Start the container:  docker compose up -d"
  echo "  4. Follow: setup/AZURE_VM_DEPLOY.md to deploy to Azure"
fi

step "Done 🎉"
echo ""
echo "Summary:"
echo "  App Registration : $A365_APP_ID"
echo "  Agent UPN        : $AGENT_IDENTITY"
echo "  AA Instance ID   : $AA_INSTANCE_ID"
echo "  Owner            : $OWNER"
echo ""
echo "Remaining portal steps:"
echo "  • Assign M365 license to $AGENT_IDENTITY (if not done)"
echo "  • Share calendar with $AGENT_IDENTITY"
echo "  • Configure Azure Bot messaging endpoint (setup/M365_AGENTS_SETUP.md)"
