# Proactive Messaging in openclaw-a365

Proactive messaging lets the agent send messages to a Teams conversation **without** an incoming message from the user. This is used for scheduled summaries, calendar reminders, async task completion, and cron-triggered workflows.

---

## How It Works

```
Incoming message (user → bot)
        ↓
  monitor.ts stores ConversationReference
        ↓
  ~/.openclaw/a365-conversations.json
        
Later: proactive trigger (cron / async task)
        ↓
  outbound.ts resolves reference
        ↓
  CloudAdapter.continueConversation()
        ↓
  Bot Framework delivers message to Teams
```

The key insight: Bot Framework requires the original `serviceUrl` and `conversationId` from a **previous** inbound activity to send proactively. You cannot initiate a completely cold conversation — the user must have messaged the bot at least once.

---

## Conversation Reference Storage

References are saved automatically on every inbound message:

**Location**: `~/.openclaw/a365-conversations.json`

**Structure**:
```json
{
  "19:conversation-id@thread.tacv2": {
    "conversationId": "19:conversation-id@thread.tacv2",
    "serviceUrl": "https://smba.trafficmanager.net/teams/",
    "channelId": "msteams",
    "botId": "your-bot-app-id",
    "botName": "Your Agent Name",
    "userId": "29:user-id",
    "userName": "Jane Smith",
    "userAadId": "aad-object-id",
    "tenantId": "tenant-id",
    "isGroup": false,
    "locale": "en-US",
    "updatedAt": 1704067200000
  }
}
```

---

## Sending Proactive Messages

### Via `sendMessageA365()`

```typescript
import { sendMessageA365 } from "@openclaw/a365";

// By conversationId
await sendMessageA365("conversation:19:abc123@thread.tacv2", "Your calendar summary is ready.");

// By AAD Object ID (sends to most-recently-seen conversation)
await sendMessageA365("user:aad-object-id-here", "Reminder: you have a meeting in 15 minutes.");

// Bare conversationId (also works)
await sendMessageA365("19:abc123@thread.tacv2", "Task completed successfully.");
```

### Via Adaptive Card

```typescript
import { sendAdaptiveCardA365 } from "@openclaw/a365";

const card = {
  type: "AdaptiveCard",
  version: "1.4",
  body: [
    { type: "TextBlock", text: "Meeting Summary", size: "Large", weight: "Bolder" },
    { type: "TextBlock", text: "3 events today. Next: Team Standup at 10:00 AM." }
  ]
};

await sendAdaptiveCardA365("19:abc123@thread.tacv2", card);
```

---

## Target Reference Formats

| Format | Description |
|--------|-------------|
| `conversation:<id>` | Direct conversationId lookup |
| `a365:<id>` | Alias for conversation: |
| `user:<aadObjectId>` | Most recent conversation for this AAD user |
| `<bare-id>` | Treated as conversationId |

---

## Cron-Triggered Proactive Messages

Use OpenClaw's cron system to schedule proactive sends. In your `openclaw.config.json`:

```json
{
  "crons": [
    {
      "id": "daily-summary",
      "schedule": "0 8 * * 1-5",
      "to": "conversation:19:your-conversation-id@thread.tacv2",
      "message": "Good morning! Here's your calendar summary for today."
    }
  ]
}
```

> **Note**: The `to` field must resolve to a stored conversation reference. The agent must have received at least one message from that conversation for the reference to exist.

---

## Text Chunking

Messages longer than **4,000 characters** are automatically split into sequential chunks. This prevents Bot Framework payload size errors for long LLM responses.

---

## Blueprint Client ID Requirement

`CloudAdapter.continueConversation()` requires the **Blueprint Client App ID** (the agentic app registration), not the bot's regular app ID. This is a Microsoft 365 Agents SDK requirement.

The correct ID is configured via:
```env
A365_GRAPH_BLUEPRINT_CLIENT_APP_ID=<your-blueprint-client-id>
# or falls back to:
A365_APP_ID=<your-bot-app-id>
```

The `adapter-store.ts` module manages this — `setBlueprintClientId()` is called at startup by `monitor.ts`, and `getBlueprintClientId()` is used by `outbound.ts`.

---

## Limitations

1. **First contact required**: The user must initiate the first message. The bot cannot cold-start a conversation.
2. **Reference expiry**: References don't expire by default, but `serviceUrl` can become invalid if Microsoft changes routing. If delivery fails, the reference may need to be refreshed (user sends another message).
3. **Group conversations**: Proactive messages to group channels work the same way — the bot must have been messaged in that channel first.
4. **Multi-instance deployments**: The JSON file store at `~/.openclaw/a365-conversations.json` is not shared across container instances. Use a shared volume or replace with a distributed store (Redis, Azure Cache) for multi-replica deployments.

---

## Related Files

- `src/outbound.ts` — `sendMessageA365`, `sendAdaptiveCardA365`, `a365Outbound`
- `src/conversation-store.ts` — JSON persistence and in-memory cache
- `src/adapter-store.ts` — CloudAdapter singleton and Blueprint Client ID
- `src/monitor.ts` — `buildConversationReference()`, reference auto-save on inbound
