# Agent Long-Term Memory

This file is the agent's persistent memory. Facts recorded here are available across all sessions.

Copy this to `~/.openclaw/workspace/MEMORY.md` and populate with facts about your environment, preferences, and ongoing work.

---

## User Preferences

<!-- Add your preferences here so the agent remembers them across sessions -->
<!-- Examples: -->
<!-- - Prefers concise bullet-point answers over long paragraphs -->
<!-- - Works primarily in Python and TypeScript -->
<!-- - Timezone: US Eastern (UTC-5) -->
<!-- - Uses VS Code as primary editor -->

---

## Project Context

<!-- Describe active projects and their current state -->
<!-- Examples: -->
<!-- ### Project: enterprise-ai-agent-lab -->
<!-- - Status: In Progress (Phase 1 complete, starting Phase 2) -->
<!-- - Goal: Build enterprise-ready autonomous AI assistant -->
<!-- - Tech stack: OpenClaw + Azure OpenAI + Microsoft Teams -->

---

## Environment Details

<!-- Technical details about your environment -->
<!-- Examples: -->
<!-- - OS: macOS Sequoia -->
<!-- - Node.js: v22.14 -->
<!-- - Primary workspace: ~/Projects -->
<!-- - Azure subscription: development -->
<!-- - M365 tenant: contoso.com -->

---

## Recurring Instructions

<!-- Things the agent should always do or remember -->
<!-- Examples: -->
<!-- - Always create dated backups before modifying important files -->
<!-- - Use git for version control on all code changes -->
<!-- - Never commit API keys or secrets to any repository -->

---

## Known Issues / Notes

<!-- Temporary notes that don't fit elsewhere -->
<!-- Delete entries when resolved -->

---

## How to Use This File

The agent reads MEMORY.md at the start of each session and uses it as background context. To update it:

```bash
# Tell the agent to remember something
openclaw agent --message "Remember: I prefer code examples in TypeScript over JavaScript"

# The agent will update MEMORY.md with the new preference

# Or edit directly
nano ~/.openclaw/workspace/MEMORY.md
```

**Tips:**
- Keep entries specific and actionable
- Date entries that are time-sensitive
- Remove entries that are no longer relevant
- Use sections to organize different types of information
