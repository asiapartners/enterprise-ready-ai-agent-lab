# Phase 2 Lab — Tool Integration & Capability Perimeters

**Duration:** ~3 hours  
**Goal:** Wire Graph API tools and constrain agent capabilities with network policy  
**Prerequisites:** Phase 1 complete; agent responding to Teams messages

---

## Objectives

By the end of this lab you will:
- Have registered the agentic identity in Entra ID
- Implemented the T1→T2→Agent FIC token exchange
- Have a working `get_calendar_events` and `create_calendar_event` tool
- Applied `NETWORK_MODE=restricted` and verified outbound traffic is blocked
- Added a custom domain to `NETWORK_ALLOWLIST` and verified access

---

## Architecture: T1 → T2 → Agent FIC Token Chain

```
openclaw-connector                 Entra ID
       │
       ├─► T1: client_credentials
       │   + fmi_path (AA_INSTANCE_ID)
       │◄─ T1 Token
       │
       ├─► T2: jwt-bearer assertion (T1)
       │◄─ T2 Token
       │
       ├─► Agent Token: user_fic grant
       │   for AGENT_IDENTITY UPN
       │◄─ Agent Token
       │
       └─► Graph API: Bearer Agent Token
           (acts as AGENT_IDENTITY)
```

**Key design principle:** The agent operates with its own Entra ID identity (`AGENT_IDENTITY`). Resources (calendar, mail) are explicitly shared *with* this identity — not granted globally. All audit logs show `AGENT_IDENTITY` as the actor.

---

## Step 1 — Register the Agentic Identity

```bash
# Create a mailbox-enabled user for the agent in Entra ID (or use an existing M365 user)
# This user will be the agent's identity — all calendar/mail actions appear as this user

TENANT_ID=$(az account show --query tenantId -o tsv)

# Option A: Use an existing M365 licensed user (recommended)
# Share their calendar/mail with the agent identity instead

# Option B: Create a dedicated user
az ad user create \
  --display-name "OpenClaw Agent" \
  --user-principal-name "openclaw-agent@<your-domain>" \
  --password "<temp-password>" \
  --force-change-password-next-sign-in false
```

Update `.env`:
```bash
AGENT_IDENTITY=openclaw-agent@<your-domain>
```

---

## Step 2 — Configure Federated Identity Credentials

FIC allows the app registration to obtain tokens on behalf of the agent identity without requiring the user's password.

```bash
APP_ID=<A365_APP_ID>
AGENT_UPN=openclaw-agent@<your-domain>

# Create FIC configuration in Azure
az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/applications/<APP_OBJECT_ID>/federatedIdentityCredentials" \
  --body '{
    "name": "agent365-fic",
    "issuer": "https://login.microsoftonline.com/<TENANT_ID>/v2.0",
    "subject": "<AA_INSTANCE_ID>",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

---

## Step 3 — Grant Graph API permissions

```bash
APP_OBJECT_ID=<object-id-of-app-registration>
GRAPH_APP_ID=00000003-0000-0000-c000-000000000000

# Calendars.ReadWrite (application permission for agentic identity)
CALENDARS_PERMISSION=ef54d2bf-783f-4e0f-bca1-3210c4d8a2c0
# Mail.Send (application permission)
MAIL_SEND_PERMISSION=b633e1c5-b582-4048-a93e-9f11b44c7e96

az ad app permission add \
  --id "$APP_OBJECT_ID" \
  --api "$GRAPH_APP_ID" \
  --api-permissions "${CALENDARS_PERMISSION}=Role" "${MAIL_SEND_PERMISSION}=Role"

az ad app permission admin-consent --id "$APP_OBJECT_ID"
```

---

## Step 4 — Complete the FIC token exchange in graph-tools.ts

Open `src/graph-tools.ts` and locate the TODO:

```typescript
// TODO: Complete the T1 → T2 → Agent FIC token exchange
// 1. T1: acquire token with client_credentials + fmi_path claim
// 2. T2: exchange T1 for T2 using jwt-bearer OBO flow
// 3. Agent: use user_fic grant with T2 to get agent token for AGENT_IDENTITY
```

Reference implementation sketch:
```typescript
// T1 — Client Credentials with FIC assertion
const t1Credential = new ClientSecretCredential(tenantId, appId, appSecret);
const t1Token = await t1Credential.getToken(['api://AzureADTokenExchange/.default']);

// T2 — On-Behalf-Of exchange
const oboParams = new URLSearchParams({
  client_id: appId,
  client_secret: appSecret,
  grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
  assertion: t1Token.token,
  requested_token_use: 'on_behalf_of',
  scope: 'https://graph.microsoft.com/.default',
});
const t2Response = await fetch(`https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`, {
  method: 'POST',
  body: oboParams,
});

// Agent Token — user_fic grant for AGENT_IDENTITY
// (exact parameters depend on Agent365 SDK release)
```

---

## Step 5 — Share the owner's calendar with the agent identity

In Outlook / Exchange Admin:
1. Go to: **Calendar** → **Share** → Enter `AGENT_IDENTITY` email
2. Grant: **Can edit** (required for `create_calendar_event`)
3. Accept the sharing invitation as the agent identity

Test via the Graph Explorer:
```bash
# As the agent identity (using the FIC token)
GET https://graph.microsoft.com/v1.0/users/AGENT_IDENTITY/calendar/events
```

---

## Step 6 — Test calendar tools end-to-end

In the Bot Framework Emulator or Teams:
```
> calendar today
> schedule a meeting with user@contoso.com tomorrow at 2pm for 1 hour
```

Verify in Application Insights:
- Trace: `get_calendar_events` span with Graph API dependency
- No token errors (401/403)

---

## Step 7 — Apply network policy

```bash
# In .env:
NETWORK_MODE=restricted
```

Restart the container with NET_ADMIN capability:
```bash
# docker-compose.yml: uncomment cap_add NET_ADMIN
docker-compose up --build
```

Verify outbound blocking:
```bash
# Should fail (outbound to non-allowed domain):
docker exec -it openclaw-agent365 wget -qO- https://example.com
# Expected: Connection refused / blocked

# Should succeed (essential domain):
docker exec -it openclaw-agent365 wget -qO- https://graph.microsoft.com
```

Add a custom domain to the allowlist:
```bash
# .env:
NETWORK_MODE=allowlist
NETWORK_ALLOWLIST=api.github.com,your-internal-api.contoso.com
```

---

## Acceptance Criteria

- [ ] `get_calendar_events` returns real calendar data (not mock)
- [ ] `create_calendar_event` creates an event visible in Outlook
- [ ] T1→T2→Agent token exchange completes without errors
- [ ] `NETWORK_MODE=restricted` blocks outbound to `example.com`
- [ ] `NETWORK_MODE=allowlist` permits `api.github.com`
- [ ] Graph API audit logs show `AGENT_IDENTITY` as actor (not the app registration)
- [ ] All 7 graph tools listed in `openclaw.plugin.json` are registered

---

## Troubleshooting

| Issue | Check |
|---|---|
| Graph API 403 | Admin consent not granted; check permissions in Azure Portal |
| FIC exchange fails | Verify AA_INSTANCE_ID matches the FIC subject in App Registration |
| Calendar not found | AGENT_IDENTITY must have calendar shared from owner |
| iptables not applied | Container needs `--cap-add=NET_ADMIN`; check NETWORK_MODE env var |
| Token cache issues | Restart container to clear in-memory token cache |

---

## Next

→ [Phase 3 — Multi-Agent Orchestration & Governance](./phase3-multi-agent.md)
