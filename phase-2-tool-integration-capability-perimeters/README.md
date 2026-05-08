# Phase 2 — Tool Integration & Capability Perimeters

> **Status**: 📐 Planned. Code generation deferred until Phase 1 is verified end-to-end in your tenant.
> **Estimated effort**: ~23 hours.
> **Prerequisites**: Phase 1 deployed and running; agent reachable from Teams.

This phase makes the agent **enterprise-governable**. We add a tool registry that all capabilities flow through, integrate Microsoft's first-party MCP servers using the **same FIC tokens** Phase 1 already mints, gate risky tool calls behind **Adaptive Card approval workflows**, and emit a structured audit log to Azure Log Analytics.

## What you'll build

```
Teams DM → A365 channel → runtime
                            │
                            ▼
                ┌────────────────────────┐
                │ Tool Registry          │
                │  ─ graph-tools (P1)    │
                │  ─ jira (Atlassian)    │
                │  ─ ms-learn-mcp        │  ← reuses agent FIC tokens
                │  ─ ms-graph-mcp        │
                │  ─ ms-azure-mcp        │
                │  ─ http-fetch          │
                └─────────┬──────────────┘
                          │
                          ▼
                ┌────────────────────────┐
                │ Perimeter Enforcer     │
                │  ─ RBAC (Owner/Req)    │
                │  ─ rate limit          │
                │  ─ arg validation      │
                │  ─ redaction           │
                └─────────┬──────────────┘
                          │
                ┌─────────┴──────────────┐
                ▼                        ▼
       allow → tool.run()      approval-required
                                       │
                                       ▼
                            ┌──────────────────────┐
                            │ Adaptive Card to     │
                            │ owner in Teams DM    │
                            │  Approve / Deny+note │
                            └──────────┬───────────┘
                                       │
                          owner clicks Approve / Deny
                                       │
                                       ▼
                            tool.run()  or  reject
                                       │
                                       ▼
                            Audit log → Log Analytics
```

## Confirmed scope

| Decision | Value |
|---|---|
| Canonical external API tool | **Jira Cloud** (full e2e: registry → enforcer → approval → audit) |
| Microsoft MCP servers | **Learn + Microsoft 365/Graph + Azure** (all three) |
| MCP authentication | **Reuse agent FIC tokens** from `src/token.ts` — zero new credentials |
| Approval persistence | **In-memory** with 10-minute auto-deny |
| Approval UX | **Adaptive Card** (Approve / Deny + reason) |
| Audit destination | **Azure Log Analytics workspace** (JSONL stdout → Azure Monitor Agent) |

## Modules

| # | Module | Focus | Estimated time |
|---|--------|-------|---------------|
| 1 | Architecture & plugin model | How `a365-plugin/` extends OpenClaw; flow from Teams → tool | 2 hours |
| 2 | Tool Registry | Refactor Phase 1 graph-tools into `src/tools/registry.ts`; add Jira | 5 hours |
| 3 | Perimeter Enforcer | RBAC, rate limits, arg validation, redaction via `src/perimeter/` | 5 hours |
| 4 | Microsoft MCP Servers | Learn + Graph + Azure MCP as HTTP+SSE clients reusing FIC tokens | 5 hours |
| 5 | Approval Workflows & Audit | Adaptive Card gates + Log Analytics JSONL audit | 6 hours |

## Repo additions in Phase 2

```
src/tools/registry.ts                src/perimeter/policy.ts
src/tools/http-tool.ts               src/perimeter/enforcer.ts
src/tools/mcp-tool.ts                src/perimeter/redaction.ts
src/tools/builtin/jira-tool.ts       src/perimeter/rate-limiter.ts
src/tools/builtin/http-fetch.ts      src/approvals/approval-card.ts
src/tools/builtin/ms-mcp/learn.ts    src/approvals/approval-store.ts
src/tools/builtin/ms-mcp/graph-mcp.ts  src/approvals/approval-handler.ts
src/tools/builtin/ms-mcp/azure-mcp.ts  src/approvals/timeout.ts
                                     src/governance/audit-log.ts
config/policy-pack.yaml              src/governance/policy-pack.ts
config/tool-manifests/jira.yaml      infra/alerts.bicep
config/tool-manifests/ms-*-mcp.yaml
```

