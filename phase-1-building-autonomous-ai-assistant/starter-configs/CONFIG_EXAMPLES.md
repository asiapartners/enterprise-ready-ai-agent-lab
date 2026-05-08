# OpenClaw Configuration Examples

Ready-to-use configuration examples for different scenarios.

---

## 1. Minimal Configuration (Quick Start)

Simplest working configuration using Azure OpenAI:

```json5
{
  // LLM Configuration
  agents: {
    defaults: {
      model: "azure/gpt-4",
      temperature: 0.7,
      maxTokens: 4096,
    }
  },
  
  // Gateway
  gateway: {
    port: 18789,
    verbose: true,
  }
}
```

**Required environment variables:**
```bash
export AZURE_OPENAI_API_KEY="your-key"
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="gpt-4"
```

**Validate:**
```bash
openclaw config validate
openclaw agent --message "Hello"
```

---

## 2. Full Featured Configuration (Production)

Complete setup with Teams, multiple agents, tools, and cost controls:

```json5
{
  agents: {
    defaults: {
      model: "azure/gpt-4",
      temperature: 0.7,
      maxTokens: 8192,
      memoryEnabled: true,
    },
    
    list: {
      // Primary assistant
      "main": {
        model: "azure/gpt-4",
        description: "General purpose assistant",
      },
      
      // Code specialist
      "coder": {
        model: "azure/gpt-4-turbo",
        description: "Code review and development",
        toolPolicies: {
          profile: "developer",
          alsoAllow: ["bash", "edit"],
        }
      }
    }
  },
  
  // Model fallover chain
  modelFailover: [
    "openai/gpt-4o",
    "anthropic/claude-sonnet-4-6",
  ],
  
  // Channels
  channels: {
    teams: {
      enabled: true,
      botId: "${TEAMS_BOT_ID}",
      botPassword: "${TEAMS_BOT_PASSWORD}",
    }
  },
  
  // Tool configuration
  tools: {
    browser: { enabled: true },
    bash: { enabled: true, timeout: 60000 },
    files: { enabled: true },
    edit: { enabled: true },
  },
  
  // Security
  sandbox: {
    enabled: true,
    mode: "restrict",
  },
  
  // Rate limiting
  rateLimit: {
    requestsPerMinute: 60,
    tokensPerMinute: 100000,
  },
  
  // Cost controls
  costs: {
    dailyLimit: 10.0,
    monthlyLimit: 200.0,
  },
  
  // Gateway
  gateway: {
    port: 18789,
    verbose: false,
    auth: {
      mode: "token",
      token: "${GATEWAY_TOKEN}",
    }
  }
}
```

---

## 3. Local Development (Ollama - Free)

No API costs, runs entirely on your machine:

```json5
{
  agents: {
    defaults: {
      model: "ollama/llama3",
      temperature: 0.7,
    }
  },
  
  gateway: {
    port: 18789,
    verbose: true,
  }
}
```

**Prerequisites:**
```bash
# Install and start Ollama
brew install ollama
ollama pull llama3
ollama serve
```

> Models run slower than cloud APIs but are completely free and private.

---

## 4. Cost-Effective Development

Use smaller models during development to minimize costs:

```json5
{
  agents: {
    defaults: {
      model: "anthropic/claude-haiku-4-5-20251001",  // ~90% cheaper than Opus
      temperature: 0.7,
      maxTokens: 2048,                                // Smaller responses
    }
  },
  
  costs: {
    dailyLimit: 2.0,    // Strict $2/day limit during dev
  },
  
  gateway: {
    port: 18789,
    verbose: true,
  }
}
```

---

## 5. Teams Integration

Focused configuration for Microsoft Teams deployment:

```json5
{
  agents: {
    defaults: {
      model: "azure/gpt-4",
      temperature: 0.7,
    }
  },
  
  channels: {
    teams: {
      enabled: true,
      botId: "${TEAMS_BOT_ID}",
      botPassword: "${TEAMS_BOT_PASSWORD}",
      messages: {
        directMessage: {
          historyLimit: 20,
        },
        groupChat: {
          historyLimit: 10,
          requireMention: true,  // Must @mention bot in channels
        }
      }
    }
  },
  
  // Safe tools for Teams (no bash for network safety)
  tools: {
    browser: { enabled: true },
    bash: { enabled: false },
    files: { enabled: true },
  },
  
  gateway: {
    port: 18789,
  }
}
```

---

## 6. Multi-Agent Routing

Route different users or channels to specialized agents:

```json5
{
  agents: {
    list: {
      "main": {
        model: "azure/gpt-4",
        description: "General assistant",
      },
      "coder": {
        model: "azure/gpt-4-turbo",
        description: "Code specialist",
      },
      "researcher": {
        model: "openai/gpt-4o",
        description: "Research specialist",
      }
    },
    
    routing: {
      // Channel-based routing
      "teams:general": "main",
      "teams:engineering": "coder",
      "teams:research": "researcher",
      
      // Keyword routing (fallback)
      keywords: {
        "code|review|debug|bug": "coder",
        "research|find|search|analyze": "researcher",
      }
    }
  },
  
  gateway: {
    port: 18789,
  }
}
```

---

## 7. Enterprise Configuration

Production-grade with Docker sandboxing, audit logging, and strict governance:

```json5
{
  agents: {
    defaults: {
      model: "azure/gpt-4",
      temperature: 0.5,      // Lower = more deterministic
      maxTokens: 4096,
      memoryEnabled: true,
    }
  },
  
  channels: {
    teams: {
      enabled: true,
      botId: "${TEAMS_BOT_ID}",
      botPassword: "${TEAMS_BOT_PASSWORD}",
      adminUsers: ["admin@company.com"],
    }
  },
  
  // Docker sandbox for all tool execution
  sandbox: {
    enabled: true,
    mode: "docker",
    image: "openclaw-sandbox:latest",
    resourceLimits: {
      memory: "512m",
      cpu: "0.5",
    }
  },
  
  // Audit logging
  audit: {
    enabled: true,
    logPath: "~/.openclaw/audit.log",
    logToolCalls: true,
    logMessages: true,
  },
  
  // Strict rate limiting
  rateLimit: {
    requestsPerMinute: 30,
    tokensPerMinute: 50000,
    perUserLimit: 10,
  },
  
  // Cost controls
  costs: {
    dailyLimit: 100.0,
    monthlyLimit: 2000.0,
    alertThreshold: 0.8,  // Alert at 80% of limit
  },
  
  // Gateway security
  gateway: {
    port: 18789,
    auth: {
      mode: "token",
      token: "${GATEWAY_TOKEN}",
    },
    bind: {
      mode: "loopback",  // Only accessible from localhost
    }
  }
}
```

---

## Switching Configurations

```bash
# Use a specific config file
openclaw gateway --config /path/to/openclaw-production.json

# Validate before switching
openclaw config validate --config /path/to/openclaw-production.json

# Test with new config
openclaw agent --message "Hello" --config /path/to/new-config.json
```

---

## Environment Variables Reference

| Variable | Purpose | Used In |
|----------|---------|---------|
| `AZURE_OPENAI_API_KEY` | Azure OpenAI auth | Azure configs |
| `AZURE_OPENAI_ENDPOINT` | Azure resource URL | Azure configs |
| `AZURE_OPENAI_DEPLOYMENT` | Model deployment name | Azure configs |
| `OPENAI_API_KEY` | OpenAI auth | OpenAI configs |
| `ANTHROPIC_API_KEY` | Anthropic auth | Anthropic configs |
| `TEAMS_BOT_ID` | Teams bot App ID | Teams configs |
| `TEAMS_BOT_PASSWORD` | Teams bot secret | Teams configs |
| `DISCORD_BOT_TOKEN` | Discord bot token | Discord configs |
| `GATEWAY_TOKEN` | Gateway auth token | Secured gateways |
