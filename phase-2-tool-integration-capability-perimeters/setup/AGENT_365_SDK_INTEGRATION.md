# Integrating the Agent 365 SDK into OpenClaw

> **What this guide is**: the concrete code-level steps for wiring Microsoft's **Agent 365 SDK** into the existing `openclaw-a365` plugin. The plugin today implements the same *concepts* (FIC tokens, agentic identity, Bot Framework messaging) by hand against the older **Microsoft 365 Agents SDK** (`@microsoft/agents-hosting`). The Agent 365 SDK adds a layer on top — governed Work IQ MCP tooling, typed notification handlers, and an Entra-managed blueprint identity.

> **Read first**: [`README.md`](../README.md#microsoft-agent-365-sdk--concepts--integration) for the conceptual overview, then [`AZURE_ENTRA_SETUP.md`](./AZURE_ENTRA_SETUP.md) for the underlying Entra resources.

> **For the broader picture** — how this plugin fits into the two integration patterns (OpenClaw Gateway-as-hub vs. SDK-standalone-with-skills), the Azure Bot setup, Teams sideload, Copilot Studio publishing, and the four Agent 365 capability tiers — see the top-level **[`../../TEAMS_COPILOT_INTEGRATION.md`](../../TEAMS_COPILOT_INTEGRATION.md)**. This guide focuses specifically on wiring the SDK into the existing `a365-plugin/` source.

---

## What the SDK actually adds

The plugin and the Agent 365 SDK live at different layers. Use this map to decide what to integrate vs. leave alone.

| Layer | Package | Provided by | What it does | Already in repo? |
|-------|---------|-------------|--------------|------------------|
| Channel runtime | `@microsoft/agents-hosting` | Microsoft 365 Agents SDK | Bot Framework adapter, `AgentApplication`, activity routing | ✅ yes |
| Hosting | `@microsoft/agents-hosting-express` | Microsoft 365 Agents SDK | Express server, `/api/messages` route | ✅ yes |
| Direct Graph | `@microsoft/microsoft-graph-client` | Microsoft Graph SDK | Hand-coded calendar/email/user calls in `src/graph-tools.ts` | ✅ yes |
| Identity (manual) | `@azure/msal-node` | MSAL | Hand-coded T1→T2→User FIC flow in `src/token.ts` | ✅ yes |
| **Notifications** | `@microsoft/agents-a365-notifications` | **Agent 365 SDK** | Typed handlers for email, Word/Excel/PPT comments, lifecycle events | ❌ missing |
| **Tooling (Work IQ MCP)** | `@microsoft/agents-a365-tooling` + extensions | **Agent 365 SDK** | Governed MCP servers (Mail, Calendar, SharePoint, Teams, etc.) instead of direct Graph | ❌ missing |
| **Blueprint lifecycle** | `@microsoft/agent365-cli` (global) | **Agent 365 CLI** | `a365 setup all`, `a365 develop add-mcp-servers`, `a365 publish` | ❌ missing |

**Bottom line**: keep everything that works (the Bot Framework channel, `runtime.ts`, `token.ts`, `graph-tools.ts`). Add three new things — the SDK packages, MCP tooling, and notification handlers.

---

## Pre-integration checklist

Before you touch a single line of code, make sure Phase 2 is healthy:

- [ ] `docker compose ps` shows `openclaw-a365` running
- [ ] `curl -X POST http://localhost:3978/api/messages` returns **401** (not 404)
- [ ] Bot replies to `Hello` in Teams
- [ ] `get_calendar_events` returns real owner data
- [ ] `./scripts/verify.sh --phase 2` reports no failures

If any of those fail, fix them first — adding SDK packages on top of a broken channel just multiplies the debugging surface.

---

## Step 1 — Install the SDK packages

The plugin has the **Microsoft 365 Agents SDK** but not the Agent 365 add-ons. Add them:

```bash
cd phase-2-tool-integration-capability-perimeters/a365-plugin

pnpm add \
  @microsoft/agents-a365-notifications \
  @microsoft/agents-a365-tooling \
  @microsoft/agents-a365-tooling-extensions-claude
```

> **Pick the right tooling extension** for your LLM orchestrator:
> - Claude Agent SDK / Anthropic-direct → `@microsoft/agents-a365-tooling-extensions-claude`
> - LangChain → `@microsoft/agents-a365-tooling-extensions-langchain`
> - OpenAI Agents SDK → `@microsoft/agents-a365-tooling-extensions-openai`
> - Microsoft Agent Framework / Semantic Kernel → `@microsoft/agents-a365-tooling-extensions-semantickernel`
>
> The default in this lab is the **Claude** extension because OpenClaw's primary model is Claude and we already mint Anthropic tokens.

After install, your `package.json` `dependencies` block should include all three new entries. Run `pnpm typecheck` to confirm there are no version conflicts with `@microsoft/agents-hosting@^1.1.0`.

---

## Step 2 — Install the Agent 365 CLI

The CLI runs on your laptop (not in the container) and manages blueprint lifecycle:

```bash
# Global install
npm install -g @microsoft/agent365-cli

# Verify
a365 --version
a365 setup -h

# Authenticate (uses your existing az login session)
az login
```

You need one of these Entra roles to use the CLI: **Global Administrator** OR **Agent ID Developer**. If you have neither, the CLI completes what it can and prints a consent URL for an admin to finish.

---

## Step 3 — Decide your blueprint path

Here you make a one-time decision: **stick with the manual Entra setup** or **let `a365 setup all` rebuild the blueprint via CLI**.

| Path | When to choose | What you keep from current setup |
|------|----------------|----------------------------------|
| **A. Keep manual setup** (current state) | You already followed [`AZURE_ENTRA_SETUP.md`](./AZURE_ENTRA_SETUP.md), the bot replies in Teams, and you don't need Work IQ MCP yet | Everything — `A365_APP_ID`, `AA_INSTANCE_ID`, FIC, agent user. Just install the SDK packages and stop here for this step. |
| **B. Migrate to `a365 setup all`** | You want governed MCP tools, Work IQ access, or to publish the agent to the M365 admin center catalogue | The agent UPN and tenant. The CLI creates a *new* blueprint (new app registration, new client secret, new FIC). Old `.env` values must be replaced. |

> **Cannot mix the two**: a single agent has one blueprint identity. If you go path B, run `a365 cleanup` against the new resources before re-running, and update `.env` with the new IDs from `a365.generated.config.json`.

### Path A — minimal change

You're done with this step. Move to Step 4.

### Path B — `a365 setup all`

```bash
# From the repo root, inside a working directory for the agent
cd phase-2-tool-integration-capability-perimeters/a365-plugin

# Create or import an a365.config.json (see template below)
cat > a365.config.json <<JSON
{
  "agentName": "OpenClaw-A365",
  "tenantId": "$(az account show --query tenantId -o tsv)",
  "subscriptionId": "$(az account show --query id -o tsv)",
  "resourceGroupName": "rg-openclaw-lab-dev",
  "appServicePlanSku": "B1",
  "messagingEndpoint": "https://openclaw-<suffix>.swedencentral.cloudapp.azure.com/api/messages",
  "deploymentProjectPath": "."
}
JSON

# Run end-to-end blueprint setup (creates Azure resources + Entra blueprint + FIC)
a365 setup all --m365

# After it finishes, port the new IDs into .env:
#   - agentBlueprintId          → A365_APP_ID
#   - agentBlueprintClientSecret → A365_APP_PASSWORD
#   - botMsaAppId / botId       → keep both for Bot Framework channel
#   - messagingEndpoint         → confirm matches your Caddy FQDN
jq '.' a365.generated.config.json
```

`a365 setup all --m365` registers the messaging endpoint via Teams Graph automatically. The pre-existing manual `infra/deploy.sh` Azure VM still hosts the container — `a365 setup all` does **not** deploy code, only identity + the App Service plan stub.

---

## Step 4 — Add notification handlers

Today the plugin only handles **conversation messages** (`POST /api/messages` with `type: "message"`). The Agent 365 SDK adds notifications: emails sent **to** the agent, @mentions in Word/Excel/PowerPoint comments, and lifecycle events (`agenticUserIdentityCreated`, etc.). These flow through the **same** `/api/messages` endpoint, just with different `type` and `entities` payloads.

### 4.1 Wire notification routing into `src/monitor.ts`

The plugin already has an `AgentApplication` instance somewhere in the runtime (created by `@microsoft/agents-hosting`). You need to grab it and register notification handlers. Add this to `src/monitor.ts` near the bottom of `monitorA365`, just before the server starts:

```typescript
// src/monitor.ts — add new imports at the top
import {
  AgentNotificationActivity,
  NotificationType,
} from "@microsoft/agents-a365-notifications";

// Inside monitorA365(), after the AgentApplication is created
// and BEFORE you start the Express server:

agentApp.onAgentNotification(
  "*",                                                // wildcard sub-channel
  async (context, _state, notification: AgentNotificationActivity) => {
    // Always preserve OpenClaw's per-request context isolation
    runWithGraphToolContext(
      {
        agentIdentity: cfg.agentIdentity,
        currentUserEmail: context.activity.from?.id ?? "unknown",
        currentUserRole: roleFor(context.activity.from?.aadObjectId),
        sendActivity: context.sendActivity.bind(context),
      },
      async () => {
        switch (notification.notificationType) {
          case NotificationType.EmailNotification:
            await handleEmailNotification(context, notification);
            break;

          case NotificationType.WpxComment:
            await handleDocumentComment(context, notification);
            break;

          case NotificationType.AgentLifecycleNotification:
            await handleLifecycleEvent(context, notification);
            break;

          default:
            // Unknown sub-channel — log and acknowledge
            console.log("[a365] unhandled notification:", notification.notificationType);
        }
      },
    );
  },
);
```

### 4.2 Implement the handlers in `src/channel.ts`

Add these companion functions (or split into a new `src/notifications.ts`):

```typescript
// src/channel.ts — new exports
import type { TurnContext } from "@microsoft/agents-hosting";
import type { AgentNotificationActivity } from "@microsoft/agents-a365-notifications";
import { sanitizeForPrompt } from "./types.js"; // small helper, see below

export async function handleEmailNotification(
  ctx: TurnContext,
  notification: AgentNotificationActivity,
): Promise<void> {
  const email = notification.emailNotification;
  if (!email) return;

  const sender = ctx.activity.from;
  const safeName = sanitizeForPrompt(sender?.name ?? "unknown");

  // Hand the email body to the agent runtime as if it were a message
  const userInput =
    `Inbound email from ${safeName} (${sender?.id}). ` +
    `Email ID: ${email.id}. ` +
    `Body: ${email.htmlBody?.slice(0, 8000) ?? "(empty)"}`;

  await runtime.handleMessage(userInput, tools);
}

export async function handleDocumentComment(
  ctx: TurnContext,
  notification: AgentNotificationActivity,
): Promise<void> {
  const comment = notification.wpxCommentNotification;
  if (!comment) return;

  const product = ctx.activity.channelData?.productContext ?? "Document";
  await ctx.sendActivity(
    `Got a ${product} comment (id: ${comment.commentId}) — reviewing.`,
  );
  // Optionally: fetch the document via Graph using comment.documentId,
  // analyse the surrounding text, post a reply via comment APIs.
}

export async function handleLifecycleEvent(
  ctx: TurnContext,
  notification: AgentNotificationActivity,
): Promise<void> {
  const lifecycle = notification.lifecycleEvent;
  console.log("[a365] lifecycle event:", lifecycle?.lifecycleEventType);
  // Common reactions:
  //   agenticUserIdentityCreated → seed memory, send welcome DM to owner
  //   agenticUserWorkloadOnboardingUpdated → re-warm token cache
  //   agenticUserDeleted → flush conversation-store.ts persisted refs
}
```

### 4.3 Sanitise sender names before LLM injection

The `from.name` field is **user-controlled text**. Add a helper to `src/types.ts`:

```typescript
// src/types.ts
export function sanitizeForPrompt(s: string, maxLen = 80): string {
  return s
    .replace(/[ --]/g, "") // strip control chars
    .replace(/[<>{}[\]()`]/g, "")                  // strip prompt-injection bait
    .slice(0, maxLen)
    .trim();
}
```

### 4.4 Test locally

```bash
docker compose up -d --build
docker compose logs -f openclaw-a365 | grep -i "notification"

