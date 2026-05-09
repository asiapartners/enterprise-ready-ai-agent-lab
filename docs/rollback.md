# Rollback Runbook — openclaw-agent365

Execute this runbook when a production deployment needs to be reverted.
All commands are copy-pasteable. Replace `<values>` with actuals from the release notes.

---

## Step 0 — Declare incident

```bash
# Notify the team immediately
# Record: previous stable image tag, incident start time, symptoms
echo "INCIDENT DECLARED — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Previous stable image: <ACR>/openclaw-agent365:<PREVIOUS_TAG>"
```

---

## Step 1 — Identify the previous stable image

```bash
# List recent images in ACR
az acr repository show-tags \
  --name <ACR_NAME> \
  --repository openclaw-agent365 \
  --orderby time_desc \
  --top 10 \
  --output table

# Or check the release workflow for the last green run's image digest
# GitHub Actions → release.yml → previous successful run → Release Summary step
```

---

## Step 2 — Rollback Container App to previous revision

```bash
RG=<RESOURCE_GROUP>
APP=<CONTAINER_APP_NAME_PROD>
PREVIOUS_TAG=<PREVIOUS_STABLE_TAG>   # e.g. v1.2.3
ACR=<ACR_LOGIN_SERVER>               # e.g. acropenclaw.azurecr.io

# Option A: Redeploy previous image (preferred — creates new revision from old image)
az containerapp update \
  --name "$APP" \
  --resource-group "$RG" \
  --image "$ACR/openclaw-agent365:$PREVIOUS_TAG"

# Option B: Traffic split — route 100% to the previous stable revision
az containerapp revision set-mode \
  --name "$APP" \
  --resource-group "$RG" \
  --mode Multiple

STABLE_REVISION=$(az containerapp revision list \
  --name "$APP" \
  --resource-group "$RG" \
  --query "[?properties.trafficWeight == \`0\` && labels.stable == 'stable'].name | [0]" \
  --output tsv)

az containerapp ingress traffic set \
  --name "$APP" \
  --resource-group "$RG" \
  --revision-weight "$STABLE_REVISION=100"
```

---

## Step 3 — Verify rollback

```bash
PROD_URL=<PROD_URL>

# Health check
curl -sf "$PROD_URL/health" | jq .

# Expect: {"status":"ok","version":"<PREVIOUS_TAG>","env":"production",...}

# Wait for all replicas to update (check active revisions)
az containerapp revision list \
  --name "$APP" \
  --resource-group "$RG" \
  --query "[].{name:name,image:properties.template.containers[0].image,traffic:properties.trafficWeight,active:properties.active}" \
  --output table
```

---

## Step 4 — Revoke problematic app registration (if security incident)

```bash
# Only if the rollback is due to a credential leak or compromised app registration
APP_OBJECT_ID=<AAD_APP_OBJECT_ID>

# Rotate the client secret immediately
az ad app credential reset --id "$APP_OBJECT_ID" --display-name "emergency-rotation"

# Update Key Vault with new secret
az keyvault secret set \
  --vault-name <KEY_VAULT_NAME> \
  --name A365-APP-PASSWORD \
  --value "<NEW_SECRET>"

# Restart the container app to pick up new secret reference
az containerapp revision restart \
  --name "$APP" \
  --resource-group "$RG" \
  --revision "$STABLE_REVISION"
```

---

## Step 5 — Post-rollback validation

```bash
# 1. Health check (again, after secret rotation if applicable)
curl -sf "$PROD_URL/health" | jq .

# 2. Check Application Insights for error rate returning to baseline
# Portal: Application Insights → Failures → last 30 min

# 3. Send a test Teams message and verify agent responds normally
```

---

## Step 6 — Root cause analysis

- Open a GitHub Issue: `[Incident] <date> — <short description>`
- Link: failing workflow run, container logs, App Insights query
- Assign: release engineer + security reviewer
- Blameless postmortem within 48 hours of resolution

---

## Rollback Decision Matrix

| Symptom | Action |
|---|---|
| `GET /health` fails | Step 2 — rollback revision |
| Agent sends wrong responses | Step 2 — rollback; check OpenClaw config |
| 5xx error rate > 5% | Step 2 — rollback; check App Insights exceptions |
| Credential leaked in logs | Step 2 + Step 4 — rollback + secret rotation |
| Graph API 403/401 errors | Check FIC token; may not need full rollback |
| Teams not receiving messages | Check Bot Framework endpoint URL; likely config issue |

---

## References

- [Azure Container Apps revisions](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Azure Container Apps traffic splitting](https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting)
- [Key Vault secret rotation](https://learn.microsoft.com/en-us/azure/key-vault/secrets/tutorial-rotation)
