# Release Checklist — openclaw-agent365

Run this checklist for every production release. Copy to a GitHub Issue or PR description and tick each box.

---

## Pre-release (developer)

### Code & Tests
- [ ] All CI checks green on `main` (`ci.yml`)
- [ ] `npm test` passes locally with 0 failures
- [ ] `npm run lint` passes with 0 warnings
- [ ] `npm run typecheck` passes
- [ ] E2E tests pass against staging (`e2e.yml` workflow green)
- [ ] SDK versions reviewed in E2E "Log SDK Versions" step — no unexpected upgrades

### Security
- [ ] Security checklist (`security/security-checklist.md`) signed off
- [ ] `npm audit --audit-level=high` exits 0
- [ ] CodeQL scan: 0 critical/high findings
- [ ] No secrets in git history: `git log --all --oneline | head -20` reviewed
- [ ] Key Vault secrets are current and not expired

### Configuration
- [ ] `.env.example` is up to date with all new env vars
- [ ] IaC (`iac/azure-resources.bicep`) reflects current resource requirements
- [ ] GitHub Secrets / Variables updated for new env vars

---

## Release (release engineer)

### Azure deployment (manual path)

If `release.yml` is unavailable, the same release can be cut from a workstation using the [scripts/](../scripts/) automation. Run in this order — each step is idempotent:

```bash
pnpm run az:login                                                 # device-code or --service-principal
pnpm run az:app-reg -- --display-name "openclaw-agent365-prod" \
                       --agent-identity agent@<domain> --write-env
AZ_RESOURCE_GROUP=rg-oca365-prod pnpm run az:provision            # validates + deploys bicep
pnpm run az:kv-seed -- --sync-env                                 # .env → Key Vault
IMAGE_TAG=v<MAJOR>.<MINOR>.<PATCH> pnpm run az:deploy             # build + roll out + health check
```

- [ ] `iac/.last-deployment.json` written with this release's outputs
- [ ] `pnpm run az:deploy` reports `Revision … Succeeded` and `/health` passes
- [ ] Image digest recorded from `az acr repository show-manifests` for rollback

### Tag & Build (CI path)
```bash
# Create signed tag
git tag -s v<MAJOR>.<MINOR>.<PATCH> -m "Release v<MAJOR>.<MINOR>.<PATCH>"
git push origin v<MAJOR>.<MINOR>.<PATCH>

# release.yml workflow fires automatically — monitor in GitHub Actions
```

- [ ] Tag pushed; `release.yml` workflow started
- [ ] Container image built and pushed to ACR: `<acr>/openclaw-agent365:v<version>`
- [ ] Image digest recorded: `sha256:...` (immutable reference for rollback)

### Staging Validation
- [ ] Deployed to staging Container App
- [ ] `GET <STAGING_URL>/health` returns `200 {"status":"ok"}`
- [ ] Manual smoke test: send a test message via Teams Bot Framework Emulator
- [ ] Application Insights shows telemetry for the staging deployment

### Manual Approval → Production
- [ ] Release approver reviews staging results in GitHub Actions
- [ ] Approver clicks "Approve" in GitHub Environments → production
- [ ] Production deployment completes
- [ ] `GET <PROD_URL>/health` returns `200 {"status":"ok"}`
- [ ] Application Insights telemetry flowing for production
- [ ] Container App revision labelled `stable`

---

## Post-release (within 1 hour)

- [ ] Send Teams message through production; verify agent responds correctly
- [ ] Check Application Insights Live Metrics for 5xx errors or dependency failures
- [ ] Verify alert rules are active (no false positives fired)
- [ ] Update CHANGELOG.md with release notes
- [ ] Notify stakeholders

---

## Acceptance Criteria (all must pass before ✅ production sign-off)

| Criterion | Verification |
|---|---|
| `GET /health → 200` | `curl -sf <PROD_URL>/health \| jq .status` = `"ok"` |
| Agent responds in Teams | Manual smoke test via deployed agent |
| No critical security findings | CodeQL + npm audit green |
| Telemetry visible | Application Insights traces appear within 5 min |
| Secrets in Key Vault only | `env \| grep -i key\|password\|secret` returns nothing on container |
| Image is immutable | Digest pinned in release notes; not just a floating tag |

---

## Rollback Trigger

Roll back immediately if:
- Production health check fails after 3 retries
- Error rate > 5% over 5 minutes (Application Insights alert)
- Security vulnerability discovered post-deploy
- Agent sends unexpected or harmful responses

→ See `docs/rollback.md` for step-by-step rollback commands.
