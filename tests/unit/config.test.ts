/**
 * Unit tests for config.ts — validate env var parsing and fail-fast behaviour
 */

describe("Config validation", () => {
  const originalEnv = process.env;

  const baseEnv = {
    APP_ENV: "development",
    PORT: "3978",
    A365_APP_ID: "test-app-id",
    A365_APP_PASSWORD: "test-password",
    A365_TENANT_ID: "test-tenant-id",
    AA_INSTANCE_ID: "test-instance-id",
    AGENT_IDENTITY: "agent@test.example.com",
    OWNER: "owner@test.example.com",
    OWNER_AAD_ID: "test-owner-aad-id",
    ANTHROPIC_API_KEY: "test-key",
    OPENCLAW_MODEL: "anthropic/claude-opus-4-6",
  };

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnv, ...baseEnv };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it("loads valid config without errors", () => {
    expect(() => require("../../src/config")).not.toThrow();
    const { config } = require("../../src/config");
    expect(config.port).toBe(3978);
    expect(config.a365AppId).toBe("test-app-id");
    expect(config.agentIdentity).toBe("agent@test.example.com");
  });

  it("throws when A365_APP_ID is missing", () => {
    delete process.env.A365_APP_ID;
    expect(() => require("../../src/config")).toThrow(/Configuration validation failed/);
  });

  it("throws when AGENT_IDENTITY is not a valid email", () => {
    process.env.AGENT_IDENTITY = "not-an-email";
    expect(() => require("../../src/config")).toThrow();
  });

  it("throws when no LLM provider key is set", () => {
    delete process.env.ANTHROPIC_API_KEY;
    expect(() => require("../../src/config")).toThrow(/LLM provider key/);
  });

  it("defaults network mode to unrestricted", () => {
    const { config } = require("../../src/config");
    expect(config.networkMode).toBe("unrestricted");
  });

  it("rejects invalid NETWORK_MODE", () => {
    process.env.NETWORK_MODE = "invalid-mode";
    expect(() => require("../../src/config")).toThrow();
  });

  it("sets correct port from PORT env var", () => {
    process.env.PORT = "4000";
    const { config } = require("../../src/config");
    expect(config.port).toBe(4000);
  });
});
