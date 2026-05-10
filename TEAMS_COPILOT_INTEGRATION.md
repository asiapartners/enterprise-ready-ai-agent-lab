# OpenClaw → Microsoft Teams & Copilot — Integration Guide

> **What this guide is**: the end-to-end developer walkthrough for combining **OpenClaw** (open-source multi-channel agent gateway), the **Microsoft 365 Agents SDK** (`AgentApplication` container with Bot Framework protocol), and the **Microsoft Agent 365 SDK** (enterprise identity + Work IQ + observability) to ship an agent into Teams and Microsoft 365 Copilot.

> **What this is *not***: it isn't a replacement for [Phase 2's `openclaw-a365` plugin](./phase-2-tool-integration-capability-perimeters/README.md). The plugin is one tightly-integrated realisation of **Pattern A** below; this guide gives you the underlying composable parts so you can pick the right pattern for your situation.

---

## 1. Two integration patterns — pick first

Before you write any code, decide which pattern fits.

### Pattern A — OpenClaw Gateway as multi-channel hub
OpenClaw receives messages from Teams, Slack, Discord, WhatsApp, etc. and **routes** them to your `AgentApplication` agent at `http://localhost:3978/api/messages`.

```
[Teams · Slack · Discord · WhatsApp]
              │
              ▼
   OpenClaw Gateway (port 18789)
              │   forwards normalised Activity
              ▼
   M365 Agents SDK Agent (port 3978)
              │
              ▼
   Anthropic / Azure OpenAI / OpenAI
```

**Best for**: a personal multi-channel assistant. One agent brain, many inboxes. Free local development — no Azure required for Slack/Discord/WhatsApp.

### Pattern B — SDK standalone + OpenClaw skills via API
Your `AgentApplication` runs **independently** with Azure Bot Service handling Teams + M365 Copilot. The agent calls the **OpenClaw Gateway API** for skills, memory search, and sandboxed tool execution.

```
[Teams · M365 Copilot]
              │
              ▼
   Azure Bot Service (Microsoft-managed)
              │
              ▼
   M365 Agents SDK Agent (Azure App Service / Container Apps)
              │   /api/skills/invoke · /api/memory/search · /api/canvas/render
              ▼
   OpenClaw Gateway API (port 18789)
```

**Best for**: enterprise Teams deployments where Azure AD/Entra SSO, Adaptive Cards, and M365 Copilot plugin compliance matter more than channel breadth.

### Decision matrix

| Factor | Pattern A | Pattern B |
|--------|-----------|-----------|
| Primary users | Personal, small teams | Enterprise, M365 Copilot |
| Channels | 20+ (Teams, Slack, Discord, WhatsApp, etc.) | Teams + Copilot only |
| Auth model | Session trust (main / dm / group) + DM pairing | Azure AD / Entra SSO |
| Memory + RAG | Built-in hybrid (vector + BM25) | Bring your own, or call OpenClaw via API |
| Tool sandbox | Built-in Docker isolation | Implement yourself |
| Deploy complexity | Moderate (Gateway + channel creds) | Lower (Azure Bot + App Service) |
| Required cloud | None for Slack/Discord; Azure Bot for Teams | Azure subscription |
| Equivalent in this lab | Phase 2's `openclaw-a365` plugin packages this | Build per the steps below |

> **Hybrid is fine.** Many production setups run Pattern A locally for personal access *and* Pattern B in Azure for the company. Both share the same workspace, skills, and memory.

---

## 2. Prerequisites

| Tool | Version | Verify |
|------|---------|--------|
| Node.js | v22.16+ (v24 recommended) | `node --version` |
| pnpm | v9+ | `pnpm --version` |
| Docker Desktop | Latest with Compose v2 | `docker compose version` |
| .NET SDK | 8.0+ (only if building .NET samples) | `dotnet --version` |
| VS Code | Latest | `code --version` |
| Azure CLI | Latest | `az --version` |
| Dev Tunnels CLI | Latest | `devtunnel --version` |
| Git | 2.40+ | `git --version` |

VS Code extensions: **Microsoft 365 Agents Toolkit** (`ms-m365agents.m365agents-toolkit`), **GitHub Copilot Chat** (Agent mode required for AI-guided setup), **ESLint**, **Adaptive Card Previewer**, **C# Dev Kit** (for .NET samples).

