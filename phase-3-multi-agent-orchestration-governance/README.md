# Phase 3 — Multi-Agent Orchestration & Governance

> **Status**: 📐 Planned. Code generation deferred until Phase 2 is complete.
> **Estimated effort**: ~39 hours.
> **Prerequisites**: Phase 2 deployed; Jira tool + Microsoft MCP servers + approval pipeline working in Teams.

This phase turns the single agent into a **governed multi-agent system** registered fully in Microsoft Agent 365, with enterprise observability, compliance, and security controls.

## What you'll build

```
                 Teams (A365)
                      │
                      ▼
        ┌────────────────────────────┐
        │ Orchestrator Agent         │   FIC identity: orch-agent@…
        │  - planner (LLM-driven)    │   Role: routing only, no domain tools
        │  - delegation policy       │
        │  - human-handoff           │
        └────┬───────────┬───────────┘
             │           │
             │ A2A (signed JWT, FIC, OTel traceparent propagated)
             ▼           ▼           ▼
      ┌──────────┐ ┌──────────┐ ┌────────────────┐
      │ Calendar │ │ Jira     │ │ Research       │
      │ Agent    │ │ Agent    │ │ Agent          │
      │ (P1 tools│ │ (P2 jira │ │ (MS Learn MCP +│
      │  reused) │ │  reused) │ │  http-fetch)   │
      └────┬─────┘ └────┬─────┘ └────────┬───────┘
           │            │                │
           └────────────┼────────────────┘
                        ▼
        Shared: Dataverse memory + Work IQ MCP,
        Audit log, Purview emitter, OTel → App Insights
```

## Confirmed scope

| Pillar | Decisions |
|---|---|
| **Multi-agent topology** | 1 orchestrator + 3 specialist agents (Calendar, Jira, Research). Each has its own Agentic User UPN, app registration, FIC, AA Instance ID. |
| **A2A protocol** | Synchronous JSON over HTTPS (`POST /a2a/invoke`). JWT-signed with caller's FIC token. W3C `traceparent` header. Async (Service Bus) deferred to Phase 3.5. |
| **Shared memory** | **Dataverse** (included in M365 tenant) for long-term memory, audit, and business state. **Work IQ MCP** (preview) as the contextual intelligence layer. No extra Azure service needed. Cosmos DB documented as the production graduation path for high-throughput / vector-search scenarios. |
| **Hosting** | Same Azure VM as Phase 1, multi-service `docker compose`. Caddy reverse-proxies by path: `/orchestrator/...`, `/calendar/a2a/invoke`, etc. ACA migration documented in `ARCHITECTURE.md` as graduation path. |
| **Observability** | OpenTelemetry SDK in every agent; exporter → Application Insights (one workspace, separate `cloud-role` per agent). 3 Azure Monitor workbooks: agent overview, approvals/denials, compliance. |
| **Compliance** | Microsoft Purview audit (every tool call attributed to agent UPN), Purview Information Protection DLP, sensitivity labels in tool manifests. |
| **Security** | Customer-managed keys (CMK) on Key Vault/Storage, Private Endpoints (`network.bicep`), Conditional Access policies per agent identity, Defender for Cloud Apps integration, supply-chain signing (cosign). Dataverse inherits M365 security model (no CMK provisioning needed for memory layer). |
| **Microsoft Agent 365 integration** | Each agent published to **Agent 365 Catalog** via Graph API (`catalog/publish.sh`); Agent 365 Admin Center governance; per-agent CA policies. |

## Repo additions in Phase 3

