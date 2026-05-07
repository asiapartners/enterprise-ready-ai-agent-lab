# Microsoft Teams Integration Setup Guide

## Overview

This guide walks you through integrating your OpenClaw agent with Microsoft Teams so it can respond to chat messages, channel conversations, and be used as an enterprise chat assistant.

---

## Prerequisites

- [ ] OpenClaw installed and working
- [ ] Your agent configured (`AGENTS.md` created)
- [ ] Microsoft Azure account with active subscription
- [ ] Microsoft Teams desktop or web client
- [ ] Azure Bot Service created (follows below)

---

## Step 1: Create Azure Bot Service

### 1.1 Go to Azure Portal

Navigate to: https://portal.azure.com

### 1.2 Create Bot Service Resource

1. Click **"Create a resource"**
2. Search for **"Bot Service"**
3. Click **"Create"**

### 1.3 Configure Bot Resource

Fill in the form:

| Field | Value |
|-------|-------|
| **Bot handle** | Name for your bot (e.g., `MyOpenClawBot`) |
| **Subscription** | Select your subscription |
| **Resource group** | Create new or select existing |
| **Location** | Select closest region |
| **Pricing tier** | F0 (free) or S1 (standard) |
| **App Service plan** | Create new or select existing |
| **Application insights** | Optional (recommended for monitoring) |

Click **"Review + Create"** → **"Create"**

### 1.4 Wait for Deployment

Wait 2-3 minutes for the Bot Service to deploy. Once complete, go to resource.

### 1.5 Configure Bot Identity

In your Bot Service resource:

