# Enterprise AI Agent Lab — Claude Code Guide

This file is read by Claude Code, GitHub Copilot CLI, and other AI coding agents.
When a user opens this repository, use this guide to help them deploy the lab end-to-end.

---

## Repository Overview

A three-phase hands-on lab for building production-ready enterprise AI agents on Microsoft 365:

| Phase | What gets built | Est. effort | Status |
|-------|----------------|-------------|--------|
| **Phase 1** | Self-hosted OpenClaw agent connected to Microsoft Teams, custom personality, persistent memory | 10–17 hours | ✅ Active |
| **Phase 2** | Same agent with its own Entra ID identity (`agent@tenant`), Microsoft 365 Graph tools (calendar, email, user), iptables capability perimeters | ~23 hours | ✅ Active |
| **Phase 3** | Multi-agent orchestration: Orchestrator + 3 specialists, Dataverse shared memory, Work IQ MCP, OpenTelemetry, Purview compliance | ~39 hours | 🔜 Planned |

Tech stack: **OpenClaw** (Node.js/TypeScript) · **openclaw-a365** (Docker) · **Azure OpenAI** · **Microsoft Graph API** · **Azure Bicep** · **Entra ID / FIC**

---

## Common Commands

> **All scripts are designed to run from the repo root.** `cd` to the repo root before running any `./scripts/*.sh` command.

```bash
# --- Prerequisites ---
./scripts/preflight.sh --phase 1        # check Phase 1 tools (use --phase 2 / 3 for later phases)

# --- Phase 1 ---
./scripts/phase1-setup.sh               # interactive wizard: LLM config + workspace files
openclaw doctor --fix                   # validate OpenClaw config
openclaw gateway                        # start the gateway (foreground)

# --- Phase 2: Entra + Azure setup ---
./scripts/preflight.sh --phase 2        # verify Azure CLI, jq, SSH key, .env state

# Run the Entra automation; --env-file lets it write directly into the plugin folder
./scripts/az-entra-setup.sh \
  --env-file phase-2-tool-integration-capability-perimeters/a365-plugin/.env.generated

cd phase-2-tool-integration-capability-perimeters/a365-plugin
cp .env.example .env                    # initialise from template
cat .env.generated >> .env              # merge generated values
# Now edit .env: fill remaining manual values (AZURE_OPENAI_*, etc.) and remove duplicate keys

docker compose up -d                    # start the agent locally
docker compose logs -f                  # tail logs
./infra/deploy.sh dev                   # deploy to Azure VM (~10 min)

# --- Verify deployment ---
cd -                                    # back to repo root
./scripts/verify.sh --phase 2           # run post-deployment health checks

# --- Phase 2 plugin dev ---
cd phase-2-tool-integration-capability-perimeters/a365-plugin
pnpm install
pnpm typecheck
pnpm test
```

---

## Deploying Phase 1

### What Claude should do

1. **Check prerequisites** — from the **repo root**, run `./scripts/preflight.sh --phase 1`. Fix anything flagged.
2. **Run the Phase 1 wizard** — run `./scripts/phase1-setup.sh`. This creates:
   - `~/.openclaw/config.json` (LLM provider + model)
   - `phase-1-building-autonomous-ai-assistant/workspace/AGENTS.md`
   - `phase-1-building-autonomous-ai-assistant/workspace/SOUL.md`
   - `phase-1-building-autonomous-ai-assistant/workspace/MEMORY.md`
3. **Install OpenClaw** (if not already installed):
   ```bash
   npm install -g @openclaw/openclaw
   # OR
   pnpm dlx @openclaw/openclaw install
   ```
4. **Validate config**:
   ```bash
   openclaw doctor --fix
   ```
5. **Start the gateway**:
   ```bash
   openclaw gateway
   # Should print: OpenClaw Gateway listening on :18789
   ```
6. **Connect a channel** — ask the user which channel they want:
   - **Teams**: follow `phase-1-building-autonomous-ai-assistant/setup/TEAMS_SETUP.md`
   - **Discord**: follow `phase-1-building-autonomous-ai-assistant/setup/DISCORD_SETUP.md`
