# Phase 1: Building Your Autonomous AI Assistant

## Overview

In Phase 1, you will build a **foundational autonomous AI assistant** deployed on user-managed hardware. This phase focuses on creating a self-hosted, local-first AI agent that can:

- 🤖 Execute autonomous tasks using connected tools
- 🔐 Run securely on your own infrastructure
- 💬 Communicate through Microsoft Teams
- 🛠️ Access and control system tools within defined perimeter boundaries
- 📚 Maintain memory and context across sessions
- 🔄 Manage task execution without human intervention

This lab is based on **OpenClaw**, a production-ready personal AI assistant framework that demonstrates enterprise-ready AI agent patterns.

---

## Learning Objectives

By the end of Phase 1, you will:

1. **Understand autonomous AI agent architecture** - Learn how agents are structured, how they coordinate tools, and how they maintain state
2. **Set up a local AI assistant** - Install and configure OpenClaw on your machine
3. **Create agent personality and capabilities** - Define your agent's skills, instructions, and tool access
4. **Connect communication channels** - Integrate with Microsoft Teams to interact with your agent
5. **Build and execute custom tools** - Create tools your agent can autonomously call
6. **Implement memory systems** - Set up persistent context and knowledge retention
7. **Define capability perimeters** - Establish security boundaries for what your agent can access
8. **Observe and debug** - Monitor agent behavior and troubleshoot issues

---

## Key Concepts

### 1. **Autonomous Agent Architecture**

An autonomous AI agent has three core components:

```
┌─────────────────────────────────────────┐
│         User/Channel Interface          │
│         (Microsoft Teams)               │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│            Gateway / Router             │
│  (Session management, auth, routing)    │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│         Agent Runtime (LLM Loop)        │
│  • Perception (observe context)         │
│  • Reasoning (think about actions)      │
│  • Planning (decide what tools to use)  │
│  • Execution (call tools + APIs)        │
│  • Memory (track state + context)       │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│        Tools & Integrations             │
│  • System tools (browser, files, bash)  │
│  • API clients (HTTP, webhooks)         │
│  • External services                    │
│  • Custom plugins                       │
└─────────────────────────────────────────┘
```

### 2. **Session Model**

Every conversation is a **session** with:
- **Isolated context** - Each session maintains its own conversation history
- **Tool policies** - Sessions can have different tool access levels
- **Sub-agent spawning** - Sessions can delegate to other agents
- **Persistence** - Sessions can be resumed with full context

### 3. **Tool Policies & Perimeters**

Define what your agent can do:

```yaml
tool_policies:
  viewer:           # Read-only access
    - read
    - list
  developer:        # Development/execution
    - read
    - write
    - bash
    - edit
  admin:           # Full system access
    - "*"
```

### 4. **Memory System**

Agents maintain three types of memory:

| Memory Type | Purpose | Example |
|------------|---------|---------|
| **Conversation** | Current session context | Last 10 messages in chat |
| **Long-term** (MEMORY.md) | Persistent facts & patterns | "User prefers email updates" |
| **Episodic** (Daily) | Daily notes & observations | "User was debugging async/await" |

---

## Phase 1 Prerequisites

### System Requirements

- **OS**: macOS, Linux, or Windows (WSL2 recommended)
- **RAM**: 4GB minimum (8GB+ recommended)
- **Disk**: 2GB available space
- **Node.js**: v22.14+ or v24+
- **Internet**: Required for LLM APIs
- **Recommended Azure VM (cloud option)**:
   - **Linux**: `Standard_D4s_v5` (4 vCPU, 16 GiB RAM), Ubuntu 22.04 LTS
   - **Windows**: `Standard_D4s_v5` (4 vCPU, 16 GiB RAM), Windows Server 2022
   - **Minimum acceptable for light testing**: `Standard_D2s_v5` (2 vCPU, 8 GiB RAM)

### Required Accounts

1. **LLM Provider** (pick one):
   - OpenAI (ChatGPT API)
   - Anthropic (Claude API)
   - Azure OpenAI
   - or other OpenAI-compatible API

2. **Communication Channel** (optional for Phase 1, required for Phase 2):
   - Microsoft Teams workspace

### Skills Needed

- Basic terminal/command line usage
- JSON/YAML configuration editing
- Understanding of environment variables
- Basic API concepts

---

## Phase 1 Structure

### Module 1: Foundation (Days 1-2)

**Topics**: Architecture, concepts, prerequisites

1. Read [OPENCLAW_ARCHITECTURE.md](../OPENCLAW_ARCHITECTURE.md)
2. Read [OPENCLAW_SETUP_GUIDE.md](../OPENCLAW_SETUP_GUIDE.md) - Installation section
3. Verify prerequisites

### Module 2: Installation & Setup (Days 2-3)

**Topics**: Install OpenClaw, configure LLM, initialize workspace

