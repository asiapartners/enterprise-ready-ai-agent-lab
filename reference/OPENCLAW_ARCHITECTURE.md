# OpenClaw Architecture & Setup Guide

## Executive Summary

OpenClaw is a self-hosted gateway platform for building autonomous AI assistants. It provides a modular architecture connecting AI agents to multiple messaging channels (Telegram, Discord, Slack, WhatsApp, Signal, iMessage, Matrix, MS Teams, etc.) with enterprise-grade security, multi-agent routing, and extensibility through plugins and skills.

---

## 1. Core Architecture Overview

### 1.1 The Gateway Pattern

OpenClaw operates on a **Gateway architecture** that serves as the central hub:

- **Single Process**: The Gateway runs as a unified Node.js process that coordinates all agent interactions, message routing, and channel communication
- **Isolation Boundaries**: Clear separation between:
  - Core agent runtime (plugin-safe execution)
  - Channel adapters (chat platform integrations)
  - Tool providers (model-agnostic capabilities)
  - Plugin system (extensible capabilities)

### 1.2 Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Chat Channels                         │
│  (Discord, Telegram, Slack, WhatsApp, Signal, etc.)     │
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

## 2. Key Architectural Components

### 2.1 Sessions Model

**Session Key** = `agent:channel:peer`

Sessions represent isolated conversation contexts:

- **Lifecycle**: Created on first message, maintained across turns, optionally persisted
- **Routing**: Messages route to specific agent+channel+user combinations
- **Threading**: Multi-agent capable (broadcast groups, multi-agent routing)
- **Sub-agents**: Can spawn child sessions for delegation/orchestration
- **Sandbox Modes**: Can inherit or require sandbox constraints

**Session Types**:
- `pi` - Embedded agent runtime (in-process)
- `codex` - External Codex app-server harness
- `claude-cli` - External Claude CLI harness
- `acp` - Agent Control Protocol (external harness agents)

### 2.2 Gateway Component

The Gateway is the central orchestrator:

**Responsibilities**:
- Inbound message reception & normalization
- Session creation/maintenance/routing
- Tool execution & policy enforcement
- Channel-specific logic (threading, mentions, group management)
- Control UI hosting (Web dashboard on port 18789)

**Configuration**:
- `gateway.auth.mode` - Authentication: "none", "token", "password", "trusted-proxy"
- `gateway.bind.mode` - Network binding: "lan", "loopback", "custom", "tailnet", "auto"
- `gateway.ports` - Control UI (18789), WebChat (18788), API endpoints
- `gateway.hooks` - Webhook endpoints for external integrations

### 2.3 Agent Runtime (Embedded PI)

The agent loop executes within the Gateway:

**Agent Loop Steps**:
1. **Bootstrap Context Assembly** - Load MEMORY.md, TOOLS.md, AGENTS.md, workspace context
2. **System Prompt Building** - Compile from base prompt + skills + bootstrap + overrides
3. **Message Submission** - Send to configured LLM/model provider
4. **Tool Execution** - Execute tool calls, stream responses
5. **Retry Logic** - Handle model failures with fallback chains
6. **Response Delivery** - Route back through appropriate channel

**Key Files**:
- `AGENTS.md` - Multi-agent routing & sub-agent configuration
- `TOOLS.md` - Available tools reference for the model
- `MEMORY.md` - Long-term memory (permanent)
- `memory/*.md` - Daily memory files (temporary)

### 2.4 Tools Architecture

Three tiers of tools available to agents:

| Tier | Source | Examples | Access |
|------|--------|----------|--------|
| **Built-in** | Core OpenClaw | message, reaction, memory_get, sessions_spawn, memory_search | Always available |
| **Skills** | Skill packages | GitHub search, calendar access, database queries | Allowlist/policy-based |
| **Plugins** | Native plugins | New channels, model providers, media understanding | Plugin-specific |