# Send a test email TO the agent's UPN. Within ~30s the logs should print:
#   [a365] EmailNotification handler entered
#   [a365] runtime.handleMessage(...) returned
```

---

## Step 5 — Add Work IQ MCP tooling

This step gives the agent access to governed MCP servers (Mail, Calendar, SharePoint, Teams, OneDrive, Word) routed through Microsoft's Tooling platform. **Existing `src/graph-tools.ts` keeps working** — MCP tools are additive.

### 5.1 One-time tenant prep (Global Administrator)

```powershell
# Run once per tenant — registers the Agent 365 Tools service principal
# Source: https://github.com/microsoft/Agent365-devTools/blob/main/scripts/cli/Auth/New-Agent365ToolsServicePrincipalProdPublic.ps1
.\New-Agent365ToolsServicePrincipalProdPublic.ps1
```

### 5.2 Register MCP servers via the CLI

```bash
cd phase-2-tool-integration-capability-perimeters/a365-plugin

# Discover what's available
a365 develop list-available

# Add the servers your agent should use
a365 develop add-mcp-servers mcp_MailTools mcp_CalendarTools mcp_TeamsTools

# This writes ToolingManifest.json into the project — commit it to git
ls ToolingManifest.json
git add ToolingManifest.json

# Apply MCP permissions to the blueprint (Global Admin only)
a365 setup permissions mcp
```

The generated `ToolingManifest.json` looks like:

```json
{
  "mcpServers": [
    {
      "mcpServerName": "mcp_MailTools",
      "mcpServerUniqueName": "mcp_MailTools",
      "scope": "McpServers.Mail.All",
      "audience": "api://05879165-0320-489e-b644-f72b33f3edf0"
    },
    {
      "mcpServerName": "mcp_CalendarTools",
      "mcpServerUniqueName": "mcp_CalendarTools",
      "scope": "McpServers.Calendar.All",
      "audience": "api://05879165-0320-489e-b644-f72b33f3edf0"
    }
  ]
}
```

### 5.3 Wire the MCP servers into the runtime

Create `src/mcp-tools.ts` to load the manifest and register tools at runtime:

```typescript
// src/mcp-tools.ts
import { McpToolServerConfigurationService } from "@microsoft/agents-a365-tooling";
import { McpToolRegistrationService } from "@microsoft/agents-a365-tooling-extensions-claude";
import type { TurnContext } from "@microsoft/agents-hosting";
import { getGraphToken } from "./token.js";