1. **Install OpenClaw**
   ```bash
   npm install -g openclaw@latest
   openclaw onboard --install-daemon
   ```
   See [SETUP_STEPS.md](./setup/SETUP_STEPS.md) for detailed instructions

2. **Configure Your LLM Provider**
   - Choose an LLM provider (OpenAI, Anthropic, or other)
   - Get an API key
   - Update `~/.openclaw/openclaw.json`
   - See [LLM_PROVIDER_CONFIG.md](./setup/LLM_PROVIDER_CONFIG.md)

3. **Initialize Workspace**
   ```bash
   openclaw setup
   ```
   Creates: `~/.openclaw/workspace/`

### Module 3: Agent Personality & Skills (Days 3-4)

**Topics**: Define agent behavior, create instructions, add skills

1. **Create Agent Instructions** (`AGENTS.md`)
   - Edit: `~/.openclaw/workspace/AGENTS.md`
   - Define agent name, role, and behavior
   - See [AGENT_PERSONALITY.md](./setup/AGENT_PERSONALITY.md) template

2. **Add Soul & Consciousness** (`SOUL.md`)
   - Edit: `~/.openclaw/workspace/SOUL.md`
   - Define core values and decision-making principles
   - Example: [workspace/SOUL.md](./workspace/SOUL.md)

3. **Create Skills** (optional but recommended)
   - Create: `~/.openclaw/workspace/skills/hello-world/SKILL.md`
   - Skills are reusable agent capabilities
   - See [workspace/skills/hello-world/SKILL.md](./workspace/skills/hello-world/SKILL.md)

### Module 4: Tools & Capabilities (Days 4-5)

**Topics**: Configure tools, set permissions, test execution

1. **Built-in Tools Overview**
   - Browser tool for web automation
   - Bash tool for system commands
   - File tools for read/write/edit

2. **Configure Tool Policies**
   - Edit: `~/.openclaw/openclaw.json`
   - Set sandbox mode and permissions
   - Example: [CONFIG_EXAMPLES.md](./starter-configs/CONFIG_EXAMPLES.md)

3. **Test Tool Access**
   ```bash
   openclaw agent --message "List my home directory"
   openclaw agent --message "What's the weather in San Francisco?"
   ```

### Module 5: First Autonomous Tasks (Days 5-6)

**Topics**: Run your first autonomous agent tasks

1. **Simple Information Retrieval**
   ```bash
   openclaw agent --message "Find and summarize the latest news about AI"
   ```

2. **File Operations**
   ```bash
   openclaw agent --message "Create a TODO list file with today's tasks"
   ```

3. **Multi-step Tasks**
   ```bash
   openclaw agent --message "Search for Python async patterns, \
                             save the best practices to a file, \
                             and create a summary"
   ```

### Module 6: Channel Integration (Days 6-7)

**Topics**: Connect communication channels, interact with agent

1. **Microsoft Teams Integration** (Recommended for Phase 1)
   - Set up Teams bot
   - Configure in `openclaw.json`
   - Test: Send message to bot
   - See [TEAMS_SETUP.md](./setup/TEAMS_SETUP.md)

2. **Discord Integration** (Alternative)
   - See [DISCORD_SETUP.md](./setup/DISCORD_SETUP.md)

### Module 7: Memory & Persistence (Day 7)

**Topics**: Set up memory systems, test context retention

1. **Long-term Memory**
   - Edit: `~/.openclaw/workspace/MEMORY.md`
   - Add facts and patterns
   - Test: Recall memory in next session

2. **Session Context**
   ```bash
   openclaw agent --message "Remember: I prefer detailed explanations"
   openclaw agent --message "Explain quantum entanglement"
   # Agent should use remembered preference
   ```

---

## Lab Deliverables

### By End of Phase 1, You Will Have:

✅ **Installation & Configuration**
- Installed OpenClaw locally
- Configured LLM provider (OpenAI, Anthropic, or other)
- Initialized agent workspace

✅ **Agent Personality**
- Created `AGENTS.md` with agent role and instructions
- Created `SOUL.md` with core principles
- (Optional) Created at least one custom skill

✅ **Tools & Execution**
- Configured tool policies
- Tested 5+ autonomous agent tasks
- Demonstrated tool execution (files, bash, browser)

✅ **Communication**
- Integrated with Microsoft Teams
- Successfully sent and received messages through Teams
- Demonstrated agent autonomously responding to messages

✅ **Memory**
- Created long-term memory entries
- Demonstrated context retention across sessions
- Verified agent uses persisted knowledge

✅ **Documentation**
- Created README for your specific setup
- Documented your agent's capabilities
- Created troubleshooting guide for common issues

---

## Quick Start (TL;DR)

For experienced users wanting to get started immediately:

