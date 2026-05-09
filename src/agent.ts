/**
 * agent.ts — Agent365 Activity Handler
 *
 * Extends ActivityHandler (from @microsoft/agents-hosting) following the
 * Node.js sample pattern in Agent365-Samples/nodejs/.
 *
 * Handles:
 *  - onMessage: routes activity to OpenClaw runtime, sends back response
 *  - onMembersAdded: welcome card on first install
 *  - Role detection: Owner vs Requester (based on OWNER_AAD_ID env var)
 *  - DM policy enforcement (open | pairing | closed)
 *
 * Ref: https://github.com/microsoft/Agent365-Samples/tree/main/nodejs
 */

import { TurnContext, ActivityHandler } from "@microsoft/agents-hosting";
import { config } from "./config";
import { openClawRuntime, AgentContext } from "./openclaw-connector";
import { trace } from "@opentelemetry/api";

const tracer = trace.getTracer("openclaw-agent365");

export class Agent365Handler extends ActivityHandler {
  constructor() {
    super();

    this.onMessage(async (ctx: TurnContext, next) => {
      await tracer.startActiveSpan("onMessage", async (span) => {
        try {
          span.setAttribute("channel.id", ctx.activity.channelId ?? "unknown");
          span.setAttribute("user.aad", ctx.activity.from?.aadObjectId ?? "");

          const agentCtx = this.buildAgentContext(ctx);
          span.setAttribute("user.role", agentCtx.userRole);

          // DM policy guard
          if (!this.isDmAllowed(ctx, agentCtx)) {
            await ctx.sendActivity(
              "I'm not authorised to respond to this conversation. Please contact the agent owner."
            );
            span.setAttribute("dm.blocked", true);
            return;
          }

          const text = ctx.activity.text?.trim() ?? "";
          if (!text) {
            await ctx.sendActivity("Please send a text message.");
            return;
          }

          await ctx.sendActivity({ type: "typing" });

          const response = await openClawRuntime.processMessage(text, agentCtx);

          await ctx.sendActivity(
            response.attachments?.length
              ? {
                  type: "message",
                  text: response.text,
                  attachments: response.attachments as never[],
                }
              : response.text
          );
        } catch (err) {
          span.recordException(err as Error);
          console.error("[agent] onMessage error:", err);
          await ctx.sendActivity(
            "An error occurred processing your request. Please try again."
          );
        } finally {
          span.end();
          await next();
        }
      });
    });

    this.onMembersAdded(async (ctx: TurnContext, next) => {
      for (const member of ctx.activity.membersAdded ?? []) {
        if (member.id !== ctx.activity.recipient.id) {
          await ctx.sendActivity(
            `👋 Hello! I'm **${config.agentIdentity.split("@")[0]}**, your AI assistant powered by OpenClaw. ` +
              `How can I help you today?`
          );
        }
      }
      await next();
    });
  }

  private buildAgentContext(ctx: TurnContext): AgentContext {
    const fromAadId = ctx.activity.from?.aadObjectId ?? "";
    const fromUpn =
      ctx.activity.from?.name ?? ctx.activity.from?.id ?? "unknown";

    const isOwner = fromAadId === config.ownerAadId;

    return {
      userUpn: fromUpn,
      userAadId: fromAadId,
      userRole: isOwner ? "Owner" : "Requester",
      conversationId: ctx.activity.conversation?.id ?? "",
      channelId: ctx.activity.channelId ?? "",
    };
  }

  /**
   * DM policy enforcement.
   * - open: anyone can DM
   * - pairing: only conversations the owner has initiated or explicitly allowed
   * - closed: owner only
   */
  private isDmAllowed(ctx: TurnContext, agentCtx: AgentContext): boolean {
    if (config.dmPolicy === "open") return true;
    if (agentCtx.userRole === "Owner") return true;

    if (config.dmPolicy === "closed") return false;

    // pairing: allow group/channel conversations; block unsolicited DMs
    const isGroupConversation =
      ctx.activity.conversation?.conversationType !== "personal";
    return isGroupConversation;
  }
}
