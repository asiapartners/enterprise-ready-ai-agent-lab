# Documentation Index

All authoritative docs for **enterprise-ready-ai-agent-lab**. The top-level [README](../README.md) is the recommended entry point; this page links every supporting document.

## Build & deploy

| Doc | Audience | When to read |
|---|---|---|
| [architecture.md](./architecture.md)               | Engineers, architects | Before adding code; defines the request flow and FIC token chain |
| [release-checklist.md](./release-checklist.md)     | Release engineers     | Every production deploy |
| [rollback.md](./rollback.md)                       | On-call               | When a deploy needs to revert |

## Hands-on labs

Progressive lab guides — complete in order.

| # | Lab | Focus |
|---|---|---|
| 1 | [labs/phase1-autonomous-agents.md](./labs/phase1-autonomous-agents.md) | First Teams-connected agent powered by OpenClaw |
| 2 | [labs/phase2-tool-integration.md](./labs/phase2-tool-integration.md)   | Graph API tools, agentic identity (FIC), capability perimeters |
| 3 | [labs/phase3-multi-agent.md](./labs/phase3-multi-agent.md)             | Multi-agent orchestration, governance, advanced security |

## Security & compliance

| Doc | Purpose |
|---|---|
| [../security/security-checklist.md](../security/security-checklist.md) | Pre-release security gate |

## Operational reference

| Resource | Notes |
|---|---|
| [../iac/azure-resources.bicep](../iac/azure-resources.bicep)   | Container App + Key Vault + App Insights + Bot Service IaC |
| [../iac/parameters.json](../iac/parameters.json)               | Bicep parameters template (edit before `pnpm run az:provision`) |
| [../scripts/](../scripts/)                                     | Azure CLI automation (`pnpm run az:*` aliases) |
| [../config/openclaw-config.json](../config/openclaw-config.json) | OpenClaw runtime + gateway config |
| [../openclaw.plugin.json](../openclaw.plugin.json)             | OpenClaw plugin manifest |
| [../teams-app/manifest.json](../teams-app/manifest.json)       | Teams app manifest |