**Tool Policies** enforce via:
- Profile-based allowlists (e.g., "messaging", "admin", "read-only")
- Per-agent configuration (`agents.list[].toolPolicies`)
- Group-level policies
- Sandbox constraints

---

## 3. Multi-Agent Architecture

### 3.1 Sub-agents & Delegation

Agents can spawn child sessions for task delegation:

```typescript
// Agent spawns sub-agent
{
  "name": "sessions_spawn",
  "input": {
    "agentId": "dev-agent",
    "prompt": "Analyze this code",
    "sandbox": "inherit" | "require"
  }
}
```

**Sub-agent Isolation**:
- Inherits or requires sandbox mode from parent
- Limited bootstrap (only `AGENTS.md` + `TOOLS.md`)
- Labeled with creator plugin ID (if plugin-created)
- Can be deleted only by creator or admin

### 3.2 Multi-Agent Routing

Agents can coordinate within a session:

**Broadcast Groups**:
- Route single message to multiple agents
- Each agent produces independent response
- Useful for getting multiple perspectives

**Session Tools** with `sessions_send()`:
- Cross-session messaging without creating new sessions
- Useful for agent orchestration within a single "turn"

**Delegate Architecture** (Google Workspace):
- Service account impersonation for organization-wide access
- Scoped service account credentials
- Admin console integration

---

## 4. Channels & Integration Points

### 4.1 Supported Chat Channels

OpenClaw connects to multiple messaging platforms:

| Channel | Platform | Status | Features |
|---------|----------|--------|----------|
| **Discord** | Discord | Bundled | Bot API + Gateway; servers, channels, DMs |
| **Telegram** | Telegram | Bundled | Bot API; groups, topics, threads |
| **Slack** | Slack | Bundled | Bot API; channels, threads, DMs |
| **WhatsApp** | WhatsApp Web | Bundled | Web-based (Baileys); personal/business |
| **Signal** | Signal | Bundled | Signal protocol; groups |
| **iMessage** | Apple | Recommended | BlueBubbles macOS server REST API |
| **Matrix** | Matrix | Bundled | Matrix protocol; rooms, threads |
| **MS Teams** | Microsoft 365 | Bundled | Teams API; teams, channels, chats |
| **WeChat** | WeChat | Plugin | Weixin monitor |
| **Google Chat** | Google Workspace | Planned | Workspace integration |

**Channel Architecture**:
- Each channel adapter normalizes messages to OpenClaw contract
- Thread/topic support enables agent-per-thread patterns
- Group chat policies (mention gating, allowlists)
- Message history buffers (configurable per channel)

### 4.2 Message Processing Pipeline

```
Channel Input
    ↓
Normalization (channel → OpenClaw contract)
    ↓
Session Routing (agent:channel:peer)
    ↓
Approval Gates (if configured)
    ↓
Agent Turn Execution
    ↓
Tool Invocation
    ↓
Channel-specific Rendering (Discord components, Slack blocks, etc.)
    ↓
Outbound Send
```

---

## 5. Plugin System Architecture

### 5.1 Plugin Capabilities

A plugin can register:

- **Channels** - New messaging platform integration
- **Model Providers** - LLM/model backends (OpenAI, Anthropic, Gemini, etc.)
- **Tools** - Agent-executable capabilities
- **Skills** - Downloadable agent extensions
- **Hooks** - Lifecycle events (startup, shutdown, config change)
- **Media Understanding** - Image/audio/video processors
- **Voice & Speech** - TTS and speech-to-text
- **Realtime Transport** - Voice/video streaming

### 5.2 Plugin Architecture

**Plugin Loading Pipeline**:
1. **Discovery** - Scan npm packages, local bundles
2. **Manifest Parse** - Extract capabilities without runtime load
3. **Setup Phase** - Collect configuration, auth choices
4. **Runtime Loading** - Initialize only enabled plugins
5. **Capability Registration** - Register tools, channels, providers

