#!/usr/bin/env bash
# =============================================================================
# scripts/azure-app-registration.sh — Create AAD App Registration + FIC + consent
#
# Usage:
#   bash scripts/azure-app-registration.sh \
#     --display-name "openclaw-agent365-dev" \
#     --agent-identity agent@contoso.com \
#     [--write-env]
#
# Environment variables:
#   AZ_TENANT_ID         (recommended) target tenant
#   AGENT_IDENTITY       agent UPN (alternative to --agent-identity)
#   AZ_DRY_RUN=1         echo commands instead of executing
#
# What it does (idempotent):
#   1. Creates (or reuses) an Entra ID App Registration with single-tenant audience.
#   2. Creates a service principal for the app.
#   3. Adds Microsoft Graph application permissions:
#        User.Read, Calendars.ReadWrite, Mail.Send
#   4. Grants tenant-wide admin consent for the service principal.
#   5. Creates a client secret (validity: 6 months) — emitted ONCE to stdout.
#   6. Configures a Federated Identity Credential bound to AGENT_IDENTITY
#      (subject = "agent://<upn>") for use by the T1→T2→Agent FIC flow.
#   7. Optionally appends A365_APP_ID, A365_APP_PASSWORD, AA_INSTANCE_ID to .env
#      when --write-env is passed.
#
# Output:
#   JSON object on stdout with appId, tenantId, principalId, clientSecret*, ficId.
#   *secret only emitted on initial creation; re-runs report secret as null.
#
# Exit codes:
#   0 success | 1 missing prereq | 2 az error
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DISPLAY_NAME=""
AGENT_UPN="${AGENT_IDENTITY:-}"
WRITE_ENV=0

print_help() { sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while (($#)); do
  case "$1" in
    --display-name)    shift; DISPLAY_NAME="${1:?--display-name requires a value}" ;;
    --agent-identity)  shift; AGENT_UPN="${1:?--agent-identity requires a value}" ;;
    --write-env)       WRITE_ENV=1 ;;
    -h|--help)         print_help ;;
    *) fail "Unknown argument: $1 (try --help)" ;;
  esac
  shift
done

require_cmd az jq
[[ -n "$DISPLAY_NAME" ]] || fail "Missing --display-name (or pass via flag)."
[[ -n "$AGENT_UPN"    ]] || fail "Missing --agent-identity / AGENT_IDENTITY."

TENANT_ID="${AZ_TENANT_ID:-$(az account show --query tenantId -o tsv 2>/dev/null || true)}"
[[ -n "$TENANT_ID" ]] || fail "Cannot determine tenant. Run scripts/azure-login.sh first."

title "App Registration: $DISPLAY_NAME"

# Microsoft Graph appId is well-known
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

# Permission GUIDs (Application role IDs on Microsoft Graph)
# Lookup: az ad sp show --id $GRAPH_APP_ID --query "appRoles[?value=='User.Read.All'].id" -o tsv
PERM_USER_READ="e1fe6dd8-ba31-4d61-89e7-88639da4683d"          # User.Read (delegated)  — fallback
PERM_CALENDARS_RW="ef54d2bf-783f-4e0f-bca1-3210c0444d99"        # Calendars.ReadWrite (app)
PERM_MAIL_SEND="b633e1c5-b582-4048-a93e-9f11b44c7e96"           # Mail.Send (app)

# ─── 1. App Registration (create or reuse) ───────────────────────────────────
EXISTING_APP_ID="$(az ad app list --display-name "$DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)"
if [[ -n "$EXISTING_APP_ID" ]]; then
  pass "Reusing existing App Registration: $EXISTING_APP_ID"
  APP_ID="$EXISTING_APP_ID"
else
  info "Creating App Registration..."
  APP_ID="$(dry_run_echo az ad app create \
    --display-name "$DISPLAY_NAME" \
    --sign-in-audience AzureADMyOrg \
    --query appId -o tsv)"
  [[ -n "$APP_ID" ]] || fail "App creation failed."
  pass "Created App: $APP_ID"
fi

# ─── 2. Service Principal ────────────────────────────────────────────────────
SP_ID="$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv 2>/dev/null || true)"
if [[ -z "$SP_ID" ]]; then
  info "Creating Service Principal..."
  SP_ID="$(dry_run_echo az ad sp create --id "$APP_ID" --query id -o tsv)"
  pass "Created SP: $SP_ID"
else
  pass "Reusing existing SP: $SP_ID"
fi

# ─── 3. Graph Permissions ────────────────────────────────────────────────────
info "Adding Microsoft Graph permissions..."
add_perm() {
  local perm_id="$1" type="$2" name="$3"
  if az ad app permission list --id "$APP_ID" \
       --query "[?resourceAppId=='$GRAPH_APP_ID'].resourceAccess[?id=='$perm_id'].id" -o tsv \
       2>/dev/null | grep -q "$perm_id"; then
    pass "Permission already present: $name"
  else
    dry_run_echo az ad app permission add \
      --id "$APP_ID" \
      --api "$GRAPH_APP_ID" \
      --api-permissions "${perm_id}=${type}" >/dev/null
    pass "Added permission: $name"
  fi
}
add_perm "$PERM_USER_READ"     "Scope" "User.Read (delegated)"
add_perm "$PERM_CALENDARS_RW"  "Role"  "Calendars.ReadWrite (application)"
add_perm "$PERM_MAIL_SEND"     "Role"  "Mail.Send (application)"

