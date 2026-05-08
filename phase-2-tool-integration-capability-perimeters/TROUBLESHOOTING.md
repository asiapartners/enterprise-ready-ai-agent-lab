# Phase 2 Troubleshooting

Common issues when deploying `openclaw-a365` and their solutions.

---

## Container Issues

### Container fails to start

**Symptoms**: `docker-compose up` exits immediately or `docker-compose logs` shows errors at startup

**Check 1: Missing .env values**
```bash
docker-compose exec openclaw-a365 env | grep A365
# Expected: A365_APP_ID, A365_APP_PASSWORD, A365_TENANT_ID all set
```

If any are missing, check your `.env` file against `.env.example`.

**Check 2: NET_ADMIN capability**
```bash
docker-compose exec openclaw-a365 iptables -L
# Should not return "Operation not permitted"
```

If iptables fails, ensure `cap_add: [NET_ADMIN]` is in `docker-compose.yml`.

**Check 3: Port conflict**
```bash
lsof -i :3978
```
If another process is using port 3978, change the port in `docker-compose.yml`:
```yaml
ports:
  - "3979:3978"  # Use 3979 externally
```
Then update your messaging endpoint in Azure Bot → Configuration.

---

### Container is running but bot doesn't respond

**Check health endpoints:**
```bash
curl http://localhost:18789/health    # OpenClaw gateway
curl http://localhost:3978/api/messages -X POST  # Should return 401, not 404
```

If the OpenClaw gateway returns 404 or refuses connection: check `docker-compose logs` for startup errors.

If the Bot Framework endpoint returns 404 (not 401): the Express server failed to start. Check for port conflicts or errors in the a365 plugin.

---

### "Operation not permitted" for iptables

The container needs `NET_ADMIN` capability. Verify your `docker-compose.yml`:
```yaml
services:
  openclaw-a365:
    cap_add:
      - NET_ADMIN
```

If you're using Kubernetes, add to the pod security context:
```yaml
securityContext:
  capabilities:
    add: ["NET_ADMIN"]
```

---

## Authentication Errors

### T1 token acquisition fails

**Error**: `Failed to acquire T1 token` or `AADSTS700016`

**Cause**: `A365_APP_ID` or `A365_APP_PASSWORD` is incorrect.

**Fix**:
1. Go to Azure Portal → App registrations → your app
2. Verify the Application (client) ID matches `A365_APP_ID`
3. Go to Certificates & secrets → create a new secret if the old one expired
4. Update `A365_APP_PASSWORD` with the new secret value

---

### T2 token request fails with 401

**Error**: `T2 token request failed: 401`

**Cause**: The M365 Agents Instance (`aaInstanceId`) is not configured or the T1 token doesn't have the right scope.

**Fix**:
1. Verify `AA_INSTANCE_ID` is set and correct
2. Confirm the Bot Framework scope is permitted: `https://api.botframework.com/.default`
3. Check that admin consent was granted for Bot Framework permissions

---

### Graph API returns 403 Forbidden

**Error**: `GraphError: Insufficient privileges to complete the operation`

**Cause**: Admin consent not granted for Graph API permissions.

**Fix**:
1. Go to Azure Portal → App registrations → your app → API permissions
2. Confirm `Calendars.ReadWrite`, `Mail.Send`, `User.Read.All` are listed
3. Click **Grant admin consent for [your org]**
4. Wait 5 minutes and retry

---

### Graph API returns 404 for calendar

**Error**: `Resource not found for the segment 'calendar'`

**Cause**: The agent user (`AGENT_IDENTITY`) doesn't have a license or mailbox.

**Fix**:
1. Go to Azure AD → Users → your agent user
2. Assign a Microsoft 365 license with Exchange Online
3. Wait 15 minutes for the mailbox to provision
4. Retry

---

### "Calendar not found" or "No events returned"

**Cause**: Calendar sharing not configured between agent and owner.

**Fix**:
1. Open Outlook Web App as the owner
2. Go to Calendar → right-click → Sharing and permissions
3. Add `AGENT_IDENTITY` email with "Can edit" permission
4. Wait 5 minutes and retry

---

## Teams Integration Issues

### Bot shows in Teams but doesn't respond

**Check 1: Messaging endpoint**
- Azure Portal → Azure Bot → Configuration
- Verify the endpoint is the HTTPS URL of your webhook (not HTTP)
- Test accessibility: `curl https://your-endpoint/api/messages` should return 401