1. Go to **Settings** → **Configuration**
2. Under **Microsoft App ID**:
   - Note your **Microsoft App ID** (you'll need this)
   - Click **"Manage"** to go to app registration

3. In App Registration:
   - Go to **Certificates & secrets**
   - Click **"New client secret"**
   - Add a secret (name: "teams-bot", expiry: 24 months)
   - Copy the secret value immediately (save it temporarily)

⚠️ **IMPORTANT**: Save both App ID and Client Secret securely. Never commit to git!

### 1.6 Configure Channels

Back in Bot Service:

1. Go to **Channels** section
2. Click **"Configure Microsoft Teams Channel"**
3. Accept Terms → **"Agree"**
4. Click **"Save"**

Teams channel is now enabled!

---

## Step 2: Configure OpenClaw

### 2.1 Edit `openclaw.json`

Open your OpenClaw configuration:

```bash
# macOS/Linux
nano ~/.openclaw/openclaw.json

# Windows
notepad $env:USERPROFILE\.openclaw\openclaw.json
```

### 2.2 Add Teams Configuration

Add the Teams section to your config:

```json5
{
  // ... existing config ...
  
  channels: {
    teams: {
      enabled: true,
      botId: "your_microsoft_app_id",        // Paste your App ID
      botPassword: "your_client_secret",     // Paste your secret
      
      // Activity settings
      activityType: "message",               // message | typing | event
      
      // Message settings
      attachmentHandling: "summary",         // summary | full | none
    }
  }
}
```

### 2.3 Set Environment Variables (Recommended)

Instead of hardcoding secrets, use environment variables:

```bash
# Set credentials
export TEAMS_BOT_ID="your_microsoft_app_id"
export TEAMS_BOT_PASSWORD="your_client_secret"

# Add to ~/.bashrc or ~/.zshrc to make permanent:
echo 'export TEAMS_BOT_ID="your_microsoft_app_id"' >> ~/.bashrc
echo 'export TEAMS_BOT_PASSWORD="your_client_secret"' >> ~/.bashrc
source ~/.bashrc
```

Then in config:

```json5
{
  channels: {
    teams: {
      enabled: true,
      botId: "$TEAMS_BOT_ID",           // Reads from environment
      botPassword: "$TEAMS_BOT_PASSWORD",
    }
  }
}
```

**Benefits**: Secrets not in config, easier to rotate

---

## Step 3: Create Teams App Manifest

### 3.1 Create `manifest.json`

In your workspace, create a Teams app manifest file:

```bash
mkdir -p ~/.openclaw/teams-manifest
nano ~/.openclaw/teams-manifest/manifest.json
```

### 3.2 Manifest Content

```json
{
  "$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.11/MicrosoftTeams.schema.json",
  "manifestVersion": "1.11",
  "version": "1.0.0",
  "id": "YOUR_MICROSOFT_APP_ID",
  "packageName": "com.openclaw.teams.bot",
  "developer": {
    "name": "OpenClaw Team",
    "websiteUrl": "https://github.com/openclaw/openclaw",
    "privacyUrl": "https://github.com/openclaw/openclaw/blob/main/PRIVACY.md",
    "termsOfUseUrl": "https://github.com/openclaw/openclaw/blob/main/LICENSE"
  },
  "icons": {
    "color": "#FF0000",
    "outline": "#FFFFFF"
  },
  "name": {
    "short": "OpenClaw Agent",
    "full": "OpenClaw Autonomous Agent"
  },
  "description": {
    "short": "Autonomous AI agent for enterprise teams",
    "full": "An intelligent autonomous AI assistant that can read files, execute tasks, and help your team"
  },
  "accentColor": "#FF0000",
  "bots": [
    {
      "botId": "YOUR_MICROSOFT_APP_ID",
      "scopes": [
        "personal",
        "team"
      ],
      "supportsFiles": false,
      "isNotificationOnly": false,
      "commandLists": [
        {
          "scopes": [
            "personal",
            "team"
          ],
          "commands": [
            {
              "title": "help",
              "description": "Shows help information"
            },
            {
              "title": "status",
              "description": "Shows agent status"
            }
          ]
        }
      ]
    }
  ],
  "permissions": [
    "identity",
    "messageTeamMembers"
  ],
  "validDomains": []
}
```

**Replace**: `YOUR_MICROSOFT_APP_ID` with your actual App ID

---

## Step 4: Install Bot in Teams

### Option A: Direct Installation (Simplest)

1. In Azure Portal, go to your Bot Service
2. Go to **Channels** → **Teams**
3. Click on the Teams channel
4. You'll see "Visit the Bot Framework Emulator" - click the link
5. This opens Teams and prompts you to add the bot

### Option B: Sideload via Manifest

1. Open Microsoft Teams
2. Click **Apps** (bottom left)
3. Click **Upload a custom app** (if you have permissions)
4. Select your manifest.json file
5. Click **Add**

### Option C: Manual Installation

If you have the installation link from Azure:

1. Copy the Teams installation URL from Azure Bot Service
2. Open it in browser: `https://teams.microsoft.com/l/app/{appId}`
3. Click **Add**
4. Select team/personal scope
5. Click **Install**

---

## Step 5: Start OpenClaw Gateway

The Gateway is the central service that handles Teams messages:

```bash
# Start the gateway
openclaw gateway --port 18789 --verbose

# You should see output like:
# ✓ Gateway listening on port 18789
# ✓ Teams channel initialized
# ✓ Ready for messages
```

Keep this running in the background or use daemon:

```bash
# If installed with daemon (recommended)
# The gateway runs as a background service automatically
openclaw gateway start
```

---

## Step 6: Test the Integration

### Test 1: Personal Chat

1. Open Teams
2. Go to **Chat**
3. Search for your bot name (e.g., "OpenClaw Agent")
4. Start a new chat
5. Send message: **"Hello!"**

**Expected Result**:
- Bot responds with introduction
- Shows its personality

### Test 2: Team Channel

1. Go to a Team channel
2. Mention your bot: **"@OpenClaw Agent what can you do?"**
3. Wait for response

**Expected**: Bot explains capabilities

### Test 3: Tool Usage

Send: **"Create a file called 'teams-test.txt' with content 'Hello Teams'"**

**Expected**: Bot uses file tool, responds with confirmation

### Test 4: Conversation Memory

1. Send: **"My name is Alice"**
2. Wait for response
3. Send: **"What is my name?"**

**Expected**: Bot remembers from earlier message

---

## Step 7: Advanced Configuration

### Channel Message Routing

Route different Teams channels to different agents:

```json5
{
  channels: {
    teams: {
      enabled: true,
      botId: "$TEAMS_BOT_ID",
      botPassword: "$TEAMS_BOT_PASSWORD",
      
      // Route channels to agents
      routing: {
        "general": "main",           // #general → main agent
        "code-review": "coder",      // #code-review → code expert
        "research": "researcher",    // #research → research expert
      }
    }
  }
}
```

**To get Channel IDs**:
1. Enable Developer Mode in Teams
2. Right-click channel name
3. Copy channel ID

### Message Type Filters

Only respond to certain message types:

```json5
{
  channels: {
    teams: {
      messageTypes: [
        "message",     // Regular messages
        "channelCreate", // Channel created notifications
      ],
      
      // Ignore these
      ignoreTypes: [
        "typingIndicator",
        "endOfConversation",
      ]
    }
  }
}
```

### Admin Commands

```json5
{
  channels: {
    teams: {
      adminCommands: {
        enabled: true,
        adminIds: ["user-id-1", "user-id-2"],
        commands: {
          "/status": "Show bot status",
          "/reset": "Reset conversation",
          "/config": "Show current config",
        }
      }
    }
  }
}
```

---

## Troubleshooting

### Issue: Bot not appearing in Teams

**Solution 1**: Verify Teams channel is enabled
1. Go to Azure Bot Service
2. Go to **Channels** section
3. Verify Teams has a checkmark

**Solution 2**: Reinstall the app
1. In Teams, go to **Apps** → **Manage your apps**
2. Find your bot and click **Uninstall**
3. Search for it again and install fresh

**Solution 3**: Check manifest.json
- Verify App ID matches your Bot Service ID
- Valid JSON syntax (use JSONLint to verify)

### Issue: Bot doesn't respond

**Check Gateway is running**:
```bash
curl http://localhost:18789/health
# Should return: {"status":"ok"}
```

**Check Credentials**:
```bash
# Verify in config
grep -A 2 "teams:" ~/.openclaw/openclaw.json
```

**Check Logs**:
```bash
# View gateway logs
openclaw logs tail -f

# Look for Teams connection errors
```

### Issue: "Invalid credentials" error

**Solution**:
1. Go to Azure Portal → Bot Service → Configuration
2. Verify Microsoft App ID and Client Secret are correct
3. Regenerate secret if needed:
   - Go to App Registration → Certificates & secrets
   - Delete old secret
   - Create new secret
   - Update openclaw.json

### Issue: Teams app installation fails

**Check manifest.json**:
```bash
# Validate JSON structure
cat ~/.openclaw/teams-manifest/manifest.json | jq .

# Should show valid JSON, not errors
```

**Common issues**:
- App ID doesn't match your Bot Service ID
- JSON has syntax errors
- Missing required fields

---

## Next Steps

Once Teams integration is working:

1. ✅ Customize agent personality in Module 3
2. ✅ Add custom tools in Module 4
3. ✅ Set up persistent memory in Module 7
4. ✅ Deploy to production with proper security

---

## Resources

- [Bot Service Documentation](https://learn.microsoft.com/en-us/azure/bot-service/bot-service-overview)
- [Teams Bot Development](https://learn.microsoft.com/en-us/microsoftteams/platform/bots/what-are-bots)
- [Bot Framework SDK](https://github.com/microsoft/botbuilder-dotnet)
- [OpenClaw Docs](https://docs.openclaw.ai)
