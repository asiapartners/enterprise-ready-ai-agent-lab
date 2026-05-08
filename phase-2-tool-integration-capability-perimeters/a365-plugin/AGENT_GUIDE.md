# OpenClaw A365 Plugin — Developer Reference

This document describes the architecture, development workflow, and key implementation details for the openclaw-a365 plugin.

---

## Architecture Overview

```
Microsoft Teams / Outlook / Email
        ↓
A365 Service (Bot Framework, port 3978)
        ↓ HTTP POST /api/messages
src/monitor.ts (Express server, AgentApplication)
        ↓
src/channel.ts (OpenClaw channel plugin)
  ├── Extracts message metadata
  ├── Runs with Graph tool context (AsyncLocalStorage)
  └── Routes to OpenClaw agent runtime
        ↓
Agent Runtime (LLM loop via OpenClaw core)
  ├── src/graph-tools.ts (Calendar, Email, User operations)
  └── Response back through Bot Framework
```

---

## Key Source Files

| File | Purpose |
|------|---------|
| `index.ts` | Plugin entry point — registers with OpenClaw |
| `src/channel.ts` | A365 channel implementation — receives/sends messages |
| `src/monitor.ts` | Express server + AgentApplication setup, port 3978 |
| `src/graph-tools.ts` | Microsoft Graph API tools (calendar, email, user) |
| `src/token.ts` | Token acquisition: T1→T2→Agent FIC flow + caching |
| `src/types.ts` | TypeScript type definitions |
| `src/outbound.ts` | Proactive messaging — send without incoming context |
| `src/conversation-store.ts` | Persist conversation references to disk |
| `src/adapter-store.ts` | Store CloudAdapter and Blueprint Client ID |
| `src/runtime.ts` | Plugin runtime singleton |

---

## Development Commands

```bash
# Install dependencies
pnpm install

# Type check
pnpm typecheck

# Run tests
pnpm test

# Run with Docker Compose (recommended)
docker-compose up -d

# View logs
docker-compose logs -f

# Restart to pick up source changes
docker-compose restart

# Using OpenClaw CLI directly (if installed locally)
pnpm openclaw doctor --fix
pnpm openclaw gateway
```

---

## Authentication Flow (T1 → T2 → Agent Token)

The plugin uses Federated Identity Credentials (FIC) — a three-step token acquisition unique to Microsoft 365 Agents SDK:

```
1. T1 Token
   Client: blueprintClientAppId (Agentic App registration)
   Credential: blueprintClientSecret
   Scope: M365 Agents SDK scope
   → Returns: T1 access token

2. T2 Token
   Use T1 token to get an intermediate token
   → Returns: T2 access token

3. Agent FIC Token
   Client: Agent's own identity (AGENT_IDENTITY UPN)
   Credential: T2 token (used as assertion)
   Scope: Microsoft Graph (https://graph.microsoft.com/.default)
   → Returns: Agent's Graph API access token
```

Token caching: 5-minute buffer before expiry to reduce redundant fetches.

---

## AsyncLocalStorage Context

`graph-tools.ts` uses `AsyncLocalStorage` for thread-safe context isolation:

```typescript
// Wrap each request handler:
runWithGraphToolContext({
  agentIdentity: "agent@contoso.com",
  currentUserEmail: "user@contoso.com",
  currentUserRole: "Owner",
  sendActivity: ctx.sendActivity.bind(ctx),
}, () => {
  // Graph tools can safely call getGraphToolContext() here
});
```

This prevents cross-request data leakage in concurrent scenarios — each request has its own isolated context.

---

## Network Policy Enforcement

When `NETWORK_MODE=restricted` or `NETWORK_MODE=allowlist`, the startup script applies iptables rules:

```bash
# Always-allowed (essential Microsoft services):
# - login.microsoftonline.com (auth)
# - graph.microsoft.com (Graph API)
# - smba.trafficmanager.net (Teams)
# - *.botframework.com (Bot Framework)
# - Your configured LLM provider endpoints

# Everything else: BLOCKED (returns ICMP unreachable)
```

This means even LLM-generated bash commands can't reach unauthorized external services.
`--cap-add=NET_ADMIN` is required in Docker for iptables access.

---

## Conversation References

Proactive messaging (sending without an incoming request) requires stored conversation references:

