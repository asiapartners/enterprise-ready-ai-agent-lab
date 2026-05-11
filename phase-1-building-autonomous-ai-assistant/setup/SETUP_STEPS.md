# Phase 1 Setup Steps - Detailed Installation Guide

## Prerequisites Checklist

Before you start, ensure you have:

- [ ] Permissions to deploy a Windows Azure VM
  - [ ] VM Specs
  - [ ] Outbound internet connectivity
- [ ] Azure OpenAI credentials:
  - [ ] Azure subscription with OpenAI resource
  - [ ] API key and endpoint from Azure portal

## Step 1: Install OpenClaw

```bash
# Install latest stable version
npm install -g openclaw@latest

# Verify installation
openclaw --version
```
---

## Step 2: Run Onboarding

The interactive onboarding guide will:
- Create `~/.openclaw/` directory structure
- Prompt for LLM configuration
- Optionally set up Microsoft Teams channel
- Set up the daemon service

```bash
# Start onboarding
openclaw onboard --install-daemon

# Follow the prompts for:
# 1. Choose LLM provider (Azure OpenAI recommended)
# 2. Enter API key
# 3. Choose to configure Microsoft Teams (optional)
# 4. Set channel tokens
# 5. Install daemon (yes recommended)
```

---

## Step 3: Verify Installation

After onboarding, verify everything is working:

```bash
# Check configuration is valid
openclaw doctor

# You should see:
# ✓ Configuration loaded
# ✓ Gateway can start
# ✓ Workspace directory exists
```

---

## Step 4: Understand Directory Structure

OpenClaw creates the following structure:

```
~/.openclaw/                      # Config root
├── openclaw.json                 # Main configuration
├── workspace/                    # Agent workspace
│   ├── AGENTS.md                 # Agent definitions
│   ├── SOUL.md                   # Agent soul/values
│   ├── TOOLS.md                  # Tools registry
│   ├── MEMORY.md                 # Long-term memory
│   ├── skills/                   # Skills directory
│   │   └── <skill-name>/
│   │       └── SKILL.md
│   └── sessions/                 # Session data (auto-created)
├── data/                         # Data storage
├── logs/                         # Log files
└── cache/                        # Cache directory
```

---

## Step 5: Configure Your Agent

### 5.1 Edit Main Configuration

Open `~/.openclaw/openclaw.json`:

```bash
# Windows (PowerShell)
notepad $env:USERPROFILE\.openclaw\openclaw.json
```

**Minimal Configuration:**

```json5
{
  // LLM Configuration
  agents: {
    defaults: {
      model: "azure/gpt-4",             // Azure OpenAI deployment
      temperature: 0.7,                // 0.0 (deterministic) to 1.0 (creative)
      maxTokens: 4096,
    }
  },
  
  // Gateway settings
  gateway: {
    port: 18789,
    verbose: true,
  },
  
  // Optional: Model failover
  modelFailover: [
    "openai/gpt-4o",
    "anthropic/claude-3-5-sonnet",
    "openai/gpt-4-turbo",
  ],
}
```

### 5.2 Set Environment Variables

Set your Azure OpenAI credentials in environment:

```bash
# Azure OpenAI
export AZURE_OPENAI_API_KEY="your-key-here"
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="gpt-4"  # Your deployment name

# Make permanent (add to ~/.bashrc or ~/.zshrc)
echo 'export AZURE_OPENAI_API_KEY="your-key-here"' >> ~/.bashrc
echo 'export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"' >> ~/.bashrc
echo 'export AZURE_OPENAI_DEPLOYMENT="gpt-4"' >> ~/.bashrc
source ~/.bashrc
```

---

## Step 6: Initialize Workspace

Create the agent workspace:

```bash
openclaw setup
```

This creates:
- `~/.openclaw/workspace/AGENTS.md`
- `~/.openclaw/workspace/SOUL.md`
- `~/.openclaw/workspace/TOOLS.md`
- `~/.openclaw/workspace/MEMORY.md`

---

## Step 7: Define Your Agent

### 7.1 Create Agent Instructions

Edit `~/.openclaw/workspace/AGENTS.md`:

```markdown
# agent:main

**Description**: Main autonomous AI assistant

**Instructions**:
- You are a helpful, curious AI assistant
- You think step-by-step before taking action
- You provide concise but thorough responses
- You ask clarifying questions when needed
- You remember context across conversations

**Personality**:
- Friendly but professional
- Detail-oriented
- Proactive in offering help
- Respectful of user preferences

**Tools Access**:
- read: File reading
- write: File writing
- bash: System commands
- browser: Web access
```

### 7.2 Define Agent Soul (Optional)

Edit `~/.openclaw/workspace/SOUL.md`:

```markdown
# Core Values

## Autonomy
I take initiative and make decisions within my defined perimeter.

## Transparency
I explain my reasoning when taking actions.

## Reliability
I complete tasks thoroughly and inform you of progress.

## Respect
I honor your preferences and maintain privacy.

## Learning
I improve over time and adapt to your needs.
```

---

## Step 8: First Test

### Test 1: Simple Chat

```bash
openclaw agent --message "Hello! Who are you?"
```

**Expected output:**
```
🤖 Agent response:
I'm your autonomous AI assistant. I'm here to help you with...
```

### Test 2: File Operations

```bash
openclaw agent --message "Create a file called 'test.txt' with the content 'Hello World'"
```

### Test 3: Information Retrieval

```bash
openclaw agent --message "What is the current time?"
```

### Test 4: Multi-step Task

```bash
openclaw agent --message "Search for the latest OpenClaw releases and summarize the features"
```

