

## Step 5: Configure Your Agent

### 5.1 Edit Main Configuration

Open `~/.openclaw/openclaw.json`:

```bash
# Windows (PowerShell)
notepad $env:USERPROFILE\.openclaw\openclaw.json
```

**Minimal Configuration:**

```json5
{
  // LLM Configuration
  agents: {
    defaults: {
      model: "azure/gpt-4",             // Azure OpenAI deployment
      temperature: 0.7,                // 0.0 (deterministic) to 1.0 (creative)
      maxTokens: 4096,
    }
  },
  
  // Gateway settings
  gateway: {
    port: 18789,
    verbose: true,
  },
  
  // Optional: Model failover
  modelFailover: [
    "openai/gpt-4o",
    "anthropic/claude-3-5-sonnet",
    "openai/gpt-4-turbo",
  ],
}
```

### 5.2 Set Environment Variables

Set your Azure OpenAI credentials in environment:

```bash
# Azure OpenAI
export AZURE_OPENAI_API_KEY="your-key-here"
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="gpt-4"  # Your deployment name

# Make permanent (add to ~/.bashrc or ~/.zshrc)
echo 'export AZURE_OPENAI_API_KEY="your-key-here"' >> ~/.bashrc
echo 'export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"' >> ~/.bashrc
echo 'export AZURE_OPENAI_DEPLOYMENT="gpt-4"' >> ~/.bashrc
source ~/.bashrc
```

---

## Step 6: Initialize Workspace

Create the agent workspace:

```bash
openclaw setup
```

This creates:
- `~/.openclaw/workspace/AGENTS.md`
- `~/.openclaw/workspace/SOUL.md`
- `~/.openclaw/workspace/TOOLS.md`
- `~/.openclaw/workspace/MEMORY.md`

---

## Step 7: Define Your Agent

### 7.1 Create Agent Instructions

Edit `~/.openclaw/workspace/AGENTS.md`:

```markdown
# agent:main

**Description**: Main autonomous AI assistant

**Instructions**:
- You are a helpful, curious AI assistant
- You think step-by-step before taking action
- You provide concise but thorough responses
- You ask clarifying questions when needed
- You remember context across conversations

**Personality**:
- Friendly but professional
- Detail-oriented
- Proactive in offering help
- Respectful of user preferences

**Tools Access**:
- read: File reading
- write: File writing
- bash: System commands
- browser: Web access
```

### 7.2 Define Agent Soul (Optional)

Edit `~/.openclaw/workspace/SOUL.md`:

```markdown
# Core Values

## Autonomy
I take initiative and make decisions within my defined perimeter.

## Transparency
I explain my reasoning when taking actions.

## Reliability
I complete tasks thoroughly and inform you of progress.

## Respect
I honor your preferences and maintain privacy.

## Learning
I improve over time and adapt to your needs.
```

---

## Step 8: First Test

### Test 1: Simple Chat

```bash
openclaw agent --message "Hello! Who are you?"
```

**Expected output:**
```
🤖 Agent response:
I'm your autonomous AI assistant. I'm here to help you with...
```

### Test 2: File Operations

```bash
openclaw agent --message "Create a file called 'test.txt' with the content 'Hello World'"
```

### Test 3: Information Retrieval

```bash
openclaw agent --message "What is the current time?"
```

### Test 4: Multi-step Task

```bash
openclaw agent --message "Search for the latest OpenClaw releases and summarize the features"
```

---

## Next Steps

1. **Customize Agent Personality** → Edit `AGENTS.md` and `SOUL.md`
2. **Add Skills** → Create skills in `~/.openclaw/workspace/skills/`
3. **Configure Tools** → Modify tool policies in `openclaw.json`
4. **Set Up Microsoft Teams** → Follow [TEAMS_SETUP.md](./TEAMS_SETUP.md)
5. **Create Memory** → Add facts to `MEMORY.md`

---

## Useful Commands