7. **Smoke test** — once the channel is connected, send `Hello` to the agent in Teams/Discord. It should respond.

### Phase 1 environment variables

| Variable | Where to get it |
|----------|----------------|
| `OPENCLAW_MODEL` | `azure/gpt-4o`, `anthropic/claude-sonnet-4-20250514`, `openai/gpt-4o`, or `ollama/<model>` |
| `AZURE_OPENAI_API_KEY` | Azure Portal → OpenAI resource → Keys |
| `AZURE_OPENAI_ENDPOINT` | Azure Portal → OpenAI resource → Endpoint |
| `ANTHROPIC_API_KEY` | console.anthropic.com |
| `OPENAI_API_KEY` | platform.openai.com |

### Phase 1 verification

```bash
curl http://localhost:18789/health        # → {"status":"ok"}
curl http://localhost:18789/v1/models     # → lists configured model
```

---

## Deploying Phase 2

### What Claude should do

1. **Check Phase 1 is running** — verify `curl http://localhost:18789/health` returns 200.
2. **Check Azure CLI login**:
   ```bash
   az account show --query '{user:user.name,subscription:name,tenant:tenantId}' -o table
   # If not logged in:
   az login
   az account set --subscription "<name-or-id>"
   ```
3. **Run the Entra setup script** from the **repo root** (automates app registration, permissions, user, FIC). Tell the script to write its output directly into the plugin folder:
   ```bash
   ./scripts/az-entra-setup.sh \
     --env-file phase-2-tool-integration-capability-perimeters/a365-plugin/.env.generated
   ```
   > The script pauses at Step 4 (AA Instance ID) because that step requires the M365 Agents portal.
   > Show the user the exact URL and fields to fill in, then resume.

4. **Merge generated values into `.env`**:
   ```bash
   cd phase-2-tool-integration-capability-perimeters/a365-plugin
   cp .env.example .env                # initialise from template
   cat .env.generated >> .env          # append generated values
   # Open .env: fill in AZURE_OPENAI_API_KEY / AZURE_OPENAI_ENDPOINT,
   # then dedupe any keys that now appear twice (the appended values win — keep them).
   # Required: A365_APP_ID, A365_APP_PASSWORD, A365_TENANT_ID, AA_INSTANCE_ID,
   #           AGENT_IDENTITY, OWNER, OWNER_AAD_ID, AZURE_OPENAI_API_KEY, AZURE_OPENAI_ENDPOINT
   ```

5. **Start the plugin locally** (validate before cloud deploy):
   ```bash
   docker compose up -d
   docker compose logs -f --tail=50
   # Wait for: "OpenClaw A365 channel started on port 3978"
   # Health: curl http://localhost:3978/api/messages -X POST → 401 (not 404)
   ```

6. **Register the messaging endpoint** — for local testing with Dev Tunnels:
   ```bash
   # Install Dev Tunnels CLI if needed
   devtunnel host -p 3978 --allow-anonymous
   # Copy the https tunnel URL and update Azure Bot → Configuration → Messaging endpoint
   # URL format: https://<tunnel-id>.devtunnels.ms/api/messages
   ```

7. **Test locally in Teams** — DM the bot with `Hello`. It should respond.

8. **Deploy to Azure VM** (production):
   ```bash
   ./infra/deploy.sh dev
   # Takes ~10 min. Outputs FQDN and SSH command when done.
   # Then update Azure Bot Configuration with the new FQDN messaging endpoint.
   ```

9. **Run verification**:
   ```bash
   ./scripts/verify.sh
   ```

### Phase 2 environment variables

