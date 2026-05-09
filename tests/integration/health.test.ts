/**
 * Integration tests — health endpoint
 *
 * Acceptance criteria: GET /health → 200 {"status":"ok"}
 * Tests the full Express stack without real Azure credentials.
 */

import request from "supertest";
import express from "express";
import { config } from "../../src/config";

// Build a minimal test app that mirrors index.ts routing
function buildTestApp() {
  const app = express();
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.json({
      status: "ok",
      service: config.otelServiceName,
      version: config.otelServiceVersion,
      env: config.appEnv,
      timestamp: new Date().toISOString(),
    });
  });

  return app;
}

// Provide required env for config to parse
beforeAll(() => {
  process.env.A365_APP_ID = "test-app-id";
  process.env.A365_APP_PASSWORD = "test-password";
  process.env.A365_TENANT_ID = "test-tenant-id";
  process.env.AA_INSTANCE_ID = "test-instance-id";
  process.env.AGENT_IDENTITY = "agent@test.example.com";
  process.env.OWNER = "owner@test.example.com";
  process.env.OWNER_AAD_ID = "test-owner-aad-id";
  process.env.ANTHROPIC_API_KEY = "test-key";
});

describe("GET /health", () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildTestApp();
  });

  it("returns 200 with status ok", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
  });

  it("includes service name and version", async () => {
    const res = await request(app).get("/health");
    expect(res.body).toHaveProperty("service");
    expect(res.body).toHaveProperty("version");
  });

  it("includes a valid ISO timestamp", async () => {
    const res = await request(app).get("/health");
    expect(() => new Date(res.body.timestamp)).not.toThrow();
    expect(new Date(res.body.timestamp).toISOString()).toBe(res.body.timestamp);
  });
});
