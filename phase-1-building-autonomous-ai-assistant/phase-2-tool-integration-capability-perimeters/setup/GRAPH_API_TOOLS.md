# Microsoft Graph API Tools Reference

`openclaw-a365` provides 8 Microsoft Graph API tools that your agent can use during conversations. This reference covers each tool's purpose, required configuration, example prompts, and what happens under the hood.

---

## Prerequisites

All tools require:
1. Completed [AZURE_ENTRA_SETUP.md](./AZURE_ENTRA_SETUP.md) — credentials and permissions
2. Agent running with Graph config in `.env`
3. Resources explicitly shared with `AGENT_IDENTITY`

---

## Tool Overview

| Tool | Graph API | Permissions Required |
|------|-----------|---------------------|
| `get_calendar_events` | `GET /users/{id}/calendar/events` | `Calendars.ReadWrite.Shared` |
| `create_calendar_event` | `POST /users/{id}/calendar/events` | `Calendars.ReadWrite.Shared` |
| `update_calendar_event` | `PATCH /users/{id}/calendar/events/{id}` | `Calendars.ReadWrite.Shared` |
| `delete_calendar_event` | `DELETE /users/{id}/calendar/events/{id}` | `Calendars.ReadWrite.Shared` |
| `find_meeting_times` | `POST /users/{id}/findMeetingTimes` | `Calendars.ReadWrite.Shared` |
| `send_email` | `POST /users/{agent}/sendMail` | `Mail.Send.Shared` |
| `get_user_info` | `GET /users/{id}` | `User.Read.All` |
| `send_gif` | Klipy API + `sendActivity` | `KLIPY_API_KEY` env var |

---

## 1. `get_calendar_events`

Retrieves calendar events for the owner within a time range.

**Example prompts:**
```
What's on my calendar today?
Show me my meetings for next week.
Do I have anything scheduled between 2pm and 5pm tomorrow?
Am I free on Friday afternoon?
```

**Parameters:**
- `startDateTime` (ISO 8601) — start of the range
- `endDateTime` (ISO 8601) — end of the range
- `userId` (optional) — defaults to owner's email from config

**Under the hood:**
```
GET https://graph.microsoft.com/v1.0/users/{userId}/calendar/events
  ?$filter=start/dateTime ge '{start}' and end/dateTime le '{end}'
  &$orderby=start/dateTime
  &$top=50
```

**Example response:**
```
You have 3 events today:
• 9:00 AM – Team Standup (30 min) – Teams call
• 2:00 PM – Sprint Review (1 hr) – Conference Room B
• 4:30 PM – 1:1 with Manager (30 min) – Teams call
```

---

## 2. `create_calendar_event`

Creates a new calendar event on the owner's calendar.

**Example prompts:**
```
Schedule a team lunch for tomorrow at noon for 1 hour.
Create a meeting with john@contoso.com and jane@contoso.com on Friday at 3pm for 30 minutes to discuss Q2 planning.
Block my calendar on Thursday from 9am to 11am for focused work time.
```

**Parameters:**
- `subject` — event title
- `startDateTime` (ISO 8601) — start time with timezone
- `endDateTime` (ISO 8601) — end time with timezone
- `timeZone` — IANA timezone (e.g., `America/Los_Angeles`)
- `attendees` (optional) — array of email addresses
- `body` (optional) — event description
- `location` (optional) — location string
- `isOnlineMeeting` (optional) — creates a Teams meeting link

**Returns:** Event ID and confirmation with meeting URL if online meeting requested.

---

## 3. `update_calendar_event`

Updates an existing calendar event.

**Example prompts:**
```
Reschedule my 2pm meeting to 3pm.
Change tomorrow's standup to be 45 minutes instead of 30.
Add sarah@contoso.com to the Friday planning meeting.
Update the sprint review location to Room A.
```

**Parameters:**
- `eventId` — the event ID (agent gets this from `get_calendar_events` first)
- `subject` (optional) — new title
- `startDateTime` (optional) — new start time
- `endDateTime` (optional) — new end time
- `timeZone` (optional) — timezone
- `attendees` (optional) — new attendee list (replaces existing)
- `body` (optional) — new description
- `location` (optional) — new location

---

## 4. `delete_calendar_event`

Cancels/deletes a calendar event.

**Example prompts:**
```
Cancel my 3pm meeting today.
Delete the team lunch on Thursday.
Remove all meetings I have on Friday afternoon.
```

**Parameters:**
- `eventId` — the event ID to delete

> **Note:** The agent will typically ask for confirmation before deleting events. This can be enforced via approval workflows (see [APPROVAL_WORKFLOWS.md](./APPROVAL_WORKFLOWS.md)).

---