| Variable | Required | Description | How to get |
|----------|----------|-------------|-----------|
| `A365_APP_ID` | ✅ | Bot app registration client ID | `az-entra-setup.sh` output |
| `A365_APP_PASSWORD` | ✅ | Bot app client secret | `az-entra-setup.sh` output |
| `A365_TENANT_ID` | ✅ | Azure AD tenant ID | `az account show --query tenantId -o tsv` |
| `AA_INSTANCE_ID` | ✅ | Autonomous Agent instance ID (FIC subject) | M365 Agents portal (portal-only) |
| `AGENT_IDENTITY` | ✅ | Agent UPN: `agent@tenant.onmicrosoft.com` | Entra admin center |
| `OWNER` | ✅ | Your own UPN | Your Microsoft 365 account |
| `OWNER_AAD_ID` | ✅ | Your Entra Object ID | `az ad signed-in-user show --query id -o tsv` |
| `AZURE_OPENAI_API_KEY` | ✅ | Azure OpenAI key | Azure Portal → OpenAI resource |
| `AZURE_OPENAI_ENDPOINT` | ✅ | Azure OpenAI endpoint | Azure Portal → OpenAI resource |
| `NETWORK_MODE` | ✅ | `restricted` (default) or `unrestricted` | Set in `.env` |
| `DM_POLICY` | optional | `pairing` / `open` / `closed` | Set in `.env` |

### Phase 2 verification

```bash
# Container running
docker compose ps

# Endpoint responds (401 = auth required, correct; 404 = routing broken)
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:3978/api/messages

# iptables perimeter applied (should show OUTPUT rules)
docker compose exec openclaw-a365 iptables -L OUTPUT -n

# Graph API reachable through perimeter
docker compose exec openclaw-a365 curl -s -o /dev/null -w "%{http_code}" https://graph.microsoft.com/v1.0/

# Azure AD audit log (shows agent's Graph calls)
az monitor activity-log list \
  --resource-group rg-openclaw-lab-dev \
  --max-events 20 \
  --query "[].{time:eventTimestamp,caller:caller,op:operationName.value}" \
  -o table
```

---

## Integrating the Agent 365 SDK into OpenClaw

**When the user asks** any of: *"add Agent 365 SDK"*, *"add Work IQ MCP"*, *"add notification handlers"*, *"register MCP servers"*, *"add `mcp_MailTools`"*, *"use `a365` CLI"*, *"`a365 setup all`"*, *"`a365 develop add-mcp-servers`"* — read [`phase-2-.../setup/AGENT_365_SDK_INTEGRATION.md`](phase-2-tool-integration-capability-perimeters/setup/AGENT_365_SDK_INTEGRATION.md) and follow its 7 steps.

### Quick decision tree

| User intent | What to do |
|-------------|-----------|
| "Just install the SDK packages" | Step 1 of the guide: `pnpm add @microsoft/agents-a365-{notifications,tooling,tooling-extensions-claude}` |
| "Wire up notification handlers" | Step 4: edit `src/monitor.ts` + `src/channel.ts` per the diff in the guide |
| "Add MCP servers" (Mail, Calendar, Teams, etc.) | Step 5: `a365 develop add-mcp-servers <name>`, then create `src/mcp-tools.ts` and call `attachMcpTools()` from `src/channel.ts` |
| "Replace `graph-tools.ts` with MCP" | Read Step 6 first — the recommended approach is **additive**, not replacement, unless you specifically need Purview audit trails or multi-user OBO |
| "Run `a365 setup all` from scratch" | Step 3 Path B — but warn the user this creates a NEW blueprint and replaces existing `A365_APP_ID` / `A365_APP_PASSWORD` |
| "Publish to M365 admin center" | After Steps 1–5 are done: `a365 publish` |

**Critical rule**: never tell the user to delete `src/token.ts` or `src/graph-tools.ts`. The Agent 365 SDK integration is **additive**. The hand-rolled FIC flow continues to mint Graph tokens — the new MCP tools reuse those tokens via `getGraphToken({audience: 'api://agent365tools'})`.

---

## Deploying Phase 3

> Phase 3 is currently in planning. Code generation begins after Phase 2 is verified end-to-end.

When the user is ready to start Phase 3, say:

> "Phase 3 build can start once Phase 2 is verified. Run `./scripts/verify.sh --phase2` to confirm readiness, then I'll scaffold the multi-agent repo additions."

See `phase-3-multi-agent-orchestration-governance/README.md` for the full spec.

---

## Azure CLI Quick Reference

