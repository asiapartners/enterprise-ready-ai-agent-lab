/**
 * index.ts — Application entry point
 *
 * Boot order (critical — telemetry must patch BEFORE any SDK imports):
 *   1. dotenv (load .env for local dev)
 *   2. telemetry.initTelemetry() — OpenTelemetry instrumentation
 *   3. config (validated env vars)
 *   4. OpenClaw runtime init
 *   5. Express server + Bot Framework adapter
 *
 * Endpoint layout:
 *   POST /api/messages  — Bot Framework / Agent365 message ingress
 *   GET  /health        — Liveness probe (Kubernetes / Container App)
 *
 * Ref: Agent365-Samples/nodejs sample agent pattern
 */

// Step 1: Load .env (no-op in production when env vars are injected)
import "dotenv/config";

// Step 2: Telemetry MUST come before any OTel-instrumented imports
import { initTelemetry, shutdownTelemetry } from "./telemetry";
initTelemetry();

// Step 3+: Config and application modules
import express, { Request, Response } from "express";
import {
  CloudAdapter,
  ConfigurationBotFrameworkAuthentication,
} from "@microsoft/agents-hosting";
import { config } from "./config";
import { openClawRuntime } from "./openclaw-connector";
import { Agent365Handler } from "./agent";

async function main(): Promise<void> {
  // ── OpenClaw runtime init ───────────────────────────────────────────────
  await openClawRuntime.init();

  // ── Bot Framework adapter ───────────────────────────────────────────────
  const botAuth = new ConfigurationBotFrameworkAuthentication({
    MicrosoftAppId: config.a365AppId,
    MicrosoftAppPassword: config.a365AppPassword,
    MicrosoftAppTenantId: config.a365TenantId,
    MicrosoftAppType: config.microsoftAppType,
  });

  const adapter = new CloudAdapter(botAuth);

  adapter.onTurnError = async (context, error) => {
    console.error("[adapter] Unhandled turn error:", error);
    try {
      await context.sendTraceActivity(
        "OnTurnError Trace",
        `${error}`,
        "https://www.botframework.com/schemas/error",
        "TurnError"
      );
      await context.sendActivity("An unexpected error occurred.");
    } catch (innerError) {
      console.error("[adapter] Error in error handler:", innerError);
    }
  };

  const agentHandler = new Agent365Handler();

  // ── Express server ──────────────────────────────────────────────────────
  const app = express();
  app.use(express.json());

  // Liveness probe — acceptance criteria: GET /health → 200
  app.get("/health", (_req: Request, res: Response) => {
    res.json({
      status: "ok",
      service: config.otelServiceName,
      version: config.otelServiceVersion,
      env: config.appEnv,
      timestamp: new Date().toISOString(),
    });
  });

  // Agent365 / Bot Framework message endpoint
  app.post("/api/messages", async (req: Request, res: Response) => {
    await adapter.process(req, res, (ctx) => agentHandler.run(ctx));
  });

  const server = app.listen(config.port, () => {
    console.info(
      `[server] openclaw-agent365 listening on port ${config.port} (${config.appEnv})`
    );
    console.info(`[server] Bot endpoint: POST http://localhost:${config.port}/api/messages`);
    console.info(`[server] Health:       GET  http://localhost:${config.port}/health`);
  });

  // ── Graceful shutdown ───────────────────────────────────────────────────
  const shutdown = async (signal: string) => {
    console.info(`[server] Received ${signal} — shutting down gracefully`);
    server.close(async () => {
      await openClawRuntime.shutdown();
      await shutdownTelemetry();
      process.exit(0);
    });
    // Force exit after 10s
    setTimeout(() => process.exit(1), 10_000);
  };

  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}

main().catch((err) => {
  console.error("[main] Fatal startup error:", err);
  process.exit(1);
});