**Security Model**:
- Native plugins run inside Gateway process (arbitrary code execution risk)
- Plugins can crash or destabilize Gateway
- Careful validation of plugin sources required
- Bundle plugins (Markdown + commands) are safer

### 5.3 Plugin Manifest Structure

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "channels": ["discord"],
  "tools": ["my-tool"],
  "providers": ["openai"],
  "hooks": ["gateway_start", "config_changed"],
  "setup": {
    "providers": [],
    "channels": []
  }
}
```

---

## 6. Setup & Initialization Workflow

### 6.1 First-Time Setup

```bash
# One-time initialization
pnpm openclaw setup

# This:
# - Creates ~/.openclaw/ workspace directory
# - Generates default configuration files
# - Sets up credential storage
# - Initializes agent/channel/model config
```

**Configuration Files Created**:
- `~/.openclaw/config.yml` - Main config
- `~/.openclaw/credentials/` - Channel/provider secrets
- `~/.openclaw/agents/` - Per-agent configuration
- `~/.openclaw/logs/` - Gateway logs

### 6.2 Agent Initialization

**Per-Agent Structure**:
```
~/.openclaw/agents/<agentId>/
├── agent/
│   ├── AGENTS.md
│   ├── TOOLS.md
│   ├── MEMORY.md
│   ├── auth-profiles.json
│   └── codex-home/ (if using external harness)
├── workspace/
│   ├── README.md (project context)
│   ├── TOOLS.md (workspace tools)
│   └── skills/ (local skill definitions)
└── sessions/
    ├── sessions.json (index)
    └── <sessionId>/ (conversation history)
```

### 6.3 Startup Process

```bash
# Start the Gateway
pnpm gateway:watch

# Or with specific config
OPENCLAW_WORKSPACE=/path/to/workspace pnpm gateway:watch
```

**Startup Checks**:
1. Load configuration schema
2. Validate credentials & secrets
3. Initialize enabled plugins
4. Load model provider catalog
5. Setup channel adapters
6. Initialize memory engines (QMD refresh if configured)
7. Bind to configured network interface
8. Listen for inbound messages

---

## 7. Key Configuration Areas

### 7.1 Agent Defaults

```yaml
agents:
  defaults:
    # Model and inference settings
    model: "openai/gpt-4"
    thinking: "off" | "inline" | "extended"
    
    # Memory and context
    memorySearch: true
    startupContext:
      maxFileBytes: 16384
      maxFileChars: 100000
    bootstrapTotalMaxChars: 60000
    
    # Tool policies
    toolPolicies:
      profile: "default"
      alsoAllow: ["memory_search"]
    
    # Sub-agent configuration
    subagents:
      allowAgents: ["analyst", "coder"]
      runTimeoutSeconds: 300
      
    # Runtime harness
    embeddedHarness:
      runtime: "pi" | "codex"
```

### 7.2 Channel Configuration Example (Discord)

```yaml
channels:
  discord:
    token: "${DISCORD_BOT_TOKEN}"
    accounts:
      default:
        prefix: "/"
    messages:
      groupChat:
        historyLimit: 10
        visibleReplies: "automatic" | "always" | "never"
      directMessage:
        visibleReplies: "automatic"
```

### 7.3 Model Provider Configuration

```yaml
agents:
  defaults:
    models:
      "openai/gpt-4": {}
      "anthropic/claude-opus": {}
      "google/gemini-2": {}
    
    # Model failover
    modelFailover:
      maxAttempts: 3
      backoffMs: 1000
      retryableErrors: ["rate_limit", "timeout"]
```

### 7.4 Security & Authentication

```yaml
gateway:
  auth:
    mode: "token" | "password" | "trusted-proxy" | "none"
    token: "${GATEWAY_TOKEN}"
    
  bind:
    mode: "loopback" | "lan" | "tailnet" | "custom"
    address: "127.0.0.1" | "0.0.0.0"
    port: 18789

  controlUi:
    # Disable device auth only for debug
    dangerouslyDisableDeviceAuth: false
    origin: "http://localhost:18789"
