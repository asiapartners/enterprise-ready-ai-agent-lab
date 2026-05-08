# OpenClaw Architecture Reference

This document describes the OpenClaw platform architecture — the foundation for all three phases of this lab.

---

## Executive Summary

OpenClaw is a self-hosted gateway platform for building autonomous AI assistants. It provides a modular architecture connecting AI agents to multiple messaging channels (Telegram, Discord, Slack, WhatsApp, Signal, iMessage, Matrix, MS Teams, and more) with enterprise-grade security, multi-agent routing, and extensibility through plugins and skills.

---

## 1. Core Architecture

### The Gateway Pattern

OpenClaw operates on a **Gateway architecture** that serves as the central hub:

- **Single Process**: The Gateway runs as a unified Node.js process that coordinates all agent interactions, message routing, and channel communication
- **Isolation Boundaries**: Clear separation between:
  - Core agent runtime (plugin-safe execution)
  - Channel adapters (chat platform integrations)
  - Tool providers (model-agnostic capabilities)
  - Plugin system (extensible capabilities)

### Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Chat Channels                         │
│  (Discord, Telegram, Slack, Teams, Signal, etc.)        │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│                Gateway & Message Router                 │
│  • Session management & routing                         │
│  • Authentication & authorization                       │
│  • Rate limiting & message queuing                      │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│              Agent Runtime (Embedded PI)                │
│  • Agent loop execution                                 │
│  • Model interaction & tool orchestration               │
│  • Context assembly & system prompt building            │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│         Tools, Skills, & Plugins Layer                  │
│  • Built-in tools (message, reaction, memory)           │
│  • Skills (downloadable agent extensions)               │
│  • Native plugins (capabilities & channels)             │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Key Components

### Sessions Model

**Session Key** = `agent:channel:peer`

Sessions represent isolated conversation contexts:
- **Lifecycle**: Created on first message, maintained across turns, optionally persisted
- **Routing**: Messages route to specific agent+channel+user combinations
- **Sub-agents**: Can spawn child sessions for delegation/orchestration

### Gateway

The central orchestrator responsible for:
- Inbound message reception & normalization
- Session creation/maintenance/routing
- Tool execution & policy enforcement
- Control UI hosting (Web dashboard on port 18789)

### Agent Runtime

The agent loop executes within the Gateway:

1. **Bootstrap Context Assembly** — Load MEMORY.md, AGENTS.md, workspace context
2. **System Prompt Building** — Compile from base prompt + skills + bootstrap
3. **Message Submission** — Send to configured LLM provider
4. **Tool Execution** — Execute tool calls, stream responses
5. **Response Delivery** — Route back through appropriate channel

### Tools Architecture

Three tiers:

| Tier | Examples | Access |
|------|----------|--------|
| **Built-in** | message, reaction, memory_get, sessions_spawn | Always available |
| **Skills** | GitHub search, calendar access | Allowlist/policy-based |
| **Plugins** | New channels, model providers | Plugin-specific |

---

## 3. Multi-Agent Architecture

Agents can spawn child sessions for task delegation:

```typescript
{
  "name": "sessions_spawn",
  "input": {
    "agentId": "dev-agent",
    "prompt": "Analyze this code",
    "sandbox": "inherit"
  }
}
```

**Broadcast Groups**: Route a single message to multiple agents for parallel independent responses.

---

## 4. Supported Channels

| Channel | Platform | Notes |
|---------|----------|-------|
| Discord | Discord | Bot API + Gateway; servers, channels, DMs |
| Telegram | Telegram | Bot API; groups, topics, threads |
| Slack | Slack | Bot API; channels, threads, DMs |
| WhatsApp | WhatsApp Web | Web-based (Baileys) |
| Signal | Signal | Signal protocol; groups |
| MS Teams | Microsoft 365 | Phase 2 focus — openclaw-a365 plugin |
| Matrix | Matrix | Matrix protocol; rooms, threads |
| iMessage | Apple | BlueBubbles macOS server REST API |

---

## 5. Plugin System

A plugin can register:
- **Channels** — New messaging platform integrations
- **Model Providers** — LLM backends (OpenAI, Anthropic, Gemini, etc.)
- **Tools** — Agent-executable capabilities
- **Skills** — Downloadable agent extensions
- **Hooks** — Lifecycle events

**Plugin Manifest**:
```json
{
  "id": "my-plugin",
  "channels": ["my-channel"],
  "tools": ["my-tool"]
}
```

---

## 6. Memory System

**Memory Hierarchy**:
- `MEMORY.md` — Permanent long-term memory
- `memory/*.md` — Daily memory files
- `memory/reports/` — Extracted insights

**Memory Tools**:
```typescript
memory_search(query, limit)   // Vector search
memory_get(file_path)         // Read specific file
memory_update(path, content)  // Write/append
```

---

## 7. Security Model

**Defense-in-Depth**:
1. **Sandbox constraints** — require vs inherit modes
2. **Tool policies** — profile-based allowlists
3. **Channel authorization** — group/channel allowlists
4. **Secret management** — SecretRef providers (env/file/exec)
5. **Audit logging** — Full event trails in session artifacts

---

## 8. Workspace Structure

```
~/.openclaw/agents/<agentId>/
├── agent/
│   ├── AGENTS.md        ← multi-agent routing
│   ├── TOOLS.md         ← available tools reference
│   ├── MEMORY.md        ← long-term memory
│   └── auth-profiles.json
├── workspace/
│   ├── README.md        ← project context
│   └── skills/          ← local skill definitions
└── sessions/
    └── <sessionId>/     ← conversation history
```

---

## 9. Deployment Options

| Mode | Use Case |
|------|---------|
| Local (macOS app) | Development, personal use |
| Docker/Container | Self-hosted production |
| VPS + Tailscale | Private network deployment |
| Kubernetes | Enterprise scale |

---

## Phase-Specific Architecture

| Phase | Architecture Focus |
|-------|-------------------|
| **Phase 1** | Core gateway + Discord/Teams channels + agent personality |
| **Phase 2** | openclaw-a365 plugin + Microsoft Graph tools + capability perimeters |
| **Phase 3** | Multi-agent orchestration + governance + monitoring |

→ See each phase's README for phase-specific architectural details.
