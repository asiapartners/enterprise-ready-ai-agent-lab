# Network Policy & Capability Perimeters

`openclaw-a365` uses iptables-based network policy enforcement to constrain which external services the agent (and any tools it uses) can reach at runtime. This is a key enterprise governance capability.

---

## Why Capability Perimeters?

A powerful AI agent with tool access can, in principle, exfiltrate data to any internet endpoint — either through misuse, a compromised LLM, or a prompt injection attack. Network policy enforcement addresses this at the infrastructure level, not the application level.

The principle: **even if the LLM decides to make a request to an unauthorized endpoint, the kernel will block it.**

---

## The Three Modes

Set `NETWORK_MODE` in your `.env`:

### `unrestricted` (default)
No iptables rules are applied. The container has full outbound internet access.

```env
NETWORK_MODE=unrestricted
```

**Use when**: Local development, initial setup, debugging connectivity issues.

### `restricted`
Only the essential Microsoft services are permitted. Everything else is blocked.

```env
NETWORK_MODE=restricted
```

**Always-allowed domains in restricted mode:**
- `login.microsoftonline.com` — Azure AD authentication (token acquisition)
- `graph.microsoft.com` — Microsoft Graph API (calendar, mail, users)
- `smba.trafficmanager.net` — Microsoft Teams messaging infrastructure
- `*.botframework.com` — Bot Framework webhook delivery
- Your LLM provider endpoint (Azure OpenAI, Anthropic, etc.)

**Use when**: Production deployments, any environment handling sensitive business data.

### `allowlist`
Fine-grained control. Allows essential Microsoft services plus your explicitly specified domains.

```env
NETWORK_MODE=allowlist
NETWORK_ALLOWLIST=api.yourcrm.com,data.youranalytics.com,internal.company.net
```

**Use when**: You need specific third-party integrations beyond the Microsoft stack, while still blocking general internet access.

---

## How Enforcement Works

The `scripts/entrypoint.sh` runs before the OpenClaw gateway starts:

```
Container startup
    ↓
entrypoint.sh reads NETWORK_MODE
    ↓
If restricted/allowlist:
  iptables -F OUTPUT (flush existing rules)
  iptables -A OUTPUT -o lo -j ACCEPT         (loopback: always allowed)
  iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 443 ...  (HTTPS to allowed hosts)
  iptables -A OUTPUT -p tcp --dport 53 ...   (DNS: always allowed)
  iptables -A OUTPUT -j REJECT --reject-with icmp-net-unreachable
    ↓
OpenClaw gateway starts
```

The `NET_ADMIN` capability in `docker-compose.yml` is required for iptables access:
```yaml
cap_add:
  - NET_ADMIN
```

---

## Progression Strategy

For a new deployment, progress through modes as you gain confidence:

```
1. Start: NETWORK_MODE=unrestricted
   → Get everything working, verify tools, debug issues
   
2. Observe: what external endpoints does the agent actually call?
   docker-compose exec openclaw-a365 ss -tnp | grep ESTABLISHED
   
3. Restrict: NETWORK_MODE=restricted
   → Verify agent still works for all intended use cases
   → Watch for "connection refused" or "name resolution failed" errors
   
4. Fine-tune: NETWORK_MODE=allowlist + NETWORK_ALLOWLIST
   → Add only the specific domains your use case needs
   → Document why each domain is permitted
```

---

## Testing Network Policy

### Verify policy is active:

```bash
docker-compose exec openclaw-a365 iptables -L OUTPUT -n --line-numbers
```

Expected output with `restricted` mode:
```
Chain OUTPUT (policy ACCEPT)
num  target     prot opt source          destination
1    ACCEPT     all  --  0.0.0.0/0       0.0.0.0/0    /* loopback */
2    ACCEPT     all  --  0.0.0.0/0       0.0.0.0/0    ctstate RELATED,ESTABLISHED
3    ACCEPT     tcp  --  0.0.0.0/0       0.0.0.0/0    tcp dpt:443
4    ACCEPT     tcp  --  0.0.0.0/0       0.0.0.0/0    tcp dpt:80
5    REJECT     all  --  0.0.0.0/0       0.0.0.0/0    reject-with icmp-net-unreachable
```

### Test that unauthorized requests are blocked:

```bash
docker-compose exec openclaw-a365 curl -m 5 https://example.com
# Expected: curl: (7) Failed to connect ... or icmp-net-unreachable
```

### Test that Graph API still works:

```bash
docker-compose exec openclaw-a365 curl -m 10 https://graph.microsoft.com/v1.0/$metadata
# Expected: OData metadata XML (200 response)
```

---

## LLM Provider Configuration

Your LLM endpoint also needs to be reachable. The entrypoint script allows port 443 (HTTPS) broadly, so this typically works automatically. For stricter IP-based rules, add your LLM provider's IP range to the allowlist.

**Azure OpenAI** (recommended for enterprise):
```env
NETWORK_MODE=restricted
# Azure OpenAI is on *.openai.azure.com — covered by HTTPS allowance
```

**Anthropic**:
```env
NETWORK_MODE=allowlist
NETWORK_ALLOWLIST=api.anthropic.com
```

**OpenAI**:
```env
NETWORK_MODE=allowlist
NETWORK_ALLOWLIST=api.openai.com
```

---

## Multi-Container Environments

If you run multiple OpenClaw containers, each container has its own independent network policy. The `docker-compose.yml` volume mounts are isolated per container.

For Kubernetes or multi-container orchestration, supplement iptables rules with:
- **Kubernetes NetworkPolicy** objects
- **Azure Private Link** for Microsoft services
- **Service Mesh** (Istio / Linkerd) for mTLS and egress control

---

## Security Model

The capability perimeter enforces the **principle of least privilege at the network layer**:

1. The container can only reach what it absolutely needs
2. Even if the LLM generates a bash command that tries to `curl` an external data sink, the kernel blocks it
3. Even if a malicious tool or npm package tries to exfiltrate data, the connection is refused

This is defense in depth — it doesn't replace application-layer security, but it catches entire categories of attacks.

---

## Known Limitations

- **DNS resolution**: The entrypoint uses DNS lookups to resolve allowed domains to IPs. If DNS fails at startup, some allowed hosts may not be reachable. The rules are re-applied on container restart.
- **IP-based rules can be bypassed via CDN IP sharing**: Microsoft's CDN IPs may overlap with non-Microsoft services. For maximum isolation, use Azure Private Endpoints instead of internet-based rules.
- **Rules are stateless**: The iptables rules are applied at startup and not dynamically updated. Restarting the container reapplies them.

---

## Next Steps

→ Continue to [APPROVAL_WORKFLOWS.md](./APPROVAL_WORKFLOWS.md) to configure safety boundaries and human-in-the-loop patterns