Accounts: Azure subscription (Owner or Contributor), Microsoft 365 dev tenant with Teams sideloading, an LLM API key (Azure OpenAI / OpenAI / Anthropic).

> **Sections 3–6 below run entirely locally — no Azure subscription needed until Section 7.**

---

## 3. Set up OpenClaw

If you've already completed [Phase 1](./phase-1-building-autonomous-ai-assistant/README.md), you have OpenClaw installed. If you want a fresh checkout following this guide's flow:

```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw

# pnpm is REQUIRED — npm install will produce a broken tree
pnpm install
pnpm openclaw setup
pnpm ui:build
pnpm gateway:watch
```

The Gateway listens on `http://127.0.0.1:18789`. Open it in your browser to access the Control UI.

Configure your AI model in `~/.openclaw/openclaw.json`:

```json
{
  "agent": { "model": "anthropic/claude-sonnet-4-20250514" }
}
```

For Azure OpenAI / Microsoft Foundry models, use the [`azure-openai-responses` provider config](./phase-1-building-autonomous-ai-assistant/setup/LLM_PROVIDER_CONFIG.md) — Azure uses an `api-key` header, not Bearer auth, so set `authHeader: false` and add `headers["api-key"]`.

---

## 4. Build a Microsoft 365 Agents SDK agent

This is the second moving part — your own agent project that runs on **port 3978** and speaks the Bot Framework Activity protocol.

```bash
# In a separate directory
git clone https://github.com/microsoft/agents.git microsoft-agents-sdk
cd microsoft-agents-sdk/samples/nodejs/quickstart
pnpm install
```

Or scaffold a fresh project:

```bash
mkdir my-agent && cd my-agent
pnpm init
pnpm add @microsoft/agents-hosting @microsoft/agents-hosting-express @microsoft/agents-activity express
pnpm add -D typescript @types/node @types/express
```

Minimal `src/index.ts`:

```typescript
import express from "express";
import {
  AgentApplication,
  CloudAdapter,
  MemoryStorage,
  TurnState,
} from "@microsoft/agents-hosting";
import { ActivityTypes } from "@microsoft/agents-activity";
import { startServer } from "@microsoft/agents-hosting-express";

const storage = new MemoryStorage();
const app = new AgentApplication<TurnState>({ storage });

app.activity(ActivityTypes.Message, async (ctx) => {
  const text = ctx.activity.text?.trim() ?? "";
  if (text === "/status") {
    await ctx.sendActivity(`Channel: ${ctx.activity.channelId}`);
    return;
  }
  await ctx.sendActivity(`You said: ${text}`);
});

const adapter = new CloudAdapter();
const server = express();
startServer(server, adapter, app, { port: 3978 });
```

Run it:

```bash
pnpm tsc && node dist/index.js
# Or in dev: pnpm tsx src/index.ts
```

Smoke-test with the **Microsoft Agents Playground** (no Azure needed):

```bash
pnpm dlx @microsoft/agents-playground -e http://localhost:3978/api/messages
```

---

## 5. Wire OpenClaw to your SDK agent — Pattern A

Edit `~/.openclaw/openclaw.json`:

```json
{
  "agent": {
    "model": "anthropic/claude-sonnet-4-20250514"
  },
  "agents": {
    "routes": [
      { "channel": "teams", "agent": "m365-sdk-agent" }
    ],
    "profiles": {
      "m365-sdk-agent": {
        "endpoint": "http://localhost:3978/api/messages"
      }
    }
  }
}
```