```bash
# 1. Install
npm install -g openclaw@latest

# 2. Onboard (interactive setup)
openclaw onboard --install-daemon

# 3. Configure your LLM provider
# Edit: ~/.openclaw/openclaw.json
# Set your API key from OpenAI/Anthropic/other

# 4. Define agent personality
# Edit: ~/.openclaw/workspace/AGENTS.md
# Edit: ~/.openclaw/workspace/SOUL.md

# 5. Test a simple task
openclaw agent --message "Hello! Who are you?"

# 6. Set up Microsoft Teams channel
# Edit: ~/.openclaw/openclaw.json
# Add your Teams bot credentials

# 7. Start the gateway
openclaw gateway --port 18789 --verbose
```

---

## File Structure

```
phase-1-building-autonomous-ai-assistant/
├── README.md                           # This file
├── INDEX.md                            # Navigation hub
├── IMPLEMENTATION_SUMMARY.md           # Phase 1 summary
├── setup/
│   ├── SETUP_STEPS.md                  # Detailed installation guide
│   ├── LLM_PROVIDER_CONFIG.md          # LLM configuration
│   ├── AGENT_PERSONALITY.md            # Agent instructions template
│   ├── TEAMS_SETUP.md                  # Microsoft Teams integration
│   └── DISCORD_SETUP.md               # Discord integration
├── starter-configs/
│   └── CONFIG_EXAMPLES.md              # Full config examples
├── workspace/
│   ├── AGENTS.md                       # Example agent definitions
│   ├── SOUL.md                         # Example agent soul
│   ├── MEMORY.md                       # Example memory entries
│   └── skills/
│       └── hello-world/
│           └── SKILL.md                # Example skill
└── TROUBLESHOOTING.md                  # Common issues & solutions
```

---

## Next: Phase 2 & 3

After completing Phase 1, you have two paths to take your agent into Microsoft Teams and M365 Copilot:

- **[`TEAMS_COPILOT_INTEGRATION.md`](../TEAMS_COPILOT_INTEGRATION.md)** — composable approach: keep OpenClaw as your multi-channel gateway, add a Microsoft 365 Agents SDK agent at port 3978, and onboard with the Agent 365 SDK via `aka.ms/agent365enable` or the `a365` CLI. Works for personal multi-channel use (Pattern A) and enterprise Teams/Copilot deployments (Pattern B).

- **[Phase 2: Tool Integration & Capability Perimeters](../phase-2-tool-integration-capability-perimeters/README.md)** — packaged approach: deploy the `openclaw-a365` plugin as a single Docker container with agentic identity, FIC tokens, Microsoft Graph calendar/email tools, and iptables-enforced network perimeter.
  - Connect to Microsoft 365 APIs and external services
  - Define safety boundaries and network policies
  - Implement approval workflows
  - Govern agent actions through Microsoft Agent 365

- **[Phase 3: Multi-Agent Orchestration & Enterprise Governance](../phase-3-multi-agent-orchestration-governance/README.md)**
  - Build multi-agent systems
  - Implement delegation patterns
  - Enterprise monitoring and logging
  - Advanced security & compliance

---

## Resources & Support

### Additional Reference Materials
- [OPENCLAW_ARCHITECTURE.md](../OPENCLAW_ARCHITECTURE.md) - Deep dive into internals
- [OPENCLAW_SETUP_GUIDE.md](../OPENCLAW_SETUP_GUIDE.md) - Comprehensive setup
- [OPENCLAW_IMPLEMENTATION_GUIDE.md](../OPENCLAW_IMPLEMENTATION_GUIDE.md) - Advanced patterns

### Community
- [Microsoft Teams Bot Documentation](https://learn.microsoft.com/en-us/microsoftteams/platform/bots/what-are-bots)
- [GitHub Issues](https://github.com/openclaw/openclaw/issues)
- [Discussions](https://github.com/openclaw/openclaw/discussions)

### Troubleshooting
- See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- Check OpenClaw logs: `openclaw doctor`

---

## Time Estimates

| Module | Duration | Effort |
|--------|----------|--------|
| Module 1: Foundation | 2-3 hours | Easy - Reading |
| Module 2: Installation | 1-2 hours | Easy - Follow steps |
| Module 3: Personality | 1-2 hours | Medium - Creative |
| Module 4: Tools | 1-2 hours | Medium - Configuration |
| Module 5: First Tasks | 2-3 hours | Medium - Experimentation |
| Module 6: Channels | 2-3 hours | Medium - Setup |
| Module 7: Memory | 1-2 hours | Medium - Configuration |
| **Total Phase 1** | **10-17 hours** | **Medium** |

---

## Success Criteria

✅ You've successfully completed Phase 1 when:

1. OpenClaw is installed and running
2. Your agent responds to a message with "Hello"
3. Your agent successfully executes a tool (file read, bash command, or web request)
4. You can send and receive messages through a connected channel
5. Your agent uses long-term memory to recall information
6. You have documented your agent's capabilities and setup

---

**Ready to build your AI assistant? Start with [setup/SETUP_STEPS.md](./setup/SETUP_STEPS.md)!**
