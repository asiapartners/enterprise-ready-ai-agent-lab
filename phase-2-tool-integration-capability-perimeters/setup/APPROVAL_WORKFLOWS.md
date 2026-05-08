# Approval Workflows & Safety Boundaries

This guide covers the human-in-the-loop patterns, access control tiers, and safety guardrails available in `openclaw-a365`. These controls let you deploy AI agents with confidence in enterprise environments.

---

## The Core Safety Model

`openclaw-a365` implements safety at three layers:

```
Layer 1: Identity & Authentication
  → Agent has its OWN Entra ID identity (not impersonating users)
  → Only accesses explicitly shared resources

Layer 2: Tool Access Control
  → Role-based tool permissions (Owner vs User vs Restricted)
  → DM policy controls who can interact with the agent

Layer 3: Capability Perimeters
  → Network policy constrains which external services are reachable
  → See NETWORK_POLICY.md for details
```

---

## Layer 1: Agentic Identity Model

The core safety property: **the agent acts as itself, not as you.**

```
Traditional OAuth delegation:
  Human logs in → grants consent → agent uses human's token → acts AS the human

Agentic Identity Model:
  Agent has its OWN Entra user → uses its OWN token → acts AS the agent
```

**Why this matters:**
- You can audit exactly what the agent did: all Graph API calls are logged under `agent@contoso.com`
- You can revoke the agent's access without affecting any human user
- You can scope permissions precisely: the agent only has access to what you explicitly share
- There's no "token theft" risk from session hijacking of a human user

**Configuration:**
```env
AGENT_IDENTITY=agent@yourdomain.com  # The agent's own Entra ID UPN
OWNER=owner@yourdomain.com           # The "principal" this agent serves
OWNER_AAD_ID=<aad-object-id>         # Used for role detection
```

---

## Layer 2: Role-Based Tool Access

When a user messages the agent, the agent determines their role:

| Role | When assigned | Tool access |
|------|---------------|-------------|
| **Owner** | Sender's AAD Object ID matches `OWNER_AAD_ID` | Full tool set |
| **User** | Any other authenticated Teams user | Read-only tools |
| **Anonymous** | User not in allowlist (with allowlist policy) | No access |

### Owner-only operations

The Owner (the person this agent primarily serves) gets elevated access:
- Create, update, delete calendar events
- Send email
- All read operations

### User-level operations (non-owners)

Users who message the bot in group channels or DMs get:
- Read calendar events (if explicitly allowed)
- Get user info
- find_meeting_times for scheduling coordination

### Customizing role access

Edit `src/channel.ts` to adjust role mappings. For more complex RBAC:

```typescript
// In channel.ts, the role is resolved in monitor.ts:
const role = cfg.ownerAadId && meta.userAadId === cfg.ownerAadId ? "Owner" : "User";

// Extend for additional roles:
function resolveRole(meta: A365MessageMetadata, cfg: A365Config): string {
  if (meta.userAadId === cfg.ownerAadId) return "Owner";
  if (cfg.adminAadIds?.includes(meta.userAadId ?? "")) return "Admin";
  return "User";
}
```

---

## DM Policy: Who Can Message the Bot

Control who can initiate direct message conversations with the agent.

### `open` (default)
Anyone in the tenant can DM the bot.

```env
DM_POLICY=open
```

**Use when**: You want broad access, the bot is a general assistant.

### `allowlist`
Only specific users can DM the bot. Others receive no response (or a "not authorized" message).

```env
DM_POLICY=allowlist
ALLOW_FROM=owner@contoso.com,manager@contoso.com,assistant@contoso.com
```

**Use when**: The agent is a personal assistant for a specific executive or team.

### `pairing`
New users must be approved before the agent responds. Useful for a gradual rollout.

```env
DM_POLICY=pairing
```

With pairing mode:
1. New user messages the bot
2. Bot holds the message
3. Owner receives a notification: "User [name] wants to chat. Approve? (yes/no)"
4. Owner replies "yes" → user is added to the pairing list and the message is processed
5. Owner replies "no" → user is rejected and gets a "not authorized" message

---

## Group Channel Policy

Separate from DM policy, you can control which Teams channels/groups the bot responds in.

