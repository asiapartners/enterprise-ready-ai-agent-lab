# Microsoft 365 Agents Setup

This guide covers registering your bot in the Microsoft 365 Agents portal, connecting it to Teams, and verifying end-to-end messaging.

**Time estimate**: 30–45 minutes  
**Prerequisites**: Completed [AZURE_ENTRA_SETUP.md](./AZURE_ENTRA_SETUP.md), Microsoft Teams admin access

---

## Overview

```
Azure Bot Registration (Bot Framework)
    ↓
Microsoft Teams Channel enabled
    ↓
Bot deployed + publicly accessible (ngrok / Azure / tunnel)
    ↓
Teams app manifest uploaded
    ↓
User installs bot → sends message → openclaw-a365 responds
```

---

## Step 1: Create an Azure Bot Resource

The Azure Bot resource is the Bridge between Teams and your webhook.

1. Go to [Azure Portal](https://portal.azure.com) → search **Azure Bot** → **Create**
2. Fill in:
   - **Bot handle**: `openclaw-agent` (must be globally unique)
   - **Subscription**: your Azure subscription
   - **Resource group**: create new or use existing
   - **Pricing tier**: F0 (free) for dev, S1 for production
   - **Microsoft App ID**: Select **Use existing app registration**
   - **App ID**: paste your `A365_APP_ID` from Entra setup
3. Click **Review + Create** → **Create**

> The Azure Bot resource connects your app registration to the Bot Framework messaging endpoint.

---

## Step 2: Configure the Messaging Endpoint

Once the Azure Bot resource is created:

1. Go to the resource → **Configuration**
2. Set **Messaging endpoint**: `https://your-public-hostname/api/messages`
3. Click **Apply**

### Getting a public endpoint

You need HTTPS access to port 3978 on your Docker container.

**Option A: ngrok (for development)**
```bash
ngrok http 3978
# Copy the https://xxxxx.ngrok.io URL
# Set as: https://xxxxx.ngrok.io/api/messages
```

**Option B: Azure Container Instances**
Deploy the container to ACI and use the public DNS name.

**Option C: VS Code Dev Tunnels**
```bash
devtunnel host -p 3978 --allow-anonymous
```

**Option D: Azure VM / App Service**
Deploy with a fixed public IP and your custom domain.

---

## Step 3: Enable the Teams Channel

1. In your Azure Bot resource → **Channels**
2. Click **Microsoft Teams**
3. Accept the Terms of Service
4. Click **Apply**

The Teams channel is now connected to your webhook endpoint.

---

## Step 4: Start the openclaw-a365 Container

Ensure your `.env` file is complete (see [AZURE_ENTRA_SETUP.md](./AZURE_ENTRA_SETUP.md)):

```bash
cd phase-2-tool-integration-capability-perimeters/a365-plugin
cp .env.example .env
# Fill in all values
docker-compose up -d
docker-compose logs -f
```

You should see:
```
[a365] Bot Framework webhook listening on port 3978
[openclaw] Gateway started on port 18789
```

Verify health:
```bash
curl http://localhost:18789/health
# → {"ok":true}
```

---

## Step 5: Create the Teams App Manifest

Create a `manifest.json` for your Teams app:

```json
{
  "$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.16/MicrosoftTeams.schema.json",
  "manifestVersion": "1.16",
  "version": "1.0.0",
  "id": "YOUR-APP-ID-GUID",
  "packageName": "com.yourorg.openclaw",
  "developer": {
    "name": "Your Organization",
    "websiteUrl": "https://yourorg.com",
    "privacyUrl": "https://yourorg.com/privacy",
    "termsOfUseUrl": "https://yourorg.com/terms"
  },
  "name": {
    "short": "AI Agent",
    "full": "OpenClaw AI Agent"
  },
  "description": {
    "short": "Your AI assistant in Teams",
    "full": "AI agent with calendar and email capabilities powered by OpenClaw."
  },
  "icons": {
    "color": "color.png",
    "outline": "outline.png"
  },
  "accentColor": "#0078D4",
  "bots": [
    {
      "botId": "YOUR-A365-APP-ID",
      "scopes": ["personal", "team", "groupchat"],
      "isNotificationOnly": false,
      "supportsCalling": false,
      "supportsVideo": false
    }
  ],
  "permissions": ["identity", "messageTeamMembers"],
  "validDomains": []
}
```

Replace:
- `YOUR-APP-ID-GUID`: a fresh UUID for the Teams app
- `YOUR-A365-APP-ID`: your `A365_APP_ID`

Package the manifest:
```bash
mkdir teams-app
cp manifest.json teams-app/
# Add 192x192 color.png and 32x32 outline.png icons
cd teams-app && zip -r ../teams-app.zip .
```

---

## Step 6: Install the Bot in Teams

### For personal testing (sideload):

1. Open Microsoft Teams → **Apps** (left sidebar)
2. Click **Manage your apps** → **Upload an app**
3. Select **Upload a custom app** → choose `teams-app.zip`
4. Click **Add**

### For organization-wide deployment:

1. Go to [Teams Admin Center](https://admin.teams.microsoft.com)
2. **Teams apps** → **Manage apps** → **Upload**
3. Upload `teams-app.zip`
4. Set availability policy as needed

---

## Step 7: Test the Integration

1. Open Teams → find your bot (search by name)
2. Start a chat with the bot
3. Send: `Hello`

Expected response: The welcome message from your `WELCOME_MESSAGE` env var, or a greeting from the agent.

### Test Graph API tools:

```
You: What meetings do I have today?
Bot: I found 2 events on your calendar today:
     • 10:00 AM - Team Standup (30 min)
     • 2:00 PM - Sprint Review (1 hour)
```

```
You: Send an email to john@contoso.com with subject "Hello" and body "Testing the AI agent"
Bot: Email sent to john@contoso.com ✓
```

---

## Step 8: Configure DM Policy

Control who can message the bot directly. In your `.env`:

```env
# Open: anyone in the tenant can DM the bot
DM_POLICY=open

# Pairing: users must be approved before the bot responds
DM_POLICY=pairing

# Allowlist: only specific users can DM
DM_POLICY=allowlist
ALLOW_FROM=user1@contoso.com,user2@contoso.com
```

See [APPROVAL_WORKFLOWS.md](./APPROVAL_WORKFLOWS.md) for more on the pairing flow.

---

## Common Issues

**Bot doesn't respond in Teams**  
→ Check that the messaging endpoint is publicly accessible and HTTPS. Test with:
```bash
curl -X POST https://your-endpoint/api/messages -H "Content-Type: application/json" -d '{}'
# Should return 401 (auth required), not connection refused
```

**"Bot not found" error**  
→ The botId in manifest.json must exactly match `A365_APP_ID`.

**"Unauthorized" in bot logs**  
→ Verify `A365_APP_PASSWORD` matches the client secret in Azure Portal.

**Graph API calls fail**  
→ Check container logs for token errors:
```bash
docker-compose logs openclaw-a365 | grep -i "token\|graph\|error"
```
See [AZURE_ENTRA_SETUP.md](./AZURE_ENTRA_SETUP.md) for credential verification steps.

**Teams shows "Something went wrong"**  
→ The bot is likely returning HTTP 500. Check container logs:
```bash
docker-compose logs -f openclaw-a365
```

---

## Next Steps

→ Continue to [GRAPH_API_TOOLS.md](./GRAPH_API_TOOLS.md) to explore all available Graph tools
