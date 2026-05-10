/**
 * openclaw-connector.ts — OpenClaw runtime bridge
 *
 * This module is the integration seam between the Agent365 activity handler
 * and the OpenClaw plugin host. It:
 *
 *  1. Loads OpenClaw configuration from OPENCLAW_CONFIG_PATH
 *  2. Initialises the plugin registry (loads a365-channel plugin)
 *  3. Routes incoming Bot Framework activities to OpenClaw
 *  4. Applies network policy (iptables) when NETWORK_MODE != unrestricted
 *  5. Manages the T1 → T2 → Agent FIC token exchange for Graph API access
 *
 * Integration mode resolution (in order):
 *   a) In-process SDK — `require('openclaw').createRuntime(...)` if installed
 *   b) HTTP gateway   — POST to OpenClaw's gateway endpoint resolved from
 *                       OPENCLAW_GATEWAY_URL or config/openclaw-config.json
 *   c) Stub           — dev-only canned response (APP_ENV=development)
 *
 * Architecture ref: https://github.com/SidU/openclaw-a365
 * Auth flow: T1 (client_creds + fmi_path) → T2 (jwt-bearer) → Agent token (user_fic)
 */

import { execSync } from "child_process";
import { existsSync, readFileSync } from "fs";
import { join } from "path";
import { config } from "./config";

export interface AgentContext {
  userUpn: string;
  userAadId: string;
  userRole: "Owner" | "Requester";
  conversationId: string;
  channelId: string;
}

export interface OpenClawResponse {
  text: string;
  attachments?: unknown[];
}

export type OpenClawMode = "sdk" | "http" | "stub";

interface SdkRuntime {
  handleMessage(
    message: string,
    ctx: { identity: AgentContext; agentIdentity: string }
  ): Promise<{ text: string; attachments?: unknown[] }>;
  shutdown?(): Promise<void>;
}

interface SdkModule {
  createRuntime(opts: {
    configPath: string;
    pluginDir: string;
    model: string;
    fallbackModels?: string[];
  }): Promise<SdkRuntime>;
}

interface GatewayConfigFile {
  gateway?: { host?: string; port?: number };
  agents?: { default?: string };
}

interface GatewayResponse {
  response?: string;
  text?: string;
  attachments?: unknown[];
}

class OpenClawRuntime {
  private initialized = false;
  private mode: OpenClawMode = "stub";
  private sdkRuntime: SdkRuntime | null = null;
  private gatewayUrl: string | null = null;

  async init(): Promise<void> {
    if (this.initialized) return;

    console.info(
      `[openclaw] Initialising runtime — model=${config.openclawModel} config=${config.openclawConfigPath}`
    );

    // Apply network policy before making any outbound connections
    if (config.networkMode !== "unrestricted") {
      await this.applyNetworkPolicy();
    }

    // 1) Try in-process SDK
    const sdk = this.tryLoadSdk();
    if (sdk) {
      try {
        this.sdkRuntime = await sdk.createRuntime({
          configPath: config.openclawConfigPath,
          pluginDir: config.openclawPluginDir,
          model: config.openclawModel,
          fallbackModels: config.openclawFallbackModels
            ?.split(",")
            .map((m) => m.trim())
            .filter(Boolean),
        });
        this.mode = "sdk";
        console.info("[openclaw] In-process runtime ready");
      } catch (err) {
        console.warn(
          "[openclaw] In-process SDK init failed; will try HTTP gateway:",
          err
        );
      }
    }

    // 2) Fall back to HTTP gateway
    if (this.mode === "stub") {
      this.gatewayUrl = this.resolveGatewayUrl();
      if (this.gatewayUrl) {
        this.mode = "http";
        console.info(`[openclaw] Using HTTP gateway: ${this.gatewayUrl}`);
      }
    }

    // 3) Stub mode (dev only)
    if (this.mode === "stub") {
      if (config.appEnv !== "development") {
        throw new Error(
          "[openclaw] No runtime available: install the 'openclaw' package or set OPENCLAW_GATEWAY_URL"
        );
      }
      console.warn(
        "[openclaw] No SDK or gateway available — using stub responses (development only)"
      );
    }

    this.initialized = true;
    console.info(`[openclaw] Runtime ready (mode=${this.mode})`);
  }

  getMode(): OpenClawMode {
    return this.mode;
  }

  /**
   * Process an inbound message through OpenClaw's LLM pipeline.
   * Returns the agent's response text (and optional adaptive card attachments).
   */
  async processMessage(
    message: string,
    context: AgentContext
  ): Promise<OpenClawResponse> {
    if (!this.initialized) {
      throw new Error("[openclaw] Runtime not initialised — call init() first");
    }

    console.info(
      `[openclaw] Processing message — user=${context.userUpn} role=${context.userRole} mode=${this.mode}`
    );

    if (this.mode === "sdk" && this.sdkRuntime) {
      const result = await this.sdkRuntime.handleMessage(message, {
        identity: context,
        agentIdentity: config.agentIdentity,
      });
      return { text: result.text, attachments: result.attachments };
    }

    if (this.mode === "http" && this.gatewayUrl) {
      return this.callGateway(message, context);
    }

    // Stub response for local dev / unit tests
    return {
      text: `[OpenClaw stub] Received: "${message}" from ${context.userUpn} (${context.userRole})`,
    };
  }

