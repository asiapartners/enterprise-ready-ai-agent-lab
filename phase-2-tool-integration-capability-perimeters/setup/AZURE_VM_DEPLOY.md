# Azure VM Deploy — Phase 1 Production Hosting

> **Time**: ~25 minutes provisioning + cloud-init.
> **Cost**: ~$65/month while running. `az vm deallocate` to drop to ~$3/month.
> **Region**: `swedencentral` (colocated with Azure OpenAI).

This deploys the OpenClaw A365 agent to a single Ubuntu 22.04 VM with Caddy + Let's Encrypt for HTTPS, system-assigned Managed Identity for Key Vault access, and an iptables-enforced network perimeter inside the container.

## Why a VM (not Azure Container Apps)?

The container needs `--cap-add=NET_ADMIN` so its `outbound.ts` startup script can write iptables rules to enforce `NETWORK_MODE=restricted` / `allowlist`. ACA does not surface raw Linux capabilities. A small B2ms VM is also cheaper than the ACA minimum-replica baseline. See `phase-3-…/ARCHITECTURE.md` for the production migration path to ACA + Private Endpoints once the network policy story matures.

## Prerequisites

- `az` CLI ≥ 2.60, logged in to the right subscription:
  ```bash
  az login
  az account set --subscription "<your-subscription-name-or-id>"
  ```
- An SSH public key at `~/.ssh/id_rsa.pub` (or `id_ed25519.pub`).
- All values in `.env` populated per [`AZURE_ENTRA_SETUP.md`](./AZURE_ENTRA_SETUP.md) and the [Phase 1 guide](../../phase-1-building-autonomous-ai-assistant/README.md).

## What gets deployed

```
Resource group: rg-openclaw-lab-dev (swedencentral)
├── Virtual Network (10.10.0.0/16)
│   └── Subnet "default" (10.10.1.0/24)
├── Public IP (Standard, static)
│   └── DNS label: openclaw-<suffix>.swedencentral.cloudapp.azure.com
├── Network Security Group
│   ├── Allow 22/tcp from <your IP>
│   └── Allow 443/tcp from 0.0.0.0/0
├── VM (Standard_B2ms, Ubuntu 22.04 LTS)
│   ├── System-assigned Managed Identity
│   ├── cloud-init.yaml → installs Docker, Caddy, systemd unit
│   └── /etc/openclaw/.env populated from Key Vault at boot
└── Key Vault (openclaw-kv-<suffix>)
    ├── Secrets: A365_APP_PASSWORD, AZURE_OPENAI_API_KEY, ...
    └── RBAC: VM MI granted "Key Vault Secrets User"
```

## Deploy

```bash
cd ~/projects/openclaw-a365-agent-lab
./infra/deploy.sh dev
```

The script:

1. **Loads `.env`** so it can populate Key Vault.
2. **Creates resource group** `rg-openclaw-lab-dev` in `swedencentral`.
3. **`az deployment group create`** against `infra/main.bicep` — provisions vNet, NSG, Public IP, KV, VM with cloud-init.
4. **Uploads secrets** from `.env` into Key Vault (`A365_APP_PASSWORD`, `AZURE_OPENAI_API_KEY`).
5. **Outputs the FQDN** and SSH command to the terminal.

Watch the VM finish provisioning:

```bash
az vm get-instance-view -g rg-openclaw-lab-dev -n openclaw-vm --query "instanceView.statuses[?code=='ProvisioningState/succeeded']"
```

Tail the cloud-init log:

```bash
ssh azureuser@openclaw-<suffix>.swedencentral.cloudapp.azure.com 'sudo tail -f /var/log/cloud-init-output.log'
```

When you see `Reached target multi-user.target`, the agent container is up.

## Update A365 endpoint

In your Azure Bot resource (created in `AZURE_ENTRA_SETUP.md` Step 7):

