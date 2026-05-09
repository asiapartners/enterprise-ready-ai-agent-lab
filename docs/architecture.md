# Architecture — openclaw-agent365

## Component Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Microsoft Teams / M365 Copilot / Outlook                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTPS — Bot Framework Activity Protocol
                           │ (JWT-validated by CloudAdapter)
┌──────────────────────────▼──────────────────────────────────────┐
│  Azure Container Apps (CA)                                       │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  index.ts — Express server                                 │ │
│  │  POST /api/messages  GET /health                           │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │  CloudAdapter (@microsoft/agents-hosting)            │ │ │
│  │  │  Validates Bot Framework JWT; calls Agent handler    │ │ │
│  │  └────────────────────┬─────────────────────────────────┘ │ │
│  │                       │ TurnContext                        │ │
│  │  ┌────────────────────▼─────────────────────────────────┐ │ │
│  │  │  Agent365Handler (agent.ts)                          │ │ │
│  │  │  - Role detection (Owner vs Requester)               │ │ │
│  │  │  - DM policy enforcement (open|pairing|closed)       │ │ │
│  │  │  - Typing indicator + error handling                 │ │ │
│  │  └────────────────────┬─────────────────────────────────┘ │ │
│  │                       │ message + AgentContext             │ │
│  │  ┌────────────────────▼─────────────────────────────────┐ │ │
│  │  │  OpenClawRuntime (openclaw-connector.ts)             │ │ │
│  │  │  - Loads openclaw.plugin.json                        │ │ │
│  │  │  - Routes to OpenClaw LLM pipeline                   │ │ │
│  │  │  - Multi-model: primary + fallback chain             │ │ │
│  │  │  - Network policy (iptables, optional NET_ADMIN)     │ │ │
│  │  └────────────────────┬─────────────────────────────────┘ │ │
│  │                       │ Graph tool calls                   │ │
│  │  ┌────────────────────▼─────────────────────────────────┐ │ │
│  │  │  GraphTools (graph-tools.ts)                         │ │ │
│  │  │  T1 → T2 → Agent FIC token exchange                  │ │ │
│  │  │  Calendar | Mail | User operations                   │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │  OpenTelemetry → Application Insights                     │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  Secrets: Azure Key Vault references (never in env literals)     │
└───────────────────┬──────────────┬───────────────────────────────┘
                    │              │
        ┌───────────▼──┐    ┌──────▼──────────────┐
        │ Microsoft    │    │ LLM Provider         │
        │ Graph API    │    │ (Anthropic / OpenAI) │
        │ (agent UPN)  │    │                      │
        └──────────────┘    └─────────────────────┘
```

---

## Authentication Flow: T1 → T2 → Agent Token (FIC)

```
openclaw-connector.ts                 Entra ID
       │                                 │
       │── T1 Request ─────────────────▶ │
       │   client_credentials            │
       │   + fmi_path (AA_INSTANCE_ID)   │
       │◀─ T1 Token ──────────────────── │
       │                                 │
       │── T2 Request ─────────────────▶ │
       │   jwt-bearer assertion (T1)     │
       │◀─ T2 Token ──────────────────── │
       │                                 │
       │── Agent Token Request ────────▶ │
       │   user_fic grant                │
       │   for AGENT_IDENTITY UPN        │
       │◀─ Agent Token ────────────────  │
       │                                 │
       │── Graph API call ─────────────▶ Graph API
       │   Bearer: Agent Token           │
       │   (acts as AGENT_IDENTITY)      │
