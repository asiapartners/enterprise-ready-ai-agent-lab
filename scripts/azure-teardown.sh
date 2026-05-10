#!/usr/bin/env bash
# =============================================================================
# scripts/azure-teardown.sh — Safely delete an openclaw-agent365 resource group
#
# Usage:
#   bash scripts/azure-teardown.sh --resource-group rg-oca365-dev
#   bash scripts/azure-teardown.sh -g rg-oca365-dev --yes        # CI mode (no prompt)
#
# Safety guards:
#   - Refuses to delete unless the RG carries tag managed-by=openclaw-agent365.
#   - Requires the user to TYPE the resource-group name to confirm
#     (unless --yes / CONFIRM_YES=1).
#   - Refuses to run against subscriptions named like prod*/*production*
#     unless --i-know-what-im-doing is also passed.
#
# Environment variables:
#   AZ_RESOURCE_GROUP    target RG (alternative to --resource-group)
#   CONFIRM_YES=1        bypass interactive confirmation (CI)
#   AZ_DRY_RUN=1         echo command instead of executing
#
# Exit codes:
#   0 success | 1 missing prereq | 2 safety check failed | 3 user aborted
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

RG="${AZ_RESOURCE_GROUP:-}"
ASSUME_YES=0
OVERRIDE_PROD=0

print_help() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while (($#)); do
  case "$1" in
    -g|--resource-group)         shift; RG="${1:?--resource-group requires a value}" ;;
    -y|--yes)                    ASSUME_YES=1 ;;
    --i-know-what-im-doing)      OVERRIDE_PROD=1 ;;
    -h|--help)                   print_help ;;
    *) fail "Unknown argument: $1 (try --help)" ;;
  esac
  shift
done

require_cmd az jq
[[ -n "$RG" ]] || fail "Missing --resource-group / AZ_RESOURCE_GROUP."

# ─── Existence ───────────────────────────────────────────────────────────────
if ! az group show --name "$RG" >/dev/null 2>&1; then
  warn "Resource group '$RG' does not exist (already deleted?)"
  exit 0
fi

# ─── Safety: tag check ───────────────────────────────────────────────────────
TAGS_JSON="$(az group show --name "$RG" --query tags -o json)"
MANAGED_BY="$(echo "$TAGS_JSON" | jq -r '."managed-by" // empty')"
if [[ "$MANAGED_BY" != "openclaw-agent365" ]]; then
  fail "Refusing to delete: '$RG' is missing tag managed-by=openclaw-agent365 (got: '$MANAGED_BY'). \
This script only deletes RGs created by azure-provision.sh."
fi

# ─── Safety: production subscription guard ───────────────────────────────────
SUB_NAME="$(az account show --query name -o tsv 2>/dev/null || echo "")"
if [[ "$SUB_NAME" =~ [Pp]rod ]] && [[ "$OVERRIDE_PROD" != "1" ]]; then
  fail "Subscription '$SUB_NAME' looks like production. Re-run with --i-know-what-im-doing if intended."
fi

title "Teardown: $RG"
warn "Subscription: $SUB_NAME"
warn "Resources to be DELETED:"
az resource list --resource-group "$RG" --query "[].{Name:name,Type:type}" -o table >&2 || true

# ─── Confirmation ────────────────────────────────────────────────────────────
if [[ "$ASSUME_YES" != "1" && "${CONFIRM_YES:-0}" != "1" ]]; then
  if ! is_interactive; then
    fail "Refusing to prompt in non-interactive mode. Pass --yes to confirm."
  fi
  echo "" >&2
  read -r -p "Type the resource group name to confirm deletion: " typed
  if [[ "$typed" != "$RG" ]]; then
    fail "Confirmation mismatch — aborting."
  fi
fi

# ─── Delete ──────────────────────────────────────────────────────────────────
info "Deleting resource group (this may take several minutes)..."
dry_run_echo az group delete --name "$RG" --yes --no-wait
pass "Delete initiated. Track: az group show --name $RG -o table"

jq -n --arg rg "$RG" --arg sub "$SUB_NAME" '{resourceGroup: $rg, subscription: $sub, status: "delete-initiated"}'
