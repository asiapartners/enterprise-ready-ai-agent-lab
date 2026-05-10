#!/usr/bin/env bash
# =============================================================================
# scripts/azure-keyvault-seed.sh — Push .env secrets into Azure Key Vault
#
# Usage:
#   bash scripts/azure-keyvault-seed.sh                       # use last deployment
#   bash scripts/azure-keyvault-seed.sh --vault kv-oca365-dev
#   bash scripts/azure-keyvault-seed.sh --env-file .env.staging
#   bash scripts/azure-keyvault-seed.sh --sync-env            # ALSO write KV outputs back into .env
#
# Environment variables:
#   AZ_KEYVAULT          Key Vault name (override deployment outputs)
#   AZ_DRY_RUN=1         echo commands instead of executing
#
# Secrets pushed (only if non-empty in .env):
#   A365_APP_PASSWORD              → A365-APP-PASSWORD
#   ANTHROPIC_API_KEY              → ANTHROPIC-API-KEY
#   APPINSIGHTS_CONNECTION_STRING  → APPINSIGHTS-CONNECTION-STRING
#   OPENAI_API_KEY                 → OPENAI-API-KEY        (optional)
#   OPENROUTER_API_KEY             → OPENROUTER-API-KEY    (optional)
#   AZURE_OPENAI_API_KEY           → AZURE-OPENAI-API-KEY  (optional)
#
# Exit codes:
#   0 success | 1 missing prereq | 2 vault not found
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ROOT="$(repo_root)"
ENV_FILE="$ROOT/.env"
VAULT="${AZ_KEYVAULT:-}"
SYNC_ENV=0

print_help() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while (($#)); do
  case "$1" in
    --vault)     shift; VAULT="${1:?--vault requires a value}" ;;
    --env-file)  shift; ENV_FILE="${1:?--env-file requires a value}" ;;
    --sync-env)  SYNC_ENV=1 ;;
    -h|--help)   print_help ;;
    *) fail "Unknown argument: $1 (try --help)" ;;
  esac
  shift
done

require_cmd az jq
[[ -f "$ENV_FILE" ]] || fail "Env file not found: $ENV_FILE"

# Resolve vault from last deployment if not supplied
if [[ -z "$VAULT" ]]; then
  OUTPUTS_FILE="$ROOT/iac/.last-deployment.json"
  [[ -f "$OUTPUTS_FILE" ]] \
    || fail "No --vault and no $OUTPUTS_FILE. Run scripts/azure-provision.sh first or pass --vault."
  KV_URI="$(jq -r '.outputs.keyVaultUri // empty' "$OUTPUTS_FILE")"
  [[ -n "$KV_URI" ]] || fail "keyVaultUri not present in $OUTPUTS_FILE"
  # Extract vault name from URI: https://<name>.vault.azure.net/
  VAULT="$(echo "$KV_URI" | sed -E 's|https://([^.]+)\..*|\1|')"
fi

az keyvault show --name "$VAULT" >/dev/null 2>&1 \
  || fail "Key Vault not found or access denied: $VAULT"

title "Seeding secrets into Key Vault: $VAULT"

# Map ENV_VAR → KV_SECRET_NAME
declare -A SECRET_MAP=(
  [A365_APP_PASSWORD]="A365-APP-PASSWORD"
  [ANTHROPIC_API_KEY]="ANTHROPIC-API-KEY"
  [APPINSIGHTS_CONNECTION_STRING]="APPINSIGHTS-CONNECTION-STRING"
  [OPENAI_API_KEY]="OPENAI-API-KEY"
  [OPENROUTER_API_KEY]="OPENROUTER-API-KEY"
  [AZURE_OPENAI_API_KEY]="AZURE-OPENAI-API-KEY"
)

# Read a single value from ENV_FILE without sourcing it (safer than `set -a`)
read_env() {
  local key="$1"
  awk -F= -v k="$key" '
    /^[[:space:]]*#/ { next }
    $1 == k { sub(/^[^=]*=/,""); print; exit }
  ' "$ENV_FILE" | sed 's/^"//; s/"$//; s/^'\''//; s/'\''$//'
}

count_pushed=0
count_skipped=0

for env_key in "${!SECRET_MAP[@]}"; do
  kv_name="${SECRET_MAP[$env_key]}"
  value="$(read_env "$env_key")"
  if [[ -z "$value" ]]; then
    debug "Skip $env_key (empty)"
    count_skipped=$((count_skipped + 1))
    continue
  fi
  info "Set $kv_name = $(mask_secret "$value")"
  dry_run_echo az keyvault secret set \
    --vault-name "$VAULT" \
    --name "$kv_name" \
    --value "$value" \
    -o none
  count_pushed=$((count_pushed + 1))
done

pass "Pushed $count_pushed secrets ($count_skipped skipped)"

# ─── Optional: sync deployment outputs back to .env ──────────────────────────
if [[ "$SYNC_ENV" == "1" ]]; then
  OUTPUTS_FILE="$ROOT/iac/.last-deployment.json"
  if [[ -f "$OUTPUTS_FILE" ]]; then
    title "Syncing deployment outputs to .env"
    upsert_env() {
      local key="$1" val="$2"
      [[ -z "$val" || "$val" == "null" ]] && return 0
      if grep -qE "^${key}=" "$ENV_FILE"; then
        sed "s|^${key}=.*|${key}=${val}|" "$ENV_FILE" > "${ENV_FILE}.tmp" && mv "${ENV_FILE}.tmp" "$ENV_FILE"
      else
        printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
      fi
      pass "$key updated"
    }
    upsert_env KEY_VAULT_URI                 "$(jq -r '.outputs.keyVaultUri        // empty' "$OUTPUTS_FILE")"
    upsert_env APPINSIGHTS_CONNECTION_STRING "$(jq -r '.outputs.appInsightsConnectionString // empty' "$OUTPUTS_FILE")"
  else
    warn "$OUTPUTS_FILE not found — cannot --sync-env"
  fi
fi

title "Done"
jq -n \
  --arg vault "$VAULT" \
  --argjson pushed "$count_pushed" \
  --argjson skipped "$count_skipped" \
  '{vault: $vault, secretsPushed: $pushed, secretsSkipped: $skipped}'
