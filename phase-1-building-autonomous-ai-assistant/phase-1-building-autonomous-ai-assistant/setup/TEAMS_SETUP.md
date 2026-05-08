# Microsoft Teams Integration

This guide walks you through connecting your OpenClaw agent to Microsoft Teams.

---

## Prerequisites

- [ ] OpenClaw installed and `openclaw doctor` passes
- [ ] Azure subscription (free tier works)
- [ ] Microsoft Teams workspace access
- [ ] LLM provider configured and tested

---

## Overview

Teams integration works via **Azure Bot Service**:

```
Microsoft Teams  →  Azure Bot Service  →  OpenClaw Gateway (port 18789)
```

Your agent needs a public endpoint OR a tunnel (ngrok/VS Code port forwarding) for Teams to reach it.

---

## Step 1: Create Azure Bot Service

1. Go to [Azure Portal](https://portal.azure.com)
2. Click **Create a resource** → search "Azure Bot"
3. Click **Create** and fill in:
   - **Bot handle**: `my-openclaw-bot` (unique name)
   - **Subscription**: Your Azure subscription
   - **Resource group**: Create new or use existing
   - **Pricing tier**: F0 (Free) for testing
   - **Microsoft App ID**: Select **Create new Microsoft App ID**
4. Click **Review + Create** → **Create**
5. Wait for deployment (~2 minutes)

---

## Step 2: Get Bot Credentials

1. Open your new Bot Service resource
2. Go to **Settings** → **Configuration**
3. Note your **Microsoft App ID** (shown at top)
4. Click **Manage Password** next to the App ID
   - This opens Azure Active Directory
   - Go to **Certificates & secrets**
   - Click **New client secret**
   - Set description: `openclaw-secret`
   - Set expiry: 24 months
   - Click **Add**
   - **Copy the secret VALUE immediately** — it won't be shown again
5. Save both values securely:
   ```
   Microsoft App ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   Client Secret:    your_client_secret_value
   ```

> **Security**: Never commit these to git. Use environment variables.

---

## Step 3: Set Up a Public Endpoint

Teams needs to reach your bot via HTTPS. Options:

### Option A: ngrok (Development)

```bash
# Install ngrok
npm install -g ngrok
# OR: brew install ngrok

# Expose local port 18789
ngrok http 18789

# Copy the HTTPS URL: https://abc123.ngrok.io
```

### Option B: VS Code Port Forwarding

In VS Code, open the Ports panel and forward port 18789 — VS Code provides a public HTTPS URL.

### Option C: Azure VM (Production)

Deploy OpenClaw on an Azure VM with a public IP and configure HTTPS via Let's Encrypt.

---

## Step 4: Configure the Bot Endpoint

1. In Azure Bot Service → **Settings** → **Configuration**
2. Set **Messaging endpoint**:
   ```
   https://your-public-url.ngrok.io/api/messages
   ```
3. Click **Apply**

---

## Step 5: Configure OpenClaw

Edit `~/.openclaw/openclaw.json`:

```json5
{
  agents: {
    defaults: {
      model: "azure/gpt-4",
    }
  },
  
  channels: {
    teams: {
      enabled: true,
      botId: "YOUR_MICROSOFT_APP_ID",        // From Step 2
      botPassword: "YOUR_CLIENT_SECRET",      // From Step 2
    }
  },
  
  gateway: {
    port: 18789,
    verbose: true,
  }
}
```

Or use environment variables (recommended):

```bash
export TEAMS_BOT_ID="YOUR_MICROSOFT_APP_ID"
export TEAMS_BOT_PASSWORD="YOUR_CLIENT_SECRET"
```

```json5
{
  channels: {
    teams: {
      enabled: true,
      botId: "${TEAMS_BOT_ID}",
      botPassword: "${TEAMS_BOT_PASSWORD}",
    }
  }
}
```

---

## Step 6: Enable Teams Channel in Azure

1. In Azure Bot Service → **Channels**
2. Click **Microsoft Teams**
3. Accept the Terms of Service
4. Click **Save**
5. The Teams channel should show as **Running**

---

## Step 7: Start the Gateway

```bash
openclaw gateway --port 18789 --verbose
```

Keep this running. In another terminal, verify:

```bash
curl http://localhost:18789/health
# Should return: {"status":"ok"}
```

---

## Step 8: Install the Bot in Teams

### Quick Install (Personal Chat)

1. Open Microsoft Teams
2. Click **Apps** in the left sidebar
3. Click **Manage your apps** → **Upload an app**
4. Upload the bot manifest or use the direct link

### Via App Studio (Full Install)

1. Open Teams → Apps → **App Studio** (or **Developer Portal**)
2. Create new app with your bot's App ID
3. Fill in app details (name, description, icons)
4. Add bot capability with your App ID
5. Configure messaging scopes: Personal, Team, Group Chat
6. Package and install the app

---

## Step 9: Test the Integration

### Test 1: Personal Chat
1. Search for your bot in Teams
2. Click on it → **Open**
3. Send: `Hello`
4. Bot should respond

### Test 2: Tool Usage
Send: `What files are in my workspace?`
The agent should list files from your workspace.

### Test 3: Conversation Memory
```
You: Remember that I prefer concise answers
You (new conversation): How do I create a Python list?
# Agent should give a concise answer
```

### Test 4: Channel Chat
1. Add the bot to a Teams channel
2. @mention the bot: `@YourBot What's the weather?`

---

## Enterprise Governance Patterns

### Channel-to-Agent Routing

Route different Teams channels to specialized agents:

```json5
{
  channels: {
    teams: {
      routing: {
        // Team ID: Agent ID mapping
        "team:T123/channel:C456": "researcher",
        "team:T123/channel:C789": "coder",
      }
    }
  }
}
```

### Message Type Filtering

Only respond to specific message types:

```json5
{
  channels: {
    teams: {
      filters: {
        onlyMentions: true,      // Only respond when @mentioned
        ignoreEdits: true,       // Don't re-process edited messages
        ignoreThreads: false,    // Allow thread responses
      }
    }
  }
}
```

### Administrator Command Restrictions

Restrict admin commands to specific users:

```json5
{
  channels: {
    teams: {
      adminUsers: [
        "admin@yourcompany.com",
        "owner@yourcompany.com"
      ],
      adminCommands: ["/reset", "/config", "/logs"]
    }
  }
}
```

---

## Troubleshooting

### Bot not appearing in Teams
- Verify App ID is correct in both Azure and openclaw.json
- Check that Teams channel shows "Running" in Azure Bot Service
- Try reinstalling the app in Teams

### "Unauthorized" or 401 errors
- Client secret may have expired — create a new one
- Verify bot password in openclaw.json matches Azure

### Bot responds in Azure portal but not Teams
- Check messaging endpoint URL is accessible from internet
- If using ngrok: ensure tunnel is still running and URL is current
- Verify HTTPS (not HTTP) is used in the endpoint URL

### Timeout or no response
- Check gateway is running: `curl http://localhost:18789/health`
- Check gateway logs: `openclaw logs tail -f`
- Verify LLM provider is configured and responding

---

## Next Steps

After Teams is working:
- Configure memory: [workspace/MEMORY.md](../workspace/MEMORY.md)
- Explore advanced routing in [CONFIG_EXAMPLES.md](../starter-configs/CONFIG_EXAMPLES.md)
- Move to **Phase 2** for Microsoft 365 integration with Graph API tools
