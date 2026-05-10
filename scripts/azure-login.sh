#!/usr/bin/env bash
# =============================================================================
# scripts/azure-login.sh — Authenticate az CLI and select subscription
#
# Usage:
#   bash scripts/azure-login.sh                          # device-code (interactive)
#   bash scripts/azure-login.sh --device-code            # explicit device-code
#   bash scripts/azure-login.sh --service-principal      # CI / non-interactive
#   bash scripts/azure-login.sh --subscription <sub-id>  # override target sub
#   pnpm run az:login -- --service-principal
#
# Environment variables:
#   AZ_TENANT_ID         (recommended) tenant to log in to
#   AZ_SUBSCRIPTION      (optional) subscription id or name to set as active
#   AZ_CLIENT_ID         required for --service-principal
#   AZ_CLIENT_SECRET     required for --service-principal
#   AZ_DRY_RUN=1         echo commands instead of running them
#
# Behaviour:
#   - If already logged in to AZ_TENANT_ID, no-op (just sets the subscription).
#   - On success, prints a JSON summary to stdout.
#
# Exit codes:
#   0 success | 1 missing prereq | 2 auth failure
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MODE="device-code"
SUBSCRIPTION="${AZ_SUBSCRIPTION:-}"
TENANT_ID="${AZ_TENANT_ID:-}"

print_help() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while (($#)); do
  case "$1" in
    --device-code)        MODE="device-code" ;;
    --service-principal)  MODE="service-principal" ;;
    --subscription)       shift; SUBSCRIPTION="${1:?--subscription requires a value}" ;;
    --tenant)             shift; TENANT_ID="${1:?--tenant requires a value}" ;;
    -h|--help)            print_help ;;
    *) fail "Unknown argument: $1 (try --help)" ;;
  esac
  shift
done

require_cmd az jq

title "Azure CLI login ($MODE)"

# ─── Already-logged-in short-circuit ─────────────────────────────────────────
CURRENT_TENANT="$(az account show --query tenantId -o tsv 2>/dev/null || true)"
if [[ -n "$CURRENT_TENANT" ]]; then
  if [[ -z "$TENANT_ID" || "$CURRENT_TENANT" == "$TENANT_ID" ]]; then
    pass "Already logged in to tenant $CURRENT_TENANT"
    SKIP_LOGIN=1
  else
    info "Currently logged in to $CURRENT_TENANT, switching to $TENANT_ID..."
    SKIP_LOGIN=0
  fi
else
  SKIP_LOGIN=0
fi

# ─── Login ───────────────────────────────────────────────────────────────────
if [[ "$SKIP_LOGIN" != "1" ]]; then
  case "$MODE" in
    device-code)
      if ! is_interactive && [[ "${AZ_DRY_RUN:-0}" != "1" ]]; then
        fail "Device-code login requires an interactive terminal. Use --service-principal for CI."
      fi
      if [[ -n "$TENANT_ID" ]]; then
        dry_run_echo az login --use-device-code --tenant "$TENANT_ID" >/dev/null
      else
        dry_run_echo az login --use-device-code >/dev/null
      fi
      ;;
    service-principal)
      require_env AZ_CLIENT_ID AZ_CLIENT_SECRET AZ_TENANT_ID
      info "Logging in as service principal $(mask_secret "$AZ_CLIENT_ID")"
      dry_run_echo az login \
        --service-principal \
        --username "$AZ_CLIENT_ID" \
        --password "$AZ_CLIENT_SECRET" \
        --tenant "$AZ_TENANT_ID" >/dev/null
      TENANT_ID="$AZ_TENANT_ID"
      ;;
    *) fail "Unknown mode: $MODE" ;;
  esac
  pass "Logged in"
fi

# ─── Subscription select ─────────────────────────────────────────────────────
if [[ -n "$SUBSCRIPTION" ]]; then
  info "Setting active subscription: $SUBSCRIPTION"
  dry_run_echo az account set --subscription "$SUBSCRIPTION"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
if [[ "${AZ_DRY_RUN:-0}" == "1" ]]; then
  pass "Dry-run complete"
  exit 0
fi

ACCOUNT_JSON="$(az account show -o json)"
TENANT="$(echo "$ACCOUNT_JSON"      | jq -r '.tenantId')"
SUB_ID="$(echo "$ACCOUNT_JSON"      | jq -r '.id')"
SUB_NAME="$(echo "$ACCOUNT_JSON"    | jq -r '.name')"
USER_NAME="$(echo "$ACCOUNT_JSON"   | jq -r '.user.name')"

pass "Tenant:       $TENANT"
pass "Subscription: $SUB_NAME ($SUB_ID)"
pass "Identity:     $USER_NAME"

# Machine-readable summary on stdout (everything else went to stderr)
jq -n \
  --arg tenantId "$TENANT" \
  --arg subscriptionId "$SUB_ID" \
  --arg subscriptionName "$SUB_NAME" \
  --arg user "$USER_NAME" \
  --arg mode "$MODE" \
  '{tenantId:$tenantId, subscriptionId:$subscriptionId, subscriptionName:$subscriptionName, user:$user, mode:$mode}'
