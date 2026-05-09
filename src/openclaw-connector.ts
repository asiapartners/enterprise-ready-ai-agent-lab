/**
 * openclaw-connector.ts — OpenClaw runtime bridge
 *
 * This module is the integration seam between the Agent365 activity handler
 * and the OpenClaw plugin host. It:
 *
 *  1. Loads OpenClaw configuration from OPENCLAW_CONFIG_PATH
 *  2. Initialises the plugin registry (loads a365-channel plugin)
 *  3. Routes incoming Bot Framework activities to OpenClaw's event bus
 *  4. Applies network policy (iptables) when NETWORK_MODE != unrestricted
 *  5. Manages the T1 → T2 → Agent FIC token exchange for Graph API access
 *
 * Architecture ref: https://github.com/SidU/openclaw-a365
 * Auth flow: T1 (client_creds + fmi_path) → T2 (jwt-bearer) → Agent token (user_fic)
 */

import { execSync } from "child_process";
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

/**
 * Minimal OpenClaw runtime interface.
 * In production this delegates to the openclaw package once installed.
 * The openclaw module exposes a plugin API; we register as a channel plugin.
 */
class OpenClawRuntime {
  private initialized = false;

  async init(): Promise<void> {
    if (this.initialized) return;

    console.info(
      `[openclaw] Initialising runtime — model=${config.openclawModel} config=${config.openclawConfigPath}`
    );

    // Apply network policy before making any outbound connections
    if (config.networkMode !== "unrestricted") {
      await this.applyNetworkPolicy();
    }

    // TODO: Replace with actual OpenClaw SDK initialisation once available:
    //
    //   import { createRuntime } from 'openclaw';
    //   this.runtime = await createRuntime({
    //     configPath: config.openclawConfigPath,
    //     pluginDir: config.openclawPluginDir,
    //     model: config.openclawModel,
    //     fallbackModels: config.openclawFallbackModels?.split(','),
    //   });
    //
    // The plugin registers itself via openclaw.plugin.json.

    this.initialized = true;
    console.info("[openclaw] Runtime ready");
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
      `[openclaw] Processing message — user=${context.userUpn} role=${context.userRole}`
    );

    // TODO: replace stub with actual runtime invocation:
    //   const result = await this.runtime.handleMessage(message, {
    //     identity: context,
    //     agentIdentity: config.agentIdentity,
    //     tools: this.graphTools,
    //   });
    //   return result;

    // Stub response for local dev / unit tests
    return {
      text: `[OpenClaw stub] Received: "${message}" from ${context.userUpn} (${context.userRole})`,
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