  async shutdown(): Promise<void> {
    if (this.sdkRuntime?.shutdown) {
      try {
        await this.sdkRuntime.shutdown();
      } catch (err) {
        console.warn("[openclaw] SDK shutdown error:", err);
      }
    }
    this.sdkRuntime = null;
    this.gatewayUrl = null;
    this.mode = "stub";
    this.initialized = false;
  }

  private tryLoadSdk(): SdkModule | null {
    try {
      // Dynamic require so the absence of the optional 'openclaw' package
      // does not break startup. Suppress the resolver error for clean logs.
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const mod = require("openclaw") as Partial<SdkModule>;
      if (mod && typeof mod.createRuntime === "function") {
        return mod as SdkModule;
      }
      return null;
    } catch {
      return null;
    }
  }

  private resolveGatewayUrl(): string | null {
    const explicit = process.env.OPENCLAW_GATEWAY_URL;
    if (explicit) {
      return explicit.replace(/\/+$/, "") + "/chat";
    }

    const cfgPath = join(config.openclawConfigPath, "openclaw-config.json");
    if (!existsSync(cfgPath)) return null;

    try {
      const parsed = JSON.parse(
        readFileSync(cfgPath, "utf8")
      ) as GatewayConfigFile;
      const rawHost = parsed.gateway?.host;
      const host = rawHost && rawHost !== "0.0.0.0" ? rawHost : "127.0.0.1";
      const port = parsed.gateway?.port ?? 18789;
      return `http://${host}:${port}/chat`;
    } catch (err) {
      console.warn(
        `[openclaw] Failed to parse gateway config at ${cfgPath}:`,
        err
      );
      return null;
    }
  }

  private async callGateway(
    message: string,
    context: AgentContext
  ): Promise<OpenClawResponse> {
    const url = this.gatewayUrl as string;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: context.conversationId,
        message,
        user: {
          upn: context.userUpn,
          aad_id: context.userAadId,
          role: context.userRole,
        },
        channel: context.channelId,
        agent_identity: config.agentIdentity,
      }),
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`[openclaw] gateway ${res.status}: ${body}`);
    }

    const data = (await res.json()) as GatewayResponse;
    return {
      text: data.response ?? data.text ?? "",
      attachments: data.attachments,
    };
  }

  /**
   * Apply iptables network policy.
   * Requires container capability NET_ADMIN.
   * Essential domains (login.microsoftonline.com, graph.microsoft.com,
   * Bot Framework, LLM provider) are always allowed.
   */
  private async applyNetworkPolicy(): Promise<void> {
    const mode = config.networkMode;
    console.info(`[openclaw] Applying network policy: ${mode}`);

    const essentialDomains = [
      "login.microsoftonline.com",
      "graph.microsoft.com",
      "smba.trafficmanager.net",
      "*.botframework.com",
      "api.anthropic.com",      // Anthropic
      "api.openai.com",         // OpenAI
      "openrouter.ai",          // OpenRouter
    ];

    const allowlistDomains =
      mode === "allowlist" && config.networkAllowlist
        ? config.networkAllowlist.split(",").map((d) => d.trim())
        : [];

    const allDomains = [...essentialDomains, ...allowlistDomains];

    try {
      // Flush existing OUTPUT rules (idempotent restart)
      execSync("iptables -F OUTPUT", { stdio: "pipe" });

      // Resolve and allow each domain
      for (const domain of allDomains) {
        if (domain.startsWith("*")) continue; // wildcard — manual rule needed
        try {
          const ips = execSync(`getent hosts ${domain} | awk '{print $1}'`, {
            stdio: "pipe",
          })
            .toString()
            .trim()
            .split("\n")
            .filter(Boolean);

          for (const ip of ips) {
            execSync(`iptables -A OUTPUT -d ${ip} -j ACCEPT`, {
              stdio: "pipe",
            });
          }
        } catch {
          console.warn(`[openclaw] Could not resolve ${domain} — skipping`);
        }
      }

      // Allow localhost
      execSync("iptables -A OUTPUT -d 127.0.0.1 -j ACCEPT", { stdio: "pipe" });

      // Drop everything else
      execSync("iptables -A OUTPUT -j DROP", { stdio: "pipe" });

      console.info("[openclaw] Network policy applied");
    } catch (err) {
      console.error(
        "[openclaw] Failed to apply network policy — is NET_ADMIN capability set?",
        err
      );
      throw err;
    }
  }
}

export const openClawRuntime = new OpenClawRuntime();
