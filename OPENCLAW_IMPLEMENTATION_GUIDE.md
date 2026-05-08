# OpenClaw Implementation Guide

Patterns and techniques for building production-grade AI agents with OpenClaw. Covers multi-agent orchestration, skill creation, plugin development, and advanced deployment patterns.

---

## Agent Tool Development

### Using Built-in Tools

Agents have access to these tools by default:

```typescript
// Memory tools
memory_search(query, limit)       // Vector search over MEMORY.md + memory/*.md
memory_get(path)                  // Read specific memory file  
memory_update(path, content)      // Write/append to memory

// Messaging tools
message(text, mentions)           // Send to current channel
reactions(emoji, action)          // Add/remove reactions

// Session tools (multi-agent)
sessions_spawn(agentId, prompt, sandbox)  // Delegate to sub-agent
sessions_send(sessionKey, message)        // Cross-session messaging
sessions_list(scope)                      // List active sessions

// Scheduling
tasks_schedule(cron, prompt)      // Schedule a cron job
```

### Defining Custom Tools in TOOLS.md

```markdown
## file_read
Reads contents of a file in the workspace.
Parameters: path (string) - relative path from workspace root
Returns: file contents as string

## http_get
Makes an HTTP GET request to an allowed URL.
Parameters: url (string), headers (object, optional)
Returns: response body as string

## database_query
Executes a read-only SQL query against the project database.
Parameters: sql (string)
Returns: JSON array of result rows
```

---

## Multi-Agent Orchestration Patterns

### Pattern 1: Delegation Pyramid

```
Coordinator Agent
    ↓ sessions_spawn
Developer Agent    Analyst Agent    Researcher Agent
```

**Coordinator AGENTS.md**:
```markdown
## Routing Rules
- **Code questions** → delegate to `developer` agent
- **Data analysis** → delegate to `analyst` agent  
- **Research requests** → delegate to `researcher` agent
- **General questions** → answer directly
```

**Spawning a sub-agent**:
```typescript
{
  "name": "sessions_spawn",
  "input": {
    "agentId": "developer",
    "prompt": "Review this TypeScript code: ...",
    "sandbox": "inherit"
  }
}
```

### Pattern 2: Parallel Processing

Route one message to multiple agents simultaneously:

```yaml
channels:
  broadcastGroups:
    - id: "tech-team"
      agents: ["developer", "architect", "security-reviewer"]
```

Each agent produces an independent response — useful for getting multiple perspectives.

### Pattern 3: Hierarchical Teams

```yaml
agents:
  list:
    - id: "cto"
      description: "Orchestrates tech team"
      subagents:
        allowAgents: ["backend-lead", "frontend-lead"]
    
    - id: "backend-lead"
      description: "Coordinates backend team"
      subagents:
        allowAgents: ["backend-dev-1", "backend-dev-2"]
```

---

## Skill Creation

### Skill Structure

```
my-skill/
├── manifest.json
├── commands/
│   └── my-feature/
│       └── README.md      ← markdown skill definition
└── skills/
    └── tools/
        └── my-tool.yaml   ← YAML tool definition
```

### Markdown Skill (README.md)

```markdown
# My Feature

## Description
This skill enables the agent to perform [specific capability].

## When to Use
Use this skill when the user asks to [trigger conditions].

## How to Use
1. [Step 1]
2. [Step 2]

## Examples
User: "Do X"
Agent: [demonstrates the skill]
```

### YAML Tool Definition

```yaml
name: my_tool
description: |
  Does something specific.
  Returns the result as a string.
parameters:
  type: object
  properties:
    input:
      type: string
      description: The input to process
    options:
      type: object
      properties:
        format:
          type: string
          enum: ["json", "text", "markdown"]
  required: ["input"]
```

### Publishing to ClawHub

```bash
# Build skill package
clawhub package build

# Publish
clawhub package publish

# Users install with
pnpm openclaw skills install my-skill-name
```

---

## Plugin Development

### TypeScript Plugin Structure

```typescript
// index.ts — plugin entry point
import type { OpenClawPlugin, ChannelPlugin, ToolDefinition } from "@openclaw/openclaw";

export default {
  id: "my-plugin",
  channels: [myChannel],
  tools: createMyTools(),
} satisfies OpenClawPlugin;
```

### Custom Channel Plugin

```typescript
export const myChannel: ChannelPlugin<MyConfig> = {
  id: "my-channel",
  
  async start(cfg: MyConfig, runtime: PluginRuntime) {
    // Set up message listener
    myApi.onMessage(async (msg) => {
      await runtime.handleMessage({
        peer: msg.userId,
        text: msg.text,
        channel: "my-channel",
        sendReply: async (text) => myApi.send(msg.chatId, text),
      });
    });
  },
  
  probe: async (cfg) => ({ ok: true }),
  resolveAccount: (cfg) => ({ accountId: "default", enabled: true, configured: true }),
};
```