Add the Teams channel to OpenClaw (you'll need an Azure Bot first — see Section 7):

```bash
openclaw channels add --channel teams \
  --bot-id "$TEAMS_BOT_ID" \
  --bot-secret "$TEAMS_BOT_SECRET"

openclaw doctor                          # health check
openclaw pairing approve teams <code>    # approve DM senders
```

OpenClaw's default `DM_POLICY` is `pairing` — unknown senders get a code and are blocked until approved. Keep this for production unless your org is fully trusted.

> **For the alternative integrated approach**, see Phase 2 — the [`openclaw-a365` plugin](./phase-2-tool-integration-capability-perimeters/README.md) packages the channel adapter, agent runtime, and Graph API tools into a single Docker container. Skip Sections 4–5 here if you go that route.

---

## 6. Wire OpenClaw to your SDK agent — Pattern B

In Pattern B, your SDK agent runs autonomously and calls OpenClaw's Gateway API for skills, memory, canvas, and sub-agent communication.

Create a workspace skill at `~/.openclaw/workspace/skills/my-agent/SKILL.md`:

```markdown
# My Agent Skill

## Tools
- `lookup_weather`: Get current weather for a city
- `search_knowledge_base`: Search internal documents

## Instructions
When the user asks about weather, use lookup_weather.
When the user asks about internal policy, use search_knowledge_base.
```

Call it from your SDK agent:

```typescript
async function invokeOpenClawSkill(skill: string, input: string): Promise<string> {
  const res = await fetch("http://localhost:18789/api/skills/invoke", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${process.env.OPENCLAW_GATEWAY_TOKEN}`,
    },
    body: JSON.stringify({ skill, input }),
  });
  return res.text();
}

app.activity(ActivityTypes.Message, async (ctx) => {
  const text = ctx.activity.text ?? "";
  if (text.startsWith("/weather ")) {
    const city = text.replace("/weather ", "");
    const result = await invokeOpenClawSkill("my-agent", city);
    await ctx.sendActivity(result);
    return;
  }
  await ctx.sendActivity(`You said: ${text}`);
});
```

Other Gateway endpoints worth knowing:

| Endpoint | Purpose |
|----------|---------|
| `POST /api/skills/invoke` | Run a workspace skill |
| `POST /api/memory/search` | Hybrid vector + BM25 search of agent memory |
| `POST /api/canvas/render` | Render an a2ui visual artefact |
| `GET  /api/sessions/list` | List active sessions |
| `POST /api/sessions/send` | Send a message to another agent |
| `POST /api/schedule/create` | Register a cron-based scheduled action |

The `OPENCLAW_GATEWAY_TOKEN` is generated by `pnpm openclaw setup` (or `./scripts/docker/setup.sh`).

---

## 7. Register an Azure Bot

Required for Teams. Skip if you only target Slack/Discord/WhatsApp via Pattern A.

```bash
az login
az account set --subscription "<your-subscription-id>"

# Resource group
az group create --name rg-openclaw-agent --location southeastasia

# App registration → BOT_ID + CLIENT_SECRET
APP_ID=$(az ad app create --display-name "OpenClaw Agent Bot" \
  --sign-in-audience AzureADMultipleOrgs --query appId -o tsv)

SECRET=$(az ad app credential reset --id "$APP_ID" \
  --display-name "bot-secret" --query password -o tsv)

# The Azure Bot resource
az bot create --resource-group rg-openclaw-agent \
  --name openclaw-agent-bot --app-type MultiTenant \
  --appid "$APP_ID" --kind azurebot

# Enable Teams channel
az bot msteams create --resource-group rg-openclaw-agent --name openclaw-agent-bot

echo "BOT_ID=$APP_ID"
echo "BOT_SECRET=$SECRET   # save now — secret is only shown once"
```

Set the messaging endpoint. For local dev, use Dev Tunnels:

```bash
devtunnel host -p 3978 --allow-anonymous
# → https://<tunnel-id>.devtunnels.ms

az bot update --resource-group rg-openclaw-agent \
  --name openclaw-agent-bot \
  --endpoint "https://<tunnel-id>.devtunnels.ms/api/messages"
