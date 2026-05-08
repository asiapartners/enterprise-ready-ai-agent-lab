#!/usr/bin/env bash
# =============================================================================
# verify.sh — Post-deployment health checks for the Enterprise AI Agent Lab
#
# Usage:
#   ./scripts/verify.sh              # check everything
#   ./scripts/verify.sh --phase 1   # check Phase 1 (local gateway)
#   ./scripts/verify.sh --phase 2   # check Phase 2 (container + Azure)
#   ./scripts/verify.sh --host <fqdn>  # check against a specific host
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
PHASE=0
HOST="localhost"
P1_PORT=18789
P2_PORT=3978

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --host)  HOST="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--phase <1|2>] [--host <fqdn>]"
      exit 0
      ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/phase-2-tool-integration-capability-perimeters/a365-plugin/.env"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; CYAN="\033[36m"; BOLD="\033[1m"; RESET="\033[0m"

PASS=0; WARN=0; FAIL=0

check_pass() { echo -e "  ${GREEN}✅ $*${RESET}"; ((PASS++)) || true; }
check_warn() { echo -e "  ${YELLOW}⚠️  $*${RESET}"; ((WARN++)) || true; }
check_fail() { echo -e "  ${RED}❌ $*${RESET}"; ((FAIL++)) || true; }
section()    { echo -e "\n${BOLD}${CYAN}── $* ──${RESET}"; }

http_check() {
  local label="$1"; local url="$2"; local expected_code="${3:-200}"
  local actual_code
  actual_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
  if [ "$actual_code" = "$expected_code" ]; then
    check_pass "$label → HTTP $actual_code"
  elif [ "$actual_code" = "000" ]; then
    check_fail "$label → unreachable (connection refused)"
  else
    check_warn "$label → HTTP $actual_code (expected $expected_code)"
  fi
}

# ---------------------------------------------------------------------------
# Phase 1 checks — OpenClaw gateway
# ---------------------------------------------------------------------------
verify_phase1() {
  section "Phase 1 — OpenClaw Gateway"

  # Gateway health
  http_check "Gateway health (localhost:$P1_PORT/health)" "http://localhost:$P1_PORT/health"

  # Models endpoint
  http_check "Gateway models  (localhost:$P1_PORT/v1/models)" "http://localhost:$P1_PORT/v1/models"

  # Process check
  if pgrep -f "openclaw gateway" >/dev/null 2>&1; then
    check_pass "openclaw gateway process running"
  else
    check_warn "openclaw gateway process not detected"
  fi
}

# ---------------------------------------------------------------------------
# Phase 2 checks — Docker container + Azure
# ---------------------------------------------------------------------------
verify_phase2() {
  section "Phase 2 — Docker Container"

  PLUGIN_DIR="${REPO_ROOT}/phase-2-tool-integration-capability-perimeters/a365-plugin"

  # Docker Compose status
  if [ -f "${PLUGIN_DIR}/docker-compose.yml" ]; then
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      CONTAINER_STATUS=$(docker compose -f "${PLUGIN_DIR}/docker-compose.yml" ps --format json 2>/dev/null | \
        jq -r '.[0].State // .[0].Status // "unknown"' 2>/dev/null || echo "unknown")
      case "$CONTAINER_STATUS" in
        running)  check_pass "Container state: running" ;;
        exited)   check_fail "Container state: exited — run: docker compose logs openclaw-a365" ;;
        *)        check_warn "Container state: $CONTAINER_STATUS" ;;
      esac
    else
      check_warn "Docker not running — cannot check container state"
    fi
  else
    check_warn "docker-compose.yml not found at $PLUGIN_DIR"
  fi

  # Bot Framework endpoint — should return 401 (auth required), NOT 404
  if [ "$HOST" = "localhost" ]; then
    BOT_URL="http://localhost:$P2_PORT/api/messages"
  else
    BOT_URL="https://${HOST}/api/messages"
  fi
  http_check "Bot Framework endpoint ($BOT_URL)" "$BOT_URL" "401"

  # OpenClaw gateway (port 18789 — should still be up)
  http_check "OpenClaw gateway (port $P1_PORT)" "http://localhost:$P1_PORT/health"

  # iptables rules applied
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    IPTABLES_RULES=$(docker compose -f "${PLUGIN_DIR}/docker-compose.yml" \
      exec -T openclaw-a365 iptables -L OUTPUT -n --line-numbers 2>/dev/null | wc -l || echo "0")
    if [ "$IPTABLES_RULES" -gt 3 ]; then
      check_pass "iptables capability perimeter applied ($IPTABLES_RULES rules)"
    else
      check_warn "iptables may not be applied (only $IPTABLES_RULES lines in OUTPUT chain)"
    fi
  fi

  section "Phase 2 — .env Configuration"

  if [ -f "$ENV_FILE" ]; then
    # Check required vars are set
    for var in A365_APP_ID A365_APP_PASSWORD A365_TENANT_ID AA_INSTANCE_ID \
               AGENT_IDENTITY OWNER OWNER_AAD_ID AZURE_OPENAI_API_KEY AZURE_OPENAI_ENDPOINT; do
      val=$(grep -E "^${var}=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")
      if [ -z "$val" ] || [[ "$val" == *"yourtenant"* ]] || [[ "$val" == *"your-"* ]]; then
        check_fail "Missing/placeholder: $var"
      else
        # Mask secret values in output
        case "$var" in
          *PASSWORD*|*KEY*|*SECRET*)
            check_pass "$var = ****${val: -4}" ;;
          *)
            check_pass "$var = $val" ;;
        esac
      fi
    done
  else
    check_fail ".env not found: $ENV_FILE"
    echo "    Run: cp ${ENV_FILE%.env}.env.example ${ENV_FILE}"
    echo "    Then: ./scripts/az-entra-setup.sh"
  fi

  section "Phase 2 — Azure Resources"

  if command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; then
    # Check VM exists
    VM_STATE=$(az vm list -g rg-openclaw-lab-dev --query "[0].powerState" -o tsv 2>/dev/null || echo "")
    if [ -n "$VM_STATE" ] && [ "$VM_STATE" != "null" ]; then
      if [[ "$VM_STATE" == *"running"* ]]; then
        check_pass "Azure VM: $VM_STATE"
      else
        check_warn "Azure VM: $VM_STATE"
      fi
    else
      check_warn "Azure VM not found in rg-openclaw-lab-dev (may not be deployed yet)"
    fi

    # Check Key Vault secrets exist
    KV_NAME=$(az keyvault list -g rg-openclaw-lab-dev --query "[0].name" -o tsv 2>/dev/null || echo "")
    if [ -n "$KV_NAME" ] && [ "$KV_NAME" != "null" ]; then
      check_pass "Key Vault found: $KV_NAME"
      for secret in A365_APP_PASSWORD AZURE_OPENAI_API_KEY; do
        SECRET_EXISTS=$(az keyvault secret list --vault-name "$KV_NAME" \
          --query "[?name=='$secret'].name | [0]" -o tsv 2>/dev/null || echo "")
        if [ -n "$SECRET_EXISTS" ]; then
          check_pass "Key Vault secret: $secret ✓"
        else
          check_warn "Key Vault secret not found: $secret"
        fi
      done
    else
      check_warn "Key Vault not found in rg-openclaw-lab-dev"
    fi

    # Check App Registration FIC
    if [ -f "$ENV_FILE" ]; then
      APP_ID=$(grep -E "^A365_APP_ID=" "$ENV_FILE" | cut -d= -f2- || echo "")
      AA_INSTANCE=$(grep -E "^AA_INSTANCE_ID=" "$ENV_FILE" | cut -d= -f2- || echo "")
      if [ -n "$APP_ID" ] && [ "$APP_ID" != "<REPLACE_WITH_AA_INSTANCE_ID>" ]; then
        FIC_SUBJECT=$(az ad app federated-credential list --id "$APP_ID" \
          --query "[?name=='aa-instance-fic'].subject | [0]" -o tsv 2>/dev/null || echo "")
        if [ -n "$FIC_SUBJECT" ]; then
          if [ "$FIC_SUBJECT" = "$AA_INSTANCE" ]; then
            check_pass "FIC subject matches AA_INSTANCE_ID"
          else
            check_fail "FIC subject ($FIC_SUBJECT) does NOT match AA_INSTANCE_ID ($AA_INSTANCE)"
          fi
        else
          check_warn "FIC 'aa-instance-fic' not found for app $APP_ID"
        fi
      fi
    fi

  else
    check_warn "Azure CLI not logged in — skipping Azure resource checks"
  fi

  # External endpoint check (if HOST is provided and not localhost)
  if [ "$HOST" != "localhost" ]; then
    section "Phase 2 — Cloud Endpoint ($HOST)"
    http_check "HTTPS messaging endpoint" "https://${HOST}/api/messages" "401"
    http_check "HTTP redirect (should be 301 or 302)" "http://${HOST}/api/messages" "301"
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Enterprise AI Agent Lab — Deployment Verification${RESET}"
echo "Host: $HOST"
echo ""

case "$PHASE" in
  1)   verify_phase1 ;;
  2)   verify_phase1; verify_phase2 ;;
  0|*) verify_phase1; verify_phase2 ;;
esac

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}━━━ Summary ━━━${RESET}"
echo -e "  ${GREEN}Passed${RESET}: $PASS"
[ "$WARN" -gt 0 ] && echo -e "  ${YELLOW}Warnings${RESET}: $WARN"
[ "$FAIL" -gt 0 ] && echo -e "  ${RED}Failed${RESET}: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}❌ Verification failed. See TROUBLESHOOTING.md for fixes.${RESET}"
  echo "   phase-2-tool-integration-capability-perimeters/TROUBLESHOOTING.md"
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  Verification passed with warnings.${RESET}"
else
  echo -e "${GREEN}✅ All checks passed. Agent is deployed and healthy.${RESET}"
fi