### Custom Tool Definition

```typescript
function createMyTools(): ToolDefinition[] {
  return [
    {
      name: "my_tool",
      description: "Does something useful.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "The query to process" },
        },
        required: ["query"],
      },
      async execute({ query }) {
        const result = await doSomethingWith(query);
        return { content: [{ type: "text", text: JSON.stringify(result) }] };
      },
    },
  ];
}
```

### Plugin Manifest

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "channels": ["my-channel"],
  "tools": ["my_tool"]
}
```

---

## Advanced Patterns

### Autonomous Scheduling

```yaml
automation:
  cron:
    tasks:
      - id: "daily-briefing"
        schedule: "0 8 * * 1-5"        # Weekdays at 8 AM
        agentId: "default"
        prompt: "Prepare my morning briefing with today's calendar and pending tasks"
        
      - id: "weekly-summary"
        schedule: "0 17 * * 5"         # Fridays at 5 PM
        agentId: "analyst"
        prompt: "Generate a weekly progress summary from memory and sessions"
```

### Approval Workflows

```yaml
approvals:
  enabled: true
  requireFor:
    - toolName: "browser"
      mode: "approve_once"    # Once per conversation
    - toolName: "exec"
      mode: "each_call"       # Every execution
    - toolName: "send_email"
      mode: "approve_once"
```

The agent shows a preview and waits for "confirm" before executing.

### Model Failover

```yaml
agents:
  defaults:
    modelFailover:
      maxAttempts: 3
      backoffMs: 1000
      retryableErrors: ["rate_limit", "timeout", "service_unavailable"]
      fallbackModels:
        - "anthropic/claude-sonnet"    # If GPT-4 fails
        - "openai/gpt-3.5-turbo"       # Final fallback
```

### Long-Running Tasks

For tasks that exceed a single LLM turn:

```typescript
// In AGENTS.md, instruct the agent:
// "For tasks that will take more than 5 minutes, use sessions_spawn with
//  a dedicated worker agent and report progress every 2 minutes."

// The worker agent updates memory with progress:
await memory_update("tasks/current.md", `
## Task: ${taskName}
Status: In progress (${percentComplete}%)
Last update: ${new Date().toISOString()}
`);
```

### Context Caching

Reduce LLM costs for high-frequency prompts:

```yaml
agents:
  defaults:
    contextCaching:
      enabled: true
      ttlSeconds: 300         # Cache compiled system prompt for 5 minutes
      keys: ["systemPrompt", "tools"]
```

---

## Testing & Validation

### Unit Testing Skills

```bash
# Test specific skill
openclaw skills test my-skill --input "test prompt"

# Test tool execution
openclaw tools test my_tool --args '{"query": "test"}'
```

### Integration Testing

```bash
# Start gateway in test mode
NODE_ENV=test pnpm gateway:watch

# Send test message
openclaw sessions create --agent default --channel test --message "Hello"
openclaw sessions view <sessionId>
```

### Load Testing

```bash
# Simulate concurrent users
openclaw sessions bulk-create \
  --agent default \
  --count 10 \
  --message "Summarize my recent tasks"
```

---

## Performance Optimization

| Setting | Impact | Recommendation |
|---------|--------|----------------|
| `bootstrapTotalMaxChars` | Context size → cost | 30k–60k depending on complexity |
| `memorySearch` | Adds QMD search overhead | Disable for simple agents |
| `thinking: "extended"` | Slower, more capable | Use only for complex reasoning |
| `historyLimit` | Context size per channel message | 5–10 for most use cases |
| Model choice | Cost vs capability tradeoff | GPT-4o or Claude Sonnet for balance |

---

## Production Readiness Checklist

**Security**
- [ ] `auth.mode: "token"` or `"trusted-proxy"` (not `"none"`)
- [ ] Private network access via Tailscale or reverse proxy with TLS
- [ ] Secrets in environment variables, not config files
- [ ] Tool policies scoped to minimum required permissions

**Reliability**
- [ ] `modelFailover` configured with at least one fallback
- [ ] Health check endpoint monitored (`/health`)
- [ ] Stuck session thresholds set (`stuckSessionWarnMs`, `stuckSessionAbortMs`)
- [ ] Process supervisor (systemd, PM2, or Docker restart policy)

**Operations**
- [ ] Log rotation configured (logs grow with session volume)
- [ ] `~/.openclaw/agents/*/sessions/` backed up regularly
- [ ] API keys rotated quarterly
- [ ] Alerting on gateway crash or health check failure

**Governance** (→ covered in Phase 2 and 3)
- [ ] Audit logging enabled
- [ ] Tool access reviewed per agent
- [ ] Network policy applied for production workloads