```
~/.openclaw/a365-conversations.json
```

Structure:
```json
{
  "conversation-id": {
    "reference": { ... },  // SDK ConversationReference
    "updatedAt": "2025-01-15T10:30:00Z",
    "userAadId": "user-aad-object-id"
  }
}
```

References are saved automatically on every inbound message and used by `src/outbound.ts` for proactive sends.

---

## Running Tests

```bash
# All tests
pnpm test

# Specific test files
pnpm test src/graph-tools.test.ts
pnpm test src/token.test.ts
pnpm test src/channel.test.ts

# Watch mode
pnpm test:watch
```

---

## Configuration Files

The `config/` directory holds runtime configuration loaded at container startup:

| File | Purpose |
|------|---------|
| `config/capability-perimeter.yaml` | Network mode, tool RBAC, rate limits, approval clauses, redaction rules. Enforced by iptables (Phase 1) and `src/perimeter/enforcer.ts` (Phase 2). |
| `config/agent-personality.md` | Identity, tone, operating principles, role definitions (Owner / Requester), refusal patterns. Prepended to the LLM system prompt. |
| `config/openclaw.json` | OpenClaw gateway config with plugin install path and channel settings. Uses `${ENV_VAR}` substitution for credentials. |

To apply a config change: edit the file and run `docker compose restart`.

---

## Infrastructure

The `infra/` directory contains the production deployment toolkit for hosting on an Azure VM:

| File | Purpose |
|------|---------|
| `infra/main.bicep` | Azure Bicep template — provisions vNet, NSG, Public IP, Key Vault, VM with system-assigned Managed Identity. |
| `infra/deploy.sh` | One-command deploy script: creates resource group, runs Bicep, uploads secrets to Key Vault. Usage: `./infra/deploy.sh dev` |
| `infra/cloud-init.yaml` | VM user-data: installs Docker, Caddy, pulls secrets from Key Vault at boot, starts the container as a systemd service. |
| `infra/Caddyfile` | Caddy reverse-proxy config — terminates TLS with Let's Encrypt and forwards to port 3978. |

See [`setup/AZURE_VM_DEPLOY.md`](../setup/AZURE_VM_DEPLOY.md) for the full deployment walkthrough (~25 min, ~$65/mo).

---

## Known Issues / TODOs

- `src/token.ts`: In-memory token cache means redundant token fetches in multi-instance deployments. Consider Redis or Azure Cache for distributed setups.
- `src/monitor.ts`: Environment variables are mutated to pass credentials to SDK, which could cause issues with multiple plugin instances. Future: subprocess isolation or SDK improvement.
- `src/outbound.ts` + `PROACTIVE_MESSAGING.md`: Cron job proactive delivery may pass incorrect `to` values. Investigate OpenClaw core `sessions_spawn` integration.

---

## Related Documentation

- [setup/AZURE_ENTRA_SETUP.md](../setup/AZURE_ENTRA_SETUP.md) — Entra ID: Agentic User, App Registration, FIC, AA Instance ID
- [setup/AZURE_VM_DEPLOY.md](../setup/AZURE_VM_DEPLOY.md) — Azure VM deploy with Caddy, Key Vault, Managed Identity (~$65/mo)
- [setup/M365_AGENTS_SETUP.md](../setup/M365_AGENTS_SETUP.md) — M365 Agents portal setup and Teams channel
- [setup/AGENT_365_SDK_INTEGRATION.md](../setup/AGENT_365_SDK_INTEGRATION.md) — Wire the Agent 365 SDK into this plugin: packages, notification handlers, MCP tooling
- [setup/GRAPH_API_TOOLS.md](../setup/GRAPH_API_TOOLS.md) — All 8 Graph tools reference + example prompts
- [setup/NETWORK_POLICY.md](../setup/NETWORK_POLICY.md) — Capability perimeters via iptables
- [setup/APPROVAL_WORKFLOWS.md](../setup/APPROVAL_WORKFLOWS.md) — Human-in-the-loop safety boundaries
- [docs/PROACTIVE_MESSAGING.md](./docs/PROACTIVE_MESSAGING.md) — Proactive messaging architecture
- [Source repo](https://github.com/SidU/openclaw-a365) — Canonical source (check for updates)
