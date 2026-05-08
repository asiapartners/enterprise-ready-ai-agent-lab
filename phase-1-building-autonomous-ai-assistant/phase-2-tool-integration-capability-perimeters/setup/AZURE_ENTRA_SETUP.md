# Microsoft Agent 365 — Tenant Setup

> **Time**: 1–2 hours of click-ops in the Azure / Entra portals.
> **Scope**: Everything needed to fill the eight `.env` values prefixed `A365_*`, `AA_INSTANCE_ID`, `AGENT_IDENTITY`, `OWNER`, and `OWNER_AAD_ID`.

This guide covers both the **portal UI** path (recommended for first-time setup — every screen surfaces concepts the lab teaches) and an **Azure CLI** path for automation and repeatability.

> **Automate everything:** From the **repo root**, run:
> ```bash
> ./scripts/az-entra-setup.sh \
>   --env-file phase-2-tool-integration-capability-perimeters/a365-plugin/.env.generated
> ```
> This executes Steps 1–3 and 5–6 via CLI and writes the values straight into `a365-plugin/.env.generated`. Step 4 (AA Instance ID) always requires the M365 Agents portal — the script pauses, guides you through it, then continues. After the script finishes:
> ```bash
> cd phase-2-tool-integration-capability-perimeters/a365-plugin
> cp .env.example .env                 # if not already created
> cat .env.generated >> .env           # append generated values
> # then dedupe duplicate keys (the appended values are correct — keep them)
> ```

## Prerequisites