```env
GROUP_POLICY=allowlist
GROUP_ALLOW_FROM=channel-id-1,channel-id-2
```

Or allow all groups:
```env
GROUP_POLICY=open
```

---

## Business Hours Enforcement

The agent can automatically restrict availability to business hours:

```env
BUSINESS_HOURS_START=08:00
BUSINESS_HOURS_END=18:00
TIMEZONE=America/Los_Angeles
```

Outside business hours:
- Incoming messages are queued (if OpenClaw session persistence is enabled)
- Or the agent responds: "I'm outside business hours. I'll get back to you tomorrow at 8:00 AM."

This is useful for preventing the agent from autonomously taking actions (sending emails, creating meetings) at unexpected hours.

---

## Human-in-the-Loop Patterns

For sensitive operations, you can require explicit confirmation before the agent executes.

### Pattern 1: Confirmation prompt (built-in)

The agent naturally asks for confirmation on destructive operations. Reinforce this in your `SOUL.md`:

```markdown
## Safety Behaviors
- Always confirm before deleting calendar events
- Always confirm before sending emails to external recipients
- Always show the draft before sending
- Ask "Shall I proceed?" for any action that can't be undone
```

### Pattern 2: Two-step workflow

For high-stakes operations, implement a two-step flow:

1. Agent drafts the action and sends it to the user as a preview
2. User explicitly says "confirm" or "send it"
3. Agent executes

Example conversation:
```
User: Send meeting notes to the entire team.
Agent: Here's the draft email:
       To: team@contoso.com
       Subject: Meeting Notes - Q2 Planning
       [email body preview]
       
       Ready to send? Say "send" to confirm.

User: send
Agent: Email sent to 12 recipients ✓
```

### Pattern 3: Approval escalation

For operations exceeding a threshold, escalate to a designated approver:

```
User: Cancel all my meetings next week.
Agent: This will cancel 8 meetings. This action requires approval from your manager.
       Sending approval request to manager@contoso.com...
       
[Manager receives notification]
Manager: approved
Agent: Cancellation confirmed. Removing 8 events from your calendar...
```

### Pattern 4: Audit trail

All agent actions are traceable through:
- **Graph API audit logs** in Azure AD — all calls are under `AGENT_IDENTITY`
- **OpenClaw session logs** — full conversation + tool call history
- **Container logs** — `docker-compose logs -f openclaw-a365`

---

## Prompt Injection Defense

Agents reading external content (emails, calendar descriptions) are vulnerable to prompt injection — malicious instructions embedded in data.

**Recommended defenses:**

1. **Scope the agent's purpose in SOUL.md** — a focused agent is harder to redirect
2. **Limit read access** — agent only reads explicitly shared calendars, not "all calendars in the org"
3. **Output review** — for any agent that sends emails or creates meetings, have it show drafts before sending
4. **Network policy** — even if the agent is "tricked" into exfiltrating data, the network policy blocks unauthorized outbound connections

---

## Configuring Sensitive Tool Guards

In `src/graph-tools.ts`, you can add validation guards on any tool. Example: require confirmation before delete:

```typescript
// In createGraphTools(), the delete_calendar_event tool:
{
  name: "delete_calendar_event",
  description: "Delete a calendar event. Always confirm with the user before calling this.",
  // The description IS the guard — it tells the LLM to ask first
}
```

For programmatic enforcement, add a `requiresConfirmation` flag to your tool schema and check it in the agent runtime.

---

## Monitoring and Alerting

Set up monitoring for anomalous agent behavior:

**What to watch:**
- Unusual volume of email sends (> N per hour)
- Calendar deletions outside business hours
- `get_user_info` calls for large numbers of users (potential enumeration)
- Any Graph API errors with 403 (permission escalation attempts)

**Where to look:**
- Azure AD Sign-in logs: filter by `agent@contoso.com`
- Graph API audit logs: Microsoft Purview Compliance Portal
- Container logs: `docker-compose logs -f`

---

## Next Steps

You've completed the Phase 2 setup guides. Return to:

→ [Phase 2 README](../README.md) — continue with the remaining modules
→ [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) — if you hit issues