```

In your SDK agent's `.env`:

```env
connections__serviceConnection__settings__clientId=<APP_ID>
connections__serviceConnection__settings__clientSecret=<SECRET>
connections__serviceConnection__settings__tenantId=<TENANT_ID>
```

Restart the agent — it now validates incoming Bot Framework tokens.

---

## 8. Sideload to Microsoft Teams

Create `appPackage/manifest.json`:

```json
{
  "$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.19/MicrosoftTeams.schema.json",
  "manifestVersion": "1.19",
  "version": "1.0.0",
  "id": "<a fresh GUID — python3 -c 'import uuid; print(uuid.uuid4())'>",
  "developer": {
    "name": "Your Org",
    "websiteUrl": "https://your-website.com",
    "privacyUrl": "https://your-website.com/privacy",
    "termsOfUseUrl": "https://your-website.com/terms"
  },
  "name": { "short": "OpenClaw Agent", "full": "OpenClaw AI Agent on M365 SDK" },
  "description": {
    "short": "AI assistant powered by OpenClaw + M365 Agents SDK",
    "full": "Multi-channel agent with workspace skills and Teams integration."
  },
  "icons": { "color": "color.png", "outline": "outline.png" },
  "accentColor": "#4F6BED",
  "bots": [
    {
      "botId": "<your APP_ID from Section 7>",
      "scopes": ["personal", "team", "groupChat"]
    }
  ],
  "permissions": ["identity", "messageTeamMembers"],
  "validDomains": ["*.devtunnels.ms"]
}
```

Add icons (`color.png` 192×192, `outline.png` 32×32 transparent), zip the package, and sideload:

```bash
cd appPackage
zip -j openclaw-agent.zip manifest.json color.png outline.png
# In Teams: Apps → Manage your apps → Upload an app → Upload a custom app
```

DM the bot in Teams. You should see the echo response. If you instead see a pairing code, run `openclaw pairing approve teams <code>`.

---

## 9. Deploy to Microsoft 365 Copilot

Once your agent is reachable at a stable HTTPS endpoint, plug into Copilot:

1. Go to **copilotstudio.microsoft.com**
2. Create a new agent or import your manifest
3. Configure the connection to your messaging endpoint
4. Publish to your M365 environment

The `microsoft/agents` SDK repo has two reference samples:

- `samples/nodejs/copilotstudio-client` — your code consumes a Copilot Studio agent
- `samples/nodejs/copilotstudio-skill` — your agent is exposed *as* a Copilot Studio skill, callable from inside Copilot

---

## 10. Production deploy (Azure Container Apps)

When local Dev Tunnels aren't enough:

```bash
# Build and push your image
docker build -t openclaw-agent:latest .
az acr login --name <your-registry>
docker tag openclaw-agent:latest <your-registry>.azurecr.io/openclaw-agent:latest
docker push <your-registry>.azurecr.io/openclaw-agent:latest

# Deploy to Container Apps
az containerapp create \
  --name openclaw-agent \
  --resource-group rg-openclaw-agent \
  --image <your-registry>.azurecr.io/openclaw-agent:latest \
  --target-port 3978 \
  --ingress external \
  --secrets "bot-id=$APP_ID" "bot-secret=$SECRET" \
  --env-vars "connections__serviceConnection__settings__clientId=secretref:bot-id" \
             "connections__serviceConnection__settings__clientSecret=secretref:bot-secret" \
  --min-replicas 1 --max-replicas 3

# Get the FQDN and update the Bot endpoint
FQDN=$(az containerapp show --name openclaw-agent --resource-group rg-openclaw-agent \
  --query properties.configuration.ingress.fqdn -o tsv)

az bot update --resource-group rg-openclaw-agent --name openclaw-agent-bot \
  --endpoint "https://$FQDN/api/messages"
