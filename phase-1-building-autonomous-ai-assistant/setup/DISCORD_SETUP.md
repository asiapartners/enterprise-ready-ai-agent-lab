# Discord Integration Setup Guide

## Overview

This guide walks you through integrating your OpenClaw agent with Discord so it can respond to DMs and channel messages.

---

## Prerequisites

- [ ] OpenClaw installed and working
- [ ] Your agent configured (`AGENTS.md` created)
- [ ] Discord account
- [ ] Access to a Discord server (or create a test server)

---

## Step 1: Create Discord Bot

### 1.1 Go to Discord Developer Portal

Navigate to: https://discord.com/developers/applications

### 1.2 Create Application

1. Click **"New Application"**
2. Name your bot (e.g., `MyOpenClawBot`)
3. Accept Terms
4. Click **"Create"**

### 1.3 Create Bot User

1. Go to **"Bot"** section (left sidebar)
2. Click **"Add Bot"**
3. Your bot user is created!

### 1.4 Copy Bot Token

1. Under the bot name, click **"Copy"** button next to the token
2. **Keep this secret!** Treat like a password
3. Save it temporarily (we'll use it next)

⚠️ **IMPORTANT**: Never share or commit this token to git!

### 1.5 Configure Bot Settings

In the Bot section:

- **Public Bot**: OFF (for now)
- **Require OAuth2 Code Grant**: OFF
- **Intents**: Enable these:
  - ✅ Message Content Intent
  - ✅ Server Members Intent
  - ✅ Direct Messages

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

### 2.2 Add Discord Configuration

Add the Discord section to your config:

```json5
{
  // ... existing config ...
  
  channels: {
    discord: {
      enabled: true,
      token: "your_bot_token_here",  // Paste your bot token
      
      // DM (Direct Message) Policy
      dmPolicy: "pairing",  // Options: "pairing", "open", "closed"
      
      // Allowed users (can be channel IDs or user IDs)
      allowFrom: [
        "*",  // Allow from anyone (in pairing mode)
      ],
      
      // Message prefix (optional)
      prefix: "!",  // Commands start with !
    }
  }
}
```

### 2.3 Understand DM Policies

| Policy | Behavior |
|--------|----------|
| **pairing** | New users get a pairing code to approve access |
| **open** | Anyone can DM the bot (less secure) |
| **closed** | Only approved users can DM |

**Recommended for Phase 1**: `"pairing"` mode (secure but user-friendly)

### 2.4 Set Environment Variable (Alternative)

Instead of hardcoding token, use environment variable:

```bash
# Set token
export DISCORD_TOKEN="your_bot_token_here"

# Add to ~/.bashrc or ~/.zshrc to make permanent:
echo 'export DISCORD_TOKEN="your_bot_token_here"' >> ~/.bashrc
source ~/.bashrc
```

Then in config:

```json5
{
  channels: {
    discord: {
      enabled: true,
      token: "$DISCORD_TOKEN",  // Reads from environment
      dmPolicy: "pairing",
    }
  }
}
```

---

## Step 3: Invite Bot to Your Server

### 3.1 Create OAuth2 URL

1. Go back to Discord Developer Portal
2. Go to **"OAuth2"** → **"URL Generator"**
3. Select Scopes:
   - ✅ `bot`
4. Select Permissions:
   - ✅ `Send Messages`
   - ✅ `Read Messages/View Channels`
   - ✅ `Read Message History`
   - ✅ `Use Slash Commands`
   - (Optional) `Manage Messages`, `Manage Roles` for advanced features

5. Copy the generated URL

### 3.2 Invite to Your Server

1. Paste the OAuth2 URL in browser
2. Select a server from dropdown
3. Click **"Authorize"**
4. Complete CAPTCHA
5. Bot is now in your server!

### 3.3 Verify Bot in Server

1. Go to your Discord server
2. Look in **Members** list
3. You should see your bot with a "Bot" label

---

## Step 4: Start OpenClaw Gateway

The Gateway is the central service that handles Discord messages:

```bash
# Start the gateway
openclaw gateway --port 18789 --verbose

# You should see output like:
# ✓ Gateway listening on port 18789
# ✓ Discord connected
# ✓ Ready for messages
```

Keep this running in the background or use daemon:

```bash
# If installed with daemon (recommended)
# The gateway runs as a background service automatically
openclaw gateway start
```

---

## Step 5: Test the Integration

### Test 1: Send DM to Bot

1. Go to Discord
2. Find your bot in Members list
3. Click to start DM
4. Send a message: `"Hello!"`

**Expected Result**:
- You'll receive a pairing code (if using `"pairing"` mode)
- Or the bot will respond directly (if using `"open"` mode)

### Test 2: Approve Pairing (if needed)

If using pairing mode and you get a code:

```bash
# Approve the pairing code
openclaw pairing approve discord CODE_HERE

# Example:
openclaw pairing approve discord a1b2c3
```

Then try messaging the bot again.

### Test 3: Actual Conversation

Send: `"What is your name?"`

**Expected**: Bot responds with introduction

### Test 4: Tool Usage

Send: `"Create a file called 'discord-test.txt'"`

**Expected**: Bot uses file tool, responds with confirmation

---

## Step 6: Advanced Configuration

### Channel Messages (Optional)

To have your bot respond in channels (not just DMs):

```json5
{
  channels: {
    discord: {
      enabled: true,
      token: "your_token",
      dmPolicy: "pairing",
      
      // Channel settings
      channels: {
        // Channel ID -> Agent mapping
        "1234567890": "main",  // Map channel to agent
      },
      
      // Respond to mentions only
      respondToMentions: true,
      
      // Or respond to all messages (spammy)
      respondToAll: false,
    }
  }
}
```

Get channel ID:
1. Enable Developer Mode in Discord
2. Right-click channel
3. Click "Copy Channel ID"

### Custom Prefix

Respond only to commands:

```json5
{
  channels: {
    discord: {
      prefix: "!",  // Commands start with !
      // User types: "!What is AI?"
      // Bot responds to that
    }
  }
}
```

### Role-Based Access

Restrict to certain roles:

```json5
{
  channels: {
    discord: {
      allowFrom: [
        "role:admin",      // Allow @admin role
        "user:12345",      // Allow specific user
      ],
    }
  }
}
```

---

## Troubleshooting

### Issue: Bot doesn't respond to DMs

**Solution 1**: Check Gateway is running
```bash
curl http://localhost:18789/health
# Should return: {"status":"ok"}
```

**Solution 2**: Check bot has Message Content Intent
1. Go to Developer Portal → Bot
2. Verify "Message Content Intent" is ON

**Solution 3**: Verify token is correct
```bash
# Check in config
grep "token:" ~/.openclaw/openclaw.json
```

### Issue: Bot in server but not accepting messages

**Likely cause**: Not in pairing list or pairing mode misconfigured

**Solution**:
```bash
# If using pairing, approve yourself:
openclaw pairing approve discord <code>

# Or switch to open mode temporarily (less secure):
# Edit openclaw.json: dmPolicy: "open"
```

### Issue: Port 18789 already in use

**Solution**:
```bash
# Use different port
openclaw gateway --port 18790 --verbose

# Update config to match new port
```

### Issue: `DISCORD_TOKEN not found`

**Solution**:
```bash
# Verify environment variable is set
echo $DISCORD_TOKEN

# If empty, set it:
export DISCORD_TOKEN="your_token_here"

# Make permanent:
echo 'export DISCORD_TOKEN="your_token_here"' >> ~/.bashrc
source ~/.bashrc
```

### Issue: Bot offline or not connecting

**Solution**:
```bash
# Check logs
openclaw logs tail -f

# Restart gateway
openclaw gateway restart

# Check Discord status page:
# https://discordstatus.com/
```

---

## Configuration Examples

### Minimal (Just DMs)

```json5
{
  channels: {
    discord: {
      enabled: true,
      token: "$DISCORD_TOKEN",
      dmPolicy: "pairing",
    }
  }
}
```

### Full Featured

```json5
{
  channels: {
    discord: {
      enabled: true,
      token: "$DISCORD_TOKEN",
      
      // DMs
      dmPolicy: "pairing",
      
      // Channels
      channels: {
        "1234567890": "main",  // Map channels to agents
      },
      respondToMentions: true,
      
      // Commands
      prefix: "!",
      
      // Access control
      allowFrom: [
        "*",  // Allow all in pairing mode
      ],
      
      // Role restrictions
      requireRoles: ["user"],  // Everyone has this
    }
  }
}
```

---

## Testing Checklist

✅ Bot created in Developer Portal
✅ Token copied and configured
✅ Message Content Intent enabled
✅ Bot invited to server
✅ Gateway running: `openclaw gateway --port 18789`
✅ Receive DM from bot
✅ Approve pairing code (if using pairing mode)
✅ Send message to bot
✅ Bot responds

---

## Next Steps

1. **Test with messages** - Have conversations with your bot
2. **Try tool usage** - Ask bot to create files, search web
3. **Test other channels** - Set up Slack or Telegram next
4. **Configure prefix** - Enable command mode if desired
5. **Add to more servers** - Invite bot to other servers

---

## Resources

- [Discord Developer Portal](https://discord.com/developers/applications)
- [Discord.py Documentation](https://discordpy.readthedocs.io/)
- [OpenClaw Discord Channel Setup](https://docs.openclaw.ai/channels/discord)
- [Discord Bot Permissions](https://discordapi.com/permissions.html)

---

## Example Full Conversation

```
User: Hi, who are you?
Bot: I'm your OpenClaw assistant! I can help with research, create files,
     run commands, and more. What would you like help with?

User: Search for the latest AI news
Bot: I'll search for recent AI news... 
     [Using browser tool to search]
     Found: OpenAI releases new model, Anthropic publishes safety research...

User: Save that to a file
Bot: I'll save the AI news summary to a file...
     [Using write tool]
     ✓ Created file: ai-news-summary.txt

User: Create a TODO list for my projects
Bot: I'll create a TODO list for you...
     [Using write tool]
     ✓ Created file: TODO.md with your projects
```

---

**Congratulations!** Your Discord integration is ready. Time to interact with your agent! 🎉

