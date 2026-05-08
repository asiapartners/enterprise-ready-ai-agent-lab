# Enterprise AI Agent Lab

A hands-on lab for building production-ready autonomous AI agents — from your first self-hosted assistant to multi-agent orchestration with enterprise governance.

---

## Three Phases

| Phase | Title | Duration | Status |
|-------|-------|----------|--------|
| **Phase 1** | [Building Autonomous AI Assistants](./phase-1-building-autonomous-ai-assistant/README.md) | 10–17 hours | ✅ Active |
| **Phase 2** | [Tool Integration & Capability Perimeters](./phase-2-tool-integration-capability-perimeters/README.md) | ~23 hours | ✅ Active |
| **Phase 3** | [Multi-Agent Orchestration & Governance](./phase-3-multi-agent-orchestration-governance/README.md) | Coming soon | 🔜 Planned |

---

## What You'll Build

**Phase 1** — A self-hosted AI assistant connected to Discord and/or Microsoft Teams, with a custom personality, persistent memory, and tool access. Deployed on your own infrastructure using [OpenClaw](https://github.com/openclaw/openclaw).

**Phase 2** — The same agent, extended with Microsoft 365 integration: the agent gets its own Entra ID identity (`agent@yourdomain.com`), reads and creates calendar events, sends emails, and operates within enterprise network controls enforced at the infrastructure level with iptables.

**Phase 3** *(coming)* — Multiple specialized agents coordinating on complex tasks, with monitoring, observability, compliance logging, and zero-trust governance.

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Agent Framework | [OpenClaw](https://github.com/openclaw/openclaw) (self-hosted, Node.js) |
| Teams Integration | [openclaw-a365](https://github.com/SidU/openclaw-a365) (Phase 2) |
| LLM Provider | Azure OpenAI (recommended), Anthropic Claude, OpenAI, Ollama |
| M365 Integration | Microsoft Graph API via Federated Identity Credentials |
| Container Runtime | Docker / Docker Compose |
| Auth & Identity | Azure Active Directory (Entra ID) |
| Network Governance | iptables capability perimeters |

---

## Prerequisites

Before starting, ensure you have:

- **Node.js v22+** — `node --version`
- **Docker + Docker Compose** — `docker --version`
- **An LLM API key** — Azure OpenAI, Anthropic, or OpenAI
- **Phase 1 only**: A Discord account, or Microsoft 365 tenant for Teams
- **Phase 2 only**: Azure subscription with App Administrator or Global Admin role

---

## Quick Start

### Start with Phase 1 (recommended)

```bash
# Open the Phase 1 guide
open phase-1-building-autonomous-ai-assistant/README.md
```

Phase 1 Module 1 starts with architecture — no prerequisites beyond Node.js.

### Jump to Phase 2 (if you have M365 infrastructure)

```bash
# Open the Phase 2 guide
open phase-2-tool-integration-capability-perimeters/README.md

# Copy and configure the environment
cd phase-2-tool-integration-capability-perimeters/a365-plugin
cp .env.example .env
```

---

## Repository Structure

```
enterprise-ai-agent-lab/
│
├── README.md                              ← this file
├── OPENCLAW_ARCHITECTURE.md               ← platform architecture reference
├── OPENCLAW_SETUP_GUIDE.md                ← installation & configuration reference
├── OPENCLAW_IMPLEMENTATION_GUIDE.md       ← patterns & best practices
│
├── phase-1-building-autonomous-ai-assistant/
│   ├── README.md                          ← 7-module Phase 1 guide ← START HERE
│   ├── INDEX.md                           ← file navigation
│   ├── TROUBLESHOOTING.md
│   ├── setup/                             ← LLM config, Teams, Discord setup
│   ├── starter-configs/                   ← ready-to-use config examples
│   └── workspace/                         ← AGENTS.md, SOUL.md, MEMORY.md templates
│
├── phase-2-tool-integration-capability-perimeters/
│   ├── README.md                          ← 5-module Phase 2 guide
│   ├── INDEX.md
│   ├── TROUBLESHOOTING.md
│   ├── setup/                             ← Azure Entra, M365, Graph tools, network policy
│   └── a365-plugin/                       ← openclaw-a365 source code
│       ├── AGENT_GUIDE.md                      ← developer reference
│       ├── .env.example
│       ├── docker-compose.yml
│       └── src/                           ← TypeScript source files
│
└── phase-3-multi-agent-orchestration-governance/
    └── README.md                          ← roadmap (coming soon)
```

---

## Key Concepts Across Phases

### Phase 1: The Agent Model
- **Session key**: `agent:channel:peer` — isolated context per conversation
- **AGENTS.md / SOUL.md / MEMORY.md** — personality, values, persistent knowledge
- **Tool permission tiers**: Viewer → Developer → Admin

### Phase 2: Agentic Identity
- **The agent has its OWN Entra ID user** — acts as itself, not as the human
- **T1 → T2 → Agent FIC token flow** — Microsoft's Federated Identity Credentials
- **Capability perimeters** — iptables rules enforced at container startup

### Phase 3 (preview): Orchestration
- **Coordinator + specialists** — delegation pyramid patterns
- **Governance as code** — audit, compliance, and zero-trust controls

---

## Reference Docs

| Document | Purpose |
|---------|---------|
| [OPENCLAW_ARCHITECTURE.md](./OPENCLAW_ARCHITECTURE.md) | Platform architecture deep-dive |
| [OPENCLAW_SETUP_GUIDE.md](./OPENCLAW_SETUP_GUIDE.md) | Installation & channel setup reference |
| [OPENCLAW_IMPLEMENTATION_GUIDE.md](./OPENCLAW_IMPLEMENTATION_GUIDE.md) | Patterns, multi-agent, plugin development |
| [phase-2-.../a365-plugin/AGENT_GUIDE.md](./phase-2-tool-integration-capability-perimeters/a365-plugin/AGENT_GUIDE.md) | openclaw-a365 developer reference |

---

## Sources

This lab combines two projects:
- [enterprise-ready-ai-agent-lab](https://github.com/miguelarcilla/enterprise-ready-ai-agent-lab) — Phase 1 curriculum
- [openclaw-a365](https://github.com/SidU/openclaw-a365) — Phase 2 plugin source