```

> **Note**: Container Apps does not currently surface `--cap-add=NET_ADMIN`, so iptables-based capability perimeters (used by the Phase 2 plugin) won't work there. Use the [Azure VM deploy](./phase-2-tool-integration-capability-perimeters/setup/AZURE_VM_DEPLOY.md) for that. ACA is fine if you're not enforcing iptables-level perimeters.

---

## 11. Onboard with Agent 365 SDK — capability tiers

Agent 365 is **incremental**. Adopt tiers in order; each builds on the previous.

| Tier | Capability | What you get | Path |
|------|-----------|--------------|------|
| **1** | **Register** | Agent visible in M365 Admin Center; Entra ID + Purview + Defender governance applied automatically | AI-guided setup or `a365 setup` |
| **2** | **Observability** | Full OTel-based tracing of inputs, outputs, tool calls, model invocations; audit trail for compliance | AI-guided setup or `@microsoft/agent365-sdk-observability` |
| **3** | **Work IQ tooling** | Governed access to Mail, Calendar, OneDrive, SharePoint, Teams via MCP — admin-controlled, fully traced | Manual SDK integration ([phase-2 SDK guide](./phase-2-tool-integration-capability-perimeters/setup/AGENT_365_SDK_INTEGRATION.md)) |
| **4** | **AI Teammate** | Agent gets its own UPN, mailbox, Teams presence, org-chart entry; people @mention it like a human | AI-guided setup; Frontier Preview required |

### Agent type decision

| Type | Identity | Use when |
|------|----------|----------|
| **Agent (OBO)** | Acts *as* the signed-in user | Reactive flows where the agent should only see what the user can see |
| **Agent (S2S)** | Acts as *itself* (app permissions) | Autonomous background work — nightly compliance scans, scheduled reports |
| **AI Teammate** | Own user identity, mailbox, presence | The agent is a "team member" — onboarding bot, HR helper, project manager |

### Path A — AI-guided setup (recommended)

1. Open your agent project in **VS Code**
2. Switch **GitHub Copilot Chat** to **Agent mode** (Ask and Edit modes don't have terminal access)
3. Paste this prompt:

   ```
   Follow the steps at aka.ms/agent365enable to enable my agent for Agent 365.
   ```

4. Answer the three questions:
   - **Already in Teams/Copilot?** Yes if you completed Sections 7–9 above.
   - **Auth model?** OBO, S2S, or both.
   - **Capabilities?** Tick Register and Observability. Tick AI Teammate only if you have Frontier Preview access.
5. Confirm the agent name, manager email, and generated identifiers when prompted.
6. Review the code the AI writes into your project before committing — auto-instrumentation may need tweaks.

### Path B — Manual CLI

```bash
# Install the Agent 365 CLI
dotnet tool install -g Microsoft.Agent365.CLI

# Authenticate
az login
az account set --subscription "<id>"

# Initialise — creates a365.config.json
a365 config init

# Provision Entra agent identity + Azure resources
a365 blueprint setup

# (optional) deploy code to Azure App Service
a365 deploy azure
# Or skip if you're already on Container Apps from Section 10.

# Register the agent with M365 admin center
a365 publish
```

For the OpenClaw-specific wiring (when to use Tier 3 Work IQ tools, MCP servers, notification handlers, and how it relates to the existing `src/token.ts` and `src/graph-tools.ts`), see [`phase-2-.../setup/AGENT_365_SDK_INTEGRATION.md`](./phase-2-tool-integration-capability-perimeters/setup/AGENT_365_SDK_INTEGRATION.md).

### Verify

```bash
# In M365 Admin Center → Agents → All Agents
#   your agent should show "Registered" and (if Tier 2) "Observable"

# Send a test message in Teams
# OTel traces should appear in App Insights / Log Analytics within ~60 s
```

---

## 12. When to use this guide vs. the openclaw-a365 plugin

| Your situation | Use… |
|----------------|------|
| You want a **personal multi-channel agent** (Slack + Discord + Teams) with rich workspace skills | This guide — Pattern A |
| You want an **enterprise Teams bot** with Entra SSO and Adaptive Cards | This guide — Pattern B + Sections 7–11 |
| You want **agentic identity, FIC tokens, iptables-enforced network perimeter, and Graph calendar/mail tools** as a single deployable container | [Phase 2 — `openclaw-a365` plugin](./phase-2-tool-integration-capability-perimeters/README.md) |
| You want **all** of the above (multi-channel for personal use **and** enterprise plugin for the company) | Both — they share the same workspace and skills |
| You want **Agent 365 SDK Tier 3 Work IQ MCP** wired into existing OpenClaw Bot Framework code | [Phase 2 SDK integration guide](./phase-2-tool-integration-capability-perimeters/setup/AGENT_365_SDK_INTEGRATION.md) |

---

## 13. Environment variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `connections__serviceConnection__settings__clientId` | prod | Azure Bot app registration client ID |
| `connections__serviceConnection__settings__clientSecret` | prod | Azure Bot app registration secret |
| `connections__serviceConnection__settings__tenantId` | prod | Azure AD tenant ID |
| `OPENCLAW_PORT` | no | OpenClaw Gateway port (default `18789`) |
| `OPENCLAW_HOME` | no | OpenClaw config dir (default `~/.openclaw`) |
| `OPENCLAW_GATEWAY_TOKEN` | yes | API auth token (from `pnpm openclaw setup`) |
| `OPENAI_API_KEY` | conditional | OpenAI provider |
| `ANTHROPIC_API_KEY` | conditional | Anthropic provider |
| `AZURE_OPENAI_ENDPOINT` | conditional | Azure OpenAI base URL |
| `AZURE_OPENAI_API_KEY` | conditional | Azure OpenAI key |
| `AZURE_OPENAI_DEPLOYMENT` | conditional | Azure deployment name |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | no | Production OTel sink |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | Custom OTel endpoint |
| `PORT` | no | Agent server port (default `3978`) |

---

## 14. Quick-reference cheat sheet

```bash
# OpenClaw
pnpm gateway:watch                                  # dev mode with reload
openclaw channels add --channel teams \
  --bot-id "$BOT_ID" --bot-secret "$SECRET"
