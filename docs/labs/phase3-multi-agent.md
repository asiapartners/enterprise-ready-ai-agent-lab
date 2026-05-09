# Phase 3 Lab — Multi-Agent Orchestration & Governance

**Duration:** ~4 hours  
**Goal:** Deploy multiple specialised agent instances and govern them as a fleet  
**Prerequisites:** Phases 1 and 2 complete; production-like staging environment

---

## Objectives

By the end of this lab you will:
- Have two agents with distinct Entra ID identities and different permissions
- Implemented agent-to-agent handoff via the `orchestration` capability
- Applied per-agent rate limits and audit log sampling
- Deployed separate Container App revisions per agent
- Used Traffic Manager / traffic splitting for blue/green routing

---

## Architecture: Multi-Agent Fleet

```
Teams
  │
  ▼
primary-agent (production-agent@contoso.com)
  │  role: intake, scheduling, delegation
  │
  ├─── needs research? ──► research-agent@contoso.com
  │                         role: web research, synthesis
  │
  └─── needs data? ─────► data-agent@contoso.com (optional)
                            role: internal data queries
```

Each agent:
- Has its own Entra ID user identity
- Has only the permissions it needs (least privilege per agent)
- Runs in its own Container App revision
- Has distinct audit trail entries
- Appears separately in Application Insights

---

## Step 1 — Create a second agent identity

```bash
# Create the research agent identity
az ad user create \
  --display-name "Research Agent" \
  --user-principal-name "research-agent@<your-domain>" \
  --password "<temp-password>" \
  --force-change-password-next-sign-in false

# License with M365 Business (required for mailbox/calendar)
# Assign via Azure Portal → Users → Licenses
```

Create a second App Registration for the research agent, OR extend the existing one with:
- A second FIC credential for `research-agent`
- Scoped permissions: `Mail.Send` only (no calendar write)

---

## Step 2 — Extend openclaw.plugin.json with orchestration capability

```json
{
  "capabilities": [
    "messaging",
    "graph-api",
    "agentic-identity",
    "network-policy",
    "orchestration"
  ],
  "orchestration": {
    "agents": [
      {
        "id": "production-agent",
        "identity": "production-agent@<your-domain>",
        "capabilities": ["calendar", "mail", "scheduling"]
      },
      {
        "id": "research-agent",
        "identity": "research-agent@<your-domain>",
        "capabilities": ["research", "synthesis"],
        "endpoint": "https://<research-agent-app>.azurecontainerapps.io/api/messages"
      }
    ],
    "handoffStrategy": "explicit",
    "maxHandoffDepth": 3
  }
}
```

---

## Step 3 — Implement agent-to-agent handoff

In `src/agent.ts`, add handoff logic:

```typescript
// When primary agent needs research:
private async delegateToResearchAgent(query: string, context: AgentContext): Promise<string> {
  const researchEndpoint = process.env.RESEARCH_AGENT_ENDPOINT;
  if (!researchEndpoint) throw new Error('RESEARCH_AGENT_ENDPOINT not configured');

  // Acquire a token for the research agent endpoint
  const token = await this.getAgentToken(process.env.RESEARCH_AGENT_APP_ID!);

  const response = await fetch(`${researchEndpoint}/api/delegate`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      'X-Correlation-ID': context.correlationId,  // propagate trace context
    },
    body: JSON.stringify({
      query,
      requesterId: context.userId,
      parentTraceId: context.traceId,
    }),
  });

  if (!response.ok) throw new Error(`Research agent returned ${response.status}`);
  const result = await response.json();
  return result.answer;
}
```

---

## Step 4 — Add governance controls

### Rate limiting (per-agent)

Add to `src/config.ts`:
```typescript
rateLimits: {
  messagesPerMinutePerUser: z.number().default(10),
  toolCallsPerRequest: z.number().default(5),
  maxDelegationDepth: z.number().default(3),
}
```

Implement in `src/agent.ts`:
```typescript
private readonly rateLimiter = new Map<string, { count: number; resetAt: number }>();

private isRateLimited(userId: string): boolean {
  const now = Date.now();
  const state = this.rateLimiter.get(userId) ?? { count: 0, resetAt: now + 60_000 };

  if (now > state.resetAt) {
    state.count = 0;
    state.resetAt = now + 60_000;
  }

  state.count++;
  this.rateLimiter.set(userId, state);
  return state.count > config.rateLimits.messagesPerMinutePerUser;
}
```

