# Discord Integration Setup

This guide connects your OpenClaw agent to Discord.

---

## Prerequisites

- [ ] OpenClaw installed and `openclaw doctor` passes
- [ ] Discord account with server access (or ability to create a server)
- [ ] LLM provider configured and tested

---

## Step 1: Create a Discord Application

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **New Application**
3. Name it (e.g., `My OpenClaw Bot`)
4. Click **Create**

---

## Step 2: Create the Bot User

1. In your application, click **Bot** in the left sidebar
2. Click **Add Bot** → **Yes, do it!**
3. Under **Token**, click **Reset Token** → copy the token
   > **Security**: Save this token securely. Never share or commit to git!
4. Enable these **Privileged Gateway Intents**:
   - ✅ **Server Members Intent**
   - ✅ **Message Content Intent**
   - ✅ **Presence Intent** (optional)
5. Click **Save Changes**

---

## Step 3: Configure OAuth2 & Permissions

1. Click **OAuth2** → **URL Generator**
2. Select scopes:
   - ✅ `bot`
   - ✅ `applications.commands`
3. Select bot permissions:
   - ✅ Send Messages
   - ✅ Read Message History
   - ✅ Add Reactions
   - ✅ Use Slash Commands
   - ✅ Embed Links
4. Copy the generated URL at the bottom

---

## Step 4: Invite Bot to Your Server

1. Paste the OAuth2 URL in your browser
2. Select your server from the dropdown
3. Click **Authorize**
4. Complete the CAPTCHA
5. The bot should appear in your server's member list (offline)

---

## Step 5: Configure OpenClaw

Edit `~/.openclaw/openclaw.json`:

```json5
{
  channels: {
    discord: {
      enabled: true,
      token: "${DISCORD_BOT_TOKEN}",    // Use env var
      accounts: {
        default: {
          prefix: "/",                  // Optional command prefix
        }
      },
      messages: {
        directMessage: {
          dmPolicy: "pairing",          // pairing | open | closed
          visibleReplies: "automatic",
        },
        groupChat: {
          historyLimit: 10,
          visibleReplies: "automatic",
        }
      }
    }
  }
}
```

Set the environment variable:

```bash
export DISCORD_BOT_TOKEN="your-bot-token-here"
echo 'export DISCORD_BOT_TOKEN="your-bot-token-here"' >> ~/.bashrc
source ~/.bashrc
```

---

## DM Policy Options

| Policy | Behavior |
|--------|----------|
| `pairing` | New users receive a pairing code; must be approved |
| `open` | Anyone can message the bot directly |
| `closed` | Only pre-approved users can DM |

### Pairing Workflow (Recommended)

With `pairing` mode:
1. User sends first DM to bot
2. Bot sends a numeric pairing code
3. Admin approves via: `openclaw channel approve <code>`
4. User can now interact freely

---

## Step 6: Start the Gateway

```bash
openclaw gateway --port 18789 --verbose
```

The bot should appear **Online** in Discord.

---

## Step 7: Test the Integration

### Test 1: Direct Message

1. Open Discord
2. Search for your bot in Members
3. Click **Message**
4. Send: `Hello`
5. Bot should respond (or send pairing code if `dmPolicy: pairing`)

### Test 2: Channel Mention

In a server channel where the bot has been added:
```
@YourBot What can you do?
```

### Test 3: Tool Usage

```
@YourBot List my workspace files
```

### Test 4: Conversation

```
You: Remember that I'm working on a Python project
You: What should I use for async HTTP requests?
# Agent should keep context from previous message
```

---

## Advanced Configuration

### Channel-Specific Responses

```json5
{
  channels: {
    discord: {
      accounts: {
        "server-name": {
          allowedChannels: ["general", "bot-commands"],
          adminRoles: ["Admin", "Moderator"],
        }
      }
    }
  }
}
```

### Role-Based Access

```json5
{
  channels: {
    discord: {
      roleAccess: {
        allowedRoles: ["Team", "Admin"],
        adminRoles: ["Admin"],
      }
    }
  }
}
```

---

## Troubleshooting

### Bot is online but doesn't respond

1. Check **Message Content Intent** is enabled in Developer Portal
2. Verify bot has permission to read messages in that channel
3. Check gateway logs: `openclaw logs tail -f`

### "Invalid Token" error

- Token may have been reset — generate a new one in Developer Portal
- Check token is correctly set: `echo $DISCORD_BOT_TOKEN`

### Bot appears offline

- Verify gateway is running: `openclaw gateway --port 18789 --verbose`
- Check for errors in gateway startup logs

### Messages not being received

- Ensure bot is added to the correct server/channel
- Verify `Message Content Intent` is enabled
- For DMs with `pairing` mode: run `openclaw channel approve <code>`

---

## Configuration Examples

### Minimal (DMs only)

```json5
{
  channels: {
    discord: {
      enabled: true,
      token: "${DISCORD_BOT_TOKEN}",
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
      token: "${DISCORD_BOT_TOKEN}",
      accounts: {
        default: {
          prefix: "!",
          dmPolicy: "pairing",
        }
      },
      messages: {
        directMessage: {
          dmPolicy: "pairing",
          historyLimit: 20,
        },
        groupChat: {
          historyLimit: 10,
          requireMention: true,    // Must @mention to trigger
        }
      }
    }
  }
}
```

---

**Next**: See [CONFIG_EXAMPLES.md](../starter-configs/CONFIG_EXAMPLES.md) for more configuration patterns.