1. **Configuration** → **Messaging endpoint**:
   ```
   https://openclaw-<suffix>.swedencentral.cloudapp.azure.com/api/messages
   ```
2. **Save**.

DM the agent in Teams. First request triggers Caddy to issue a Let's Encrypt cert (~10s pause), then responses flow normally.

## How secrets work on the VM

The cloud-init script runs `boot-secrets.sh` on every boot:

```bash
#!/bin/bash
# Authenticate to Azure as the VM's Managed Identity
TOKEN=$(curl -s -H Metadata:true \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" \
  | jq -r .access_token)

# Fetch each secret and write to /etc/openclaw/.env (chmod 600)
for name in A365_APP_PASSWORD AZURE_OPENAI_API_KEY; do
  value=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "https://openclaw-kv-${SUFFIX}.vault.azure.net/secrets/${name}?api-version=7.4" \
    | jq -r .value)
  echo "${name}=${value}" >> /etc/openclaw/.env
done
chmod 600 /etc/openclaw/.env
```

Non-secret env vars (`A365_APP_ID`, `AGENT_IDENTITY`, etc.) are baked into the cloud-init template at deploy time. Secrets never appear in deploy artifacts.

## Operational tasks

### Tail logs

```bash
ssh azureuser@<fqdn> 'sudo docker logs -f openclaw-a365'
```

### Update agent (rebuild)

```bash
ssh azureuser@<fqdn>
cd /opt/openclaw && git pull && sudo docker compose pull && sudo docker compose up -d
```

### Rotate `A365_APP_PASSWORD`

```bash
# 1. Create new secret in Entra → App registration → Certificates & secrets
# 2. Update Key Vault secret
az keyvault secret set --vault-name openclaw-kv-<suffix> \
  --name A365_APP_PASSWORD --value '<new>'
# 3. Restart VM (cloud-init re-runs and pulls new value)
az vm restart -g rg-openclaw-lab-dev -n openclaw-vm
```

### Stop billing while not using

```bash
az vm deallocate -g rg-openclaw-lab-dev -n openclaw-vm
```

The static Public IP keeps the FQDN reserved (~$3/month). To resume:

```bash
az vm start -g rg-openclaw-lab-dev -n openclaw-vm
```

### Tear down completely

```bash
az group delete -g rg-openclaw-lab-dev --yes --no-wait
```

> Note: this deletes the Key Vault. Soft-delete retains it for 90 days. To purge immediately:
> `az keyvault purge --name openclaw-kv-<suffix>`

## Hardening checklist (before showing to anyone)

- [ ] `NETWORK_MODE=restricted` in Key Vault `.env` template
- [ ] NSG inbound 22 rule scoped to **your IP only**, not `0.0.0.0/0`
- [ ] `DM_POLICY=pairing` so unknown Teams users can't message the agent
- [ ] `OWNER_AAD_ID` correct (otherwise no one has Owner role)
- [ ] Bot resource in Azure: **Single tenant**, not multi-tenant
- [ ] Key Vault: soft-delete enabled (default), purge protection enabled (set in Bicep)
- [ ] `npm audit` clean on the container image (Phase 3 adds CI for this)

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Caddy shows "no such site" or HTTP 502 | Container not listening on 3978 | `sudo docker logs openclaw-a365` — usually a missing env var |
| `acme: error: 429: too many failed authorizations` | DNS not propagated yet for the FQDN | Wait 5 min, `caddy reload` |
| Bot reaches endpoint but Teams shows "Sorry, I couldn't reach the bot" | Bot resource endpoint mismatch (`/api/messages` missing) | Re-edit Azure Bot Configuration |
| iptables errors in container logs | `NET_ADMIN` capability missing | Check `docker-compose.yml` has `cap_add: [NET_ADMIN]` |
| Container exits with `Failed to acquire token` | KV secret pull failed (MI not granted yet) | `az role assignment list --assignee <MI-principal-id>` to verify |
