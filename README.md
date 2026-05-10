# enterprise-ready-ai-agent-lab

> A production-ready scaffold and **hands-on learning track** for AI developers building Microsoft 365 Copilot / Teams agents that combine the [OpenClaw](https://github.com/openclaw/openclaw) multi-channel runtime with the [Microsoft Agent 365](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/) SDK.

You will go from "no agent" → "Teams-connected agent on your laptop" → "agent on Azure with FIC-bound identity, Key Vault secrets, telemetry, and multi-agent orchestration" — without writing the boilerplate.

---

## Table of contents

1. [Who this is for](#who-this-is-for)
2. [What you'll build](#what-youll-build)
3. [How it works (60-second tour)](#how-it-works-60-second-tour)
4. [Repository map](#repository-map)
5. [Prerequisites](#prerequisites)
6. [Quickstart — local agent in 5 steps](#quickstart--local-agent-in-5-steps)
7. [Configuration reference](#configuration-reference)
8. [Deploy to Azure](#deploy-to-azure)
9. [Publish to Teams / Copilot](#publish-to-teams--copilot)
10. [Hands-on learning track](#hands-on-learning-track)
11. [Testing strategy](#testing-strategy)
12. [Troubleshooting](#troubleshooting)
13. [Glossary](#glossary)
14. [References](#references)
15. [License](#license)

---

## Who this is for

You are an **AI developer** comfortable with TypeScript who wants to ship an enterprise agent — not just a chatbot. You care about identity, audit trails, secret hygiene, and graceful failure under load. You may or may not have written a Bot Framework app before; this scaffold removes the bot-plumbing toil so you can focus on agent behaviour.

If any of these match, you're in the right place:

- *"I want my LLM to act on Outlook/Teams as a non-human identity."*
- *"I want a Teams-facing agent with proper Azure AD permissions, not a hard-coded user token."*
- *"I want to evolve from one agent to a fleet of specialised agents with handoff."*

---

## What you'll build

A single TypeScript service that:

| Capability | How |
|---|---|
| Receives messages from Microsoft Teams / M365 Copilot | `CloudAdapter` from [`@microsoft/agents-hosting`](https://github.com/Microsoft/Agents-for-js) |
| Routes turns to an LLM pipeline | OpenClaw runtime — primary model + fallback chain |
| Acts on user data with its **own** Entra ID identity | T1 → T2 → Agent FIC token exchange |
| Enforces network egress policy | iptables-based perimeter (`NETWORK_MODE`) |
| Emits OpenTelemetry traces and metrics | Application Insights exporter |
| Resolves secrets from Azure Key Vault at runtime | Managed identity + KV references |
| Deploys via Bicep + a single `pnpm run` chain | [iac/azure-resources.bicep](iac/azure-resources.bicep) + [scripts/](scripts/) |

---

## How it works (60-second tour)

```
                           ┌──────────────────────────────────────┐
 user types in Teams ─────▶│  Teams / M365 Copilot                │
                           └──────────────┬───────────────────────┘
                                          │ Bot Framework Activity (HTTPS)
                           ┌──────────────▼───────────────────────┐
                           │  POST /api/messages                  │
                           │  ───────────────                     │
                           │  CloudAdapter (JWT-validated)        │  src/index.ts
                           │  ↓                                   │
                           │  Agent365Handler                     │  src/agent.ts
                           │  ↓                                   │
                           │  OpenClawRuntime  ──┐                │  src/openclaw-connector.ts
                           │   ├ primary model    │                │
                           │   └ fallback chain   │ tool calls     │
                           │                      ▼                │
                           │  GraphTools (T1 → T2 → Agent FIC) ──┐ │  src/graph-tools.ts
                           │                                     │ │
                           │  OpenTelemetry → App Insights       │ │  src/telemetry.ts
                           └─────────────────────────────────────┘ │
                                                                   │
   Microsoft Graph (calendar, mail) ◀──────────────────────────────┘
   acts AS the agent identity, not as the user
```

Three things are unusual compared to a vanilla Teams bot:

1. **The agent has its own user-style identity** (e.g. `agent@contoso.com`). Mailboxes and calendars are explicitly shared *with* this identity. Audit logs show the agent — not a human — as the actor.
2. **Federated Identity Credentials (FIC)** let the app registration mint Graph tokens for the agent identity without storing the agent's password.
3. **OpenClaw is the LLM runtime**, not raw API calls. It owns model selection, fallback, plugin host, and channel routing — the wrapper just bridges Teams ↔ OpenClaw.

The full flow lives in [docs/architecture.md](docs/architecture.md).

---

## Repository map

```
enterprise-ready-ai-agent-lab/
├── src/                       # Application source (TypeScript)
│   ├── index.ts               #   Express server + CloudAdapter — entry point
│   ├── agent.ts               #   Agent365Handler — turn dispatch, role/DM policy
│   ├── openclaw-connector.ts  #   OpenClaw runtime bridge (SDK → gateway → stub)
│   ├── graph-tools.ts         #   Microsoft Graph tools + FIC token exchange
│   ├── config.ts              #   Zod-validated env config (fail-fast at boot)
│   └── telemetry.ts           #   OpenTelemetry / App Insights setup
│
├── tests/                     # Test suites
│   ├── unit/                  #   Pure-function tests (config, agent, connector)
│   ├── integration/           #   In-process Express tests (health, /api/messages)
│   ├── e2e/                   #   Full agent flow against a live runtime
│   └── load/                  #   k6 load test
│
├── scripts/                   # Bash automation — every step is idempotent
│   ├── lib/common.sh          #   Shared helpers (pass/warn/fail, dry-run, etc.)
│   ├── setup.sh               #   Local dev bootstrap (pnpm run setup)
│   ├── install-azure-cli.sh   #   Multi-OS az installer + extensions
│   ├── azure-login.sh         #   Device-code or service-principal login
│   ├── azure-app-registration.sh  # AAD App + FIC + admin consent
│   ├── azure-provision.sh     #   Validate + deploy Bicep template
│   ├── azure-keyvault-seed.sh #   Push .env secrets into Key Vault
│   ├── azure-deploy-image.sh  #   acr build → containerapp update → /health
│   └── azure-teardown.sh      #   Safe RG delete (tag-guarded)
│
├── iac/                       # Infrastructure as code
│   ├── azure-resources.bicep  #   ACR + Container Apps + Key Vault + App Insights + Bot Service
│   ├── parameters.json        #   Bicep parameters template — edit before provisioning
│   └── .last-deployment.json  #   (gitignored) outputs cache from last provision
│
├── docs/                      # All long-form docs
│   ├── README.md              #   Documentation index — start here
│   ├── architecture.md        #   Component diagram + responsibility matrix
│   ├── release-checklist.md   #   Pre-prod gate
│   ├── rollback.md            #   Incident runbook
│   └── labs/                  #   Hands-on labs (3 phases)
│
├── security/
│   └── security-checklist.md
├── config/openclaw-config.json     # OpenClaw runtime + gateway config
├── openclaw.plugin.json            # OpenClaw plugin manifest
├── teams-app/manifest.json         # Teams app manifest
├── Dockerfile                      # Multi-stage production image
├── jest.config.js  tsconfig.json  package.json  pnpm-lock.yaml
└── .env.example                    # Local env template — copy to .env
```

> **Not yet committed:** `.devcontainer/` and `.github/workflows/`. CI/CD is captured in [docs/release-checklist.md](docs/release-checklist.md) as a contract to implement before `v1.0.0`.

---

## Prerequisites

| Tool | Version | Why |
|---|---|---|
| **Node.js**          | ≥ 24 LTS | Matches `engines.node` in [package.json](package.json) |
| **pnpm**             | ≥ 9      | Workspace package manager (`corepack enable && corepack prepare pnpm@latest --activate`) |
| **Docker**           | any      | Building the production image; running OpenClaw locally |
| **Azure CLI**        | latest   | Optional locally; required to deploy. Auto-installable via `pnpm run az:install` |
| **Azure subscription** | — | With permission to register apps and create resources |
| **An LLM key**       | — | Anthropic / OpenAI / OpenRouter / Azure OpenAI — at least one |

You do **not** need to clone OpenClaw or Agent365-Samples as sibling repos. They are referenced for documentation only; the runtime is loaded from npm.

---

## Quickstart — local agent in 5 steps

The goal of this section is the loop **edit code → see Teams reply** running on your laptop. No Azure deployment yet.

### 1. Clone & enter

```bash
git clone https://github.com/asiapartners/enterprise-ready-ai-agent-lab.git
cd enterprise-ready-ai-agent-lab
```

### 2. Bootstrap

```bash
pnpm run setup
```

`setup.sh` will:
- Verify Node 24+ / pnpm 9+
- Run `pnpm install`
- Copy [.env.example](.env.example) → `.env` if missing
- Offer to install the Azure CLI (interactive)
- Run `pnpm run typecheck && pnpm run lint && pnpm run build`

If you prefer to do it by hand:

```bash
pnpm install
cp .env.example .env
pnpm run build
```

### 3. Configure `.env`

For Phase 1 you only need an LLM key plus placeholder bot fields. The agent will run in **stub mode** for OpenClaw if no SDK is published yet.

```dotenv
APP_ENV=development
PORT=3978
ANTHROPIC_API_KEY=sk-ant-...        # any one LLM key
A365_APP_ID=00000000-0000-0000-0000-000000000000   # placeholder if no real bot yet
A365_APP_PASSWORD=placeholder
A365_TENANT_ID=00000000-0000-0000-0000-000000000000
AGENT_IDENTITY=agent@your-domain
OWNER=you@your-domain
OWNER_AAD_ID=00000000-0000-0000-0000-000000000000
AA_INSTANCE_ID=local-dev
```

See the [Configuration reference](#configuration-reference) for everything.

### 4. Run

```bash
pnpm run dev          # hot-reload via ts-node-dev
# or:
pnpm run build && pnpm start
```

In another shell:

```bash
curl -s http://localhost:3978/health | jq
# → { "status": "ok", "service": "openclaw-agent365", ... }
```

### 5. Send a Teams-shaped message

You don't need a registered bot for the first round-trip. Use the [Bot Framework Emulator](https://github.com/microsoft/BotFramework-Emulator) or curl an activity payload:

```bash
curl -X POST http://localhost:3978/api/messages \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "message",
    "text": "hello agent",
    "from": { "id": "u1", "name": "you" },
    "conversation": { "id": "c1" },
    "recipient": { "id": "agent" }
  }'
```

You should see the agent reply in the response and a trace in your terminal logs.

> Want a real Teams sidecar? Continue with [Phase 1 lab](docs/labs/phase1-autonomous-agents.md) — it walks you through ngrok + Bot Framework registration.

---

## Configuration reference

All config is read by [src/config.ts](src/config.ts) and **fail-fast validated** with Zod at startup. Missing or malformed values stop the process before listening on a port.

### Categories

| Category | Variables | Purpose |
|---|---|---|
| **Runtime**          | `APP_ENV`, `PORT`, `LOG_LEVEL` | Process basics |
| **OpenClaw**         | `OPENCLAW_MODEL`, `OPENCLAW_FALLBACK_MODELS`, `OPENCLAW_CONFIG_PATH`, `OPENCLAW_PLUGIN_DIR`, `OPENCLAW_GATEWAY_URL` | Resolution order: in-process SDK → gateway → stub |
| **Bot identity**     | `A365_APP_ID`, `A365_APP_PASSWORD`, `A365_TENANT_ID`, `MICROSOFT_APP_TYPE` | App registration credentials |
| **Agentic identity** | `AA_INSTANCE_ID`, `AGENT_IDENTITY` | Federated identity (Phase 2) |
| **Owner / RBAC**     | `OWNER`, `OWNER_AAD_ID` | Owner-only commands and audit attribution |
| **LLM keys**         | `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT` | One required |
| **Policy**           | `BUSINESS_HOURS_START`, `BUSINESS_HOURS_END`, `TIMEZONE`, `DM_POLICY` | Business-hours gating, DM permissions |
| **Network policy**   | `NETWORK_MODE`, `NETWORK_ALLOWLIST` | `unrestricted` \| `restricted` \| `allowlist` (requires `NET_ADMIN` capability) |
| **Observability**    | `OTEL_SERVICE_NAME`, `OTEL_SERVICE_VERSION`, `APPINSIGHTS_CONNECTION_STRING` | OpenTelemetry resource + exporter |
| **Production**       | `KEY_VAULT_URI` | Resolves secrets at runtime via Managed Identity |

The full annotated template is [.env.example](.env.example). **Never commit secrets.** In production they live in Azure Key Vault and GitHub Secrets only — see the security checklist at [security/security-checklist.md](security/security-checklist.md).

---

## Deploy to Azure

The [scripts/](scripts/) directory ships an end-to-end deploy chain. Each script is idempotent, supports `AZ_DRY_RUN=1`, and emits a JSON summary on stdout (greppable in CI). Stderr carries human messages.

### Script catalogue

| Script | `pnpm` alias | Purpose |
|---|---|---|
| [scripts/install-azure-cli.sh](scripts/install-azure-cli.sh)        | `pnpm run az:install`   | Install/upgrade `az` (apt/brew/winget) + extensions `containerapp`, `bot-service`, `application-insights` |
| [scripts/azure-login.sh](scripts/azure-login.sh)                    | `pnpm run az:login`     | `az login` via device-code (interactive) or service-principal (CI), select subscription |
| [scripts/azure-app-registration.sh](scripts/azure-app-registration.sh) | `pnpm run az:app-reg`   | Create AAD App + Graph permissions + admin consent + client secret + Federated Identity Credential |
| [scripts/azure-provision.sh](scripts/azure-provision.sh)            | `pnpm run az:provision` | Validate + deploy [iac/azure-resources.bicep](iac/azure-resources.bicep); cache outputs to `iac/.last-deployment.json` |
| [scripts/azure-keyvault-seed.sh](scripts/azure-keyvault-seed.sh)    | `pnpm run az:kv-seed`   | Push `.env` secrets into Key Vault; `--sync-env` writes deployment outputs back to `.env` |
| [scripts/azure-deploy-image.sh](scripts/azure-deploy-image.sh)      | `pnpm run az:deploy`    | `az acr build` → `az containerapp update` → poll revision → curl `/health` |
| [scripts/azure-teardown.sh](scripts/azure-teardown.sh)              | `pnpm run az:teardown`  | Safe RG delete (refuses untagged RGs and prod-named subs unless overridden) |

### Deploy walkthrough

The "happy path" — copy/paste, top to bottom. Each step is idempotent, so re-running on partial failure is safe.

#### Step 1 — Install + log in

```bash
pnpm run az:install              # one-time per machine
pnpm run az:login                # interactive device-code; or --service-principal in CI
```

#### Step 2 — App Registration + Federated Identity Credential

This step replaces a multi-page Azure portal click-through. The script:

- Creates (or reuses) an AAD App Registration
- Adds Microsoft Graph permissions: `User.Read`, `Calendars.ReadWrite`, `Mail.Send`
- Grants tenant-wide admin consent (requires Global Admin role)
- Creates a 6-month client secret (emitted **once** — capture it)
- Configures a Federated Identity Credential bound to the agent UPN
- With `--write-env`, populates `A365_APP_ID`, `A365_TENANT_ID`, `A365_APP_PASSWORD`, `AGENT_IDENTITY` in your local `.env`

```bash
pnpm run az:app-reg -- \
  --display-name "openclaw-agent365-dev" \
  --agent-identity agent@<your-domain> \
  --write-env
```

#### Step 3 — Edit Bicep parameters

Open [iac/parameters.json](iac/parameters.json) and replace the `REPLACE_ME` values (especially `containerImage`, `a365AppId` from Step 2, `aaInstanceId`, `ownerAadId`).

#### Step 4 — Provision

```bash
AZ_RESOURCE_GROUP=rg-oca365-dev \
AZ_LOCATION=eastus \
  pnpm run az:provision
```

This:

1. Creates the resource group with tag `managed-by=openclaw-agent365` (the teardown script keys off this tag).
2. Runs `az deployment group validate`.
3. Deploys [iac/azure-resources.bicep](iac/azure-resources.bicep): ACR + Container Apps Environment + Container App + Key Vault + App Insights + Log Analytics + Azure Bot Service + Teams channel + RBAC.
4. Caches outputs (Container App URL, ACR login server, KV URI, App Insights conn string) to `iac/.last-deployment.json` (gitignored). Subsequent scripts read this file so you don't re-pass values.

> **Preview only?** Set `AZ_DRY_RUN=1` to run `az deployment group what-if` instead of creating resources.

#### Step 5 — Seed Key Vault

```bash
pnpm run az:kv-seed -- --sync-env
```

Pushes the secret subset of `.env` (`A365_APP_PASSWORD`, `ANTHROPIC_API_KEY`, `APPINSIGHTS_CONNECTION_STRING`, optional LLM keys) into the deployed Key Vault. `--sync-env` writes `KEY_VAULT_URI` and `APPINSIGHTS_CONNECTION_STRING` back into `.env` so local dev points at the same App Insights instance.

#### Step 6 — Build the image and roll out a revision

```bash
pnpm run az:deploy
```

Equivalent to:

```
az acr build --registry <ACR> --image openclaw-agent365:<sha> .
az containerapp update --image <ACR>.azurecr.io/openclaw-agent365:<sha>
# wait for revision = Succeeded
curl https://<fqdn>/health
```

The image tag defaults to the short git SHA; override with `IMAGE_TAG=v1.2.3 pnpm run az:deploy`.

#### Cleanup

```bash
pnpm run az:teardown -- --resource-group rg-oca365-dev
```

Refuses to delete RGs that don't carry `managed-by=openclaw-agent365`, and refuses production-named subscriptions unless `--i-know-what-im-doing` is passed.

### CI / non-interactive use

```bash
AZ_CLIENT_ID=...  AZ_CLIENT_SECRET=...  AZ_TENANT_ID=... \
  pnpm run az:login -- --service-principal

CONFIRM_YES=1 pnpm run az:teardown -- --resource-group rg-oca365-ephemeral --yes
```

All scripts honour `AZ_DRY_RUN=1`. See [docs/release-checklist.md](docs/release-checklist.md) for the full release contract.

---

## Publish to Teams / Copilot

After [Deploy to Azure](#deploy-to-azure):

1. **Bot Service** is already registered by the Bicep template (`Microsoft.BotService/botServices` resource), with the Teams channel enabled.
2. **App Registration** is already done by `pnpm run az:app-reg`.
3. **Package the Teams app manifest** in [teams-app/manifest.json](teams-app/manifest.json) — replace `botId` with `A365_APP_ID`, then zip the manifest with icons.
4. **Upload** via Teams Admin Center → *Manage apps* → *Upload custom app*. For organisation-wide release, submit to Microsoft Partner Center.
5. **Smoke-test** following [docs/release-checklist.md](docs/release-checklist.md).

The official platform hosting reference: <https://learn.microsoft.com/en-us/microsoft-agent-365/developer/>.

---

## Hands-on learning track

Three progressive labs under [docs/labs/](docs/labs/). Each includes prerequisites, objectives, step-by-step instructions, and verification commands.

| Phase | Lab | What you'll learn | Duration |
|---|---|---|---|
| **1** | [Building autonomous AI assistants](docs/labs/phase1-autonomous-agents.md)        | OpenClaw plugin host, CloudAdapter request flow, Bot Framework registration, end-to-end telemetry | ~2 hrs |
| **2** | [Tool integration & capability perimeters](docs/labs/phase2-tool-integration.md)  | Federated Identity (T1→T2→Agent), Graph API tools, network egress policy via iptables           | ~3 hrs |
| **3** | [Multi-agent orchestration & governance](docs/labs/phase3-multi-agent.md)         | Agent-to-agent handoff, per-agent rate limits, blue/green Container App revisions, advanced security | ~4 hrs |

**Recommended progression:** Quickstart → Phase 1 → Deploy to Azure → Phase 2 → Phase 3.

---

## Testing strategy

| Suite | Command | Scope |
|---|---|---|
| Unit + integration | `pnpm test`           | Tests in `tests/unit/` and `tests/integration/` with coverage |
| End-to-end          | `pnpm run test:e2e`   | Live agent flow — requires `.env` populated |
| Load                | `pnpm run test:load`  | k6 — install separately from <https://k6.io> |
| Type check          | `pnpm run typecheck`  | `tsc --noEmit` |
| Lint                | `pnpm run lint`       | ESLint with `--max-warnings 0` |

The full release gate (security checks, audit, smoke tests) is in [docs/release-checklist.md](docs/release-checklist.md).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `pnpm run setup` fails on Node version | Wrong Node | `nvm install 24 && nvm use 24` |
| `pnpm install` hangs | Corporate proxy on the registry | Set `npm_config_registry` or use `pnpm config set registry` |
| `/health` returns 500 with config errors | Missing or malformed env var | Check stderr — Zod prints which key failed and why |
| Bot Framework returns 401 on `/api/messages` | `A365_APP_ID` / `A365_APP_PASSWORD` mismatch | Re-run `pnpm run az:app-reg` (does not reset existing creds — pass `--rotate` if added) |
| `az login` works but `az deployment` fails on permissions | Subscription not selected | `pnpm run az:login -- --subscription <sub-id>` |
| `az ad app permission admin-consent` denied | Not Global Admin | Ask an admin to run `az ad app permission admin-consent --id <APP_ID>` |
| Container App revision stuck `Provisioning` | ACR pull failed | `az containerapp logs show --name <app> -g <rg>` and check `az role assignment list` for AcrPull |
| FIC token exchange fails (Phase 2) | `AGENT_IDENTITY` mismatch with FIC subject | `subject` must equal `agent://<UPN>`; recreate via `pnpm run az:app-reg` |
| `pnpm run az:teardown` refuses | RG missing `managed-by=openclaw-agent365` tag | Either tag the RG or delete via Azure Portal — the guard is intentional |

If you find a new failure mode, add it here and to [docs/rollback.md](docs/rollback.md).

---

## Glossary

| Term | Meaning |
|---|---|
| **Agent 365**           | The Control Plane for Agents Observe, govern, and secure AI agents confidently with Agent 365. Extend Microsoft 365 and Microsoft Security controls to manage agentic AI at scale. |
| **Agentic identity**    | A non-human Entra ID user that an agent acts *as*. Receives delegations and shows up as the actor in audit logs. |
| **CloudAdapter**        | The `@microsoft/agents-hosting` adapter that validates Bot Framework JWTs and dispatches turns. |
| **FIC (Federated Identity Credential)** | An AAD construct that lets an app federate trust into another identity without storing the target's credentials. |
| **OpenClaw**            | Multi-channel AI runtime (TypeScript) — plugin host, model-agnostic, with primary/fallback chains. |
| **Plugin manifest**     | [openclaw.plugin.json](openclaw.plugin.json) — declares the agent's capabilities to the OpenClaw runtime. |
| **T1 / T2 / Agent token** | Three legs of the FIC token chain: app-cred → JWT-bearer → user_fic. The agent only ever calls Graph with the third token. |
| **Capability perimeter** | The combined limits enforced on the agent: network egress allowlist, business-hours gate, DM policy, RBAC. |

---

## References

- [OpenClaw](https://github.com/openclaw/openclaw)
- [Microsoft Agent 365 Developer Docs](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/)
- [Microsoft 365 Agents SDK (Node.js)](https://github.com/Microsoft/Agents-for-js)
- [Agent365-Samples](https://github.com/microsoft/Agent365-Samples)
- [Bot Framework Activity protocol](https://learn.microsoft.com/en-us/azure/bot-service/rest-api/bot-framework-rest-connector-activities)
- [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [Azure Container Apps docs](https://learn.microsoft.com/en-us/azure/container-apps/)

---

## License

MIT © 2026
