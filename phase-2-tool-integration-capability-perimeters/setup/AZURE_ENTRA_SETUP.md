# Microsoft Agent 365 — Tenant Setup

> **Time**: 1–2 hours of click-ops in the Azure / Entra portals.
> **Scope**: Everything needed to fill the eight `.env` values prefixed `A365_*`, `AA_INSTANCE_ID`, `AGENT_IDENTITY`, `OWNER`, and `OWNER_AAD_ID`.

This guide intentionally uses the **portal UI** (not CLI) for first-time setup because every screen surfaces concepts (Agentic Users, FIC, AA registration) that the lab teaches. Once you understand the model, automate via Microsoft Graph PowerShell or Terraform — see [`scripts/`](../scripts/) for stubs.

## Prerequisites

- A Microsoft 365 dev tenant where you are **Global Administrator** (or at least Application Administrator + User Administrator). Get one free at [developer.microsoft.com/microsoft-365/dev-program](https://developer.microsoft.com/microsoft-365/dev-program).
- **One available license** in your tenant (Microsoft 365 Business Basic or above) to assign to the Agentic User. The dev program tenant comes with 25 licenses — plenty.
- Microsoft Agent 365 enabled for the tenant. Most M365 dev tenants now have it on by default; if not, enable it from the M365 admin center.

---

## Step 1 — Create the Agentic User

Microsoft Agent 365 requires the agent to have **its own user identity** (not just a service principal). This is the architectural shift from "bots that act as users" to "agents that act as themselves."

1. **Entra admin center** → **Users** → **All users** → **+ New user** → **Create new user**.
2. Fill in:
   - **User principal name**: `agent` → suffix `@yourtenant.onmicrosoft.com`
   - **Display name**: `OpenClaw Agent`
   - **Password**: auto-generate (we won't use it; FIC handles auth) — copy and discard
3. **Properties** → set **Job title** to "Autonomous Agent" and **Department** to "AI Agents" (helps the audit log later).
4. **Assignments** → **Add license** → assign **Microsoft 365 Business Basic** (or whatever's free).
5. **Note the UPN**. This goes in `.env` as `AGENT_IDENTITY=agent@yourtenant.onmicrosoft.com`.

> **Mental model**: from now on, treat this account like you'd treat a junior teammate. It will see what you share with it, nothing more.

---

## Step 2 — App Registration (Bot identity)

This is the OAuth client the bot framework uses to authenticate **into** Microsoft (separate from the agent identity, which it authenticates **as**).

1. **Entra admin center** → **App registrations** → **+ New registration**.
2. Fields:
   - **Name**: `openclaw-a365-bot`
   - **Supported account types**: **Single tenant** (recommended for a dev lab)
   - **Redirect URI**: leave blank
3. Click **Register**.
4. On the **Overview** blade, copy:
   - **Application (client) ID** → `.env` → `A365_APP_ID`
   - **Directory (tenant) ID** → `.env` → `A365_TENANT_ID`
5. **Certificates & secrets** → **+ New client secret**.
   - **Description**: `phase-1-dev`
   - **Expires**: 6 months (rotate via Key Vault later)
   - Click **Add**, then **immediately copy the Value** (not the Secret ID) → `.env` → `A365_APP_PASSWORD`.
6. **API permissions** → **+ Add a permission** → **Microsoft Graph** → **Application permissions**:
   - `Calendars.ReadWrite.Shared`
   - `Mail.Send.Shared`
   - `User.Read.All`
   - Click **Grant admin consent for <tenant>** (you must be Global Admin).

> **Why "Shared" scopes?** The agent will only access calendars/mail that the owner has *explicitly shared* with the agent UPN. This is the least-privilege model.

---

## Step 3 — Configure Federated Identity Credentials (FIC)

FIC is what lets the bot identity (Step 2) mint tokens **as the agent identity** (Step 1) without storing the agent's password.

1. App registration → **Certificates & secrets** → **Federated credentials** → **+ Add credential**.
2. **Federated credential scenario**: **Other issuer**.
3. Fields (these exact values):
   - **Issuer**: `api://AzureAdTokenExchange`
   - **Subject identifier**: leave blank for now (Step 4 fills this)
   - **Name**: `aa-instance-fic`
   - **Audience**: `api://AzureAdTokenExchange`
4. **Save**. We come back to set the Subject after Step 4.

---

## Step 4 — Register the Autonomous Agent

This step issues the `AA_INSTANCE_ID` that the FIC subject is bound to.

> **Note**: The exact UI for Autonomous Agent registration is evolving rapidly in the Microsoft Agent 365 admin experience. Microsoft's reference is at https://learn.microsoft.com/en-us/microsoft-agent-365/developer/registration. The flow below reflects the current portal as of early 2026; if your tenant shows a different UI, the conceptual fields are unchanged.

1. **Microsoft 365 Admin Center** → **Settings** → **Agents** → **Autonomous agents** → **+ Register agent**.
2. Fields:
   - **Display name**: `OpenClaw Phase 1`
   - **Agentic user**: pick `agent@yourtenant.onmicrosoft.com` (Step 1)
   - **Bot app**: pick `openclaw-a365-bot` (Step 2)
   - **Owner**: pick yourself
3. Submit. Copy the resulting **Autonomous Agent Instance ID** → `.env` → `AA_INSTANCE_ID`.
4. Go back to **Step 3's federated credential** and set the **Subject identifier** to your `AA_INSTANCE_ID`.

---

## Step 5 — Capture owner identity

1. **Entra admin center** → **Users** → click *your own* account.
2. **Object ID** → `.env` → `OWNER_AAD_ID`.
3. **User principal name** → `.env` → `OWNER`.

---

## Step 6 — Share resources with the agent

This is the explicit-consent step. The agent only sees what you share.

1. **Outlook on the web** → **Calendar** → right-click your calendar → **Sharing and permissions**.
2. Add `agent@yourtenant.onmicrosoft.com`.
3. Permission level: **Can view all details** (Phase 1) or **Can edit** (if you want write actions tested).
4. Repeat for any mailbox folder you want the agent to read/send from.

---

## Step 7 — Bot endpoint (placeholder for now)

The bot needs a public HTTPS endpoint to receive A365 messages. We don't have one yet — that comes after [`AZURE_VM_DEPLOY.md`](./AZURE_VM_DEPLOY.md).

For now:
1. **Azure Portal** → search for **Azure Bot** → **+ Create**.
2. **Bot type**: **Multi-tenant** disabled — pick **Single tenant**.
3. **Microsoft App ID**: paste the `A365_APP_ID` from Step 2.
4. **Messaging endpoint**: leave as `https://placeholder/api/messages` — we'll update it after VM deploy.
5. Pricing tier: **F0** (free).

---

## Verification checklist

Before moving on, confirm your `.env` has all of:

- [ ] `A365_APP_ID`
- [ ] `A365_APP_PASSWORD`
- [ ] `A365_TENANT_ID`
- [ ] `AA_INSTANCE_ID`
- [ ] `AGENT_IDENTITY=agent@yourtenant.onmicrosoft.com`
- [ ] `OWNER=you@yourtenant.onmicrosoft.com`
- [ ] `OWNER_AAD_ID`
- [ ] Calendar shared with the agent UPN

You can sanity-test FIC token acquisition without running the bot:

```bash
# After AOAI provisioning + .env populated, on the VM (or any machine with az):
docker run --rm --env-file .env ghcr.io/sidu/openclaw-a365:latest \
  node -e "import('./dist/token.js').then(m => m.acquireAgentToken().then(t => console.log('OK', t.slice(0,20)+'...')))"
```

Expect a token starting with `eyJ...`. If you get an error about FIC subject mismatch, double-check that Step 3's Subject identifier exactly matches the `AA_INSTANCE_ID` from Step 4.

---

## Common pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| `AADSTS700024 — Client assertion is not within its valid time range` | Clock drift on Azure VM | `sudo timedatectl set-ntp true` |
| `AADSTS50105 — User does not have access` | Calendar not actually shared with agent UPN | Re-share via Outlook web; wait 5 min for replication |
| `AADSTS70021 — No matching federated identity record found` | FIC Subject identifier ≠ `AA_INSTANCE_ID` | Edit FIC, paste Instance ID exactly |
| `Unauthorized` on `/api/messages` | Bot endpoint URL wrong, or `A365_APP_PASSWORD` rotated and not updated | Re-check Bot resource → Configuration → Messaging endpoint |
| Agent replies but Graph tools error 403 | Admin consent not granted for Application permissions | Re-grant in App registration → API permissions |

---

## What you have at the end of this doc

- An Agentic User identity ready to receive Teams messages
- An Entra app registration with FIC bound to the AA Instance ID
- All credentials in `.env` (which **never** gets committed — `.gitignore` ensures this)
- Calendar shared so Graph tools work end-to-end

Next: **[`AZURE_VM_DEPLOY.md`](./AZURE_VM_DEPLOY.md)** to host the agent.
