# OpenClaw Setup & Configuration Guide

A reference for installing and configuring OpenClaw. For lab-specific setup instructions, see the README in each phase folder.

---

## Installation

### Prerequisites

- **Node.js**: 22.x (LTS recommended)
- **pnpm**: `npm install -g pnpm`
- **Disk Space**: 500MB minimum, 2GB+ recommended
- **Memory**: 1GB RAM minimum, 2GB+ recommended

### macOS

```bash
# Using Homebrew
brew tap openclaw/tap
brew install openclaw

# Or from source
git clone https://github.com/openclaw/openclaw.git
cd openclaw && pnpm install && pnpm openclaw setup
pnpm gateway:watch
```

### Linux / VPS

```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw
pnpm install
pnpm openclaw setup
pnpm gateway:watch
```

### Docker

```bash
docker run -d \
  -p 18789:18789 \
  -v ~/.openclaw:/root/.openclaw \
  -e OPENAI_API_KEY=$OPENAI_API_KEY \
  openclaw:latest
```

---

## Initial Configuration

### Workspace Structure

After `pnpm openclaw setup`:

```
~/.openclaw/
├── config.yml          ← main configuration
├── credentials/        ← channel & provider secrets
├── agents/             ← per-agent state
├── logs/               ← gateway logs
└── skills/             ← installed skills
```

### Model Provider Configuration

#### Azure OpenAI (recommended for enterprise)

```yaml
agents:
  defaults:
    model: "azure/gpt-4o"

providers:
  azure:
    apiKey: "${AZURE_OPENAI_API_KEY}"
    endpoint: "${AZURE_OPENAI_ENDPOINT}"
```

#### Anthropic Claude

```yaml
agents:
  defaults:
    model: "anthropic/claude-opus"

providers:
  anthropic:
    apiKey: "${ANTHROPIC_API_KEY}"
```

#### OpenAI

```yaml
agents:
  defaults:
    model: "openai/gpt-4"

providers:
  openai:
    apiKey: "${OPENAI_API_KEY}"
```

#### Local Models (Ollama)

```yaml
agents:
  defaults:
    model: "ollama/llama3"

providers:
  ollama:
    baseUrl: "http://localhost:11434"
```

---

## Channel Setup

### Discord

1. Go to https://discord.com/developers/applications → New Application → Bot → Add Bot
2. Copy token, enable **Message Content Intent**
3. Generate invite URL with: Send Messages, Read Message History, Add Reactions

```yaml
channels:
  discord:
    token: "${DISCORD_BOT_TOKEN}"
    accounts:
      default: {}
    messages:
      groupChat:
        historyLimit: 10
        requireMention: false
```

Test: `curl -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" https://discord.com/api/v10/users/@me`

### Telegram

1. Search @BotFather on Telegram → `/newbot` → copy token

```yaml
channels:
  telegram:
    token: "${TELEGRAM_BOT_TOKEN}"
    accounts:
      default:
        allowedUserIds: ["YOUR_USER_ID"]
```

Test: `curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"`

### Slack

1. https://api.slack.com/apps → Create → Socket Mode → Enable → generate App-Level Token
2. OAuth & Permissions: add scopes `chat:write`, `channels:read`, `im:read`

```yaml
channels:
  slack:
    appToken: "${SLACK_APP_TOKEN}"
    botToken: "${SLACK_BOT_TOKEN}"
    accounts:
      default: {}
```

### Microsoft Teams

→ Covered in [Phase 2: Tool Integration & Capability Perimeters](./phase-2-tool-integration-capability-perimeters/README.md)  
→ Uses the `openclaw-a365` plugin with Bot Framework

---

## Agent Configuration

### Agent Definition

```yaml
agents:
  list:
    - id: "default"
      name: "My AI Agent"
      description: "Personal assistant"
      model: "anthropic/claude-opus"
      channels:
        - id: "discord"
          accountId: "default"
      toolPolicies:
        profile: "default"
        alsoAllow: ["memory_search"]
      memorySearch: true
```

### Per-Agent Files

```
~/.openclaw/agents/default/agent/
├── AGENTS.md     ← multi-agent routing definitions
├── TOOLS.md      ← available tools reference
└── MEMORY.md     ← long-term memory
```

---

## Gateway Startup

```bash
# Development (watch mode)
pnpm gateway:watch

# Production
pnpm gateway:start

# Verify
curl http://localhost:18789/health
```

---

## Security Configuration

```yaml
gateway:
  auth:
    mode: "token"               # none | token | password | trusted-proxy
    token: "${GATEWAY_TOKEN}"
  bind:
    mode: "loopback"            # loopback | lan | tailnet | custom
    port: 18789
```

---

## Troubleshooting

**Agent not responding**: Check `tail -f ~/.openclaw/logs/gateway.log`

**Channel connection issues**:
```bash
# Discord
curl -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" https://discord.com/api/v10/users/@me

# Telegram
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
```

**Session debugging**:
```bash
openclaw sessions list
openclaw sessions view <sessionId>
```

---

## Environment Variables Reference

```bash
# LLM providers
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
AZURE_OPENAI_API_KEY=...
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/

# Channels
DISCORD_BOT_TOKEN=MTA...
TELEGRAM_BOT_TOKEN=123456:ABC...
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...

# OpenClaw
OPENCLAW_WORKSPACE=~/.openclaw
```
