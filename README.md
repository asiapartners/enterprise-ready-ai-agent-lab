# openclaw-agent365-integration

Production-ready scaffold for building Microsoft 365 Copilot and Teams agents by integrating [OpenClaw](https://github.com/openclaw/openclaw) (TypeScript multi-channel AI runtime) with the [Microsoft Agent 365 SDK](https://github.com/microsoft/Agent365-Samples) (Node.js sample).

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  Microsoft Teams / M365 Copilot                         │
└────────────────────────┬────────────────────────────────┘
                         │ Bot Framework / Agent Protocol
┌────────────────────────▼────────────────────────────────┐
│  Azure Container App / Web App                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Agent365 Activity Handler (src/agent.ts)        │   │
│  │  ┌────────────────────────────────────────────┐  │   │
│  │  │  OpenClaw Connector (src/openclaw-connector│  │   │
│  │  │  .ts) — routes activities to OpenClaw     │  │   │
│  │  │  runtime (plugin host, multi-channel)      │  │   │
│  │  └────────────────────────────────────────────┘  │   │
│  │  OpenTelemetry → Application Insights            │   │
│  └──────────────────────────────────────────────────┘   │
│  Azure Key Vault (secrets) | Azure AD App Registration  │
└─────────────────────────────────────────────────────────┘
```

See [docs/architecture.md](docs/architecture.md) for the full component diagram and responsibility matrix.

---

## Quick Start

### Prerequisites

- Node.js ≥ 20 LTS
- Docker Desktop (or compatible OCI runtime)
- Azure CLI (`az login` ready)
- An Azure subscription with permissions to register apps and create resources

### 1 — Clone upstream repos + this scaffold

```bash
git clone https://github.com/openclaw/openclaw.git
git clone https://github.com/microsoft/Agent365-Samples.git
git clone <this-repo-url> openclaw-agent365
cd openclaw-agent365
```

### 2 — Configure environment

```bash
cp .env.example .env
# Edit .env — fill in non-secret values; secrets go into Key Vault / GitHub Secrets
```

### 3 — Dev container (recommended)

```bash
# VS Code: open folder → "Reopen in Container"
# or manually:
docker compose -f .devcontainer/docker-compose.yml up
```

### 4 — Local run (without container)

```bash
npm ci
npm run build
npm start
```

Verify:

```bash
curl http://localhost:8080/health
# → {"status":"ok","version":"..."}
```

### 5 — Run tests

```bash
npm test            # unit + integration
npm run test:e2e    # end-to-end (requires env vars set)
```

---

## Project Structure

```
openclaw-agent365/
├── src/
│   ├── index.ts               # Express server + Bot Framework adapter
│   ├── agent.ts               # TeamsActivityHandler (Agent365 pattern)
│   ├── openclaw-connector.ts  # OpenClaw runtime bridge
│   ├── config.ts              # Typed config from env vars
│   └── telemetry.ts           # OpenTelemetry / App Insights setup
├── .devcontainer/
│   ├── devcontainer.json
│   └── docker-compose.yml
├── Dockerfile
├── .github/workflows/
│   ├── ci.yml                 # Build, lint, unit tests
│   ├── e2e.yml                # E2E tests + SDK version logging
│   └── release.yml            # Container build → ACR → staging → prod
├── iac/
│   └── azure-resources.bicep  # Container App, Key Vault, App Insights, AAD
├── security/
│   └── security-checklist.md
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
└── docs/
    ├── architecture.md
    ├── release-checklist.md
    └── rollback.md
```

---

## Environment Variables

| Variable | Example | Notes |
|---|---|---|
| `APP_ENV` | `development` | `development` \| `staging` \| `production` |
| `PORT` | `8080` | HTTP listen port |
| `OPENCLAW_CONFIG_PATH` | `/app/config` | Path to OpenClaw config dir |
| `OPENCLAW_PLUGIN_DIR` | `/app/plugins` | Optional plugin directory |
| `AGENT365_SDK_VERSION` | `^1.0.0` | Pinned in package.json; inspect E2E "Log SDK Versions" step |
| `AZURE_TENANT_ID` | `<guid>` | From App Registration |
| `AZURE_CLIENT_ID` | `<guid>` | Bot app client ID |
| `AZURE_SUBSCRIPTION_ID` | `<guid>` | Target Azure subscription |
| `MICROSOFT_APP_TYPE` | `MultiTenant` | `MultiTenant` \| `SingleTenant` \| `UserAssignedMSI` |
| `KEY_VAULT_URI` | `https://<name>.vault.azure.net/` | Secrets resolved at runtime |
| `APPINSIGHTS_CONNECTION_STRING` | `InstrumentationKey=...` | From App Insights resource |
| `OTEL_SERVICE_NAME` | `openclaw-agent365` | OpenTelemetry resource attribute |

**Never commit secrets.** Secrets (`MICROSOFT_APP_PASSWORD`, `AZURE_CLIENT_SECRET`) are stored in Azure Key Vault and GitHub Secrets only.

---

## Publishing to Teams / Copilot

1. Complete the [Azure AD App Registration](iac/azure-resources.bicep) (app manifest permissions included).
2. Package the Teams app manifest: follow the [Agent365 platform hosting patterns](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/).
3. Submit via Teams Admin Center or Microsoft Partner Center.
4. Run the post-publish smoke test in [docs/release-checklist.md](docs/release-checklist.md).

---

## CI/CD

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci.yml` | Every push / PR | Lint → unit test → build artifact |
| `e2e.yml` | Push to `main`, nightly | Deploy ephemeral → E2E → log SDK versions |
| `release.yml` | Tag `v*.*.*` | Build image → push ACR → staging → manual approval → prod |

---

## References

- [OpenClaw](https://github.com/openclaw/openclaw)
- [Agent365-Samples](https://github.com/microsoft/Agent365-Samples)
- [Microsoft Agent 365 Developer Docs](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/)
- [Microsoft 365 Agents SDK (Node.js)](https://github.com/Microsoft/Agents-for-js)
- [Agent365 SDK Versions — E2E workflow summaries](https://github.com/microsoft/Agent365-Samples/actions/workflows/e2e-orchestrator.yml)

---

## License

MIT © 2026