```

**Why this matters:** The agent operates with its own Entra ID identity (`AGENT_IDENTITY`), accessing only resources explicitly shared with it — not the user's full mailbox/calendar. All actions appear in audit logs as `AGENT_IDENTITY did X`, not `user did X via app`.

---

## Component Responsibilities

| Component | File | Responsibility |
|---|---|---|
| Entry point | `src/index.ts` | Express + adapter wiring, boot order, graceful shutdown |
| Activity handler | `src/agent.ts` | Message routing, role detection, DM policy, typing indicator |
| OpenClaw bridge | `src/openclaw-connector.ts` | LLM pipeline, plugin init, network policy (iptables) |
| Graph tools | `src/graph-tools.ts` | Calendar/mail/user ops via agent FIC token |
| Config | `src/config.ts` | Typed env var parsing with fail-fast validation |
| Telemetry | `src/telemetry.ts` | OTel SDK init, App Insights export |
| Plugin descriptor | `openclaw.plugin.json` | OpenClaw channel plugin registration |

---

## Network Policy (Container-level)

When `NETWORK_MODE=restricted` or `allowlist`, iptables rules are applied at startup:

- Essential domains always allowed: Entra ID, Graph API, Bot Framework, configured LLM provider
- `allowlist` mode adds custom domains from `NETWORK_ALLOWLIST`
- All other outbound traffic is dropped at the kernel level (catches LLM-generated code too)
- Requires container capability: `--cap-add=NET_ADMIN`

---

## Hands-On Lab Phases

### Phase 1 — Building Autonomous AI Assistants with OpenClaw

**Goal:** Understand OpenClaw as a plugin host and get the agent responding in Teams.

1. Clone repos and configure `.env` (see README Quick Start)
2. Run `docker-compose up` in devcontainer; verify `GET /health → 200`
3. Register a Bot Framework app in Azure and point it to `http://<ngrok>/api/messages`
4. Send a message in Teams; observe the stub response from `openclaw-connector.ts`
5. Replace the stub with a real OpenClaw runtime invocation (see TODO comment in `openclaw-connector.ts`)

**Acceptance criteria:** Agent responds to a Teams message with a non-stub reply.

---

### Phase 2 — Tool Integration & Capability Perimeters using Agent365 SDK and CLI

**Goal:** Wire Graph API tools and constrain agent capabilities with network policy.

1. Register the agentic identity (`AGENT_IDENTITY`) in Entra ID
2. Have the owner share their calendar with `AGENT_IDENTITY` in Outlook
3. Complete the T1→T2→Agent FIC token exchange in `graph-tools.ts` (see TODO)
4. Test `get_calendar_events` and `create_calendar_event` end-to-end
5. Set `NETWORK_MODE=restricted` and verify blocked requests via container logs
6. Add a custom domain to `NETWORK_ALLOWLIST` and verify it is accessible

**Acceptance criteria:** Agent can read/write the owner's calendar; all other outbound traffic is blocked in restricted mode.

---

### Phase 3 — Multi-Agent Orchestration & Governance

**Goal:** Deploy multiple specialised agent instances and govern them as a fleet.

1. Create a second agent identity (e.g., `research-agent@contoso.com`) with different permissions
2. Extend `openclaw.plugin.json` with an `orchestration` capability
3. Implement agent-to-agent handoff: when the primary agent needs research, it delegates to the research agent via Graph API or a shared queue
4. Add governance controls: per-agent rate limits, audit log sampling, alert rules in Application Insights
5. Deploy with separate Container App revisions per agent; use Traffic Manager for blue/green routing

**Acceptance criteria:** Two agents operate independently with distinct identities; handoff is visible in Application Insights traces; governance controls are enforced.

---

## Security Boundaries

| Boundary | Mechanism |
|---|---|
| Inbound message auth | Bot Framework JWT (CloudAdapter) |
| Secret access | Key Vault RBAC (Secrets User role) |
| Image pull | ACR + Managed Identity (AcrPull) |
| Agent graph access | FIC token scoped to shared resources only |
| Outbound network | iptables (NET_ADMIN, optional) |
| Role separation | `OWNER_AAD_ID` check in `agent.ts` |

---

## References

- [SidU/openclaw-a365](https://github.com/SidU/openclaw-a365) — Reference implementation
- [microsoft/Agent365-Samples](https://github.com/microsoft/Agent365-Samples) — Sample agents and E2E patterns
- [Microsoft Agent 365 Identity docs](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/identity)
- [OpenTelemetry Node.js SDK](https://opentelemetry.io/docs/languages/js/)
