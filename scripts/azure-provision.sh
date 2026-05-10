#!/usr/bin/env bash
# =============================================================================
# scripts/azure-provision.sh — Deploy iac/azure-resources.bicep
#
# Usage:
#   bash scripts/azure-provision.sh                                    # uses iac/parameters.json
#   bash scripts/azure-provision.sh --resource-group rg-oca365-dev
#   AZ_DRY_RUN=1 bash scripts/azure-provision.sh                       # what-if only
#
# Environment variables (override parameters.json):
#   AZ_RESOURCE_GROUP    target resource group (required)
#   AZ_LOCATION          Azure region                       (default: eastus)
#   AZ_DEPLOYMENT_NAME   deployment name                    (default: oca365-<timestamp>)
#   AZ_PARAMETERS_FILE   bicep parameters file              (default: iac/parameters.json)
#   AZ_DRY_RUN=1         use `az deployment group what-if` instead of `create`
#
# Behaviour (idempotent):
#   - Creates the resource group if absent (tagged managed-by=openclaw-agent365).
#   - Runs validation (`az deployment group validate`); exits non-zero on failure.
#   - Deploys the bicep template.
#   - Captures all outputs into iac/.last-deployment.json (gitignored).
#
# Exit codes:
#   0 success | 1 missing prereq | 2 validation failure | 3 deployment failure
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ROOT="$(repo_root)"
RESOURCE_GROUP="${AZ_RESOURCE_GROUP:-}"
LOCATION="${AZ_LOCATION:-eastus}"
PARAMETERS_FILE="${AZ_PARAMETERS_FILE:-$ROOT/iac/parameters.json}"
DEPLOYMENT_NAME="${AZ_DEPLOYMENT_NAME:-oca365-$(date +%Y%m%d-%H%M%S)}"
TEMPLATE_FILE="$ROOT/iac/azure-resources.bicep"
OUTPUTS_FILE="$ROOT/iac/.last-deployment.json"

print_help() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while (($#)); do
  case "$1" in
    --resource-group) shift; RESOURCE_GROUP="${1:?--resource-group requires a value}" ;;
    --location)       shift; LOCATION="${1:?--location requires a value}" ;;
    --parameters)     shift; PARAMETERS_FILE="${1:?--parameters requires a value}" ;;
    --name)           shift; DEPLOYMENT_NAME="${1:?--name requires a value}" ;;
    -h|--help)        print_help ;;
    *) fail "Unknown argument: $1 (try --help)" ;;
  esac
  shift
done

require_cmd az jq
[[ -n "$RESOURCE_GROUP" ]] || fail "Missing --resource-group / AZ_RESOURCE_GROUP."
[[ -f "$TEMPLATE_FILE"  ]] || fail "Bicep template not found: $TEMPLATE_FILE"
[[ -f "$PARAMETERS_FILE" ]] || fail "Parameters file not found: $PARAMETERS_FILE"

az account show >/dev/null 2>&1 \
  || fail "Not logged in to Azure. Run scripts/azure-login.sh first."

title "Provisioning Azure resources"
info "Resource group: $RESOURCE_GROUP   Location: $LOCATION"
info "Template:       $TEMPLATE_FILE"
info "Parameters:     $PARAMETERS_FILE"
info "Deployment:     $DEPLOYMENT_NAME"

# ─── Resource group ──────────────────────────────────────────────────────────
if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  pass "Resource group exists: $RESOURCE_GROUP"
else
  info "Creating resource group..."
  dry_run_echo az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags managed-by=openclaw-agent365 created-by=azure-provision.sh \
    >/dev/null
  pass "Created resource group"
fi

# ─── Validate (always) ───────────────────────────────────────────────────────
info "Validating deployment..."
if ! az deployment group validate \
       --resource-group "$RESOURCE_GROUP" \
       --template-file "$TEMPLATE_FILE" \
       --parameters "@$PARAMETERS_FILE" \
       -o none 2>/dev/null; then
  fail "Bicep validation failed. Re-run for details: az deployment group validate --resource-group $RESOURCE_GROUP --template-file $TEMPLATE_FILE --parameters @$PARAMETERS_FILE"
fi
pass "Validation passed"

# ─── Deploy or What-If ───────────────────────────────────────────────────────
if [[ "${AZ_DRY_RUN:-0}" == "1" ]]; then
  title "What-If (AZ_DRY_RUN=1)"
  az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --name "$DEPLOYMENT_NAME"
  pass "What-If complete (no changes applied)"
  exit 0
fi

title "Deploying..."
DEPLOY_OUTPUT="$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "@$PARAMETERS_FILE" \
  --name "$DEPLOYMENT_NAME" \
  -o json)" \
  || fail "Deployment failed. Check Azure portal: portal.azure.com → Resource Groups → $RESOURCE_GROUP → Deployments → $DEPLOYMENT_NAME"

# ─── Persist outputs ─────────────────────────────────────────────────────────
mkdir -p "$(dirname "$OUTPUTS_FILE")"
echo "$DEPLOY_OUTPUT" | jq '{
  resourceGroup: "'"$RESOURCE_GROUP"'",
  deploymentName: .name,
  timestamp: .properties.timestamp,
  outputs: (.properties.outputs // {} | with_entries(.value = .value.value))
}' > "$OUTPUTS_FILE"

pass "Outputs saved to: ${OUTPUTS_FILE#$ROOT/}"

title "Deployment Outputs"
jq '.outputs' "$OUTPUTS_FILE"

cat "$OUTPUTS_FILE"
