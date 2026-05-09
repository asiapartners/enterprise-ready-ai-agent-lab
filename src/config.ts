/**
 * config.ts — Typed configuration loader
 *
 * All config is read from environment variables. Secrets (A365_APP_PASSWORD,
 * ANTHROPIC_API_KEY, etc.) must be injected via Azure Key Vault references or
 * GitHub Secrets — never committed to source control.
 *
 * Pattern: fail fast on missing required vars so misconfigurations surface
 * at startup, not at runtime.
 */

import { z } from "zod";

const NetworkMode = z.enum(["unrestricted", "restricted", "allowlist"]);
const DmPolicy = z.enum(["open", "pairing", "closed"]);
const AppType = z.enum(["MultiTenant", "SingleTenant", "UserAssignedMSI"]);

const ConfigSchema = z.object({
  // Runtime
  appEnv: z.enum(["development", "staging", "production"]).default("development"),
  port: z.coerce.number().default(3978),
  logLevel: z.enum(["debug", "info", "warn", "error"]).default("info"),

  // OpenClaw
  openclawModel: z.string().default("anthropic/claude-opus-4-6"),
  openclawFallbackModels: z.string().optional(),
  openclawConfigPath: z.string().default("/app/config"),
  openclawPluginDir: z.string().default("/app/plugins"),

  // Microsoft Agent 365 — Agentic App Registration
  a365AppId: z.string().min(1),
  a365AppPassword: z.string().min(1),
  a365TenantId: z.string().min(1),
  microsoftAppType: AppType.default("SingleTenant"),

  // Federated Identity Credentials
  aaInstanceId: z.string().min(1),

  // Agentic Identity (agent's own Entra ID user account)
  agentIdentity: z.string().email(),

  // Owner
  owner: z.string().email(),
  ownerAadId: z.string().min(1),

  // LLM providers (at least one must be set)
  anthropicApiKey: z.string().optional(),
  openaiApiKey: z.string().optional(),
  openrouterApiKey: z.string().optional(),
  azureOpenaiApiKey: z.string().optional(),
  azureOpenaiEndpoint: z.string().url().optional(),

  // Business hours & policy
  businessHoursStart: z.string().default("08:00"),
  businessHoursEnd: z.string().default("18:00"),
  timezone: z.string().default("America/Los_Angeles"),
  dmPolicy: DmPolicy.default("pairing"),

  // Network policy
  networkMode: NetworkMode.default("unrestricted"),
  networkAllowlist: z.string().optional(),

  // Observability
  appInsightsConnectionString: z.string().optional(),
  otelServiceName: z.string().default("openclaw-agent365"),
  otelServiceVersion: z.string().default("0.1.0"),

  // Azure Key Vault
  keyVaultUri: z.string().url().optional(),
});

export type Config = z.infer<typeof ConfigSchema>;

function loadConfig(): Config {
  const raw = {
    appEnv: process.env.APP_ENV,
    port: process.env.PORT,
    logLevel: process.env.LOG_LEVEL,

    openclawModel: process.env.OPENCLAW_MODEL,
    openclawFallbackModels: process.env.OPENCLAW_FALLBACK_MODELS,
    openclawConfigPath: process.env.OPENCLAW_CONFIG_PATH,
    openclawPluginDir: process.env.OPENCLAW_PLUGIN_DIR,

    a365AppId: process.env.A365_APP_ID,
    a365AppPassword: process.env.A365_APP_PASSWORD,
    a365TenantId: process.env.A365_TENANT_ID,
    microsoftAppType: process.env.MICROSOFT_APP_TYPE,

    aaInstanceId: process.env.AA_INSTANCE_ID,
    agentIdentity: process.env.AGENT_IDENTITY,
    owner: process.env.OWNER,
    ownerAadId: process.env.OWNER_AAD_ID,

    anthropicApiKey: process.env.ANTHROPIC_API_KEY,
    openaiApiKey: process.env.OPENAI_API_KEY,
    openrouterApiKey: process.env.OPENROUTER_API_KEY,
    azureOpenaiApiKey: process.env.AZURE_OPENAI_API_KEY,
    azureOpenaiEndpoint: process.env.AZURE_OPENAI_ENDPOINT,

    businessHoursStart: process.env.BUSINESS_HOURS_START,
    businessHoursEnd: process.env.BUSINESS_HOURS_END,
    timezone: process.env.TIMEZONE,
    dmPolicy: process.env.DM_POLICY,

    networkMode: process.env.NETWORK_MODE,
    networkAllowlist: process.env.NETWORK_ALLOWLIST,

    appInsightsConnectionString: process.env.APPINSIGHTS_CONNECTION_STRING,
    otelServiceName: process.env.OTEL_SERVICE_NAME,
    otelServiceVersion: process.env.OTEL_SERVICE_VERSION,

    keyVaultUri: process.env.KEY_VAULT_URI,
  };

  const result = ConfigSchema.safeParse(raw);
  if (!result.success) {
    const issues = result.error.issues
      .map((i) => `  ${i.path.join(".")}: ${i.message}`)
      .join("\n");
    throw new Error(`Configuration validation failed:\n${issues}`);
  }

  const cfg = result.data;

  // Validate at least one LLM provider key is present
  const hasLlmKey =
    cfg.anthropicApiKey ||
    cfg.openaiApiKey ||
    cfg.openrouterApiKey ||
    cfg.azureOpenaiApiKey;
  if (!hasLlmKey) {
    throw new Error(
      "At least one LLM provider key required: ANTHROPIC_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY, or AZURE_OPENAI_API_KEY"
    );
  }

  return cfg;
}

export const config = loadConfig();
