Open `~/.openclaw/openclaw.json`:

```bash
# Windows (PowerShell)
notepad $env:USERPROFILE\.openclaw\openclaw.json
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

### Verify Installation

If things are going wrong, you can verify everything is working:

```bash
# Check configuration is valid
openclaw doctor

# You should see:
# ✓ Configuration loaded
# ✓ Gateway can start
# ✓ Workspace directory exists
```

####  (Optional): Review  Directory Structure

OpenClaw creates the following structure:

```
~/.openclaw/                      # Config root
├── openclaw.json                 # Main configuration
├── workspace/                    # Agent workspace
│   ├── AGENTS.md                 # Agent definitions
│   ├── SOUL.md                   # Agent soul/values
│   ├── TOOLS.md                  # Tools registry
│   ├── MEMORY.md                 # Long-term memory
│   ├── skills/                   # Skills directory
│   │   └── <skill-name>/
│   │       └── SKILL.md
│   └── sessions/                 # Session data (auto-created)
├── data/                         # Data storage
├── logs/                         # Log files
└── cache/                        # Cache directory
```
---