### Audit log sampling

Add Application Insights custom events for governance:
```typescript
// In src/telemetry.ts
export function recordAgentAction(action: {
  agentId: string;
  userId: string;
  tool: string;
  success: boolean;
  durationMs: number;
}) {
  tracer.startActiveSpan('agent.action', (span) => {
    span.setAttributes({
      'agent.id':      action.agentId,
      'user.id':       action.userId,
      'tool.name':     action.tool,
      'tool.success':  action.success,
      'tool.duration': action.durationMs,
    });
    span.end();
  });
}
```

---

## Step 5 — Deploy with separate Container App revisions

```bash
RG=<resource-group>
APP=ca-oca365-production

# Deploy research-agent as a separate revision
az containerapp update \
  --name "$APP" \
  --resource-group "$RG" \
  --image "<acr>/openclaw-agent365:research-agent-v1.0.0" \
  --revision-suffix "research-agent" \
  --set-env-vars "AGENT_IDENTITY=research-agent@<your-domain>"

# Label the revisions
az containerapp revision label add \
  --name "$APP" \
  --resource-group "$RG" \
  --revision "${APP}--research-agent" \
  --label "research"

# Traffic split: 90% primary, 10% research (for gradual rollout)
az containerapp ingress traffic set \
  --name "$APP" \
  --resource-group "$RG" \
  --revision-weight "latest=90" "research=10"
```

---

## Step 6 — Configure alert rules for fleet governance

```bash
# Alert: any agent's error rate > 5% over 5 min
az monitor metrics alert create \
  --name "agent-error-rate-alert" \
  --resource-group "$RG" \
  --scopes /subscriptions/<sub>/resourceGroups/$RG/providers/Microsoft.App/containerApps/ca-oca365-production \
  --condition "avg requests/failed > 5" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action <action-group-id>
```

In Application Insights, create a workbook with:
- Per-agent message volume
- Per-agent tool call breakdown
- Handoff frequency (primary → research)
- Rate limit hit counts
- p95 latency per agent

---

## Acceptance Criteria

- [ ] Two agents running with distinct Entra ID identities
- [ ] `production-agent` can delegate to `research-agent` and return composed answer
- [ ] Handoff visible in Application Insights distributed traces (X-Correlation-ID propagated)
- [ ] Rate limiting enforced: >10 messages/min/user receives a graceful 429 response
- [ ] Audit logs show distinct identity entries per agent
- [ ] Traffic split: `az containerapp ingress traffic show` shows two revisions with weights
- [ ] Alert fires correctly when test request spike exceeds 5% error rate
- [ ] `pnpm test` still passes after orchestration code additions

---

## Governance Checklist

Before fleet goes to production:
- [ ] Each agent has documented permission scope (RBAC minimums)
- [ ] Max delegation depth enforced (no infinite loops)
- [ ] Circuit breaker in place for downstream agent failures
- [ ] Each agent identity enrolled in Entra ID Conditional Access
- [ ] Agent identities excluded from self-service password reset (SSPR)
- [ ] Audit log retention ≥ 90 days for compliance

---

## Troubleshooting

| Issue | Check |
|---|---|
| Handoff returns 401 | Research agent endpoint token not scoped correctly |
| Circular delegation | Check `maxHandoffDepth` enforcement in agent.ts |
| Traces not correlating | Verify X-Correlation-ID header propagation |
| Traffic split not working | Revision mode must be `Multiple`: `az containerapp revision set-mode --mode Multiple` |
| Rate limiter not resetting | In-memory; restarts reset state — use Redis for persistent rate limiting |

---

## Congratulations

You've completed all three lab phases:
1. ✅ Autonomous AI Assistant running in Teams
2. ✅ Tool integration with Graph API and network policy
3. ✅ Multi-agent fleet with governance and observability

→ For production deployment: follow `docs/release-checklist.md`  
→ For rollback procedures: `docs/rollback.md`
