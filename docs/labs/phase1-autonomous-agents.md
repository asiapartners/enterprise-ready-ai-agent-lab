# Phase 1 Lab — Building Autonomous AI Assistants with OpenClaw

**Duration:** ~2 hours  
**Goal:** Wire the OpenClaw runtime as a Teams-connected agent that responds to messages  
**Prerequisites:** Completed `scripts/setup.sh`, Docker, ngrok, Azure account with Teams admin

---

## Objectives

By the end of this lab you will:
- Understand the OpenClaw plugin host architecture
- Have a running agent that responds to Teams messages
- Understand the Bot Framework / CloudAdapter request flow
- Observe end-to-end telemetry in Application Insights

---

## Architecture Recap

```
Teams → Bot Framework Service (HTTPS) → CloudAdapter (JWT validation)
      → Agent365Handler → OpenClawRuntime → LLM pipeline → response
```

The A365 channel plugin (port 3978) bridges Teams into the OpenClaw gateway (port 18789). The `openclaw.plugin.json` descriptor registers this channel so the OpenClaw runtime knows how to route inbound messages.

---

## Step 1 — Clone and configure

```bash
git clone <your-fork-url> openclaw-agent365
cd openclaw-agent365
bash scripts/setup.sh
```

Edit `.env`:
```bash
# Minimum required for Phase 1 (use any LLM key you have)
A365_APP_ID=<from-step-3>
A365_APP_PASSWORD=<from-step-3>
A365_TENANT_ID=<your-tenant-guid>
AA_INSTANCE_ID=<from-step-3>
AGENT_IDENTITY=agent@<your-domain>
OWNER=<your-upn>
OWNER_AAD_ID=<your-object-id>
ANTHROPIC_API_KEY=<your-key>
```

---

## Step 2 — Start the dev environment

```bash
# Option A: Docker Compose (recommended)
docker-compose up --build

# Option B: Direct (requires Node 24 + pnpm locally)
pnpm run dev
```

Verify health endpoint:
```bash
curl http://localhost:3978/health | jq .
# Expected: {"status":"ok","service":"openclaw-agent365","env":"development",...}
```

---

## Step 3 — Register an App in Azure

```bash
# Create App Registration
az ad app create \
  --display-name "openclaw-agent365-lab" \
  --sign-in-audience AzureADMyOrg

# Note: appId from output → A365_APP_ID in .env

# Create a client secret
az ad app credential reset \
  --id <APP_ID> \
  --display-name "lab-secret"

# Note: password from output → A365_APP_PASSWORD in .env (use Key Vault in prod)
```

For `AA_INSTANCE_ID`, register the agent in Microsoft Agent 365:
- Follow: https://learn.microsoft.com/en-us/microsoft-agent-365/developer/registration

---

## Step 4 — Expose localhost via ngrok

```bash
ngrok http 3978

# Note the HTTPS URL: https://abc123.ngrok-free.app
```

Configure the Bot Framework messaging endpoint in Azure:
1. Azure Portal → Bot Services → Create → Azure Bot
2. Set Messaging endpoint: `https://<ngrok-url>/api/messages`
3. Use the App ID and secret from Step 3

---

## Step 5 — Test via Bot Framework Emulator

```bash
# Download: https://github.com/microsoft/BotFramework-Emulator/releases
# Connect to: http://localhost:3978/api/messages
# App ID: <A365_APP_ID>
# App Password: <A365_APP_PASSWORD>
```

Send a message. You should see:
1. `POST /api/messages` hit in terminal logs
2. A response from the agent (stubbed or real depending on OpenClaw integration)
3. An OTel span in Application Insights (if APPINSIGHTS_CONNECTION_STRING is set)

---

## Step 6 — Wire the real OpenClaw runtime

Open `src/openclaw-connector.ts` and find the TODO comment:

```typescript
// TODO: Replace stub with real OpenClaw runtime invocation
// 1. Start the OpenClaw gateway: await this.runtime.start()
// 2. Route the message: return await this.runtime.processMessage(message, context)
```

Follow the OpenClaw SDK docs to complete the integration:
- https://github.com/openclaw/openclaw

---

## Acceptance Criteria

- [ ] `GET /health` returns `200 {"status":"ok"}`
- [ ] Agent responds to a message in Bot Framework Emulator (non-stub reply)
- [ ] OTel trace visible in Application Insights (or local Jaeger if configured)
- [ ] No errors in container logs
- [ ] `pnpm test` passes with coverage thresholds met

---

## Troubleshooting

| Issue | Check |
|---|---|
| `POST /api/messages` returns 401 | Verify A365_APP_ID + A365_APP_PASSWORD in .env |
| Agent not responding | Check OpenClaw runtime stub; review `src/openclaw-connector.ts` |
| No OTel traces | APPINSIGHTS_CONNECTION_STRING not set; check telemetry.ts init order |
| ngrok tunnel drops | Restart ngrok; update Bot Service messaging endpoint URL |
| Build errors | Run `pnpm typecheck` to isolate TypeScript errors |

---

## Next

→ [Phase 2 — Tool Integration & Capability Perimeters](./phase2-tool-integration.md)