```bash
# Run a single agent message
openclaw agent --message "Your question here"

# With thinking enabled
openclaw agent --message "Why is the sky blue?" --thinking high

# Start interactive REPL
openclaw repl

# Run the gateway (central service)
openclaw gateway --port 18789 --verbose

# Check system status
openclaw doctor

# Update to latest version
openclaw update

# List installed skills
openclaw skills list

# View logs
openclaw logs tail
```

---

## Success Indicators

✅ Phase 1 Setup is complete when:

- [ ] `openclaw --version` returns a version
- [ ] `openclaw doctor` shows all checks passing
- [ ] `openclaw agent --message "Hi"` returns a response
- [ ] `~/.openclaw/workspace/` contains AGENTS.md and SOUL.md
- [ ] Gateway starts without errors: `openclaw gateway --port 18789`
- [ ] (Optional) Teams bot responds to messages

---



### Module 3: Agent Personality & Skills (Days 3-4)

**Topics**: Define agent behavior, create instructions, add skills

1. **Create Agent Instructions** (`AGENTS.md`)
   - Edit: `~/.openclaw/workspace/AGENTS.md`
   - Define agent name, role, and behavior
   - See [AGENT_PERSONALITY.md](./setup/AGENT_PERSONALITY.md) template

2. **Add Soul & Consciousness** (`SOUL.md`)
   - Edit: `~/.openclaw/workspace/SOUL.md`
   - Define core values and decision-making principles
   - Example: [workspace/SOUL.md](./workspace/SOUL.md)

3. **Create Skills** (optional but recommended)
   - Create: `~/.openclaw/workspace/skills/hello-world/SKILL.md`
   - Skills are reusable agent capabilities
   - See [workspace/skills/hello-world/SKILL.md](./workspace/skills/hello-world/SKILL.md)

### Module 4: Tools & Capabilities (Days 4-5)

**Topics**: Configure tools, set permissions, test execution

1. **Built-in Tools Overview**
   - Browser tool for web automation
   - Bash tool for system commands
   - File tools for read/write/edit

2. **Configure Tool Policies**
   - Edit: `~/.openclaw/openclaw.json`
   - Set sandbox mode and permissions
   - Example: [CONFIG_EXAMPLES.md](./starter-configs/CONFIG_EXAMPLES.md)

3. **Test Tool Access**
   ```bash
   openclaw agent --message "List my home directory"
   openclaw agent --message "What's the weather in San Francisco?"
   ```

### Module 5: First Autonomous Tasks (Days 5-6)

**Topics**: Run your first autonomous agent tasks

1. **Simple Information Retrieval**
   ```bash
   openclaw agent --message "Find and summarize the latest news about AI"
   ```

2. **File Operations**
   ```bash
   openclaw agent --message "Create a TODO list file with today's tasks"
   ```

3. **Multi-step Tasks**
   ```bash
   openclaw agent --message "Search for Python async patterns, \
                             save the best practices to a file, \
                             and create a summary"
   ```

### Module 6: Channel Integration (Days 6-7)

**Topics**: Connect communication channels, interact with agent

1. **Microsoft Teams Integration** (Recommended for Phase 1)
   - Set up Teams bot
   - Configure in `openclaw.json`
   - Test: Send message to bot
   - See [TEAMS_SETUP.md](./setup/TEAMS_SETUP.md)

2. **Discord Integration** (Alternative)
   - See [DISCORD_SETUP.md](./setup/DISCORD_SETUP.md)

### Module 7: Memory & Persistence (Day 7)

**Topics**: Set up memory systems, test context retention

1. **Long-term Memory**
   - Edit: `~/.openclaw/workspace/MEMORY.md`
   - Add facts and patterns
   - Test: Recall memory in next session

2. **Session Context**
   ```bash
   openclaw agent --message "Remember: I prefer detailed explanations"
   openclaw agent --message "Explain quantum entanglement"
   # Agent should use remembered preference
   ```