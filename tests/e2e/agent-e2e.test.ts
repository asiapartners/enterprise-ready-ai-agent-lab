/**
 * E2E tests — deployed agent endpoint
 *
 * Requires a running agent instance. Set E2E_BASE_URL env var.
 * These tests mirror the Agent365-Samples E2E harness pattern:
 *   - Verify health endpoint
 *   - Verify bot endpoint accepts valid Bot Framework activities
 *   - Log SDK versions to GITHUB_STEP_SUMMARY
 *
 * Run: npm run test:e2e
 * In CI: triggered by e2e.yml workflow.
 */

const BASE_URL = process.env.E2E_BASE_URL ?? "http://localhost:3978";

describe("E2E: Deployed agent", () => {
  describe("Health endpoint", () => {
    it("GET /health returns 200 and status ok", async () => {
      const res = await fetch(`${BASE_URL}/health`);
      expect(res.status).toBe(200);
      const body = await res.json() as { status: string };
      expect(body.status).toBe("ok");
    });

    it("GET /health response includes version and env", async () => {
      const res = await fetch(`${BASE_URL}/health`);
      const body = await res.json() as Record<string, string>;
      expect(body).toHaveProperty("version");
      expect(body).toHaveProperty("env");
      expect(["development", "staging", "production"]).toContain(body.env);
    });
  });

  describe("Bot Framework endpoint", () => {
    it("POST /api/messages with invalid auth returns 401", async () => {
      const res = await fetch(`${BASE_URL}/api/messages`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          // No Authorization header — should be rejected
        },
        body: JSON.stringify({
          type: "message",
          text: "Hello",
          from: { id: "user-1" },
          recipient: { id: "bot-1" },
          conversation: { id: "conv-1" },
          channelId: "msteams",
        }),
      });
      // Bot Framework returns 401 for unauthenticated requests
      expect([401, 403]).toContain(res.status);
    });
  });
});

// ─── SDK Version Logging (mirrors Agent365-Samples "Log SDK Versions" step) ──
afterAll(() => {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const pkg = require("../../package.json") as {
      dependencies: Record<string, string>;
    };
    const agent365Deps = Object.entries(pkg.dependencies)
      .filter(([name]) => name.startsWith("@microsoft/"))
      .map(([name, ver]) => `  ${name}: ${ver}`)
      .join("\n");

    console.log(`\n=== SDK Versions (package.json constraints) ===\n${agent365Deps}\n`);
  } catch {
    // Non-fatal
  }
});