## Capability perimeter (final schema)

The `config/capability-perimeter.yaml` already exists with placeholder fields (`rate_limit`, `approval`, `redact_args`) that Phase 2 starts honoring. See [`a365-plugin/config/capability-perimeter.yaml`](./a365-plugin/config/capability-perimeter.yaml) for the live schema.

The three enforcement modes:

| Mode | Effect |
|---|---|
| `unrestricted` | No network restrictions. Start here for development. |
| `restricted` | Only essential Microsoft auth, Graph, Bot Framework + your LLM provider. |
| `allowlist` | Restricted + the explicit `allowlist:` domains (e.g. `api.atlassian.com`). |

## Flow summary

1. LLM calls a registered tool.
2. `enforcer.ts` checks: tool enabled? user role allowed? rate limit OK? args valid?
3. If `approval` clause matches → create `ApprovalRequest` (in-memory, UUID), post Adaptive Card to owner's Teams DM, await `Action.Submit` or 10-min timeout.
4. Approved → tool runs. Denied / timeout → tool returns a structured denial to the LLM, which explains to the requester.
5. Every transition logged via `audit-log.ts` → JSONL to stdout → Azure Monitor Agent → Log Analytics.

## Microsoft MCP integration

`src/tools/mcp-tool.ts` is an **HTTP+SSE** client (no stdio — Microsoft MCP servers are remote-hosted). On startup it:

1. Calls `tools/list` on each configured MCP server.
2. Registers each discovered tool prefixed with the server name (`ms_learn_mcp.search`, `ms_graph_mcp.calendar_read`, etc.).
3. Applies wildcard perimeter rules from `config/capability-perimeter.yaml`.
4. Authenticates each call by minting an FIC token for the right audience (`learn.microsoft.com`, `graph.microsoft.com`, `management.azure.com`).

**Dedup rule**: where an MCP server overlaps with direct Graph tools (calendar, mail), the direct tool is preferred for latency; the MCP variant is registered but disabled by default.

## Files in this directory

