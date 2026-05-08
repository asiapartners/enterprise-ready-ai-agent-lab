#!/usr/bin/env bash
# =============================================================================
# openclaw-a365-agent-lab — Phase 1 deployment
#
# Usage:  ./infra/deploy.sh [env]
#         env defaults to "dev"
#
# Provisions Azure resources via main.bicep, then populates Key Vault
# from your local .env so the VM can fetch secrets via Managed Identity
# at boot.
# =============================================================================

set -euo pipefail

ENV="${1:-dev}"
LOCATION="swedencentral"
RG="rg-openclaw-lab-${ENV}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
BICEP="${REPO_ROOT}/infra/main.bicep"
PARAMS="${REPO_ROOT}/infra/parameters.${ENV}.bicepparam"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v az  >/dev/null || { echo "❌ az CLI not installed. See docs/AZURE_VM_DEPLOY.md."; exit 1; }
command -v jq  >/dev/null || { echo "❌ jq not installed. brew install jq"; exit 1; }
[ -f "$ENV_FILE" ] || { echo "❌ $ENV_FILE missing. cp .env.example .env and fill in."; exit 1; }
[ -f "$BICEP" ]    || { echo "❌ $BICEP missing"; exit 1; }
[ -f "$PARAMS" ]   || { echo "❌ $PARAMS missing"; exit 1; }

az account show >/dev/null 2>&1 || { echo "❌ Run: az login"; exit 1; }

# Source .env (skipping comments/blank)
set -a
# shellcheck disable=SC2046
. <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE")
set +a

# ---------------------------------------------------------------------------
# Discover values for the Bicep deployment
# ---------------------------------------------------------------------------
echo "▶ Detecting your public IP..."
MY_IP=$(curl -fsS https://api.ipify.org)
export SSH_SOURCE_PREFIX="${MY_IP}/32"
echo "  SSH allowed from: $SSH_SOURCE_PREFIX"

echo "▶ Reading SSH public key..."
if   [ -f "$HOME/.ssh/id_ed25519.pub" ]; then KEY_FILE="$HOME/.ssh/id_ed25519.pub"
elif [ -f "$HOME/.ssh/id_rsa.pub"     ]; then KEY_FILE="$HOME/.ssh/id_rsa.pub"
else echo "❌ No SSH public key at ~/.ssh/id_ed25519.pub or id_rsa.pub. Generate with: ssh-keygen -t ed25519"; exit 1
fi
export ADMIN_PUBLIC_KEY="$(cat "$KEY_FILE")"
echo "  Using key: $KEY_FILE"

echo "▶ Resolving your AAD Object ID..."
export DEPLOYER_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
echo "  Deployer Object ID: $DEPLOYER_PRINCIPAL_ID"

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------
echo "▶ Creating resource group $RG in $LOCATION..."
az group create -n "$RG" -l "$LOCATION" -o none

# ---------------------------------------------------------------------------
# Bicep deployment
# ---------------------------------------------------------------------------
echo "▶ Running Bicep deployment (~10 min for VM)..."
DEPLOY_NAME="openclaw-${ENV}-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
  --resource-group "$RG" \
  --name "$DEPLOY_NAME" \
  --template-file "$BICEP" \
  --parameters "$PARAMS" \
  --parameters \
      adminPublicKey="$ADMIN_PUBLIC_KEY" \
      sshSourceAddressPrefix="$SSH_SOURCE_PREFIX" \
      deployerPrincipalId="$DEPLOYER_PRINCIPAL_ID" \
  -o none

OUT=$(az deployment group show -g "$RG" -n "$DEPLOY_NAME" --query properties.outputs -o json)
FQDN=$(echo "$OUT" | jq -r .fqdn.value)
KV=$(echo "$OUT" | jq -r .keyVaultName.value)
SSH_CMD=$(echo "$OUT" | jq -r .sshCommand.value)
MSG_URL=$(echo "$OUT" | jq -r .messagingUrl.value)

mkdir -p "${REPO_ROOT}/infra"
echo "$OUT" > "${REPO_ROOT}/infra/.outputs.${ENV}.json"

echo "  FQDN:           $FQDN"
echo "  Key Vault:      $KV"

# ---------------------------------------------------------------------------
# Populate Key Vault with secrets from .env
# ---------------------------------------------------------------------------
echo "▶ Uploading secrets to Key Vault $KV..."
for name in A365_APP_PASSWORD AZURE_OPENAI_API_KEY; do
  value="${!name:-}"
  if [ -z "$value" ] || [[ "$value" == "your-app-password-here" ]] || [[ "$value" == sk-ant-* ]]; then
    echo "  ⚠️  $name missing/placeholder in .env — skipping. Set it later with:"
    echo "      az keyvault secret set --vault-name $KV --name $name --value '<...>'"
    continue
  fi
  az keyvault secret set --vault-name "$KV" --name "$name" --value "$value" -o none
  echo "  ✔ $name"
done

# ---------------------------------------------------------------------------
# Push non-secret env to /etc/openclaw/env.public on the VM (over SSH)
# ---------------------------------------------------------------------------
echo "▶ Writing non-secret env vars to VM /etc/openclaw/env.public ..."
PUBLIC_ENV=$(cat <<EOF
OPENCLAW_MODEL=${OPENCLAW_MODEL:-azure/gpt-4o}
OPENCLAW_FALLBACK_MODELS=${OPENCLAW_FALLBACK_MODELS:-}
OPENCLAW_LOG_LEVEL=${OPENCLAW_LOG_LEVEL:-info}
NETWORK_MODE=${NETWORK_MODE:-restricted}
NETWORK_ALLOWLIST=${NETWORK_ALLOWLIST:-}
DM_POLICY=${DM_POLICY:-pairing}
BUSINESS_HOURS_START=${BUSINESS_HOURS_START:-08:00}
BUSINESS_HOURS_END=${BUSINESS_HOURS_END:-18:00}
TIMEZONE=${TIMEZONE:-Europe/Stockholm}

A365_APP_ID=${A365_APP_ID}
A365_TENANT_ID=${A365_TENANT_ID}
AA_INSTANCE_ID=${AA_INSTANCE_ID}
AGENT_IDENTITY=${AGENT_IDENTITY}
OWNER=${OWNER}
OWNER_AAD_ID=${OWNER_AAD_ID}
AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
EOF
)

# Wait for VM to be SSH-reachable (cloud-init still booting)
echo "▶ Waiting for SSH on $FQDN (cloud-init can take ~5-10 min)..."
for i in {1..60}; do
  if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 azureuser@"$FQDN" 'true' 2>/dev/null; then
    echo "  SSH reachable."
    break
  fi
  printf '.'
  sleep 10
done

ssh azureuser@"$FQDN" "echo \"$PUBLIC_ENV\" | sudo tee /etc/openclaw/env.public >/dev/null && sudo chmod 644 /etc/openclaw/env.public && sudo systemctl restart openclaw-fetch-secrets.service openclaw-a365.service" || {
  echo "⚠️  Could not push env over SSH. Run manually:"
  echo "    $SSH_CMD"
  echo "    sudo \${EDITOR:-vi} /etc/openclaw/env.public"
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<EOF

============================================================================
✅ Deployment complete.

   FQDN:              $FQDN
   Messaging URL:     $MSG_URL
   Key Vault:         $KV
   SSH:               $SSH_CMD

Next steps:
  1. Update your Azure Bot resource (Configuration → Messaging endpoint):
       $MSG_URL
  2. DM your agent in Teams.
  3. Tail logs:
       $SSH_CMD 'sudo docker logs -f openclaw-a365'
============================================================================
EOF
