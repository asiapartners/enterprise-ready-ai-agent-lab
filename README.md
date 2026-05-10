# enterprise-ready-ai-agent-lab

Production-ready scaffold for building Microsoft 365 Copilot and Teams agents by integrating [OpenClaw](https://github.com/openclaw/openclaw) (TypeScript multi-channel AI runtime) with the [Microsoft Agent 365 SDK](https://github.com/microsoft/Agent365-Samples) (Node.js sample).

Npm package name: `openclaw-agent365` (see [package.json](package.json)).

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

- Node.js ≥ 24 LTS (see [`engines` in package.json](package.json))
- pnpm ≥ 9 (`corepack enable && corepack prepare pnpm@latest --activate`)
- Docker (optional locally; required for container builds)
- Azure CLI (optional locally; required for Azure deployments)
- An Azure subscription with permissions to register apps and create resources

### 1 — Clone this scaffold

```bash
git clone <this-repo-url> enterprise-ready-ai-agent-lab
cd enterprise-ready-ai-agent-lab
```

The upstream [OpenClaw](https://github.com/openclaw/openclaw) and [Agent365-Samples](https://github.com/microsoft/Agent365-Samples) repos are referenced for documentation only — they are not required as sibling clones.

### 2 — Bootstrap the dev environment

```bash
pnpm run setup     # tool checks, deps, .env scaffold, typecheck, lint
# or step-by-step:
pnpm install
cp .env.example .env
# Edit .env — fill in non-secret values; secrets go into Key Vault / GitHub Secrets
```

### 3 — Local run

```bash
pnpm run build
pnpm start
# or for hot-reload:
pnpm run dev
```

Verify:

```bash
curl http://localhost:3978/health
# → {"status":"ok","version":"..."}
```

### 4 — Run tests

```bash
pnpm test            # unit + integration with coverage
pnpm run test:e2e    # end-to-end (requires env vars set)
pnpm run test:load   # k6 load test (requires k6 installed)
pnpm run typecheck   # tsc --noEmit
pnpm run lint        # eslint with --max-warnings 0
```

---

## Project Structure

```
enterprise-ready-ai-agent-lab/
├── src/
│   ├── index.ts               # Express server + CloudAdapter (Agent365)
│   ├── agent.ts               # Agent365Handler — turn dispatch
│   ├── openclaw-connector.ts  # OpenClaw runtime bridge (SDK → gateway → stub)
│   ├── graph-tools.ts         # Microsoft Graph tools + FIC token exchange
│   ├── config.ts              # Typed, Zod-validated env config
│   └── telemetry.ts           # OpenTelemetry / App Insights setup
├── config/
│   └── openclaw-config.json   # OpenClaw runtime + gateway config
├── openclaw.plugin.json       # OpenClaw plugin manifest
├── teams-app/
│   └── manifest.json          # Teams app manifest
├── iac/
│   └── azure-resources.bicep  # Container App, Key Vault, App Insights, AAD
├── scripts/
│   └── setup.sh               # Local dev bootstrap (pnpm run setup)
├── security/
│   └── security-checklist.md
├── tests/
│   ├── unit/                  # agent, config, openclaw-connector
│   ├── integration/           # health endpoint
│   ├── e2e/                   # full agent flow
│   └── load/                  # k6 load test
├── docs/
│   ├── architecture.md
│   ├── release-checklist.md
│   ├── rollback.md
│   └── labs/                  # Hands-on lab guides
│       ├── phase1-autonomous-agents.md
│       ├── phase2-tool-integration.md
│       └── phase3-multi-agent.md
├── Dockerfile                 # Multi-stage production image
├── jest.config.js
├── tsconfig.json
├── pnpm-lock.yaml
└── package.json
```

> **Not yet present:** `.devcontainer/` and `.github/workflows/` are planned but not committed. CI/CD must be wired up before first release — see [docs/release-checklist.md](docs/release-checklist.md).

---

## Environment Variables

See [.env.example](.env.example) for the full template. Key variables:

| Variable | Example | Notes |
|---|---|---|
| `APP_ENV` | `development` | `development` \| `staging` \| `production` |
| `PORT` | `3978` | HTTP listen port (Bot Framework default) |
| `OPENCLAW_MODEL` | `anthropic/claude-opus-4-6` | Primary LLM model id |
| `OPENCLAW_FALLBACK_MODELS` | `openai/gpt-4o,...` | Comma-separated fallback chain |
| `OPENCLAW_CONFIG_PATH` | `./config` | Path to OpenClaw config dir |
| `OPENCLAW_PLUGIN_DIR` | `./plugins` | Optional plugin directory |
| `OPENCLAW_GATEWAY_URL` | `http://127.0.0.1:18789` | Optional override; otherwise resolved from `config/openclaw-config.json` |
| `A365_APP_ID` | `<guid>` | Bot app registration client ID |
| `A365_APP_PASSWORD` | `<secret>` | Bot client secret (Key Vault in prod) |
| `A365_TENANT_ID` | `<guid>` | Entra ID tenant GUID |
| `MICROSOFT_APP_TYPE` | `SingleTenant` | `MultiTenant` \| `SingleTenant` \| `UserAssignedMSI` |
| `AA_INSTANCE_ID` | `<id>` | Agent 365 Federated Identity instance |
| `AGENT_IDENTITY` | `agent@contoso.com` | Agent's own Entra ID UPN |
| `OWNER` | `owner@contoso.com` | Agent owner UPN |
| `OWNER_AAD_ID` | `<guid>` | Owner Entra ID object ID |
| `ANTHROPIC_API_KEY` | `sk-ant-...` | One LLM key required (or `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `AZURE_OPENAI_API_KEY`) |
| `DM_POLICY` | `pairing` | `open` \| `pairing` \| `closed` |
| `NETWORK_MODE` | `unrestricted` | `unrestricted` \| `restricted` \| `allowlist` (requires `NET_ADMIN`) |
| `KEY_VAULT_URI` | `https://<name>.vault.azure.net/` | Secrets resolved at runtime |
| `APPINSIGHTS_CONNECTION_STRING` | `InstrumentationKey=...` | From App Insights resource |
| `OTEL_SERVICE_NAME` | `openclaw-agent365` | OpenTelemetry resource attribute |

**Never commit secrets.** Secrets (`A365_APP_PASSWORD`, LLM keys) are stored in Azure Key Vault and GitHub Secrets only.

---

## Publishing to Teams / Copilot

1. Complete the [Azure AD App Registration](iac/azure-resources.bicep) (app manifest permissions included).
2. Package the Teams app manifest: follow the [Agent365 platform hosting patterns](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/).
3. Submit via Teams Admin Center or Microsoft Partner Center.
4. Run the post-publish smoke test in [docs/release-checklist.md](docs/release-checklist.md).

---

## CI/CD (planned)

The following GitHub Actions workflows are part of the target release pipeline but are **not yet committed** to `.github/workflows/`. Treat this as the contract to implement before cutting `v1.0.0`.

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci.yml` | Every push / PR | `pnpm lint` → `pnpm typecheck` → `pnpm test` → build artifact |
| `e2e.yml` | Push to `main`, nightly | Deploy ephemeral → `pnpm run test:e2e` → log SDK versions |
| `release.yml` | Tag `v*.*.*` | Build image → push ACR → staging → manual approval → prod |

---

## Hands-on Labs

Progressive lab guides under [docs/labs/](docs/labs/):

1. [Phase 1 — Autonomous agents](docs/labs/phase1-autonomous-agents.md)
2. [Phase 2 — Tool integration](docs/labs/phase2-tool-integration.md)
3. [Phase 3 — Multi-agent orchestration](docs/labs/phase3-multi-agent.md)

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