# ─── 4. Admin Consent ────────────────────────────────────────────────────────
info "Granting admin consent (tenant-wide)..."
if dry_run_echo az ad app permission admin-consent --id "$APP_ID" 2>/dev/null; then
  pass "Admin consent granted"
else
  warn "Admin consent failed — you may need a Global Admin role. Re-run: az ad app permission admin-consent --id $APP_ID"
fi

# ─── 5. Client Secret ────────────────────────────────────────────────────────
# Secret values can never be retrieved after creation. We only mint a new one if
# the app currently has zero credentials, OR if --write-env is set and the user
# confirms overwriting.
SECRET_VALUE=""
EXISTING_CREDS="$(az ad app credential list --id "$APP_ID" --query "length([])" -o tsv 2>/dev/null || echo 0)"
if [[ "$EXISTING_CREDS" -eq 0 ]]; then
  info "Creating client secret (valid 6 months)..."
  SECRET_VALUE="$(dry_run_echo az ad app credential reset \
    --id "$APP_ID" \
    --append \
    --display-name "openclaw-agent365-secret-$(date +%Y%m%d)" \
    --years 0 \
    --query password -o tsv)"
  pass "Client secret created (shown ONCE below — store securely)"
else
  warn "App already has $EXISTING_CREDS credential(s). Skipping secret creation."
  warn "To rotate: az ad app credential reset --id $APP_ID --append"
fi

# ─── 6. Federated Identity Credential ────────────────────────────────────────
# Subject convention used by Microsoft Agent 365: "agent://<upn>"
FIC_NAME="agent-${AGENT_UPN//[^a-zA-Z0-9]/-}"
FIC_SUBJECT="agent://${AGENT_UPN}"
FIC_ISSUER="https://login.microsoftonline.com/${TENANT_ID}/v2.0"

EXISTING_FIC_ID="$(az ad app federated-credential list --id "$APP_ID" \
  --query "[?name=='$FIC_NAME'].id" -o tsv 2>/dev/null || true)"

if [[ -n "$EXISTING_FIC_ID" ]]; then
  pass "Federated credential already configured: $FIC_NAME"
  FIC_ID="$EXISTING_FIC_ID"
else
  info "Creating federated identity credential for $AGENT_UPN..."
  FIC_ID="$(dry_run_echo az ad app federated-credential create \
    --id "$APP_ID" \
    --parameters "$(jq -n \
      --arg name "$FIC_NAME" \
      --arg subject "$FIC_SUBJECT" \
      --arg issuer "$FIC_ISSUER" \
      '{name:$name, issuer:$issuer, subject:$subject, audiences:["api://AzureADTokenExchange"], description:"Agent 365 federated identity for OpenClaw"}')" \
    --query id -o tsv)"
  pass "FIC created: $FIC_NAME"
fi

# ─── 7. Optional: append to .env ─────────────────────────────────────────────
if [[ "$WRITE_ENV" == "1" ]]; then
  ENV_FILE="$(repo_root)/.env"
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$(repo_root)/.env.example" "$ENV_FILE"
    info "Created $ENV_FILE from .env.example"
  fi
  # Update or append a single key=value pair
  upsert_env() {
    local key="$1" val="$2"
    if grep -qE "^${key}=" "$ENV_FILE"; then
      # macOS-compatible in-place edit: write to temp and move
      sed "s|^${key}=.*|${key}=${val}|" "$ENV_FILE" > "${ENV_FILE}.tmp" && mv "${ENV_FILE}.tmp" "$ENV_FILE"
    else
      printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
    fi
  }
  upsert_env A365_APP_ID    "$APP_ID"
  upsert_env A365_TENANT_ID "$TENANT_ID"
  upsert_env AGENT_IDENTITY "$AGENT_UPN"
  if [[ -n "$SECRET_VALUE" ]]; then
    upsert_env A365_APP_PASSWORD "$SECRET_VALUE"
    pass "Wrote A365_APP_PASSWORD to .env"
  fi
  pass "Updated .env with App Registration values"
fi

# ─── Summary (machine-readable) ──────────────────────────────────────────────
title "Summary"
pass "App ID:        $APP_ID"
pass "Tenant ID:     $TENANT_ID"
pass "SP ID:         $SP_ID"
pass "FIC name:      $FIC_NAME"
pass "FIC subject:   $FIC_SUBJECT"
[[ -n "$SECRET_VALUE" ]] && pass "Client secret: $(mask_secret "$SECRET_VALUE")  (full value emitted as JSON below)"

jq -n \
  --arg appId          "$APP_ID" \
  --arg tenantId       "$TENANT_ID" \
  --arg principalId    "$SP_ID" \
  --arg ficId          "$FIC_ID" \
  --arg ficSubject     "$FIC_SUBJECT" \
  --arg agentIdentity  "$AGENT_UPN" \
  --arg clientSecret   "${SECRET_VALUE}" \
  '{
    appId: $appId,
    tenantId: $tenantId,
    principalId: $principalId,
    ficId: $ficId,
    ficSubject: $ficSubject,
    agentIdentity: $agentIdentity,
    clientSecret: (if $clientSecret == "" then null else $clientSecret end)
  }'