- A Microsoft 365 dev tenant where you are **Global Administrator** (or at least Application Administrator + User Administrator). Get one free at [developer.microsoft.com/microsoft-365/dev-program](https://developer.microsoft.com/microsoft-365/dev-program).
- **One available license** in your tenant (Microsoft 365 Business Basic or above) to assign to the Agentic User. The dev program tenant comes with 25 licenses — plenty.
- Microsoft Agent 365 enabled for the tenant. Most M365 dev tenants now have it on by default; if not, enable it from the M365 admin center.

---

## Step 1 — Create the Agentic User

Microsoft Agent 365 requires the agent to have **its own user identity** (not just a service principal). This is the architectural shift from "bots that act as users" to "agents that act as themselves."

### Portal

1. **Entra admin center** → **Users** → **All users** → **+ New user** → **Create new user**.
2. Fill in:
   - **User principal name**: `agent` → suffix `@yourtenant.onmicrosoft.com`
   - **Display name**: `OpenClaw Agent`
   - **Password**: auto-generate (we won't use it; FIC handles auth) — copy and discard
3. **Properties** → set **Job title** to "Autonomous Agent" and **Department** to "AI Agents" (helps the audit log later).
4. **Assignments** → **Add license** → assign **Microsoft 365 Business Basic** (or whatever's free).
5. **Note the UPN**. This goes in `.env` as `AGENT_IDENTITY=agent@yourtenant.onmicrosoft.com`.

### Azure CLI

```bash
# Set your tenant domain
TENANT_DOMAIN=$(az account show --query tenantId -o tsv | xargs -I{} az rest \
  --method GET --url "https://graph.microsoft.com/v1.0/organization?$select=verifiedDomains" \
  --query "value[0].verifiedDomains[?isDefault].name | [0]" -o tsv 2>/dev/null \
  || az ad signed-in-user show --query 'userPrincipalName' -o tsv | cut -d@ -f2)

AGENT_IDENTITY="agent@${TENANT_DOMAIN}"

# Create the agent user (password is temporary — FIC replaces credential usage)
TEMP_PW="Oc$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9!@#' | head -c 14)!"

az ad user create \
  --display-name "OpenClaw Agent" \
  --user-principal-name "$AGENT_IDENTITY" \
  --password "$TEMP_PW" \
  --force-change-password-next-sign-in false \
  --job-title "Autonomous Agent" \
  --department "AI Agents"

AGENT_OBJECT_ID=$(az ad user show --id "$AGENT_IDENTITY" --query id -o tsv)
echo "AGENT_IDENTITY=$AGENT_IDENTITY"
echo "Agent Object ID: $AGENT_OBJECT_ID"

# Assign license (requires Microsoft Graph PowerShell or portal — see note below)
# The license SKU ID varies; use portal for first-time license assignment.
```

> **License note**: License assignment via CLI requires the Microsoft Graph PowerShell module or `az rest` with the correct SKU GUID. Use the portal for initial license assignment, then automate with `scripts/az-entra-setup.sh`.

> **Mental model**: from now on, treat this account like you'd treat a junior teammate. It will see what you share with it, nothing more.

---

## Step 2 — App Registration (Bot identity)

This is the OAuth client the bot framework uses to authenticate **into** Microsoft (separate from the agent identity, which it authenticates **as**).

### Portal

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
   - **Description**: `phase-2-dev`
   - **Expires**: 6 months (rotate via Key Vault later)
   - Click **Add**, then **immediately copy the Value** (not the Secret ID) → `.env` → `A365_APP_PASSWORD`.
6. **API permissions** → **+ Add a permission** → **Microsoft Graph** → **Application permissions**:
   - `Calendars.ReadWrite.Shared`
   - `Mail.Send.Shared`
   - `User.Read.All`
   - Click **Grant admin consent for <tenant>** (you must be Global Admin).

### Azure CLI

```bash
GRAPH_API_ID="00000003-0000-0000-c000-000000000000"

# 1. Create app registration
A365_APP_ID=$(az ad app create \
  --display-name "openclaw-a365-bot" \
  --sign-in-audience AzureADMyOrg \
  --query appId -o tsv)

A365_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "A365_APP_ID=$A365_APP_ID"
echo "A365_TENANT_ID=$A365_TENANT_ID"

# 2. Create client secret (copy password immediately — it's only shown once)
SECRET_RESULT=$(az ad app credential reset \
  --id "$A365_APP_ID" \
  --append \
  --display-name "phase-2-dev" \
  -o json)
A365_APP_PASSWORD=$(echo "$SECRET_RESULT" | jq -r '.password')
echo "A365_APP_PASSWORD=$A365_APP_PASSWORD"

# 3. Resolve Graph permission IDs dynamically
get_graph_role_id() {
  az ad sp show --id "$GRAPH_API_ID" \
    --query "appRoles[?value=='$1'].id | [0]" -o tsv
}
PERM_CAL=$(get_graph_role_id "Calendars.ReadWrite.Shared")
PERM_MAIL=$(get_graph_role_id "Mail.Send.Shared")
PERM_USER=$(get_graph_role_id "User.Read.All")

# 4. Add permissions
az ad app permission add \
  --id "$A365_APP_ID" \
  --api "$GRAPH_API_ID" \
  --api-permissions "${PERM_CAL}=Role" "${PERM_MAIL}=Role" "${PERM_USER}=Role"

# 5. Grant admin consent (requires Global Administrator role)
az ad app permission admin-consent --id "$A365_APP_ID"
echo "✅ Admin consent granted"
```

> **Why "Shared" scopes?** The agent will only access calendars/mail that the owner has *explicitly shared* with the agent UPN. This is the least-privilege model.

---

## Step 3 — Configure Federated Identity Credentials (FIC)

FIC is what lets the bot identity (Step 2) mint tokens **as the agent identity** (Step 1) without storing the agent's password.

### Portal

1. App registration → **Certificates & secrets** → **Federated credentials** → **+ Add credential**.
2. **Federated credential scenario**: **Other issuer**.
3. Fields (these exact values):
   - **Issuer**: `api://AzureAdTokenExchange`
   - **Subject identifier**: leave blank for now (Step 4 fills this)
   - **Name**: `aa-instance-fic`
   - **Audience**: `api://AzureAdTokenExchange`
4. **Save**. We come back to set the Subject after Step 4.

### Azure CLI (run AFTER Step 4 — you need AA_INSTANCE_ID first)

```bash
# Replace <AA_INSTANCE_ID> with the value from Step 4
AA_INSTANCE_ID="<AA_INSTANCE_ID>"

az ad app federated-credential create \
  --id "$A365_APP_ID" \
  --parameters "{
    \"name\": \"aa-instance-fic\",
    \"issuer\": \"api://AzureAdTokenExchange\",
    \"subject\": \"${AA_INSTANCE_ID}\",
    \"audiences\": [\"api://AzureAdTokenExchange\"],
    \"description\": \"FIC for OpenClaw agent T2 token exchange\"
  }"

# Verify FIC was created correctly
az ad app federated-credential list --id "$A365_APP_ID" \
  --query "[].{name:name, subject:subject}" -o table
```

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

### Portal

1. **Entra admin center** → **Users** → click *your own* account.
2. **Object ID** → `.env` → `OWNER_AAD_ID`.
3. **User principal name** → `.env` → `OWNER`.

### Azure CLI

```bash
# Get your own identity from the current az login session
OWNER=$(az ad signed-in-user show --query userPrincipalName -o tsv)
OWNER_AAD_ID=$(az ad signed-in-user show --query id -o tsv)

echo "OWNER=$OWNER"
echo "OWNER_AAD_ID=$OWNER_AAD_ID"
```

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

### Azure CLI verification commands

```bash
# 1. Confirm app registration exists
az ad app show --id "$A365_APP_ID" \
  --query '{appId:appId, name:displayName, signInAudience:signInAudience}' -o table

# 2. Confirm API permissions and admin consent
az ad app permission list --id "$A365_APP_ID" -o table
az ad app permission list-grants --id "$A365_APP_ID" -o table

# 3. Confirm FIC subject matches AA_INSTANCE_ID
az ad app federated-credential list --id "$A365_APP_ID" \
  --query "[].{name:name, subject:subject, issuer:issuer}" -o table

# 4. Confirm agent user exists
az ad user show --id "$AGENT_IDENTITY" \
  --query '{upn:userPrincipalName, id:id, jobTitle:jobTitle}' -o table

# 5. Confirm your owner identity
az ad signed-in-user show --query '{upn:userPrincipalName, id:id}' -o table
```

### Automated .env verification

```bash
# Run the full preflight check for Phase 2
./scripts/preflight.sh --phase 2

# Or just verify .env completeness inline
cd phase-2-tool-integration-capability-perimeters/a365-plugin
for var in A365_APP_ID A365_APP_PASSWORD A365_TENANT_ID AA_INSTANCE_ID \
           AGENT_IDENTITY OWNER OWNER_AAD_ID; do
  val=$(grep -E "^${var}=" .env | cut -d= -f2- || echo "")
  if [ -z "$val" ]; then
    echo "❌ MISSING: $var"
  else
    echo "✅ $var = ${val:0:8}..."
  fi
done
```

### FIC token acquisition test

```bash
# Sanity-test FIC token acquisition without running the full container:
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
