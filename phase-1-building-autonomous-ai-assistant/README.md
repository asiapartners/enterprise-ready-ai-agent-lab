# Phase 1: Building Your Autonomous AI Assistant

## Overview

In Phase 1, you will build a **foundational autonomous AI assistant** deployed on user-managed hardware.

---

## Learning Objectives

By the end of Phase 1, you will:

1. **Understand autonomous AI agent architecture** - Learn how agents are structured, how they coordinate tools, and how they maintain state
2. **Set up a local AI assistant** - Install and configure OpenClaw on your machine
3. **Create agent personality and capabilities** - Define your agent's skills, instructions, and tool access
4. **Connect communication channels** - Integrate with Microsoft Teams to interact with your agent

---

## Autonomous Agent Architecture

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
---

## Phase 1 Setup Steps - Detailed Installation Guide

### Prerequisites

Before you start, ensure you have:

- [ ] [az cli](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows?view=azure-cli-latest) installed 
- [ ] [Microsoft 365 Agents Toolkit](https://learn.microsoft.com/en-us/microsoftteams/platform/toolkit/install-agents-toolkit?tabs=vscode) installed
- [ ] Permissions to deploy Azure resources 
  - [ ] A Windows 11 Azure VM (D4s v5)
  - [ ] Configure outbound internet connectivity (NAT Gateway, public IP)
  - [ ] RDP connectivity (Remote Desktop or Azure Bastion)
  - [ ] An Azure OpenAI resource



### Step 1: Deploy Windows Virtual Machine in Azure

Create a Windows VM to host the OpenClaw agent:

```powershell
# Set variables
$resourceGroup = "openclaw-rg"
$location = "eastus2"
$vnetName = "openclaw-vnet"
$subnetName = "openclaw-subnet"
$vmName = "openclaw-vm"
$vmSize = "Standard_D4s_v5"
$imageName = "MicrosoftWindowsDesktop:windows-11:win11-25h2-pro:latest"

# Login to your Azure subscription
# az login

# Create resource group
az group create --name $resourceGroup --location $location

# Create Virtual Network
az network vnet create `
  --resource-group $resourceGroup `
  --name $vnetName `
  --address-prefix 10.0.0.0/16 `
  --subnet-name $subnetName `
  --subnet-prefix 10.0.1.0/24

# Create Network Security Group
$nsgName = "openclaw-nsg"
az network nsg create `
  --resource-group $resourceGroup `
  --name $nsgName

# Add RDP rule to NSG
az network nsg rule create `
  --resource-group $resourceGroup `
  --nsg-name $nsgName `
  --name allow-rdp `
  --priority 1000 `
  --source-address-prefixes '*' `
  --source-port-ranges '*' `
  --destination-address-prefixes '*' `
  --destination-port-ranges 3389 `
  --access Allow `
  --protocol Tcp

# Create Windows VM
az vm create `
  --resource-group $resourceGroup `
  --name $vmName `
  --image $imageName `
  --size $vmSize `
  --admin-username azureuser `
  --admin-password YourSecurePassword123! `
  --public-ip-sku Standard `
  --output json

# Get VM public IP
$publicIp = az vm show --resource-group $resourceGroup --name $vmName --show-details --query publicIps -o tsv

# Open RDP port (3389)
# az vm open-port --resource-group $resourceGroup --name $vmName --port 3389 --priority 1001

# Connect via RDP
mstsc /v:$publicIp
```

**VM Details:**
- **Image:** Windows 11 Pro 25H2 (`MicrosoftWindowsDesktop:windows-11:win11-25h2-pro:latest`)
- **Size:** Standard_D4s_v5 (4 vCPUs, 16 GB RAM)
- **Location:** East US 2 (adjust as needed; check SKU availability with `az vm list-skus --location <region> --size Standard_D4s_v5`)
- **Note:** Change the admin password to a secure value before deploying

---

### Step 2: Deploy Azure OpenAI Resource

Deploy an Azure OpenAI resource:

```powershell
# Set variables
$resourceGroup = "openclaw-rg"
$openaiName = "openclaw-openai"
$location = "eastus2"
$skuName = "S0"

# Create Azure OpenAI resource
az cognitiveservices account create `
  --name $openaiName `
  --resource-group $resourceGroup `
  --kind OpenAI `
  --sku $skuName `
  --location $location `
  --yes

# Get the API key and endpoint
$apiKey = az cognitiveservices account keys list --name $openaiName --resource-group $resourceGroup --query key1 -o tsv
$endpoint = az cognitiveservices account show --name $openaiName --resource-group $resourceGroup --query properties.endpoint -o tsv

# Display credentials for later use
Write-Host "API Key: $apiKey"
Write-Host "Endpoint: $endpoint"
```

**Deploy a Model:**

```powershell
# Deploy GPT-5.4-mini model (generally available in eastus2)
az cognitiveservices account deployment create `
  --name $openaiName `
  --resource-group $resourceGroup `
  --deployment-name "gpt-5.4-mini" `
  --model-name "gpt-5.4-mini" `
  --model-version "2026-03-17" `
  --model-format "OpenAI" `
  --sku-name "GlobalStandard" `
  --sku-capacity 10
```

**Azure OpenAI Details:**
- **Location:** East US 2 (same as VM for optimal latency)
- **SKU:** Standard S0 (pay-as-you-go pricing)
- **Models:** Deploy GPT-5.4-mini (generally available in eastus2)
- **Note:** Save the API key and endpoint for configuration in Step 5

---

### Step 3: (In Azure VM) Install Node.js

From the remote VM, download and install Node.js from the official website:

1. Visit https://nodejs.org/
2. Download the **LTS (Long Term Support)** version MSI installer for Windows
3. Run the MSI installer and follow the installation wizard
4. Accept the default settings (includes npm)
5. Verify installation:

```bash
# Check Node.js version
node --version

# Check npm version
npm --version
```

---

### Step 3: (In Azure VM) Install OpenClaw
Install OpenClaw via npm:

```bash
# Install latest stable version
npm install -g openclaw@latest

# Verify installation
openclaw --version
```
---

### Step 4: (In Azure VM) Run Onboarding

The interactive onboarding guide will:
- Create the `~/.openclaw/` directory structure
- Prompt for LLM configuration
- Optionally set up Microsoft Teams channel
- Set up the daemon service

```bash
# Start onboarding
openclaw onboard --install-daemon

# I understand this is personal-by-default and shared/multi-user use requires lock-down. Continue?
  # Yes

# Setup mode
  # QuickStart (recommended)

# Model/auth provider
  # More... >> Custom Provider

# API Base URL
  # (Paste the Endpoint from Step 2)

# How do you want to provide this API key?
  # Paste API key now
  
# API Key (leave blank if not required)
  # (Paste the API Key from Step 2)

# Endpoint compatibility
  # OpenAI-compatible

# Model ID
  # gpt-5.4-mini

# Endpoint ID
  # (Accept default)

# Model alias (optional)
  # gpt-5.4-mini

# Select channel (QuickStart)
  # Microsoft Teams (Teams SDK)

# Configure MS Teams channels access?
  # No


```

---

### Step 5: Verify Installation

After onboarding, verify everything is working:

```bash
# Check configuration is valid
openclaw doctor

# You should see:
# ✓ Configuration loaded
# ✓ Gateway can start
# ✓ Workspace directory exists
```
### (Optional): Review  Directory Structure

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