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
| [`setup/GRAPH_API_TOOLS.md`](./setup/GRAPH_API_TOOLS.md) | All 8 Graph tools reference + example prompts |
| [`setup/NETWORK_POLICY.md`](./setup/NETWORK_POLICY.md) | Capability perimeters via iptables |
| [`setup/APPROVAL_WORKFLOWS.md`](./setup/APPROVAL_WORKFLOWS.md) | Adaptive Card approval gates + human-in-the-loop |

## Resuming Phase 2

When Phase 1 is verified and you're ready, ask:

> *"Resume Phase 2 build — start with tool registry."*

Work begins at Step 1: refactoring existing graph-tools to register through `src/tools/registry.ts`.
