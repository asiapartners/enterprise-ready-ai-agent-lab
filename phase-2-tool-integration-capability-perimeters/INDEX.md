# Phase 2 Index

Quick navigation for Phase 2: Tool Integration & Capability Perimeters.

---

## File Structure

```
phase-2-tool-integration-capability-perimeters/
├── README.md                    ← START HERE — 5-module learning guide
├── INDEX.md                     ← this file
├── TROUBLESHOOTING.md           ← common issues and fixes
│
├── setup/                       ← step-by-step configuration guides
│   ├── AZURE_ENTRA_SETUP.md     ← Module 2: create Entra ID credentials
│   ├── M365_AGENTS_SETUP.md     ← Module 3: register bot in Teams
│   ├── GRAPH_API_TOOLS.md       ← Module 4: all 8 Graph tools reference
│   ├── NETWORK_POLICY.md        ← Module 5: iptables network perimeters
│   └── APPROVAL_WORKFLOWS.md    ← Module 5: safety boundaries & HITL
│
└── a365-plugin/                 ← openclaw-a365 plugin source code
    ├── AGENT_GUIDE.md                ← developer reference
    ├── .env.example             ← environment variable template
    ├── docker-compose.yml       ← container orchestration
    ├── Dockerfile               ← container image definition
    ├── package.json             ← npm dependencies
    ├── index.ts                 ← plugin entry point
    │
    ├── docs/
    │   └── PROACTIVE_MESSAGING.md   ← proactive messaging architecture
    │
    └── src/
        ├── channel.ts           ← a365 channel plugin
        ├── channel.test.ts
        ├── monitor.ts           ← Express server + AgentApplication
        ├── graph-tools.ts       ← 8 Microsoft Graph API tools
        ├── graph-tools.test.ts
        ├── token.ts             ← T1→T2→Agent FIC token flow
        ├── token.test.ts
        ├── outbound.ts          ← proactive messaging
        ├── runtime.ts           ← plugin runtime singleton
        ├── conversation-store.ts ← JSON persistence for conversation refs
        ├── adapter-store.ts     ← CloudAdapter singleton
        └── types.ts             ← TypeScript type definitions
```

---

## "I Want To..."

| Goal | Where to go |
|------|-------------|
| Understand the architecture | [README.md — Modules](./README.md#modules) |
| Create Azure credentials | [setup/AZURE_ENTRA_SETUP.md](./setup/AZURE_ENTRA_SETUP.md) |
| Deploy the container | [README.md — Modules](./README.md#modules) |
| Connect to Microsoft Teams | [setup/M365_AGENTS_SETUP.md](./setup/M365_AGENTS_SETUP.md) |
| Understand calendar/email tools | [setup/GRAPH_API_TOOLS.md](./setup/GRAPH_API_TOOLS.md) |
| Enable network restrictions | [setup/NETWORK_POLICY.md](./setup/NETWORK_POLICY.md) |
| Set up access controls | [setup/APPROVAL_WORKFLOWS.md](./setup/APPROVAL_WORKFLOWS.md) |
| Set up proactive messaging | [a365-plugin/docs/PROACTIVE_MESSAGING.md](./a365-plugin/docs/PROACTIVE_MESSAGING.md) |
| Read the plugin developer docs | [a365-plugin/AGENT_GUIDE.md](./a365-plugin/AGENT_GUIDE.md) |
| Fix a deployment issue | [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) |
| Understand the token flow | [README.md — Modules](./README.md#modules) |

---

## Module-by-Module Path

```
Module 1: Architecture
  README.md → Modules table (row 1)

Module 2: Entra ID Setup
  README.md → Modules table (row 2)
  setup/AZURE_ENTRA_SETUP.md (full guide)

Module 3: Deploy
  README.md → Modules table (row 3)
  setup/M365_AGENTS_SETUP.md (Teams connection)
  setup/AZURE_VM_DEPLOY.md (cloud deployment)
  a365-plugin/.env.example (all variables)

Module 4: Graph Tools
  README.md → Modules table (row 4)
  setup/GRAPH_API_TOOLS.md (tool reference)
  a365-plugin/src/graph-tools.ts (source)

Module 5: Capability Perimeters
  README.md → Modules table (row 5)
  setup/NETWORK_POLICY.md (network policy)
  setup/APPROVAL_WORKFLOWS.md (safety boundaries)
  a365-plugin/scripts/entrypoint.sh (iptables rules)
```

---

## Phase Completion Checklist

Before moving to Phase 3, verify:

- [ ] Azure Entra app registration created with correct permissions
- [ ] Agent user account (`agent@yourdomain.com`) created with M365 license
- [ ] Calendar sharing configured between agent and owner
- [ ] `docker-compose up -d` runs without errors
- [ ] Bot responds in Teams: `Hello`
- [ ] `get_calendar_events` returns real calendar data
- [ ] `send_email` sends a test email successfully
- [ ] `NETWORK_MODE=restricted` still allows Teams messaging and Graph API
- [ ] `docker-compose exec openclaw-a365 iptables -L OUTPUT -n` shows rules
- [ ] Azure AD audit logs show agent's Graph API calls under `agent@yourdomain.com`

---

## Navigation

- ← [Phase 1](../phase-1-building-autonomous-ai-assistant/README.md)
- → [Phase 3](../phase-3-multi-agent-orchestration-governance/README.md)
- ↑ [Lab Root](../README.md)
