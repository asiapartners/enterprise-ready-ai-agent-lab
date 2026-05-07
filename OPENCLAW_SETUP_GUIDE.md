# OpenClaw Setup & Configuration Guide

## Table of Contents

1. [Installation](#installation)
2. [Initial Configuration](#initial-configuration)
3. [Channel Setup](#channel-setup)
4. [Agent Configuration](#agent-configuration)
5. [Advanced Scenarios](#advanced-scenarios)
6. [Troubleshooting](#troubleshooting)

---

## Installation

### Prerequisites

- **Node.js**: 18.x or later (LTS recommended)
- **pnpm**: Package manager (install globally: `npm install -g pnpm`)
- **Disk Space**: 500MB minimum, 2GB+ recommended
- **Memory**: 1GB RAM minimum, 2GB+ recommended
- **Network**: Internet for LLM API calls; local network or VPN for Gateway access

### Platform-Specific Installation

#### macOS (Recommended Desktop Experience)

```bash
# Using Homebrew
brew tap openclaw/tap
brew install openclaw

# Launches native app with tray integration
openclaw

# Or from source
git clone https://github.com/openclaw/openclaw.git
cd openclaw
pnpm install
pnpm build
pnpm openclaw setup
pnpm gateway:watch
```

#### Linux / VPS

```bash
# Clone repository
git clone https://github.com/openclaw/openclaw.git
cd openclaw

# Install dependencies
pnpm install

# Initial setup
pnpm openclaw setup

# Start in development mode
pnpm gateway:watch

# Start in background (production)
nohup pnpm gateway:start > ~/.openclaw/logs/gateway.log 2>&1 &
```

#### Docker / Kubernetes

```dockerfile
# Dockerfile
FROM node:18-alpine
WORKDIR /app
COPY . .
RUN pnpm install
RUN pnpm build
EXPOSE 18789 18788
CMD ["pnpm", "gateway:start"]
```

```bash
# Run container
docker run -d \
  -p 18789:18789 \
  -p 18788:18788 \
  -v ~/.openclaw:/home/openclaw/.openclaw \
  -e OPENAI_API_KEY=$OPENAI_API_KEY \
  openclaw:latest
```

#### Raspberry Pi / ARM64

```bash
# ARM64 dependencies available
# Install same as Linux, verify architecture
uname -m  # Should output: aarch64

# Most features work native on ARM64
# Optional CLI tools (Go/Rust) may need compilation
```

---

## Initial Configuration

### 1. First-Time Setup

```bash
# Initialize workspace
pnpm openclaw setup

# This creates:
# ~/.openclaw/
#   ├── config.yml
#   ├── credentials/
#   ├── agents/
#   ├── logs/
#   └── skills/
```

### 2. Choose Primary Model Provider

Create `~/.openclaw/config.yml`:

#### OpenAI

```yaml
agents:
  defaults:
    model: "openai/gpt-4"

providers:
  openai:
    apiKey: "${OPENAI_API_KEY}"
    models:
      - "gpt-4"
      - "gpt-4-turbo"
      - "gpt-3.5-turbo"
```

#### Anthropic

```yaml
agents:
  defaults:
    model: "anthropic/claude-opus"

providers:
  anthropic:
    apiKey: "${ANTHROPIC_API_KEY}"
    models:
      - "claude-opus"
      - "claude-sonnet"
      - "claude-haiku"
```

#### Google Gemini

```yaml
agents:
  defaults:
    model: "google/gemini-2"

providers:
  google:
    apiKey: "${GOOGLE_API_KEY}"
    models:
      - "gemini-2-flash"
      - "gemini-1.5-pro"
```

#### Local Models (Ollama / LM Studio)

```yaml
agents:
  defaults:
    model: "ollama/llama2"

providers:
  ollama:
    baseUrl: "http://localhost:11434"
    models:
      - "llama2"
      - "mistral"
```

### 3. Environment Variables

```bash
# Create ~/.profile or ~/.zshrc
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GOOGLE_API_KEY="..."
export DISCORD_BOT_TOKEN="MTA..."
export TELEGRAM_BOT_TOKEN="123456:ABC..."
```

Or use SecretRef providers for credentials:

```yaml
providers:
  openai:
    apiKey:
      type: "secretRef"
      provider: "env"          # Read from environment
      key: "OPENAI_API_KEY"
```

### 4. Gateway Startup

```bash
# Development mode (watch for changes)
pnpm gateway:watch

# Production mode
pnpm gateway:start

# With custom workspace
OPENCLAW_WORKSPACE=/path/to/workspace pnpm gateway:watch

# With logging
DEBUG="*" pnpm gateway:watch

# Specific log filters
OPENCLAW_LOG_FLAGS="telegram.*,discord" pnpm gateway:watch
```

**Verify Gateway is Running**:
```bash
# Check Control UI
open http://localhost:18789

# Check gateway logs
tail -f ~/.openclaw/logs/gateway.log

# List status
openclaw status
```

---

## Channel Setup

### Discord Setup

#### 1. Create Discord Bot

```
1. Go to https://discord.com/developers/applications
2. Click "New Application"
3. Name: "OpenClaw Agent"
4. Go to "Bot" → "Add Bot"
5. Copy token → save as DISCORD_BOT_TOKEN
6. Enable "Message Content Intent" (required for reading messages)
7. Go to "OAuth2" → "URL Generator"
8. Scopes: bot
9. Permissions: 
   - Send Messages
   - Read Message History
   - Add Reactions
   - Manage Messages
10. Copy generated URL and add bot to your server
```

#### 2. Configure OpenClaw

```yaml
channels:
  discord:
    token: "${DISCORD_BOT_TOKEN}"
    
    accounts:
      default:
        guildId: "YOUR_GUILD_ID"
        
    # Default behavior
    messages:
      groupChat:
        historyLimit: 10              # Include last N messages for context
        visibleReplies: "automatic"   # Post to channel or DM
        requireMention: false         # Respond to all messages or only @mentions
      directMessage:
        visibleReplies: "automatic"
    
    # Thread binding for multi-agent setups
    threadBindings:
      spawnSessions: true
```

#### 3. Test

```bash
# Send message in Discord channel
# Bot should respond after ~5-10 seconds

# Verify in logs
tail -f ~/.openclaw/logs/gateway.log | grep discord
```

### Telegram Setup

#### 1. Create Telegram Bot

```
1. Open Telegram
2. Search for @BotFather
3. Send /newbot
4. Follow prompts to name bot
5. Copy token → save as TELEGRAM_BOT_TOKEN
6. Get Your Chat ID:
   - Message @userinfobot
   - Note your User ID
```

#### 2. Configure OpenClaw

```yaml
channels:
  telegram:
    token: "${TELEGRAM_BOT_TOKEN}"
    
    accounts:
      default:
        # For personal use (single user)
        allowedUserIds: ["YOUR_USER_ID"]
        
        # Or for groups
        allowedGroupIds: ["GROUP_CHAT_ID"]
    
    # Message behavior
    messages:
      groupChat:
        historyLimit: 5
        requireMention: false
    
    # Reply mode (thread-like behavior on topics)
    replyToMode: "thread"  # or "chain"
    
    # Topic bindings for multi-agent
    threadBindings:
      spawnSessions: true
```

#### 3. Test

```bash
# Send message to bot in Telegram
# Bot responds within 5-10 seconds

# Get chat ID if needed
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
```

### Slack Setup

#### 1. Create Slack App

```
1. Go to https://api.slack.com/apps
2. Click "Create New App" → "From scratch"
3. Name: "OpenClaw Agent"
4. Select workspace
5. Go to "Socket Mode" → Enable
6. Generate App-Level Token (save as SLACK_APP_TOKEN)
7. Go to "OAuth & Permissions"
8. Bot Token Scopes:
   - chat:write
   - reactions:write
   - files:read
   - channels:read
   - groups:read
   - im:read
   - mpim:read
9. Copy Bot Token (save as SLACK_BOT_TOKEN)
10. Install to workspace
```

#### 2. Configure OpenClaw

```yaml
channels:
  slack:
    # Using Socket Mode (recommended, no webhooks)
    appToken: "${SLACK_APP_TOKEN}"
    botToken: "${SLACK_BOT_TOKEN}"
    
    accounts:
      default:
        # Channel allowlist
        allowedChannels:
          - "#general"
          - "#ai-agent"
        
        # User allowlist (optional)
        allowedUserIds: []
    
    messages:
      groupChat:
        historyLimit: 10
        visibleReplies: "automatic"  # Thread replies
      directMessage:
        visibleReplies: "automatic"
```

#### 3. Test

```bash
# Send message mentioning bot in Slack
# @OpenClaw your question

# Or DM bot directly
```

### WhatsApp Setup

#### 1. Baileys Configuration (Web-based)

```yaml
channels:
  whatsapp:
    # Web-based WhatsApp via Baileys
    accounts:
      default:
        # Phone number in E.164 format
        phoneNumber: "+1234567890"
        
        # First run: opens QR code for scanning
        # Subsequent runs: uses saved auth
    
    messages:
      groupChat:
        historyLimit: 5
      directMessage:
        historyLimit: 5
    
    # WebSocket timing
    timing:
      connectionRetryMs: 5000
      qrCodeTimeoutMs: 60000
```

#### 2. First Run (Scan QR Code)

```bash
# Start OpenClaw with WhatsApp enabled
pnpm gateway:watch

# On first run:
# 1. QR code appears in terminal or Control UI
# 2. Scan with WhatsApp camera (3 dots → Linked devices)
# 3. Confirm pairing
# 4. Auth saved to ~/.openclaw/credentials/

# Subsequent runs use saved auth
```

#### 3. Test

```bash
# Send WhatsApp message to bot number
# Bot responds within 10-15 seconds (slower than Telegram/Discord)
```

### Multiple Channels

```yaml
channels:
  discord:
    token: "${DISCORD_BOT_TOKEN}"
    accounts:
      default: {}
  
  telegram:
    token: "${TELEGRAM_BOT_TOKEN}"
    accounts:
      default: {}
  
  slack:
    appToken: "${SLACK_APP_TOKEN}"
    botToken: "${SLACK_BOT_TOKEN}"
    accounts:
      default: {}
  
  whatsapp:
    accounts:
      default:
        phoneNumber: "+1234567890"

# Route different agents to different channels
# Or use broadcast groups to respond on all channels
```

---

## Agent Configuration

### 1. Create First Agent

```yaml
agents:
  # Define agents
  list:
    - id: "default"
      name: "Default Assistant"
      description: "My personal AI assistant"
      
      # Model configuration
      model: "openai/gpt-4"
      thinking: "off"  # or "inline", "extended" for reasoning
      
      # Channel access
      channels:
        - id: "discord"
          accountId: "default"
        - id: "telegram"
          accountId: "default"
      
      # Tool policies
      toolPolicies:
        profile: "default"       # Predefined profile
        alsoAllow:
          - "memory_search"
          - "browser"
      
      # Memory & context
      memorySearch: true
      startupContext:
        maxFileBytes: 16384
        maxFileChars: 100000

  defaults:
    # Global defaults for all agents
    model: "openai/gpt-4"
    
    # Model failover
    modelFailover:
      maxAttempts: 2
      backoffMs: 1000
    
    # Sub-agents
    subagents:
      allowAgents: []  # Empty = allow all
      runTimeoutSeconds: 300
    
    # Bootstrap files
    bootstrapTotalMaxChars: 60000
```

### 2. Create Agent Workspace

```bash
# Create agent directory
mkdir -p ~/.openclaw/agents/default/agent
mkdir -p ~/.openclaw/agents/default/workspace
mkdir -p ~/.openclaw/agents/default/sessions

# Create core files
cd ~/.openclaw/agents/default/agent
```

#### AGENTS.md (Multi-agent definitions)

```markdown
# Available Agents

## default
- **Purpose**: Personal AI assistant
- **Channels**: Discord, Telegram
- **Model**: GPT-4
- **Tools**: Memory search, browser control
- **Sub-agents**: analyst, developer

## developer
- **Purpose**: Technical problem-solving
- **Parent agent**: default
- **Model**: GPT-4
- **Tools**: Code execution, GitHub API

## analyst
- **Purpose**: Data analysis
- **Parent agent**: default
- **Model**: GPT-4
- **Tools**: Python execution, file processing
```

#### TOOLS.md (Available tools)

```markdown
# Available Tools

## Messages (Channel Communication)
- `message(text, mentions)` - Send message to current channel
- `reactions(emoji, action)` - Add/remove reactions

## Memory
- `memory_search(query, limit)` - Search MEMORY.md and memory/*.md
- `memory_get(path)` - Read specific memory file
- `memory_update(path, content)` - Write/append to memory

## Sessions (Multi-Agent)
- `sessions_spawn(agentId, prompt, sandbox)` - Delegate to sub-agent
- `sessions_send(sessionKey, message)` - Cross-session messaging
- `sessions_list(scope)` - List sessions

## Browser (Web Automation)
- `browser_navigate(url)` - Open URL
- `browser_screenshot()` - Take screenshot
- `browser_type(selector, text)` - Type text

## Utilities
- `tasks_schedule(cron, prompt)` - Schedule cron job
- `config_schema_lookup(path)` - Query config schema
```

#### MEMORY.md (Long-term memory)

```markdown
# Long-Term Memory

## Personal Info
- Name: Your Name
- Timezone: America/New_York
- Occupation: Software Engineer

## Project Context
- **Current Project**: Enterprise AI Agent Lab
- **Tech Stack**: Node.js, TypeScript, OpenClaw
- **Status**: In development

## Goals
1. Build autonomous AI agent system
2. Connect multiple channels (Discord, Telegram, Slack)
3. Implement multi-agent delegation

## Important Contacts
- Tech Lead: john@example.com
- Project Manager: jane@example.com

---

## Recent Decisions
- Using OpenClaw for agent framework (vs LangChain)
- Deploy on VPS with Tailscale for security
- WhatsApp as primary channel

---

## Daily Memory
- See memory/2024-01-*.md for daily notes
```

#### Workspace README.md (Project context)

```markdown
# My Project

## Overview
This is my AI agent lab for building autonomous assistants.

## Structure
```
├── src/
│   ├── agents/
│   └── tools/
├── docs/
└── config/
```

## Key Files
- `/docs/API.md` - API reference
- `/docs/ARCHITECTURE.md` - System design
- `/config/agents.yml` - Agent configuration

## Running Locally
```bash
pnpm install
pnpm dev
```
```

### 3. Memory Files Setup

```bash
# Create daily memory
mkdir -p ~/.openclaw/agents/default/agent/memory

# Create today's file
date_str=$(date +%Y-%m-%d)
cat > ~/.openclaw/agents/default/agent/memory/${date_str}.md << 'EOF'
# Daily Notes - $(date +%Y-%m-%d)

## Tasks
- [ ] Setup Discord bot
- [ ] Configure memory system
- [ ] Test multi-agent delegation

## Learnings
- OpenClaw uses session-based routing
- Multi-agent delegation via sessions_spawn

## Next Steps
- Deploy to VPS
- Add Telegram channel
EOF
```

### 4. Test Agent

```bash
# Start gateway
pnpm gateway:watch

# Send test message on Discord or Telegram
# Agent should respond with memory search and tools available

# Check logs for any issues
tail -f ~/.openclaw/logs/gateway.log | grep "agent\|default"
```

---

## Advanced Scenarios

### Multi-Agent Orchestration

```yaml
agents:
  list:
    - id: "coordinator"
      name: "Main Agent"
      description: "Orchestrates sub-agents"
      model: "openai/gpt-4"
      channels:
        - id: "discord"
    
    - id: "developer"
      name: "Developer Agent"
      description: "Handles coding tasks"
      model: "openai/gpt-4-turbo"
      # No channels - only accessible via delegation
    
    - id: "analyst"
      name: "Analyst Agent"
      description: "Data analysis tasks"
      model: "openai/gpt-4"

  defaults:
    subagents:
      allowAgents: ["developer", "analyst"]  # Coordinator can spawn these
```

**AGENTS.md**:
```markdown
# Coordinator (Main Agent)

When faced with:
- **Coding tasks**: Delegate to `developer` agent
- **Data analysis**: Delegate to `analyst` agent
- **General questions**: Respond directly

Example sub-agent spawn:
```typescript
{
  "name": "sessions_spawn",
  "input": {
    "agentId": "developer",
    "prompt": "Analyze this code and suggest improvements:\n\n```python\ncode_here\n```",
    "sandbox": "inherit"
  }
}
```
```

### Scheduled Tasks (Cron)

```yaml
automation:
  cron:
    tasks:
      - id: "daily-summary"
        schedule: "0 9 * * *"  # 9 AM daily
        agentId: "default"
        prompt: "Generate a daily summary of all conversations from yesterday"
        # Sends result to default channel
      
      - id: "weekly-report"
        schedule: "0 9 * * 1"  # Mondays 9 AM
        agentId: "analyst"
        prompt: "Create weekly metrics report"
        targets:
          - channel: "discord"
            thread: "reports"
```

### Broadcast Groups (Multi-Channel)

```yaml
channels:
  broadcastGroups:
    - id: "all-agents"
      agents: ["default", "analyst", "developer"]
      # Single message routes to all agents
      # Each agent responds independently
      
    - id: "tech-team"
      agents: ["developer", "analyst"]
      channels:
        - "discord"
        - "slack"
      # Technical questions go to both agents
```

### Approval Gates

```yaml
approvals:
  enabled: true
  requireFor:
    - "browser"  # Require approval for browser automation
    - "exec"     # Require approval for code execution
  
  exec:
    # Tool-specific approval rules
    targets:
      - toolName: "browser"
        mode: "approve_once"  # Approve once per conversation
      - toolName: "exec"
        mode: "each_call"     # Approve each execution
```

### Sandbox Constraints

```yaml
sandbox:
  enabled: true
  
  # Default sandbox for all agents
  defaults:
    mode: "strict"  # or "permissive"
    
    # Network policies
    network:
      allowUrls:
        - "https://api.github.com"
        - "https://*.example.com"
      denyUrls: []
    
    # Filesystem policies
    filesystem:
      allowPaths:
        - "~/.openclaw/agents/*/workspace"
      denyPaths:
        - "/etc"
        - "/proc"
```

---

## Troubleshooting

### Agent Not Responding

**Check gateway logs**:
```bash
tail -f ~/.openclaw/logs/gateway.log
```

**Look for**:
- `ERROR` messages
- Channel connection issues
- Model API failures
- Tool execution errors

### Session Listing & Debugging

```bash
# List all sessions
openclaw sessions list

# View specific session
openclaw sessions view <sessionId>

# Inspect session transcript
openclaw sessions transcript <sessionId> --json
```

### Memory System Issues

```bash
# Force memory refresh
openclaw memory qmd update --force

# Check memory index
openclaw memory qmd status

# View memory files
ls -la ~/.openclaw/agents/default/agent/memory/
```

### Channel Connection Issues

#### Discord
- Verify bot token in config
- Check "Message Content Intent" is enabled
- Ensure bot has permissions in channel
- Check firewall/network access

```bash
# Test Discord connectivity
curl -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
  https://discord.com/api/v10/users/@me
```

#### Telegram
```bash
# Test Telegram bot token
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"

# Get chat ID
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
```

#### Slack
```bash
# Test Slack bot token
curl -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
  https://slack.com/api/auth.test
```

### Performance Tuning

```yaml
agents:
  defaults:
    # Reduce context for faster responses
    bootstrapTotalMaxChars: 30000
    memorySearch: false  # Disable if memory search is slow
    
    # Model settings
    model: "openai/gpt-3.5-turbo"  # Use faster model
    thinking: "off"  # Disable extended thinking

gateway:
  # Message queue settings
  queue:
    maxQueuedPerSession: 10
    processingTimeoutMs: 30000  # 30 second timeout
```

### Resource Monitoring

```bash
# Check process resource usage
ps aux | grep gateway

# Monitor memory
watch -n 1 'ps aux | grep gateway'

# Check disk usage
du -sh ~/.openclaw/
ls -lh ~/.openclaw/logs/gateway.log

# Rotate large logs
gzip ~/.openclaw/logs/gateway.log.*
```

---

## Environment Variable Reference

```bash
# LLM API Keys
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GOOGLE_API_KEY="..."

# Channel Tokens
export DISCORD_BOT_TOKEN="MTA..."
export TELEGRAM_BOT_TOKEN="123456:ABC..."
export SLACK_BOT_TOKEN="xoxb-..."
export SLACK_APP_TOKEN="xapp-..."

# OpenClaw Configuration
export OPENCLAW_WORKSPACE="~/.openclaw"
export OPENCLAW_LOG_FLAGS="*"
export OPENCLAW_GATEWAY_WATCH_AUTO_DOCTOR=1
export OPENCLAW_UPDATE_IN_PROGRESS=0

# Optional: Development
export DEBUG="openclaw:*"
export NODE_ENV="development"
```

---

## Production Deployment Checklist

- [ ] Use strong authentication (`auth.mode: "token"` or "trusted-proxy")
- [ ] Configure TLS/HTTPS for remote access
- [ ] Use Tailscale or VPN for private network access
- [ ] Enable audit logging and monitoring
- [ ] Set appropriate resource limits
- [ ] Configure regular backups of `~/.openclaw/agents/*/sessions/`
- [ ] Monitor disk usage (logs and session history grow over time)
- [ ] Rotate API keys regularly
- [ ] Test failover/recovery procedures
- [ ] Document agent configurations and workflows
- [ ] Set up alerts for gateway crashes or offline status