**Check 2: Bot ID mismatch**
- In your Teams manifest, `botId` must exactly match `A365_APP_ID`
- Even a single character difference prevents message delivery

**Check 3: Container is running**
```bash
docker-compose ps
docker-compose logs --tail=50 openclaw-a365
```

---

### "Bot not found" when searching in Teams

The bot hasn't been installed yet. Follow [setup/M365_AGENTS_SETUP.md](./setup/M365_AGENTS_SETUP.md) Steps 5–6 to create and install the Teams app manifest.

---

### Bot responds but shows HTML or raw JSON

The LLM provider is likely returning an error that the agent is passing through. Check:
```bash
docker-compose logs openclaw-a365 | grep -i "error\|openai\|anthropic\|azure"
```

Common causes:
- Invalid or expired API key for the LLM provider
- Rate limit exceeded
- Model not available in the Azure OpenAI deployment

---

### Bot responds with "I'm outside business hours"

You have `BUSINESS_HOURS_START` and `BUSINESS_HOURS_END` configured. Either:
1. Adjust business hours in `.env`
2. Remove business hours configuration for 24/7 access

---

## Network Policy Issues

### Agent stops working after enabling `NETWORK_MODE=restricted`

This means the LLM provider or another required endpoint is being blocked.

**Debug**:
```bash
# Check what's being blocked
docker-compose exec openclaw-a365 iptables -L OUTPUT -n -v

# Test specific endpoints
docker-compose exec openclaw-a365 curl -m 5 https://graph.microsoft.com/v1.0/
docker-compose exec openclaw-a365 curl -m 5 https://api.anthropic.com/  # if using Anthropic
docker-compose exec openclaw-a365 curl -m 5 https://your-resource.openai.azure.com/  # if using Azure OpenAI
```

**Fix**: Switch to `allowlist` mode and add your LLM provider:
```env
NETWORK_MODE=allowlist
NETWORK_ALLOWLIST=api.anthropic.com
# or: NETWORK_ALLOWLIST=your-resource.openai.azure.com
```

---

### iptables rules not applied on restart

**Cause**: The entrypoint script may have failed silently.

```bash
docker-compose exec openclaw-a365 cat /entrypoint.sh
docker-compose logs openclaw-a365 | grep "entrypoint\|iptables"
```

Verify `NETWORK_MODE` is set in `.env` (not just in `docker-compose.yml` environment section).

---

## Graph Tool Issues

### `send_gif` tool not available

The `send_gif` tool only appears when `KLIPY_API_KEY` is set:
```env
KLIPY_API_KEY=your-klipy-api-key
```

Get a key at https://partner.klipy.com/api-keys

---

### Calendar events show wrong timezone

Set the correct timezone in your `.env`:
```env
BUSINESS_HOURS_TIMEZONE=America/Los_Angeles
```

Ensure you're passing IANA timezone names (not Windows timezone names):
- ✅ `America/New_York`
- ❌ `Eastern Standard Time`

---

### `find_meeting_times` returns "No suggestions found"

This happens when there are no overlapping free slots in the requested window.

Try:
- A wider time window (e.g., 2 weeks instead of 1 week)
- A shorter meeting duration
- Fewer attendees

---

### Email sends but goes to spam

The agent sends from `AGENT_IDENTITY`. If this account is new or sends infrequently, emails may be flagged as spam.

To improve deliverability:
1. Set SPF/DKIM records for your domain (Exchange Online does this automatically for managed domains)
2. Have the agent send a test email to verify it's not flagged
3. For bulk sends, consider using the owner's "Send on behalf of" delegation

---

## Token Cache Issues

### Agent gets stale tokens after credential rotation

```bash
# Restart the container to flush the in-memory token cache
docker-compose restart openclaw-a365
```

Or add a cache invalidation endpoint to the plugin for production use.

---

## Getting More Debug Info

Enable verbose logging:
```env
LOG_LEVEL=debug
```

View structured logs:
```bash
docker-compose logs -f --tail=100 openclaw-a365 | grep -E "ERROR|WARN|graph|token|auth"
```

---

## Still Stuck?

1. Check [a365-plugin/AGENT_GUIDE.md](./a365-plugin/AGENT_GUIDE.md) for architecture details
2. Check [Known Issues](./a365-plugin/AGENT_GUIDE.md) section for documented limitations
3. Verify all prerequisites in [AZURE_ENTRA_SETUP.md](./setup/AZURE_ENTRA_SETUP.md)
4. Open an issue at the [openclaw-a365 source repo](https://github.com/SidU/openclaw-a365)
