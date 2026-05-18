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

### Step 4: (In Azure VM) Install OpenClaw
Install OpenClaw via npm:

```bash
# Install latest stable version
npm install -g openclaw@latest

# Verify installation
openclaw --version
```
---

### Step 5: (In Azure VM) Install Dev Tunnels
Download and install Dev Tunnels, which will be used to expose OpenClaw's messaging endpoint to Microsoft Teams:

```bash
# Download and Install Dev Tunnels
Invoke-WebRequest -Uri https://aka.ms/TunnelsCliDownload/win-x64 -OutFile devtunnel.exe

# Login to Dev Tunnels
.\devtunnel user login
# Create a tunnel named bot-openclaw with anonymous access
.\devtunnel create bot-openclaw --allow-anonymous

# Create a port forwarding for port 3978 with automatic protocol detection
.\devtunnel port create bot-openclaw -p 3978 --protocol auto

# Start hosting the tunnel
.\devtunnel host bot-openclaw

# Note the URL in the output and retain it for the next step
  # Connect via browser: TEAMS_MESSAGING_TUNNEL_URL
```
---

### Step 6: Set Up Teams App using Microsoft 365 Agents Toolkit


```bash
# Install Microsoft 365 Agents Toolkit
npm install -g @microsoft/teams.cli@preview

# Login to Microsoft 365
teams login

# Create Teams app with OpenClaw name and messaging endpoint
teams app create --name "OpenClaw" --endpoint "https://TEAMS_MESSAGING_TUNNEL_URL/api/messages"

# Save the outputs below somewhere for later use 
  # CLIENT_ID=<YOUR_CLIENT_ID>
  # CLIENT_SECRET=<YOUR_CLIENT_SECRET>
  # TENANT_ID=<YOUR_TENANT_ID>

# Open the output link below in your browser to install the Teams app 
  # Install in Teams → https://teams.microsoft.com/l/app/....
```

---

### Step 7: (In Azure VM) Run OpenClaw Onboarding

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

# Enter MS Teams App ID
  # (Paste the CLIENT_ID from Step 6)

# Enter MS Teams App Password
  # (Paste the CLIENT_SECRET from Step 6)

# Enter MS Teams Tenant ID
  # (Paste the TENANT_ID from Step 6)

# Enable delegated auth? (required for reactions and write operations)
  # No

# Search provider
  # DuckDuckGo Search (experimental)

# Configure skills now? (recommended)
  # No

# Enable hooks?
  # Skip for now

# How do you want to hatch your agent?
  # Hatch in Browser
```

---

### Step 8: (In Azure VM) Set up MS Teams pairing

Once OpenClaw is up and running, you will need to grant pairing access to the Teams user before responses can be sent back. This seems to be a bug and may be fixed in future releases.

First, send a message in Teams, and then run the following commands:

```bash
# List all pending pairing requests from MS Teams
openclaw pairing list msteams 

# Approve the pairing request using the pairing code received
openclaw pairing approve msteams PAIRING_CODE
```

---

### Step 9: Verify Installation

After onboarding, verify everything is working:

```bash
# Check configuration is valid
openclaw doctor

# You should see:
# ✓ Configuration loaded
# ✓ Gateway can start
# ✓ Workspace directory exists
```

####  (Optional): Review  Directory Structure

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