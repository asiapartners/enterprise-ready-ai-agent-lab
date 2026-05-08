# Hello World Skill

This is a starter skill template. Skills are reusable agent capabilities that can be loaded into your OpenClaw workspace.

Copy this directory to `~/.openclaw/workspace/skills/hello-world/` to activate it.

---

## What This Skill Does

This skill teaches the agent to:
- Greet users in a friendly, personalized way
- Introduce itself and explain its capabilities
- Demonstrate the skill system is working correctly

---

## Skill Instructions

When the user says "hello", "hi", "hey", or asks "who are you":

1. Greet the user warmly by name if you know it
2. Briefly introduce yourself and your current capabilities
3. Offer 2-3 specific things you can help with right now
4. Ask what they'd like to work on

**Example greeting:**
```
Hello! I'm your AI assistant. I can help you with:
• 🔍 Researching topics and summarizing information
• 📁 Managing files and creating documents
• 💻 Running commands and automating tasks

What would you like to work on today?
```

---

## How to Create Your Own Skills

### Skill Structure

```
skills/your-skill-name/
└── SKILL.md       # This file — defines the skill behavior
```

For advanced skills with custom tools:

```
skills/your-skill-name/
├── SKILL.md       # Skill definition and instructions
└── tools/
    └── tool.yaml  # Custom tool definitions (optional)
```

### SKILL.md Format

```markdown
# Skill Name

## Description
Brief description of what this skill does.

## When to Use
Conditions that trigger this skill.

## Instructions
Step-by-step guidance for the agent when using this skill.

## Examples
Concrete examples of inputs and expected outputs.
```

### Loading Skills

Skills in `~/.openclaw/workspace/skills/` are automatically loaded.
Restart the gateway to pick up new skills:

```bash
openclaw gateway restart
openclaw skills list  # Should show your new skill
```

---

## Example Custom Skills

### Daily Standup Helper
```markdown
# Daily Standup

When the user says "standup" or "daily update":
1. Ask: "What did you work on yesterday?"
2. Ask: "What are you working on today?"
3. Ask: "Any blockers?"
4. Format responses as a standup update
5. Save to ~/standup-notes/YYYY-MM-DD.md
```

### Code Documentation Generator
```markdown
# Code Documenter

When the user shares code and asks for documentation:
1. Read the code carefully
2. Identify public functions, classes, and interfaces
3. Generate JSDoc/docstring comments for each
4. Return the documented version
5. Explain any complex logic inline
```

---

**Next**: See [AGENT_PERSONALITY.md](../../setup/AGENT_PERSONALITY.md) to customize agent behavior beyond skills.
