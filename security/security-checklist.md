# Security Checklist — openclaw-agent365

Validate before every production release. Each item has an owner and a verification command where applicable.

---

## 1. Secrets Management

- [ ] **No secrets in source** — `git grep -rn "APP_PASSWORD\|API_KEY\|CLIENT_SECRET" -- ':!*.example' ':!*.md'` returns nothing sensitive
- [ ] **All secrets in Key Vault** — `A365_APP_PASSWORD`, `ANTHROPIC_API_KEY`, and `APPINSIGHTS_CONNECTION_STRING` set via Key Vault references in Container App
- [ ] **GitHub Secrets configured** — Workflow secrets set in repo Settings → Secrets (not hardcoded in YML)
- [ ] **`.env` in `.gitignore`** — verified: `git ls-files .env` returns empty
- [ ] **Secret rotation plan documented** — Key Vault secrets have expiry dates set

---

## 2. App Registration & Permissions (Least Privilege)

- [ ] **Minimum required Graph API permissions only:**
  - `Calendars.ReadWrite` — application permission, for agent identity only
  - `Mail.Send` — application permission, for agent identity only
  - `User.Read.All` — application permission (if user lookup required)
  - Remove any broader scopes (e.g., `Mail.ReadWrite`, `Files.ReadWrite.All`) unless justified
- [ ] **Admin consent granted** for application permissions
- [ ] **Token lifetime policy** — access tokens ≤ 1 hour; refresh token lifetime configured per tenant policy
- [ ] **Federated Identity Credentials (FIC)** configured for `AA_INSTANCE_ID` in Agent365 registration
- [ ] **Single-tenant** app registration (`AzureADMyOrg` audience) unless multi-tenant is explicitly required

---

## 3. Container & Runtime Security

- [ ] **Non-root user** in Dockerfile — `docker inspect <image> --format '{{.Config.User}}'` returns `appuser`
- [ ] **No admin-level capabilities by default** — `--cap-add=NET_ADMIN` only when `NETWORK_MODE=restricted|allowlist`
- [ ] **Network policy tested** — if `NETWORK_MODE=restricted`, verify outbound connections are blocked to non-essential domains
- [ ] **Image pinned to digest** in production — use `sha256:...` digest, not just a tag
- [ ] **Base image scanned** — `docker scout cves openclaw-agent365:<tag>` or Trivy scan in CI
- [ ] **No sensitive data in image layers** — `docker history --no-trunc <image>` shows no env vars with secrets

---

## 4. Static Analysis & Dependencies

- [ ] **CodeQL passes** — no critical or high findings in GitHub Security → Code scanning
- [ ] **`npm audit` clean** — `npm audit --audit-level=high` exits 0
- [ ] **Dependabot alerts addressed** — GitHub Security → Dependabot alerts: 0 critical/high open
- [ ] **License compliance** — all dependencies compatible with MIT (check with `license-checker`)

---

## 5. Transport & Endpoint Security

- [ ] **HTTPS enforced** — Container App ingress uses HTTPS; HTTP redirects to HTTPS
- [ ] **Bot Framework auth enabled** — `MicrosoftAppId` and `MicrosoftAppPassword` set; adapter rejects unauthenticated requests
- [ ] **Health endpoint is read-only** — `GET /health` returns no sensitive data (no secrets, connection strings, or AAD IDs)
- [ ] **Content-Security-Policy** — if serving any HTML, add CSP headers

---

## 6. Agentic Identity

- [ ] **Agent identity has only shared resources** — verify `AGENT_IDENTITY` calendar and mail access is explicitly shared by owner, not granted globally
- [ ] **Audit logs reviewed** — Entra ID sign-in logs for `AGENT_IDENTITY` show expected access patterns only
- [ ] **Owner AAD ID validated** — `OWNER_AAD_ID` matches the intended owner's Entra ID object (prevents privilege escalation)
- [ ] **DM policy set appropriately** for production (`pairing` or `closed` recommended)

---

## 7. Observability & Incident Response

- [ ] **Application Insights connected** — telemetry visible in Azure portal
- [ ] **Alert rules configured** — alert on 5xx error rate, health probe failures, and dependency failures
- [ ] **Log retention** — Log Analytics workspace retention ≥ 30 days (90 for compliance)
- [ ] **Incident runbook linked** — `docs/rollback.md` is current and tested

---

## Sign-off

| Role | Name | Date |
|---|---|---|
| Developer | | |
| Security reviewer | | |
| Release approver | | |

---

## References

- [Microsoft Agent 365 Security Guidance](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/)
- [Azure Key Vault best practices](https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices)
- [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
- [SidU/openclaw-a365 — Network policy](https://github.com/SidU/openclaw-a365#network-policy)