```
agents/
├── orchestrator/                # planner, delegation, handoff
├── specialist-calendar/         # thin wrapper around P1 graph-tools
├── specialist-jira/             # thin wrapper around P2 jira-tool
└── specialist-research/         # MS Learn MCP + http-fetch

shared/                          # promoted from Phase 1+2 src/
├── a2a/                         # server, client, contract, JWT auth
├── memory/                      # Dataverse-backed conversation store
│   ├── dataverse-client.ts      #   OData Web API wrapper (DynamicsWebApi)
│   ├── conversation-store.ts    #   turn-per-row in msdyn_aicopilotmessage
│   └── work-iq-client.ts        #   Work IQ MCP client for context hints
├── otel/                        # OpenTelemetry init + correlation
├── governance/                  # audit-log, purview-emitter, dlp
└── perimeter/                   # policy, enforcer (per-agent overlays)

catalog/                         # Microsoft Agent 365 catalog manifests
├── orchestrator.agent.json
├── specialist-*.agent.json
└── publish.sh

compliance/                      # Purview, DLP, sensitivity labels, retention
observability/                   # workbooks (KQL), alerts
infra/
├── network.bicep                # vNet, NSGs, Private Endpoints
├── identity.bicep               # per-agent MIs + Conditional Access
├── purview.bicep
└── cmk.bicep                    # customer-managed keys on KV/Storage
                                 # (Dataverse uses M365 managed keys by default)
```

## Memory tier design (Dataverse + Work IQ)

Phase 3 uses two complementary layers instead of a standalone Cosmos DB:

### Layer 1 — Dataverse (operational memory)

| What it stores | How |
|---|---|
| Conversation turns between orchestrator ↔ specialist agents | One row per turn in `msdyn_aicopilotmessage` (or a custom table) |
| Session correlation IDs (cross-agent `sessionId`) | Custom Dataverse table: `openclaw_agentsession` |
| Long-term user preferences & patterns | Custom table: `openclaw_usermemory` |
| Audit log (every tool call, tool result, approval decision) | Dataverse activity log + Purview emitter |