```bash
# ── Authentication ──────────────────────────────────────────────────────────
az login                                                # interactive browser login
az login --use-device-code                              # device code (headless)
az account show                                         # current subscription
az account list -o table                                # all subscriptions
az account set --subscription "<name-or-id>"            # switch subscription

# ── Entra ID ─────────────────────────────────────────────────────────────────
az ad user show --id "agent@tenant.onmicrosoft.com"     # check agent user
az ad user list --filter "startswith(displayName,'OpenClaw')" -o table
az ad app list --display-name "openclaw-a365-bot" -o table
az ad app show --id "<APP_ID>"                          # app registration details
az ad app permission list --id "<APP_ID>" -o table      # list permissions

# ── Resource groups / VMs ────────────────────────────────────────────────────
az group list -o table                                  # all resource groups
az vm list -g rg-openclaw-lab-dev -o table              # VMs in group
az vm show -g rg-openclaw-lab-dev -n openclaw-vm-dev --query instanceView.statuses -o table
az vm start  -g rg-openclaw-lab-dev -n openclaw-vm-dev  # start VM
az vm deallocate -g rg-openclaw-lab-dev -n openclaw-vm-dev  # stop billing (~$3/mo)
az vm restart -g rg-openclaw-lab-dev -n openclaw-vm-dev     # restart

# ── Key Vault ────────────────────────────────────────────────────────────────
az keyvault secret list --vault-name openclaw-kv-<suffix> -o table
az keyvault secret set --vault-name openclaw-kv-<suffix> --name A365_APP_PASSWORD --value '<val>'
az keyvault secret show --vault-name openclaw-kv-<suffix> --name A365_APP_PASSWORD --query value -o tsv

# ── App Service (Option B deploy) ────────────────────────────────────────────
az webapp list -g rg-openclaw-lab-dev -o table
az webapp log tail -n <app-name> -g rg-openclaw-lab-dev
az webapp restart -n <app-name> -g rg-openclaw-lab-dev
az webapp config appsettings list -n <app-name> -g rg-openclaw-lab-dev -o table
az webapp deploy -n <app-name> -g rg-openclaw-lab-dev --src-path ./dist

# ── Costs ────────────────────────────────────────────────────────────────────
az consumption budget list -o table
az costmanagement query --type Usage --timeframe MonthToDate \
  --dataset-aggregation '{"totalCost":{"name":"Cost","function":"Sum"}}' \
  --scope "/subscriptions/$(az account show --query id -o tsv)"
```

---

## Environment File Quick Setup

> Run from the **repo root**.

```bash
# Phase 2 — pre-fill the values you can derive from the current az login
ENV_PATH="phase-2-tool-integration-capability-perimeters/a365-plugin/.env"
cp phase-2-tool-integration-capability-perimeters/a365-plugin/.env.example "$ENV_PATH"

# Auto-fill tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
sed -i.bak "s/^A365_TENANT_ID=$/A365_TENANT_ID=${TENANT_ID}/" "$ENV_PATH"

# Auto-fill OWNER and OWNER_AAD_ID from current az login
OWNER_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
OWNER_OID=$(az ad signed-in-user show --query id -o tsv)
sed -i.bak "s|^OWNER=owner@yourtenant.onmicrosoft.com|OWNER=${OWNER_UPN}|" "$ENV_PATH"
sed -i.bak "s|^OWNER_AAD_ID=$|OWNER_AAD_ID=${OWNER_OID}|" "$ENV_PATH"

rm -f "${ENV_PATH}.bak"
echo "✅ .env pre-filled with tenant, OWNER, OWNER_AAD_ID"
echo "📋 Still needed: A365_APP_ID, A365_APP_PASSWORD, AA_INSTANCE_ID, AGENT_IDENTITY, AZURE_OPENAI_*"
echo "   Run: ./scripts/az-entra-setup.sh --env-file ${ENV_PATH}.generated"
```

---

## Secrets Management

**Never commit `.env` to git.** The `.gitignore` already excludes `.env` and `*.env`.

For cloud deployments, secrets live in **Azure Key Vault** (`openclaw-kv-<suffix>`). The VM's Managed Identity reads them at boot via `cloud-init.yaml`. The `infra/deploy.sh` script populates Key Vault automatically from your local `.env`.

To rotate a secret:
```bash
# 1. Update in Key Vault
az keyvault secret set --vault-name openclaw-kv-<suffix> \
  --name A365_APP_PASSWORD --value '<new-value>'

# 2. Restart the VM to reload secrets
az vm restart -g rg-openclaw-lab-dev -n openclaw-vm-dev
```

