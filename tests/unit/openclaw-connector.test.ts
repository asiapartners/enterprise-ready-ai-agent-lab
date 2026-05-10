/**
 * Unit tests for openclaw-connector.ts — runtime mode resolution and
 * message dispatch (stub, HTTP gateway, error propagation).
 *
 * The in-process SDK path is exercised indirectly: the optional `openclaw`
 * package is intentionally not installed, so tryLoadSdk() returns null and
 * we exercise gateway/stub fallbacks.
 */

jest.mock("../../src/config", () => ({
  config: {
    appEnv: "development",
    openclawModel: "anthropic/claude-opus-4-6",
    openclawFallbackModels: undefined,
    openclawConfigPath: "/nonexistent",
    openclawPluginDir: "/nonexistent/plugins",
    networkMode: "unrestricted",
    agentIdentity: "agent@test.example.com",
  },
}));

import { openClawRuntime, AgentContext } from "../../src/openclaw-connector";

const baseContext: AgentContext = {
  userUpn: "user@test.example.com",
  userAadId: "aad-id",
  userRole: "Requester",
  conversationId: "conv-1",
  channelId: "msteams",
};

describe("OpenClawRuntime", () => {
  afterEach(async () => {
    delete process.env.OPENCLAW_GATEWAY_URL;
    await openClawRuntime.shutdown();
  });

  it("falls back to stub mode in development when no SDK or gateway is available", async () => {
    await openClawRuntime.init();
    expect(openClawRuntime.getMode()).toBe("stub");

    const res = await openClawRuntime.processMessage("hello", baseContext);
    expect(res.text).toContain("[OpenClaw stub]");
    expect(res.text).toContain("hello");
    expect(res.text).toContain(baseContext.userUpn);
  });

  it("uses HTTP gateway mode when OPENCLAW_GATEWAY_URL is set", async () => {
    process.env.OPENCLAW_GATEWAY_URL = "http://gateway.test:18789";

    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ response: "hello back", attachments: [{ a: 1 }] }),
      text: async () => "",
    });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (globalThis as any).fetch = fetchMock;

    await openClawRuntime.init();
    expect(openClawRuntime.getMode()).toBe("http");

    const res = await openClawRuntime.processMessage("ping", baseContext);
    expect(res.text).toBe("hello back");
    expect(res.attachments).toEqual([{ a: 1 }]);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("http://gateway.test:18789/chat");
    expect(init.method).toBe("POST");
    const body = JSON.parse(init.body);
    expect(body).toMatchObject({
      session_id: baseContext.conversationId,
      message: "ping",
      channel: baseContext.channelId,
      agent_identity: "agent@test.example.com",
      user: {
        upn: baseContext.userUpn,
        aad_id: baseContext.userAadId,
        role: baseContext.userRole,
      },
    });
  });

  it("propagates gateway errors with status and body", async () => {
    process.env.OPENCLAW_GATEWAY_URL = "http://gateway.test:18789";

    const fetchMock = jest.fn().mockResolvedValue({
      ok: false,
      status: 502,
      json: async () => ({}),
      text: async () => "upstream down",
    });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (globalThis as any).fetch = fetchMock;

    await openClawRuntime.init();
    await expect(
      openClawRuntime.processMessage("ping", baseContext)
    ).rejects.toThrow(/gateway 502/);
  });

  it("throws if processMessage is called before init", async () => {
    // Force uninitialised state
    await openClawRuntime.shutdown();
    await expect(
      openClawRuntime.processMessage("x", baseContext)
    ).rejects.toThrow(/not initialised/);
  });
});
