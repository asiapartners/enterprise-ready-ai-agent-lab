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

---