## 5. `find_meeting_times`

Finds available meeting times for a group of attendees.

**Example prompts:**
```
When is everyone free for a 1-hour meeting next week? Attendees: john@contoso.com, jane@contoso.com
Find a 30-minute slot for me and my manager this week.
What's the earliest we can all meet? Add sarah and mike to the attendee list.
```

**Parameters:**
- `attendees` — array of email addresses (including the owner)
- `meetingDuration` — ISO 8601 duration (e.g., `PT1H` for 1 hour, `PT30M` for 30 minutes)
- `timeConstraint` (optional) — object with `startTime` and `endTime` to narrow the search window

**Returns:** Up to 3 suggested meeting slots with confidence scores.

**Under the hood:**
```
POST https://graph.microsoft.com/v1.0/users/{userId}/findMeetingTimes
{
  "attendees": [{"emailAddress": {"address": "john@contoso.com"}, "type": "Required"}],
  "meetingDuration": "PT1H",
  "minimumAttendeePercentage": 100
}
```

---

## 6. `send_email`

Sends an email from the agent's mailbox.

**Example prompts:**
```
Send an email to the team at team@contoso.com with subject "Meeting Notes" and the key decisions from today's standup.
Email john@contoso.com to let him know the project deadline is next Friday.
Draft and send a follow-up to the Q2 planning attendees summarizing the action items.
```

**Parameters:**
- `to` — array of recipient email addresses
- `subject` — email subject line
- `body` — email body (plain text or HTML)
- `cc` (optional) — CC recipients
- `bcc` (optional) — BCC recipients

**Sender**: The email comes from `AGENT_IDENTITY` (e.g., `agent@contoso.com`).

**Under the hood:**
```
POST https://graph.microsoft.com/v1.0/users/{agentIdentity}/sendMail
{
  "message": {
    "subject": "...",
    "body": {"contentType": "HTML", "content": "..."},
    "toRecipients": [{"emailAddress": {"address": "..."}}]
  }
}
```

> **Important**: The agent sends as itself, not as the owner. Recipients see `agent@contoso.com` as the sender unless "Send on behalf of" delegation is configured (see [AZURE_ENTRA_SETUP.md](./AZURE_ENTRA_SETUP.md)).

---

## 7. `get_user_info`

Looks up information about a Microsoft 365 user by email address.

**Example prompts:**
```
Who is john.doe@contoso.com?
What's the job title for sarah@contoso.com?
Find information about the person who emailed me — their address is mike@contoso.com.
Is alex@contoso.com in our organization?
```

**Parameters:**
- `userId` — email address or AAD Object ID

**Returns:** Display name, job title, department, office location, phone number, manager.

**Under the hood:**
```
GET https://graph.microsoft.com/v1.0/users/{userId}
  ?$select=displayName,jobTitle,department,officeLocation,businessPhones,mail
```

---

## 8. `send_gif` (optional)

Sends an animated GIF to the Teams chat. Requires a [Klipy API key](https://partner.klipy.com/api-keys).

**Example prompts:**
```
Send a celebration GIF!
React with a thumbs up GIF.
Send a "good morning" GIF.
```

**Parameters:**
- `query` — search term for the GIF

**Configuration**: Set `KLIPY_API_KEY` in your `.env`. The tool is only registered when this key is present.

**Dedup**: The last 20 sent GIFs are tracked to avoid sending the same GIF twice in a row.

---

## Tool Context: AsyncLocalStorage Isolation

All 8 tools share a per-request context (injected via `AsyncLocalStorage`) that contains:
- `agentIdentity` — which account to use for Graph API calls
- `currentUserEmail` — the user who sent the message
- `currentUserRole` — "Owner" or "User" (affects what tools are available)
- `sendActivity` — for real-time progress indicators during long operations

This ensures that concurrent requests from different users never leak context into each other.

---

## Testing Tools Manually

You can test individual tools without Teams by using the OpenClaw CLI:

```bash
docker-compose exec openclaw-a365 sh -c "
  pnpm openclaw eval --tool get_calendar_events \
    --args '{\"startDateTime\":\"2025-01-01T00:00:00Z\",\"endDateTime\":\"2025-01-07T00:00:00Z\",\"userId\":\"owner@contoso.com\"}'
"
```

Or through the gateway API:
```bash
curl -X POST http://localhost:18789/api/tools/invoke \
  -H "Content-Type: application/json" \
  -d '{"tool":"get_calendar_events","args":{"startDateTime":"2025-01-01T00:00:00Z","endDateTime":"2025-01-07T00:00:00Z"}}'
```

---

## Next Steps

→ Continue to [NETWORK_POLICY.md](./NETWORK_POLICY.md) to enforce capability perimeters