```

---

## 8. Skills System

### 8.1 Skill Structure

Skills are downloadable agent extensions:

```
skill-package/
├── commands/
│   └── feature-name/
│       ├── README.md (skill documentation)
│       └── index.md (markdown-based skill)
├── skills/
│   └── tool-definitions/
│       └── tool.yaml (YAML tool definitions)
└── manifest.json
```

### 8.2 Skill Lifecycle

1. **Discovery** - ClawHub public registry or local bundles
2. **Installation** - Download & extract to `~/.openclaw/skills/`
3. **Loading** - Reload on-disk changes (with debounce)
4. **Registration** - Expose to agent via TOOLS.md
5. **Gating** - Apply per-agent allowlist policies

**Configuration**:
```yaml
skills:
  load:
    enabled: true
    watchFileChanges: true
    watchDebounceMs: 500
  allowlist: ["github-search", "calendar"]
```

---

## 9. Workspace & Memory Management

### 9.1 Workspace Structure

```
project-workspace/
├── README.md (project overview for agents)
├── TOOLS.md (workspace-specific tools)
├── architecture/
├── src/
├── docs/
└── config/
```

### 9.2 Memory System (QMD - Quill Markdown)

**Memory Hierarchy**:
- `MEMORY.md` - Permanent long-term memory
- `memory/*.md` - Daily memory files (day-based organization)
- `memory/reports/` - Extracted insights and summaries

**Memory Access**:
```typescript
// Built-in tools
memory_search(query, limit)      // Vector search over MEMORY.md + memory/*.md
memory_get(file_path)             // Read specific memory file
memory_update(path, content)       // Write/append to memory (with audit trail)
```

**Startup Context**:
- Recent memory files pre-loaded for `/new` and `/reset` turns
- Reduces cold-start context window usage
- Configurable via `agents.defaults.startupContext`

---

## 10. Architectural Patterns & Best Practices

### 10.1 Security Boundaries

**Defense-in-Depth**:
1. **Host Boundaries** - Sandbox constraints (require vs inherit)
2. **Tool Policies** - Profile-based allowlists
3. **Channel Authorization** - Group/channel-specific agent allowlists
4. **Secret Management** - SecretRef providers (env/file/exec)
5. **Audit Logging** - Full event trails in session artifacts

**Threat Model Coverage**:
- Prompt injection (mitigated by tool policy boundaries)
- SSRF attacks (mitigated by tool controls)
- Credential exposure (mitigated by SecretRef + audit)
- Multi-tenancy isolation (session boundaries + group policies)

### 10.2 Scaling Patterns

**Multi-Agent Orchestration**:
- Broadcast groups for parallel processing
- Sub-agent spawning for task delegation
- Session-level threading for isolation
- Cross-agent memory sharing via MEMORY.md

**High-Volume Scenarios**:
- Message queue with backoff/retry
- Diagnostics for stuck sessions (`stuckSessionWarnMs`, `stuckSessionAbortMs`)
- Connection pooling per channel
- Browser sandbox for resource-heavy tasks

### 10.3 Development Workflow

```bash
# Watch mode development
pnpm gateway:watch

# Run tests
pnpm test

# Build plugins
pnpm openclaw plugins build

# Publish to ClawHub
clawhub package publish

# Inspect plugin
openclaw plugins inspect <plugin-id> --runtime --json

# View sessions
openclaw sessions list
openclaw sessions view <sessionId>
```

---

## 11. Deployment Options

### 11.1 Local Development

- macOS: Bundled app, native tray icon, XPC integration
- Linux: Direct Node.js process
- Container: Docker/Podman images with env config

### 11.2 Production Deployment

**VPS/Server Setup**:
```yaml
gateway:
  bind:
    mode: tailnet           # Private network via Tailscale
    # OR trusted-proxy behind auth proxy
  controlUi:
    origin: "https://claw.example.com"

channels:
  discord:
    token: "${DISCORD_TOKEN}"  # SecretRef
  telegram:
    token: "${TELEGRAM_TOKEN}"
```

**Kubernetes**:
- StatefulSet for persistence
- ConfigMap for configuration
- Secrets for credentials
- NodePort/LoadBalancer for chat webhooks

### 11.3 ARM64 Support

- Raspberry Pi support (tested)
- Most features work natively on ARM64
- Optional CLI tools (Go/Rust binaries) may need building from source
- Verify architecture: `uname -m` (should show `aarch64`)

---

## 12. OpenClaw vs. Clawpilot

**Note**: Based on extensive GitHub search, **Clawpilot appears to be either deprecated, not publicly available, or part of the OpenClaw ecosystem under a different name.** 

The current OpenClaw project includes:
- `openclaw/openclaw` - Core framework
- `openclaw/openclaw-windows-node` - Windows Node support
- `openclaw/openclaw.ai` - Public website & documentation
- Various language SDK repositories (Node, Python, Go)

**If Clawpilot was a previous product or internal project**, it has been integrated into or superseded by the modern OpenClaw architecture described above.

---

## 13. Reference Documentation Structure

### 13.1 Key Documentation Paths

| Topic | Location |
|-------|----------|
| Architecture | `/docs/concepts/architecture`, `/docs/concepts/agent` |
| Setup Guide | `/docs/start/setup.md` |
| Gateway Config | `/docs/gateway/configuration.md`, `/docs/gateway/configuration-reference.md` |
| Channel Guides | `/docs/channels/{discord,telegram,slack,...}.md` |
| Plugins | `/docs/plugins/building-plugins`, `/docs/plugins/manifest` |
| Security | `/docs/gateway/security`, `/docs/security/threat-model` |
| API Reference | `/docs/reference/rpc` |
| Troubleshooting | `/docs/help/troubleshooting.md` |

### 13.2 Getting Help

- **Discord Community**: OpenClaw community server
- **ClawHub**: https://clawhub.ai (skill registry)
- **GitHub Issues**: Report bugs and request features
- **Documentation**: https://docs.openclaw.ai

---

## 14. Quick-Start Checklist

### Initial Setup
- [ ] Clone or install OpenClaw
- [ ] Run `pnpm openclaw setup`
- [ ] Choose primary LLM model (OpenAI, Anthropic, etc.)
- [ ] Create first agent config

### Channel Integration
- [ ] Choose messaging platform(s) (Telegram, Discord, etc.)
- [ ] Obtain bot tokens/credentials
- [ ] Add to `channels` config
- [ ] Test message routing

### Agent Customization
- [ ] Define agent in `agents.list`
- [ ] Set tool policies and allowlist
- [ ] Create `MEMORY.md` for long-term context
- [ ] Configure bootstrap workspace

### Multi-Agent Setup (Optional)
- [ ] Define sub-agents in `AGENTS.md`
- [ ] Configure routing patterns
- [ ] Set sandbox constraints
- [ ] Test delegation workflows

### Deployment
- [ ] Configure appropriate auth mode
- [ ] Set network binding (tailnet or reverse proxy)
- [ ] Enable logging/diagnostics
- [ ] Deploy to target platform

---

## 15. Key Takeaways

1. **Gateway-centric architecture** - Single unified process coordinates all agent activity
2. **Session-based routing** - `agent:channel:peer` model ensures isolation
3. **Extensible through plugins** - Native plugin system + markdown skills
4. **Multi-channel support** - 10+ messaging platforms out of the box
5. **Enterprise security** - Tool policies, sandbox modes, secret management
6. **Self-hosted control** - All data stays on your infrastructure
7. **AI-agnostic** - Works with any LLM provider (OpenAI, Anthropic, etc.)
8. **Sub-agent orchestration** - Build multi-agent systems with task delegation
9. **Memory-first design** - Long-term memory accessible to all agents
10. **Production-ready** - VPS, Kubernetes, and single-machine deployments supported

