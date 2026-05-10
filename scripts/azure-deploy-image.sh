#!/usr/bin/env bash
# =============================================================================
# scripts/azure-deploy-image.sh — Build image in ACR and roll out to Container App
#
# Usage:
#   bash scripts/azure-deploy-image.sh                            # uses last deployment + git sha
#   bash scripts/azure-deploy-image.sh --tag v1.2.3
#   bash scripts/azure-deploy-image.sh --acr myacr --app ca-oca365-dev --tag v1.0
#
# Environment variables:
#   AZ_ACR              ACR name (override last-deployment.json)
#   AZ_CONTAINER_APP    Container App name (override last-deployment.json)
#   AZ_RESOURCE_GROUP   Resource group containing the Container App
#   IMAGE_TAG           image tag (default: short git sha)
#   AZ_DRY_RUN=1        echo commands instead of executing
#
# Behaviour:
#   1. `az acr build` from repo root using Dockerfile.
#   2. `az containerapp update` to pin the new image, creating a new revision.
#   3. Polls the latest revision until provisioning state == Succeeded.
#   4. Curls /health on the public FQDN.
#
# Exit codes:
#   0 success | 1 missing prereq | 2 build failed | 3 update failed | 4 health check failed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ROOT="$(repo_root)"
OUTPUTS_FILE="$ROOT/iac/.last-deployment.json"
ACR="${AZ_ACR:-}"
APP="${AZ_CONTAINER_APP:-}"
RG="${AZ_RESOURCE_GROUP:-}"
TAG="${IMAGE_TAG:-}"

print_help() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while (($#)); do
  case "$1" in
    --acr)            shift; ACR="${1:?--acr requires a value}" ;;
    --app)            shift; APP="${1:?--app requires a value}" ;;
    --resource-group) shift; RG="${1:?--resource-group requires a value}" ;;
    --tag)            shift; TAG="${1:?--tag requires a value}" ;;
    -h|--help)        print_help ;;
    *) fail "Unknown argument: $1 (try --help)" ;;
  esac
  shift
done

require_cmd az jq

# Resolve defaults from last deployment outputs
if [[ -f "$OUTPUTS_FILE" ]]; then
  ACR="${ACR:-$(jq -r '.outputs.acrLoginServer // empty' "$OUTPUTS_FILE" | sed -E 's|\..*||')}"
  RG="${RG:-$(jq -r '.resourceGroup // empty' "$OUTPUTS_FILE")}"
  if [[ -z "$APP" ]]; then
    URL="$(jq -r '.outputs.containerAppUrl // empty' "$OUTPUTS_FILE")"
    # extract container app name from RG via az
    if [[ -n "$RG" ]]; then
      APP="$(az containerapp list --resource-group "$RG" --query "[0].name" -o tsv 2>/dev/null || true)"
    fi
  fi
fi

# Default tag = short git sha (or 'latest' if not in a git repo)
if [[ -z "$TAG" ]]; then
  TAG="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo latest)"
fi

[[ -n "$ACR" ]]  || fail "Missing --acr / AZ_ACR (and not in $OUTPUTS_FILE)."
[[ -n "$APP" ]]  || fail "Missing --app / AZ_CONTAINER_APP."
[[ -n "$RG" ]]   || fail "Missing --resource-group / AZ_RESOURCE_GROUP."

IMAGE="${ACR}.azurecr.io/openclaw-agent365:${TAG}"

title "Deploying $IMAGE → $APP (rg: $RG)"

# ─── 1. Build via ACR ────────────────────────────────────────────────────────
info "Building image in ACR (this may take several minutes)..."
dry_run_echo az acr build \
  --registry "$ACR" \
  --image "openclaw-agent365:${TAG}" \
  --file "$ROOT/Dockerfile" \
  "$ROOT" \
  -o none \
  || fail "az acr build failed"
pass "Image built: $IMAGE"

# ─── 2. Update Container App ─────────────────────────────────────────────────
info "Updating Container App to pin new image..."
dry_run_echo az containerapp update \
  --name "$APP" \
  --resource-group "$RG" \
  --image "$IMAGE" \
  -o none \
  || fail "az containerapp update failed"
pass "Container App updated"

if [[ "${AZ_DRY_RUN:-0}" == "1" ]]; then
  pass "Dry-run complete"; exit 0
fi

# ─── 3. Wait for revision to succeed ─────────────────────────────────────────
info "Waiting for new revision to reach 'Succeeded' state..."
DEADLINE=$(( $(date +%s) + 300 ))   # 5 minute timeout
LATEST_REV=""
while (( $(date +%s) < DEADLINE )); do
  LATEST_REV="$(az containerapp revision list \
    --name "$APP" --resource-group "$RG" \
    --query "sort_by([], &properties.createdTime)[-1].name" -o tsv 2>/dev/null || true)"
  STATE="$(az containerapp revision show \
    --name "$APP" --resource-group "$RG" --revision "$LATEST_REV" \
    --query "properties.provisioningState" -o tsv 2>/dev/null || echo Unknown)"
  case "$STATE" in
    Provisioned|Succeeded) pass "Revision $LATEST_REV → $STATE"; break ;;
    Failed) fail "Revision $LATEST_REV failed. Inspect: az containerapp logs show --name $APP -g $RG --revision $LATEST_REV" ;;
    *) info "  state=$STATE — waiting..."; sleep 10 ;;
  esac
done

# ─── 4. Health check ─────────────────────────────────────────────────────────
FQDN="$(az containerapp show --name "$APP" --resource-group "$RG" --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || true)"
if [[ -n "$FQDN" ]]; then
  HEALTH_URL="https://${FQDN}/health"
  info "Health check: $HEALTH_URL"
  if curl -fsS --max-time 10 "$HEALTH_URL" >/dev/null; then
    pass "Health check passed"
  else
    warn "Health check failed (the app may still be warming up). Verify: curl $HEALTH_URL"
  fi
fi

jq -n \
  --arg image "$IMAGE" \
  --arg revision "$LATEST_REV" \
  --arg fqdn "${FQDN:-}" \
  '{image: $image, revision: $revision, fqdn: $fqdn}'