---

## Troubleshooting

### Agent doesn't respond in Teams
```bash
# Check container is running
docker compose ps
docker compose logs --tail=50

# Check endpoint routing
curl -X POST http://localhost:3978/api/messages    # should return 401
curl -X POST https://<fqdn>/api/messages           # should return 401

# Check Azure Bot messaging endpoint (must be HTTPS)
az bot show -g rg-openclaw-lab-dev -n openclaw-bot --query properties.endpoint -o tsv
```

### Token acquisition fails
```bash
# Verify env vars are set
docker compose exec openclaw-a365 env | grep -E "^A365_|^AA_|^AGENT_"

# Check app registration exists
az ad app show --id "$A365_APP_ID" --query '{id:appId,name:displayName}' -o table

# Verify FIC subject matches AA_INSTANCE_ID
az ad app federated-credential list --id "$A365_APP_ID" \
  --query "[].{name:name,subject:subject}" -o table
```

### Graph API returns 403
```bash
# Check admin consent was granted
az ad app permission list-grants --id "$A365_APP_ID" -o table

# Re-grant if needed (requires Global Admin)
az ad app permission admin-consent --id "$A365_APP_ID"
```

### iptables not applying
```bash
# Must run with NET_ADMIN capability
docker compose exec openclaw-a365 iptables -L OUTPUT -n
# If "Operation not permitted": check docker-compose.yml has cap_add: [NET_ADMIN]
```

### VM deployment fails
```bash
# Check cloud-init log on the VM
ssh azureuser@<fqdn> 'sudo cat /var/log/cloud-init-output.log | tail -100'

# Check container status
ssh azureuser@<fqdn> 'sudo docker ps -a && sudo docker logs openclaw-a365 --tail=50'
```

---

## Project Conventions

- **TypeScript** — all plugin source in `a365-plugin/src/`. Run `pnpm typecheck` before any PR.
- **Tests** — `pnpm test` (Vitest). Tests in `*.test.ts` alongside source.
- **Secrets** — never commit. Use `.env` locally; Azure Key Vault in production.
- **Config changes** — edit files in `a365-plugin/config/`, then `docker compose restart`.
- **Azure resources** — always use `infra/deploy.sh` (not portal) so Bicep stays the source of truth.
- **Branches** — `main` = stable. Feature work on `phase-N/<description>` branches.

---

## Key Documentation

| Doc | Purpose |
|-----|---------|
| [`README.md`](README.md) | Lab overview, tech stack, quick start |
| [`phase-1-.../README.md`](phase-1-building-autonomous-ai-assistant/README.md) | Phase 1 learning guide (7 modules) |
| [`phase-2-.../README.md`](phase-2-tool-integration-capability-perimeters/README.md) | Phase 2 guide + Microsoft Agent 365 SDK reference |
| [`phase-2-.../setup/AZURE_ENTRA_SETUP.md`](phase-2-tool-integration-capability-perimeters/setup/AZURE_ENTRA_SETUP.md) | Step-by-step: app reg, FIC, agent user, AA instance |
| [`phase-2-.../setup/AZURE_VM_DEPLOY.md`](phase-2-tool-integration-capability-perimeters/setup/AZURE_VM_DEPLOY.md) | Azure VM deploy: Bicep, Caddy, Key Vault, ~$65/mo |
| [`phase-2-.../setup/AGENT_365_SDK_INTEGRATION.md`](phase-2-tool-integration-capability-perimeters/setup/AGENT_365_SDK_INTEGRATION.md) | **Wire Agent 365 SDK into OpenClaw — packages, notification handlers, MCP tools, blueprint paths** |
| [`phase-2-.../a365-plugin/AGENT_GUIDE.md`](phase-2-tool-integration-capability-perimeters/a365-plugin/AGENT_GUIDE.md) | Plugin architecture, source files, token flow |
| [`phase-3-.../README.md`](phase-3-multi-agent-orchestration-governance/README.md) | Phase 3 spec: multi-agent, Dataverse, Work IQ |