const configService = new McpToolServerConfigurationService();
const toolService = new McpToolRegistrationService();

/**
 * Bind Work IQ MCP tools onto an OpenClaw runtime invocation.
 * Call this from src/channel.ts inside runWithGraphToolContext.
 */
export async function attachMcpTools(
  agent: unknown,                  // OpenClaw agent handle
  agenticUserId: string,           // AGENT_IDENTITY OID
  authorization: unknown,          // M365 Agents SDK Authorization context
  turnContext: TurnContext,
): Promise<unknown> {
  // The MCP gateway accepts the same agent FIC token we already mint
  // for Graph in token.ts — reuse it; no new credentials needed.
  const mcpAuthToken = await getGraphToken({
    audience: "api://agent365tools",  // MCP gateway audience
  });

  return toolService.addToolServersToAgent(
    agent,
    agenticUserId,
    authorization,
    turnContext,
    mcpAuthToken,
  );
}
```

Then in `src/channel.ts`, where the agent runtime is invoked:

```typescript
// src/channel.ts — inside the message handler, after building `tools`
import { attachMcpTools } from "./mcp-tools.js";

// ... existing graph-tools registration ...

const agent = await runtime.createAgent({ tools });
const agentWithMcp = await attachMcpTools(
  agent,
  cfg.agentIdentityOid,    // resolve once at startup from agentIdentity UPN
  authorization,
  turnContext,
);