**Access from Node.js**: [`DynamicsWebApi`](https://github.com/AleksandrRogov/DynamicsWebApi) npm package — a TypeScript-native OData Web API client. Auth reuses the agent's app registration (add `Dynamics CRM → user_impersonation` API permission).

**Connection string in `.env`**:
```
DATAVERSE_URL=https://yourtenant.crm.dynamics.com
```

**Why not Cosmos DB?** Dataverse is already provisioned in your M365 tenant — no extra Azure service, no serverless cold-start, no CMK provisioning, and it integrates natively with Agent 365, Purview, and DLP. Trade-offs: no built-in TTL, no vector/DiskANN search. See the "Graduation path" note at the end of this section.

### Layer 2 — Work IQ MCP (contextual intelligence)

Work IQ is Microsoft's intelligence layer for Agent 365, built on three pillars:

| Pillar | Content |
|---|---|
| **Data** | Structured business data from Dataverse, SharePoint, Teams |
| **Memory** | Communication style, recurring tasks, frequent collaborators ("work chart") |
| **Inference** | Patterns learned from M365 signals (email, calendar, Teams activity) |

Agents access Work IQ via its **MCP server** (preview, GA Summer 2026). The Orchestrator calls `work_iq.get_context(userUpn)` before planning to seed the LLM with the user's current priorities and collaboration patterns — without storing that data themselves.

```
Orchestrator planning step:
  1. Call Work IQ MCP → get user context (priorities, collaborators, pending tasks)
  2. Inject context into LLM system prompt
  3. LLM plans delegation across Calendar / Jira / Research specialists
```

> **Work IQ vs. Cosmos DB**: they are not the same layer. Work IQ provides *who the user is and how they work*. Dataverse provides *what happened in this session*. Cosmos DB (if needed) would provide *high-throughput ephemeral turn storage with vector search*. For lab throughput, Dataverse covers both operational needs.

### Graduation path → Cosmos DB

When you need:
- Sub-10ms turn writes at high concurrency (production-scale)
- Vector similarity search over conversation history (semantic retrieval)
- Per-turn TTL to auto-expire short-term memory

…migrate `shared/memory/conversation-store.ts` to Cosmos DB for NoSQL (serverless, ~$0–10/mo). The `sessionId` partition key design is identical; only the client changes from OData to `@azure/cosmos`. See [Azure Cosmos DB Agent Memory patterns](https://learn.microsoft.com/en-us/azure/cosmos-db/gen-ai/agentic-memories) for the recommended turn-per-item data model.

## A2A protocol contract

```typescript
// shared/a2a/contract.ts
export const A2ARequest = z.object({
  task: z.string(),
  args: z.record(z.unknown()),
  sessionId: z.string().uuid(),
  requesterUpn: z.string().email(),
  sensitivityLabel: z.enum(['Public', 'Internal', 'Confidential', 'Highly Confidential']).optional(),
  deadline: z.string().datetime().optional(),
});

export const A2AResponse = z.object({
  result: z.unknown(),
  citations: z.array(z.string()).optional(),
  sensitivityLabel: z.string().optional(),
  auditId: z.string().uuid(),
});
```

**Authentication**: caller mints an FIC token for the callee's app audience and includes it as `Authorization: Bearer <jwt>`. Callee verifies signature against tenant's discovery doc, then maps the `oid` claim to the calling agent's allowed task list.

## Cost summary (Phase 3 add-on, on top of Phases 1+2)

| Resource | Estimate | Notes |
|---|---|---|
| Dataverse (memory layer) | **$0/mo** | Included in M365 dev tenant; 2 GB default capacity |
| Work IQ MCP | **$0/mo** | Included in M365 Copilot license |
| Application Insights | $0–5/mo | First 5 GB/mo free |
| Microsoft Purview | ~$30–50/mo | Pause when idle; skip if dev tenant lacks license |
| Private Endpoints (4) | ~$30/mo | Optional; skip for dev lab |
| Key Vault Premium (CMK) | ~$3/mo | For KV + Storage CMK only |
| **Total Phase 3 add-on** | **~$35–88/mo** | vs. ~$70–110/mo with Cosmos DB |

> **Saving ~$10–22/mo** by using Dataverse instead of Cosmos DB serverless. For production/high-throughput migration, add back Cosmos DB serverless (~$0–10/mo) and update `shared/memory/` to use `@azure/cosmos`.

## Risks tracked from planning

1. **Agent 365 Catalog API maturity**: `agentApplications` Graph endpoint is evolving. `catalog/publish.sh` will be version-checked at build time.
2. **Purview tenant licensing**: if dev tenant lacks Purview, those sections degrade to stubs and document the upgrade path.
3. **4 Agentic User licenses required** in dev tenant.
4. **A2A trust model**: agents authenticate to each other via FIC; same trust boundary as user-facing agent. Documented in `SECURITY.md`.
5. **Async A2A** intentionally deferred to keep scope finite.
6. **Work IQ MCP preview**: broad GA targeted Summer 2026. If unavailable in your tenant, the Orchestrator planning step skips the Work IQ context injection and falls back to a static system prompt. No code change required — just set `WORK_IQ_ENABLED=false`.
7. **Dataverse capacity**: M365 dev tenant default is 2 GB. At ~2 KB/turn, that's ~1M turns — more than enough for Phase 3. If you exceed it, add Dataverse capacity add-on or migrate conversation turns to Cosmos DB.

## Planned files

| File | Purpose |
|---|---|
| `PHASE_3_GUIDE.md` | Detailed step-by-step build guide (to be authored at build time) |
| `ARCHITECTURE.md` | Multi-agent system design, ACA graduation path |
| `A2A_PROTOCOL.md` | A2A contract, JWT auth, traceparent propagation |
| `COMPLIANCE.md` | Purview setup, DLP policies, sensitivity labels |
| `SECURITY.md` | CMK, Private Endpoints, Conditional Access, supply-chain signing |
| `OBSERVABILITY.md` | OpenTelemetry init, App Insights workbooks, KQL alert rules |

## Resuming Phase 3

When Phase 2 is verified and you're ready, ask:

> *"Resume Phase 3 build — start with shared/a2a."*

Work begins at the 14-step Phase 3 breakdown.
