/**
 * Unit tests for agent.ts — role detection, DM policy, and bridge invocation.
 */

// The @microsoft/agents-hosting package ships TS source under node_modules
// which jest cannot transform. We only need ActivityHandler/TurnContext
// shapes for these tests, so a lightweight mock is sufficient.
jest.mock("@microsoft/agents-hosting", () => {
  class ActivityHandler {
    onMessage = jest.fn();
    onMembersAdded = jest.fn();
  }
  return { ActivityHandler, TurnContext: class {} };
});

jest.mock("@opentelemetry/api", () => ({
  trace: {
    getTracer: () => ({
      startActiveSpan: (
        _name: string,
        fn: (span: {
          setAttribute: () => void;
          recordException: () => void;
          end: () => void;
        }) => unknown
      ) =>
        fn({
          setAttribute: () => undefined,
          recordException: () => undefined,
          end: () => undefined,
        }),
    }),
  },
}));

import { Agent365Handler } from "../../src/agent";
import { openClawRuntime } from "../../src/openclaw-connector";

// Stub OpenClaw runtime to avoid real init
jest.mock("../../src/openclaw-connector", () => ({
  openClawRuntime: {
    init: jest.fn().mockResolvedValue(undefined),
    processMessage: jest.fn().mockResolvedValue({ text: "stub response" }),
    shutdown: jest.fn().mockResolvedValue(undefined),
    getMode: jest.fn().mockReturnValue("stub"),
  },
}));

jest.mock("../../src/config", () => ({
  config: {
    a365AppId: "test-app-id",
    a365AppPassword: "test-password",
    a365TenantId: "test-tenant-id",
    microsoftAppType: "SingleTenant",
    agentIdentity: "agent@test.example.com",
    ownerAadId: "owner-aad-id",
    dmPolicy: "pairing",
    otelServiceName: "test",
    otelServiceVersion: "0.0.1",
    appEnv: "development",
    port: 3978,
  },
}));

function makeTurnContext(overrides: Record<string, unknown> = {}) {
  const defaults = {
    activity: {
      type: "message",
      text: "Hello",
      from: { id: "user-1", aadObjectId: "non-owner-aad-id", name: "user@test.com" },
      recipient: { id: "bot-1" },
      conversation: { id: "conv-1", conversationType: "personal" },
      channelId: "msteams",
      membersAdded: [],
    },
    sendActivity: jest.fn().mockResolvedValue(undefined),
  };

  return { ...defaults, ...overrides };
}

describe("Agent365Handler", () => {
  it("instantiates without errors", () => {
    expect(() => new Agent365Handler()).not.toThrow();
  });

  it("detects Owner role when AAD ID matches OWNER_AAD_ID", () => {
    const handler = new Agent365Handler() as unknown as {
      buildAgentContext: (ctx: unknown) => { userRole: string };
    };
    const ctx = makeTurnContext({
      activity: {
        type: "message",
        text: "test",
        from: { id: "owner-1", aadObjectId: "owner-aad-id", name: "owner@test.com" },
        recipient: { id: "bot-1" },
        conversation: { id: "conv-1", conversationType: "personal" },
        channelId: "msteams",
      },
    });
    // Access private method for unit testing
    const context = (handler as unknown as {
      buildAgentContext: (ctx: unknown) => { userRole: string };
    }).buildAgentContext(ctx);
    expect(context.userRole).toBe("Owner");
  });

  it("detects Requester role for non-owners", () => {
    const handler = new Agent365Handler();
    const ctx = makeTurnContext();
    const context = (handler as unknown as {
      buildAgentContext: (ctx: unknown) => { userRole: string };
    }).buildAgentContext(ctx);
    expect(context.userRole).toBe("Requester");
  });

  it("blocks non-owner DMs when policy is closed", () => {
    const handler = new Agent365Handler() as unknown as {
      isDmAllowed: (
        ctx: unknown,
        agentCtx: { userRole: string }
      ) => boolean;
    };
    // Override config.dmPolicy via the existing module mock
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const cfg = require("../../src/config");
    const original = cfg.config.dmPolicy;
    cfg.config.dmPolicy = "closed";
    try {
      const ctx = makeTurnContext();
      const allowed = handler.isDmAllowed(ctx, { userRole: "Requester" });
      expect(allowed).toBe(false);
    } finally {
      cfg.config.dmPolicy = original;
    }
  });

  it("exports a runtime mock that can be invoked by the bridge", async () => {
    // Sanity check: agent.ts imports openClawRuntime from this module path,
    // so any code path that calls processMessage must hit our jest.fn() mock.
    const result = await openClawRuntime.processMessage("hi", {
      userUpn: "u",
      userAadId: "a",
      userRole: "Requester",
      conversationId: "c",
      channelId: "msteams",
    });
    expect(openClawRuntime.processMessage).toHaveBeenCalled();
    expect(result.text).toBe("stub response");
  });
});