await runtime.run(agentWithMcp, message);
```

### 5.4 Local development with the mock tooling server

Don't burn through tenant quotas while developing. Use the CLI's mock:

```bash
a365 develop start-mock-tooling-server
# Listens on http://localhost:5309

# Set in .env (development only):
MCP_PLATFORM_ENDPOINT=http://localhost:5309
```

The mock returns canned responses for all MCP servers — no auth, no rate limits, no real Graph traffic.

---

## Step 6 — Decision matrix: direct Graph vs. MCP

You now have **two ways** to read calendar events. Use this table to decide which path each new tool should take:

| Situation | Use direct Graph (`graph-tools.ts`) | Use MCP (`mcp-tools.ts`) |
|-----------|--------------------------------------|--------------------------|
| You need sub-100ms latency | ✅ direct call wins | ❌ MCP adds gateway hop |
| You need governance/audit trails in Microsoft Purview | ❌ | ✅ MCP calls are auditable in Purview |
| You don't have a Microsoft 365 Copilot license | ✅ Graph works without Copilot | ❌ Work IQ MCP requires Copilot license |
| You're sharing this agent across multiple users | ❌ direct Graph is per-FIC-token | ✅ MCP enforces per-user OBO at gateway |
| You need a tool that doesn't exist in MCP yet | ✅ keep direct Graph | n/a |

**Recommendation for this lab**: keep `graph-tools.ts` as the fast path for owner-only operations and add MCP tools for new domains (SharePoint, Teams, OneDrive). Don't migrate calendar/email yet — the existing tools work and have tests.

---

## Step 7 — Verification

Run these checks after the integration is wired:

```bash
# 1. SDK packages are installed
pnpm list | grep "@microsoft/agents-a365"
# Expected: agents-a365-notifications, agents-a365-tooling, agents-a365-tooling-extensions-claude