---

## Step 9: Run the Gateway

The Gateway is the central service that:
- Routes messages from channels
- Manages sessions
- Coordinates tool execution
- Handles auth and security

### Start the Gateway

```bash
# Foreground (useful for debugging)
openclaw gateway --port 18789 --verbose

# Or use daemon (if installed with --install-daemon)
# It runs as a background service
```

### Verify Gateway is Running

```bash
# In another terminal
curl http://localhost:18789/health

# Should return: {"status":"ok"}
```

---

## Step 10: Set Up Your First Channel (Optional)

### Microsoft Teams (Recommended for Phase 1)

1. **Create Azure Bot Service**
   - Go to https://portal.azure.com
   - Create a new "Bot Service" resource
   - Fill in required fields (name, subscription, resource group, location)
   - Wait for deployment

2. **Get Credentials**
   - In Bot Service → Settings → Configuration
   - Copy your **Microsoft App ID** and **Client Secret**
   - Save temporarily (treat like passwords)

3. **Configure in `openclaw.json`**
   ```json5
   channels: {
     teams: {
       enabled: true,
       botId: "your_microsoft_app_id",
       botPassword: "your_client_secret",
     }
   }
   ```

4. **Install Bot in Teams**
   - Go to Bot Service → Channels
   - Click "Configure Microsoft Teams Channel"
   - Accept terms and save
   - Click on Teams channel link to install

5. **Test**
   - Search for your bot in Teams
   - Send message: "Hello!"
   - Agent should respond

**For detailed setup**: See [TEAMS_SETUP.md](./TEAMS_SETUP.md)

---

## Troubleshooting

### Issue: "openclaw: command not found"

```bash
# Solution: Ensure npm global path is in PATH
npm config get prefix

# Add to ~/.bashrc or ~/.zshrc:
export PATH="$(npm config get prefix)/bin:$PATH"
```

### Issue: API Key Not Found

```bash
# Solution: Verify environment variable
echo $OPENAI_API_KEY  # Should not be empty

# If empty, set it:
export OPENAI_API_KEY="sk-..."
```

### Issue: Port 18789 Already in Use

```bash
# Use different port
openclaw gateway --port 18790 --verbose

# Or find process using port 18789:
lsof -i :18789
kill -9 <PID>
```

### Issue: "Cannot find AGENTS.md"

```bash
# Solution: Run setup
openclaw setup

# Or manually create:
mkdir -p ~/.openclaw/workspace
touch ~/.openclaw/workspace/AGENTS.md
```

---

## Next Steps

1. **Customize Agent Personality** → Edit `AGENTS.md` and `SOUL.md`
2. **Add Skills** → Create skills in `~/.openclaw/workspace/skills/`
3. **Configure Tools** → Modify tool policies in `openclaw.json`
4. **Set Up Microsoft Teams** → Follow [TEAMS_SETUP.md](./TEAMS_SETUP.md)
5. **Create Memory** → Add facts to `MEMORY.md`

---

## Useful Commands

```bash
# Run a single agent message
openclaw agent --message "Your question here"

# With thinking enabled
openclaw agent --message "Why is the sky blue?" --thinking high

# Start interactive REPL
openclaw repl

# Run the gateway (central service)
openclaw gateway --port 18789 --verbose

# Check system status
openclaw doctor

# Update to latest version
openclaw update

# List installed skills
openclaw skills list

# View logs
openclaw logs tail
```

---

## Success Indicators

✅ Phase 1 Setup is complete when:

- [ ] `openclaw --version` returns a version
- [ ] `openclaw doctor` shows all checks passing
- [ ] `openclaw agent --message "Hi"` returns a response
- [ ] `~/.openclaw/workspace/` contains AGENTS.md and SOUL.md
- [ ] Gateway starts without errors: `openclaw gateway --port 18789`
- [ ] (Optional) Teams bot responds to messages

---

**Ready for Module 3? Move to [AGENT_PERSONALITY.md](./AGENT_PERSONALITY.md)**


# OpenClaw Setup & Configuration Guide

## Table of Contents

1. [Installation](#installation)\
1. [Channel Setup](#channel-setup)
1. [Agent Configuration](#agent-configuration)
1. [Advanced Scenarios](#advanced-scenarios)
1. [Troubleshooting](#troubleshooting)

---

## Installation

### Prerequisites

- **Node.js**: [MSI Install here](https://nodejs.org/en/download)
- **Disk Space**: 500MB minimum, 2GB+ recommended
- **Memory**: 1GB RAM minimum, 2GB+ recommended
- **Network**: Internet for LLM API calls; local network or VPN for Gateway access

#### Windows Installation

```bash
# Install OpenClaw via npm
npm install -g openclaw@latest

# Run the OpenClaw onboarding process
openclaw onboard --install-daemon

```
---

## Channel Setup

### Microsoft Teams
```bash
# Install OpenClaw via npm
npm install -g openclaw@latest

# Run the OpenClaw onboarding process
openclaw onboard --install-daemon

# Install the Teams Toolkit CLI 
npm install -g @microsoft/teams.cli@preview
teams login
teams app create --name "OpenClaw" --endpoint "https://<your-tunnel-url>/api/messages"
teams app get <teamsAppId> --install-link

# Install DevTunnels
Invoke-WebRequest -Uri https://aka.ms/TunnelsCliDownload/win-x64 -OutFile devtunnel.exe
.\devtunnel user login
.\devtunnel create app-openclaw --allow-anonymous
.\devtunnel port create app-openclaw -p 3978 --protocol auto
.\devtunnel host app-openclaw

```