openclaw channels login                             # WhatsApp QR pairing
openclaw doctor                                     # health check
openclaw pairing approve <channel> <code>           # approve DM sender
openclaw agent --message "hello"                    # send test message

# M365 Agents SDK agent
pnpm tsx src/index.ts                               # dev
pnpm tsc && node dist/index.js                      # prod build
pnpm dlx @microsoft/agents-playground \
  -e http://localhost:3978/api/messages             # local test tool
devtunnel host -p 3978 --allow-anonymous            # expose to Azure Bot

# Agent 365 CLI
a365 config init
a365 blueprint setup
a365 deploy azure
a365 publish
```

---

## 15. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `pnpm install` fails in OpenClaw | Used `npm install` instead | Delete `node_modules`, run `pnpm install` |
| Server up but no response | SDK agent in `start:anon` mode but Teams expects auth | Use `npm run start` with `.env` populated |
| 401 from Azure OpenAI | Key not yet activated | New keys can take up to 2 hours; verify in Azure Portal |
| Bot not responding in Teams | Wrong messaging endpoint or tunnel down | `devtunnel host -p 3978 …` running? Endpoint matches `<tunnel>/api/messages`? |
| Gateway won't start | Port 18789 in use | `lsof -i :18789` and kill, or change port in `~/.openclaw/openclaw.json` |
| DM pairing code instead of reply | OpenClaw security working as designed | `openclaw pairing approve teams <code>` |
| Container App returns 502 | App failed to start or env vars missing | `az containerapp logs show -n openclaw-agent -g rg-openclaw-agent` |
| `Invalid audience` token error | Bot ID mismatch between Azure Bot and `.env` | `clientId` in `.env` must match `appId` from `az bot create` |
| AI-guided setup skips steps | GitHub Copilot Chat in Ask or Edit mode | Switch to **Agent mode** — only that mode has terminal access |
| `a365` commands fail with permission error | Custom client app registration incomplete | See [Agent 365 troubleshooting](https://learn.microsoft.com/microsoft-agent-365/troubleshooting) |

For Phase 2-specific issues, see [`phase-2/TROUBLESHOOTING.md`](./phase-2-tool-integration-capability-perimeters/TROUBLESHOOTING.md).

---

## 16. Reference links

| Resource | URL |
|----------|-----|
| OpenClaw GitHub | https://github.com/openclaw/openclaw |
| OpenClaw docs | https://docs.openclaw.ai |
| M365 Agents SDK | https://github.com/microsoft/agents |
| M365 Agents SDK docs | https://learn.microsoft.com/microsoft-365/agents-sdk/ |
| Agent 365 developer docs | https://learn.microsoft.com/microsoft-agent-365/developer/ |
| AI-guided setup prompt | https://aka.ms/agent365enable |
| Azure Bot Service | https://azure.microsoft.com/services/bot-services/ |
| Azure Container Apps | https://learn.microsoft.com/azure/container-apps/ |
| Copilot Studio | https://copilotstudio.microsoft.com |
| **This lab — Phase 2 plugin** | [`./phase-2-tool-integration-capability-perimeters/README.md`](./phase-2-tool-integration-capability-perimeters/README.md) |
| **This lab — Phase 2 SDK integration** | [`./phase-2-tool-integration-capability-perimeters/setup/AGENT_365_SDK_INTEGRATION.md`](./phase-2-tool-integration-capability-perimeters/setup/AGENT_365_SDK_INTEGRATION.md) |