# 2. Typecheck still passes
pnpm typecheck

# 3. Tests still pass (no regressions in existing graph-tools/token/channel tests)
pnpm test

# 4. Container starts cleanly
docker compose up -d --build
docker compose logs --tail=30 openclaw-a365 | grep -E "started|error"

# 5. Bot Framework endpoint still responds
curl -X POST http://localhost:3978/api/messages -o /dev/null -w "%{http_code}\n"
# Expected: 401

# 6. ToolingManifest.json is loaded
docker compose exec openclaw-a365 ls /app/ToolingManifest.json && \
  docker compose exec openclaw-a365 cat /app/ToolingManifest.json | jq '.mcpServers | length'

# 7. Send a test email → check the new notification handler fires
# (Send an email from your owner UPN to the agent UPN, then:)
docker compose logs openclaw-a365 | grep -i "EmailNotification\|notification handler"

# 8. End-to-end: ask the agent in Teams to use a Work IQ tool
# > "Search my SharePoint for documents about project X"
# Expected: agent invokes mcp_SharePointTools.search and returns real results
```

---

## What didn't change

So you can sanity-check no scope creep happened, here's what stays exactly the same after this integration:

- `src/token.ts` — manual T1→T2→User FIC flow still mints Graph tokens
- `src/graph-tools.ts` — all 8 existing direct-Graph tools, unchanged
- `src/runtime.ts` — OpenClaw runtime singleton, unchanged
- `src/conversation-store.ts`, `src/adapter-store.ts`, `src/outbound.ts` — unchanged
- `infra/main.bicep` and the VM deployment — unchanged
- `config/capability-perimeter.yaml` — unchanged (MCP gateway calls are subject to the same iptables rules as Graph)
- `.env` — unchanged unless you took blueprint Path B in Step 3

What's new on disk: `src/mcp-tools.ts`, `ToolingManifest.json`, three new entries in `package.json`, optional `src/notifications.ts`, optional `a365.config.json` and `a365.generated.config.json` (Path B only).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `pnpm add` errors with peer-dep conflict | `@microsoft/agents-a365-*` requires `@microsoft/agents-hosting@^1.1.0` exactly | Pin `agents-hosting` in `package.json`; rerun `pnpm install` |
| `addToolServersToAgent` throws `Unauthorized` | Agent 365 Tools service principal not registered in tenant | Re-run `New-Agent365ToolsServicePrincipalProdPublic.ps1` as Global Admin |
| Notifications never fire | Bot endpoint registered for Bot Framework only, not for A365 notifications | `a365 setup blueprint --update-endpoint https://<your-fqdn>/api/messages --m365` |
| `mcp_MailTools` returns 403 | Blueprint hasn't been granted MCP permissions | `a365 setup permissions mcp` (Global Admin) |
| MCP token request fails with `invalid_audience` | Wrong audience used for MCP gateway | Use `api://agent365tools` (not `graph.microsoft.com`) for `getGraphToken({audience})` |
| `ToolingManifest.json` not found in container | File not committed or not copied into image | `git add ToolingManifest.json` and rebuild the image (it's part of the project root copy in the Dockerfile) |
| Lifecycle event `agenticUserDeleted` never received | Agent user wasn't actually deleted, or your blueprint isn't subscribed | Check `a365 develop list-configured`; lifecycle events come automatically once notifications are wired |

For the underlying Bot Framework / Graph / FIC issues that are unrelated to the SDK, see the main [`TROUBLESHOOTING.md`](../TROUBLESHOOTING.md).

---

## Where to go next

1. **Publish the agent** to the M365 admin center catalogue:
   ```bash
   a365 publish
   ```
   Admins can then activate your blueprint and provision agent instances per-user.

2. **Add observability** — wire `@opentelemetry/sdk-node` so every MCP call carries a `traceparent`. See Phase 3's `shared/otel/` plan.

3. **Migrate to ACA** — once Phase 3 introduces network policy via Private Endpoints, the `--cap-add=NET_ADMIN` requirement disappears and you can move from VM to Azure Container Apps. Until then, the VM deployment is the right shape.

4. **Phase 3** — multi-agent orchestration with shared Dataverse memory and Work IQ MCP context. See [`../../phase-3-multi-agent-orchestration-governance/README.md`](../../phase-3-multi-agent-orchestration-governance/README.md).