| File | Purpose |
|---|---|
| [`README.md`](./README.md) | This file — Phase 2 learning guide |
| [`INDEX.md`](./INDEX.md) | Module navigation |
| [`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md) | Phase 2-specific issues |
| [`a365-plugin/`](./a365-plugin/) | Microsoft 365 Agents channel plugin source |
| [`a365-plugin/config/`](./a365-plugin/config/) | Runtime config: capability perimeter, agent personality |
| [`a365-plugin/infra/`](./a365-plugin/infra/) | Azure Bicep templates, cloud-init, deploy script |
| [`setup/AZURE_ENTRA_SETUP.md`](./setup/AZURE_ENTRA_SETUP.md) | Entra ID: Agentic User, App Registration, FIC, AA Instance ID |
| [`setup/AZURE_VM_DEPLOY.md`](./setup/AZURE_VM_DEPLOY.md) | Azure VM deployment with Caddy, Key Vault, Managed Identity (~$65/mo) |
| [`setup/M365_AGENTS_SETUP.md`](./setup/M365_AGENTS_SETUP.md) | M365 Agents channel registration and Teams setup |
| [`setup/AGENT_365_SDK_INTEGRATION.md`](./setup/AGENT_365_SDK_INTEGRATION.md) | **Wiring the Agent 365 SDK into OpenClaw — packages, notification handlers, MCP tools, blueprint paths** |
| [`setup/GRAPH_API_TOOLS.md`](./setup/GRAPH_API_TOOLS.md) | All 8 Graph tools reference + example prompts |
| [`setup/NETWORK_POLICY.md`](./setup/NETWORK_POLICY.md) | Capability perimeters via iptables |
| [`setup/APPROVAL_WORKFLOWS.md`](./setup/APPROVAL_WORKFLOWS.md) | Adaptive Card approval gates + human-in-the-loop |

---

## Microsoft Agent 365 SDK — Concepts & Integration

The `openclaw-a365` plugin already implements the core mechanics of the Microsoft Agent 365 SDK by hand — FIC tokens, Bot Framework messaging, proactive send. This section maps the official Agent 365 SDK vocabulary to what we've built, adds the concepts not yet covered (tooling servers, notifications, blueprint CLI), and gives you the reference you need when expanding or migrating to the official SDK.

> **For the actual code-level integration steps** — installing the SDK packages, wiring notification handlers into `src/monitor.ts`, registering Work IQ MCP tools alongside the existing direct-Graph tools, and choosing between manual Entra setup vs. `a365 setup all` — see **[`setup/AGENT_365_SDK_INTEGRATION.md`](./setup/AGENT_365_SDK_INTEGRATION.md)**.

> **Official reference**: [learn.microsoft.com/en-us/microsoft-agent-365/developer/](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/)

> **AI-guided setup**: Open this repo in Claude Code or GitHub Copilot CLI and say _"Set up the Enterprise AI Agent Lab Phase 2"_. The AI reads [`CodingAgent.md`](../../CodingAgent.md) and walks you through every step automatically — the same pattern used by the official Agent 365 [`aka.ms/agent365enable`](https://aka.ms/agent365enable) instruction file.

---

### Agent 365 SDK Architecture

The Agent 365 SDK is **not** an agent framework — it layers enterprise capabilities on top of agents you have already built, regardless of the underlying stack.

| Layer | Role | Provided by |
|-------|------|-------------|
| **Enterprise Capabilities** | Identity, notifications, observability, governed tooling | Agent 365 SDK |
| **Agent Logic** | Prompts, workflows, reasoning | Your implementation (this lab) |
| **LLM Orchestrator Runtime** | Model invocation, tool orchestration | OpenClaw + your chosen LLM |

Supported agent platforms: Copilot Studio, Azure AI Foundry, Microsoft Agent Framework, **Claude Code SDK**, OpenAI Agents SDK, LangChain — and any custom code including this lab.

---

### Agent 365 CLI — Installation

The `a365` CLI automates the full development lifecycle: blueprint setup, identity configuration, MCP integration, Azure deployment, and admin center publishing.

```bash
# Install via npm
npm install -g @microsoft/agent365-cli

# Or via winget (Windows)
winget install Microsoft.Agent365CLI

# Verify installation
a365 --version

# Authenticate (uses az login context)
az login
a365 setup -h
```

> **Permissions required**: Global Administrator **or** Agent ID Developer role in your Entra tenant, plus Azure subscription contributor access.

---

### Agent Identity

Every enterprise agent in the Agent 365 model has **three identity components** that work together:

| Component | What it is | In this lab |
|-----------|-----------|-------------|
| **Agent blueprint** (Agentic application) | IT-approved template: Entra app registration, Graph scopes, auth config, resource definitions | Your `A365_APP_ID` app registration in Entra |
| **Agent instance** | A deployment of the blueprint: unique Entra Agent ID, service principal, FIC credentials | The running container — one instance per tenant |
| **Agent user** | Runtime identity visible in your org: mailbox, Teams presence, org chart entry, `agent@tenant.onmicrosoft.com` | `AGENT_IDENTITY` env var |

#### Agent user characteristics

- Marked as **agentic** in the directory (`idtyp=user` in tokens)
- **Cannot** have passwords, passkeys, or MFA factors
- Must be created via API call from the parent agent instance
- Can be @mentioned in Teams, Word, email, and other M365 apps
- Appears in the org chart under an assigned manager
- Mailbox and OneDrive provisioned after license assignment (10–15 min, up to 24 h)

#### Authentication flows

The Agent 365 SDK supports two flows, both already implemented in `src/token.ts`:

| Flow | Description | When to use |
|------|-------------|-------------|
| **Agent identity** (FIC/T1→T2→Agent) | Agent authenticates with its own credentials; acts as itself | Autonomous tasks: calendar, email from agent's mailbox, background processing |
| **On-Behalf-Of (OBO)** | Agent receives user's delegated token; acts as the user | Accessing user-specific data with user's permissions; auditable reactive flows |

#### Permission management

Permissions can be set at three levels:
- **Blueprint level** — base permissions inherited by all instances
- **Instance level** — specific permissions for this deployment
- **Agent user level** — user-specific grants and licenses

Required licenses for full Microsoft 365 capabilities: **Microsoft 365 E5**, **Teams Enterprise**, or **Microsoft 365 Copilot**.

---

### Agent Blueprint

The blueprint is the **IT-approved, governance-enforced definition** of your agent's capabilities. It defines:

- Permitted Work IQ tool access
- Security and compliance constraints (Purview DLP, Defender monitoring)
- Audit requirements and lifecycle metadata
- Linked governance policy templates (DLP, external access, logging)

When a blueprint is **activated** in the M365 admin center, users can request new agent instances from it. Every instance inherits the blueprint's rules — preventing shadow/rogue agents and anchoring each agent in Entra governance.

#### Create a blueprint with the Agent 365 CLI

The `a365` CLI automates the full setup. Install it and run:

```bash
# Default agent setup (reads a365.config.json if present)
a365 setup all

# Config-free (no a365.config.json needed)
a365 setup all --agent-name <your-agent-name>

# M365 agent (Teams / Copilot) — registers messaging endpoint automatically
a365 setup all --m365

# AI Teammate (Frontier preview — own mailbox + Teams presence)
a365 setup all --aiteammate
```

`a365 setup all` performs:
1. Creates Azure infrastructure (resource group, App Service Plan, Web App with managed identity)
2. Registers agent blueprint in Entra (app registration, service principal, FIC, `managerApplications`)
3. Configures API permissions (Microsoft Graph, Messaging Bot API, inheritable instance permissions)
4. Saves all generated IDs and the messaging endpoint to `a365.generated.config.json`

> **Note:** Blueprints must have `managerApplications` set or the platform rejects them. The CLI sets this automatically.

#### Configuration file (`a365.config.json`)

```json
{
  "agentName": "OpenClaw-A365",
  "tenantId": "${AZURE_TENANT_ID}",
  "subscriptionId": "${AZURE_SUBSCRIPTION_ID}",
  "resourceGroupName": "rg-openclaw-lab-dev",
  "appServicePlanSku": "B1",
  "messagingEndpoint": "https://your-app.azurewebsites.net/api/messages",
  "deploymentProjectPath": "."
}
```

#### Apply custom Graph API permissions

```bash
a365 setup permissions custom \
  --resource-app-id 00000003-0000-0000-c000-000000000000 \
  --scopes Mail.Read.Shared,Mail.Send.Shared,Calendars.ReadWrite.Shared,User.Read.All
```

#### Verify setup

```bash
# Check generated config
cat a365.generated.config.json | jq .

# Verify Azure resources
az resource list --resource-group rg-openclaw-lab-dev --output table

# Verify managed identity is enabled
az webapp identity show --name <your-web-app> --resource-group rg-openclaw-lab-dev
```

Expected key fields in `a365.generated.config.json`:

| Field | Purpose |
|-------|---------|
| `agentBlueprintId` | Your agent's unique Entra ID — used in Developer Portal and admin center |
| `messagingEndpoint` | Where Teams/Outlook route inbound messages |
| `managedIdentityPrincipalId` | Azure managed identity for Key Vault access |
| `resourceConsents` | API permissions granted (Graph, Messaging Bot, Observability, Power Platform) |
| `completed` | Must be `true` before deployment |

---

### Agent Messaging Endpoint

The **messaging endpoint** is the HTTPS URL where the Agent 365 service delivers agentic notification messages to your agent. In the lab this is already wired as `POST /api/messages` served by `src/monitor.ts` on port 3978 behind Caddy TLS.

#### Configure in `a365.config.json`

```json
{
  "messagingEndpoint": "https://your-app.azurewebsites.net/api/messages",
  "deploymentProjectPath": "."
}
```

#### Register the endpoint

```bash
# M365 agents (Teams / Copilot) — registers via Teams Graph / MCP Platform
a365 setup blueprint --endpoint-only --m365

# Non-M365 agents — prints the Teams Developer Portal URL for manual config
a365 setup blueprint --endpoint-only

# Update an existing endpoint URL
a365 setup blueprint --update-endpoint https://your-new-host.example.com/api/messages --m365
```

#### Endpoint URL patterns by deployment

| Target | URL pattern |
|--------|------------|
| Azure Web App | `https://<app>.azurewebsites.net/api/messages` |
| Azure VM + Caddy (this lab) | `https://<fqdn>.cloudapp.azure.com/api/messages` |
| AWS API Gateway | `https://<id>.execute-api.<region>.amazonaws.com/api/messages` |
| GCP Cloud Run | `https://<hash>-<region>.run.app/api/messages` |
| Local (Dev Tunnels) | `https://<id>.devtunnels.ms:3978/api/messages` |

#### Remove the endpoint registration

```bash
# M365 agents
a365 cleanup blueprint --endpoint-only --m365

# Non-M365 agents
a365 cleanup blueprint --endpoint-only
```

---

### Tooling Servers (Work IQ MCP)

**Work IQ MCP** is the governed gateway for Microsoft 365 tool access. It replaces direct Graph API calls with standardized, admin-controlled, auditable MCP servers. The lab's `src/graph-tools.ts` implements the same operations as Work IQ tools — the migration path is clear.

#### Agent 365 tools catalog

| MCP Server | Capabilities |
|------------|-------------|
| **Work IQ Copilot** | Chat with M365 Copilot, multi-turn threads, ground responses with files |
| **Work IQ Calendar** | Create, list, update, delete events; accept/decline; resolve conflicts |
| **Work IQ Mail** | Create, update, delete messages; reply; semantic search |
| **Work IQ SharePoint** | Upload files; get metadata; search; manage lists |
| **Work IQ OneDrive** | Manage files and folders in personal OneDrive |
| **Work IQ Teams** | Create/update chats; add members; post messages; channel operations |
| **Work IQ User** | Get manager, direct reports, profile info; search users |
| **Work IQ Word** | Create/read documents; add/reply to comments |
| **Dataverse / Dynamics 365** | CRUD operations and domain-specific business actions |

> **Note:** Work IQ MCP servers require a **Microsoft 365 Copilot license**.

#### One-time tenant setup (Global Administrator, run once per tenant)

Before any agent in your tenant can call Work IQ MCP servers, a Global Administrator must register the Agent 365 Tools service principal:

```bash
# Download and run the one-time setup script
# Source: https://github.com/microsoft/Agent365-devTools/blob/main/scripts/cli/Auth/New-Agent365ToolsServicePrincipalProdPublic.ps1

# PowerShell (Windows / pwsh on Mac/Linux)
.\New-Agent365ToolsServicePrincipalProdPublic.ps1
# Sign in with Global Admin credentials when prompted.
# This is a one-time operation per tenant.
```

After this runs, your tenant is ready for MCP server configuration and any developer in the tenant can start adding MCP servers to their agents.

#### Add MCP servers to your agent

```bash
# List all available MCP servers in the catalog
a365 develop list-available

# Add one or more servers (updates ToolingManifest.json only — no permissions granted yet)
a365 develop add-mcp-servers mcp_MailTools
a365 develop add-mcp-servers mcp_CalendarTools mcp_TeamsTools

# List currently configured servers
a365 develop list-configured

# Remove a server
a365 develop remove-mcp-servers mcp_MailTools

# Grant blueprint permissions (Global Administrator required)
# First-time: permissions are included in a365 setup all
# After blueprint exists:
a365 setup permissions mcp
```

#### `ToolingManifest.json` structure

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

#### Integrate tools into your agent (Node.js / TypeScript)

For the OpenClaw a365-plugin (Node.js + LangChain or Claude):

```typescript
// Claude integration (official package)
import { McpToolRegistrationService } from '@microsoft/agents-a365-tooling-extensions-claude';

// LangChain integration
import { McpToolRegistrationService } from '@microsoft/agents-a365-tooling-extensions-langchain';

const toolService = new McpToolRegistrationService();

// Register all MCP tools with your agent — handles both agentic and OBO auth
try {
  const agent = await toolService.addToolServersToAgent(
    agent,
    process.env.AGENTIC_USER_ID || '',  // agent user object ID
    authorization,                        // user authorization context
    turnContext,                          // current turn context from Agents SDK
    process.env.MCP_AUTH_TOKEN || '',     // optional OBO bearer token
  );
} catch (error) {
  console.error('Error adding MCP tool servers:', error);
}
```

The `addToolServersToAgent` method automatically:
- Loads all MCP servers from `ToolingManifest.json`
- Registers tools with the orchestrator
- Sets up authentication from manifest configuration
- Makes all tools immediately available for invocation

#### Local development with mock tooling server

```bash
# Start mock server (no auth required — good for early testing)
a365 develop start-mock-tooling-server

# Point your agent at the mock server
MCP_PLATFORM_ENDPOINT=http://localhost:5309
```

#### Use Work IQ MCP directly in Claude Code

Add to `.mcp.json` in your project directory:

```json
{
  "mcpServers": {
    "WorkIQ-MailServer": {
      "type": "http",
      "url": "https://agent365.svc.cloud.microsoft/agents/tenants/<tenantId>/servers/mcp_MailTools",
      "oauth": {
        "clientId": "<your-enterprise-app-client-id>",
        "callbackPort": 8080
      }
    }
  }
}
```

Then run `/mcp` in Claude Code and authenticate.

---

### Handle Messages

The agent receives messages through the **Activity Protocol** — the same HTTP-based protocol used by the Bot Framework. In the lab, `src/channel.ts` implements the full receive→process→reply loop and `src/monitor.ts` hosts the Express server.

#### Message routing in the lab

```
POST /api/messages
        ↓
src/monitor.ts  (CloudAdapter, AgentApplication)
        ↓
src/channel.ts  (A365Channel.receive)
        ├── extract metadata (user UPN, conversation ID)
        ├── store ConversationReference → conversation-store.ts
        ├── run with graph tool context (AsyncLocalStorage)
        └── route to OpenClaw agent runtime (LLM loop)
                ↓
        agent response → sendActivity(ctx, text)
```

#### Key implementation patterns

```typescript
// src/channel.ts — receive a message with full context isolation
runWithGraphToolContext({
  agentIdentity: process.env.AGENT_IDENTITY!,
  currentUserEmail: activity.from.aadObjectId,
  currentUserRole: getRole(activity.from.aadObjectId),
  sendActivity: ctx.sendActivity.bind(ctx),
}, async () => {
  // All graph-tools calls safely isolated per request
  await runtime.handleMessage(message, tools);
});
```

#### Identify the sender (all message types)

Every activity — conversation messages AND notification callbacks — includes a pre-populated `activity.from` object. No Graph API call needed:

```typescript
// Works in any handler: message, notification, invoke
const sender = context.activity.from;
console.log(`From: ${sender.name} (UPN: ${sender.id}, AAD OID: ${sender.aadObjectId})`);

// Use aadObjectId with Graph API to fetch full profile (job title, manager, dept)
// if your agent has User.Read.All permission
```

| `from` property | Value |
|---|---|
| `name` | Display name (user-controlled — sanitise before LLM injection) |
| `id` | Channel user ID / UPN |
| `aadObjectId` | Microsoft Entra Object ID |

#### Agent 365 SDK approach (official)

The official SDK adds typed routing via `AgentApplication` with per-activity-type handlers:

```typescript
import { AgentApplication } from '@microsoft/agents-hosting';

const app = new AgentApplication();

// Handle standard conversational messages
app.activity(ActivityTypes.Message, async (context, state) => {
  const userText = context.activity.text;
  await context.sendActivity(`You said: ${userText}`);
});

// Handle Teams-specific events
app.activity('invoke', async (context, state) => {
  // Adaptive Card Action.Submit callbacks land here
});
```

---

### Notify Agents

The Agent 365 SDK lets your agent **receive push notifications** from Microsoft 365 — not just respond to user messages. Your agent is notified when someone emails it, @mentions it in a Word comment, or when its identity lifecycle changes.

#### Supported notification types

| Notification type | Trigger | Sub-channel |
|------------------|---------|-------------|
| **Email** | Agent receives an email (addressed or @mentioned) | `email` |
| **Word** | Agent @mentioned in a Word document comment | `word` |
| **Excel** | Agent @mentioned in an Excel comment | `excel` |
| **PowerPoint** | Agent @mentioned in a PowerPoint comment | `powerpoint` |
| **Lifecycle: UserIdentityCreated** | Agent user identity created | N/A |
| **Lifecycle: WorkloadOnboardingUpdated** | Agent user workload onboarding status changed | N/A |
| **Lifecycle: UserDeleted** | Agent user identity deleted | N/A |

#### Notification payload reference

Each notification type carries structured data in `Activity.entities`. Key fields by type:

**Email notification** — `notification.emailNotification`

```json
{
  "type": "emailNotification",
  "id": "<email-id>",
  "conversationId": "<thread-id>",
  "htmlBody": "<body dir=\"ltr\"><div>Email body content here</div></body>"
}
```

The activity also carries `from.name` (sender display name), `from.id` (sender UPN), and `from.aadObjectId` (Entra Object ID) — pre-populated by the Agent 365 platform, no extra Graph calls needed.

**Document comment notification** — `notification.wpxCommentNotification` (Word / Excel / PowerPoint)

```json
{
  "type": "wpxcomment",
  "parentCommentId": "<parent-id>",
  "commentId": "<comment-id>",
  "documentId": "<doc-id>"
}
```

The `activity.attachments[0].contentUrl` contains the document URL; `activity.channelData.productContext` is `"Word"`, `"Excel"`, or `"PowerPoint"`.

**Lifecycle notification** — `notification.lifecycleEvent`

| `lifecycleEventType` | Meaning |
|---|---|
| `agenticUserIdentityCreated` | Agent user mailbox + presence provisioned |
| `agenticUserWorkloadOnboardingUpdated` | License workload (Teams, Mail, etc.) now ready |
| `agenticUserDeleted` | Agent user removed — clean up state |

> **Security note**: `Activity.From.Name` is user-controlled text. Always sanitise it (strip control characters, enforce max length) before injecting into LLM system prompts to prevent prompt injection.

#### Add notification handling (Node.js / TypeScript)

```typescript
import { AgentApplication, TurnContext, TurnState } from '@microsoft/agents-hosting';
import { ActivityTypes } from '@microsoft/agents-activity';
import {
  AgentNotificationActivity,
  NotificationType
} from '@microsoft/agents-a365-notifications';

const app = new AgentApplication<TurnState>();

// Handle all notification types
app.onAgentNotification(async (context: TurnContext, state: TurnState, notification: AgentNotificationActivity) => {
  switch (notification.notificationType) {
    case NotificationType.EmailNotification:
      const email = notification.emailNotification;
      console.log('Email received:', email?.id, 'from conversation:', email?.conversationId);
      await context.sendActivity('Got your email — I will follow up shortly.');
      break;

    case NotificationType.WpxComment:
      const comment = notification.wpxCommentNotification;
      console.log('Document comment received in:', comment?.documentUrl);
      await context.sendActivity('I see your comment — reviewing now.');
      break;

    case NotificationType.AgentLifecycleNotification:
      console.log('Lifecycle event:', notification.lifecycleEvent);
      // Initialize resources, clean up state, etc.
      break;
  }
});

// Specialized handler — email only (with auto-authentication)
app.onAgenticEmailNotification(
  async (context, state, notification) => {
    const email = notification.emailNotification;
    await context.sendActivity(`Received email: ${email?.subject}`);
  },
  32767,          // rank (lower = higher priority)
  ['agentic']     // autoSignInHandlers
);
```

#### Install notification packages

```bash
# Node.js / TypeScript
npm install @microsoft/agents-a365-notifications

# Python
pip install microsoft-agents-a365-notifications

# .NET
dotnet add package Microsoft.Agents.A365.Notifications
```

#### Identify the sender

Every notification activity includes `Activity.From` — pre-populated by the Agent 365 platform, no extra API calls needed:

```typescript
app.onAgentNotification(async (context, state, notification) => {
  const sender = context.activity.from;
  console.log(`Notification from: ${sender.name} (${sender.aadObjectId})`);
});
```

---

### Deploy Your Agent

Phase 2 already includes a full Azure VM deployment via `a365-plugin/infra/` (Bicep + cloud-init + Caddy). The Agent 365 CLI provides an alternative path to Azure App Service with deeper SDK integration.

#### Option A — VM deployment (this lab, ~$65/mo)

See [`setup/AZURE_VM_DEPLOY.md`](./setup/AZURE_VM_DEPLOY.md) for the full walkthrough.

```bash
# One-command deploy to Azure VM
./a365-plugin/infra/deploy.sh dev

# Tail cloud-init log until container is up
ssh azureuser@<fqdn> 'sudo tail -f /var/log/cloud-init-output.log'
```

#### Option B — Azure App Service via Agent 365 CLI

```bash
# 1. Build your project
npm run build

# 2. Deploy to Azure Web App (created by a365 setup all)
az webapp deploy \
  --name <your-web-app> \
  --resource-group <your-resource-group> \
  --src-path ./dist

# 3. Verify deployment
az webapp show --name <your-web-app> --resource-group <your-resource-group> --query state
# Expected: "Running"

# 4. Tail logs
az webapp log tail --name <your-web-app> --resource-group <your-resource-group>
```

#### Environment variable management for App Service

```bash
# List current app settings
az webapp config appsettings list \
  --name <your-web-app> --resource-group <your-resource-group>

# Set individual variables
az webapp config appsettings set \
  --name <your-web-app> --resource-group <your-resource-group> \
  --settings A365_APP_ID=<id> AGENT_IDENTITY=agent@yourtenant.onmicrosoft.com

# Use Key Vault references for secrets (recommended)
az webapp config appsettings set \
  --name <your-web-app> --resource-group <your-resource-group> \
  --settings A365_APP_PASSWORD="@Microsoft.KeyVault(SecretUri=https://...)"
```

#### Verify messaging endpoint responds

```bash
# Should return 401, not 404
curl https://<your-app>.azurewebsites.net/api/messages -X POST

# Or for VM deployment
curl https://<fqdn>/api/messages -X POST
```

#### Publish to Microsoft 365 admin center

Once deployed, make your agent discoverable by IT admins:

```bash
# Publish agent package to M365 admin center
a365 publish
```

This creates a `manifest.zip` and uploads it, making the agent visible in the Microsoft 365 admin center under **Agents and Tools**. Admins can then activate the blueprint, grant permissions, and create agent instances for their users.

#### Post-deployment checklist

- [ ] Container/Web App is running (`Running` state)
- [ ] `POST /api/messages` returns `401` (not `404`)
- [ ] Bot responds in Teams: `Hello`
- [ ] `get_calendar_events` returns real data
- [ ] `send_email` delivers a test email from `AGENT_IDENTITY`
- [ ] `NETWORK_MODE=restricted` still allows Teams + Graph API
- [ ] Azure AD audit logs show agent calls under `agent@yourtenant.onmicrosoft.com`
- [ ] Application Insights / Log Analytics shows agent traces

---

## Resuming Phase 2

When Phase 1 is verified and you're ready, ask:

> *"Resume Phase 2 build — start with tool registry."*

Work begins at Step 1: refactoring existing graph-tools to register through `src/tools/registry.ts`.
