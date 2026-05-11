# OpenClaw Configuration Examples

This file contains ready-to-use `openclaw.json` configuration examples for different scenarios.

---

## 1. Minimal Configuration (Quick Start)

**File**: `~/.openclaw/openclaw.json`

```json5
{
  // LLM Configuration - Azure OpenAI
  agents: {
    defaults: {
      model: "azure/gpt-4",
      temperature: 0.7,
      maxTokens: 8192,
    }
  },
  
  // Gateway settings
  gateway: {
    port: 18789,
    verbose: true,
  }
}
```

**Setup**:
1. Save as `~/.openclaw/openclaw.json`
2. Set environment: 
   ```bash
   export AZURE_OPENAI_API_KEY="your-key"
   export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"
   export AZURE_OPENAI_DEPLOYMENT="gpt-4"
   ```
3. Run: `openclaw gateway --port 18789`

---

## 2. Full Featured Configuration

**For**: Production use with all features

```json5
{
  // ==================== AGENTS ====================
  agents: {
    defaults: {
      // Model (primary)
      model: "openai/gpt-4o",
      temperature: 0.7,
      maxTokens: 8192,
      
      // Context limits
      contextLimits: {
        systemPromptMaxChars: 50000,
        toolResultMaxChars: 10000,
        postCompactionMaxChars: 200000,
      },
      
      // Memory
      memoryEnabled: true,
      memoryRetentionDays: 90,
      
      // Thinking mode (Claude only)
      thinkingDefault: "medium",
    },
    
    // Define multiple agents
    list: [
      {
        name: "main",
        model: "openai/gpt-4o",
        temperature: 0.5,
        systemPrompt: "You are the main assistant",
      },
      {
        name: "coder",
        model: "anthropic/claude-3-5-sonnet-20241022",
        temperature: 0.3,
        systemPrompt: "You are a code specialist",
      },
    ]
  },
  
  // ==================== MODEL FAILOVER ====================
  modelFailover: [
    "openai/gpt-4o",
    "anthropic/claude-3-5-sonnet-20241022",
    "openai/gpt-4-turbo",
    "deepseek/deepseek-chat",
  ],
  
  // ==================== GATEWAY ====================
  gateway: {
    port: 18789,
    host: "localhost",
    verbose: true,
    
    // Logging
    logging: {
      level: "info",  // debug, info, warn, error
      format: "json",
      file: "~/.openclaw/logs/gateway.log",
    },
    
    // Session management
    sessions: {
      maxConcurrent: 50,
      idleTimeoutMinutes: 60,
      persistSessions: true,
    },
  },
  
  // ==================== CHANNELS ====================
  channels: {
    // Microsoft Teams
    teams: {
      enabled: true,
      botId: "$TEAMS_BOT_ID",        // Read from env
      botPassword: "$TEAMS_BOT_PASSWORD",
    },
    
    // WebChat (built-in web interface)
    webchat: {
      enabled: true,
      port: 3000,
    },
  },
  
  // ==================== TOOLS ====================
  tools: {
    // Browser tool
    browser: {
      enabled: true,
      headless: true,
      timeout: 30000,  // 30 seconds
    },
    
    // Bash/Shell tool
    bash: {
      enabled: true,
      timeout: 60000,  // 60 seconds
      
      // Commands that are blocked
      blocked: [
        "rm -rf /",
        "sudo rm",
        "format",
        "dd if=/dev/zero",
      ],
    },
    
    // File tools
    files: {
      enabled: true,
      
      // Restrict to workspace
      restrictedDirectories: [
        "/root",
        "/etc",
        "/sys",
      ],
    },
    
    // Edit tool
    edit: {
      enabled: true,
      maxFileSize: 10485760,  // 10MB
    },
  },
  
  // ==================== SECURITY ====================
  security: {
    // Sandbox for non-main sessions
    sandbox: {
      mode: "docker",  // docker | ssh | none
      enabled: true,
      
      // Allowed tools in sandbox
      allowedTools: [
        "bash",
        "read",
        "write",
        "edit",
      ],
      
      // Blocked tools in sandbox
      blockedTools: [
        "browser",
        "discord",
        "telegram",
        "system",
      ],
    },
    
    // Rate limiting
    rateLimit: {
      enabled: true,
      requestsPerMinute: 60,
      burst: 10,
    },
    
    // API key management
    apiKeys: {
      rotate: true,
      rotationIntervalDays: 90,
    },
  },
  
  // ==================== STORAGE ====================
  storage: {
    type: "local",  // local | s3 | database
    
    // Local storage
    path: "~/.openclaw/data",
    
    // Session persistence
    sessions: {
      persist: true,
      retentionDays: 365,
    },
    
    // Memory
    memory: {
      persist: true,
      retentionDays: 90,
    },
  },
  
  // ==================== WORKSPACE ====================
  workspace: {
    root: "~/.openclaw/workspace",
    
    // Prompt injection
    promptFiles: [
      "AGENTS.md",
      "SOUL.md",
      "TOOLS.md",
    ],
    
    // Skills directory
    skills: {
      dir: "~/.openclaw/workspace/skills",
      autoLoad: true,
    },
  },
  
  // ==================== COST CONTROL ====================
  costs: {
    dailyLimit: 10.0,  // USD per day
    monthlyLimit: 200.0,  // USD per month
    alertThreshold: 0.8,  // Alert at 80% of limit
  },
}
```

**Use When**:
- Production deployment
- Multiple agents and channels
- Advanced security needed
- Complex workflows

---

## 3. Local Development (No Costs)

**For**: Development and testing with Ollama (free local model)

```json5
{
  agents: {
    defaults: {
      model: "ollama/llama2",  // Free, local
      temperature: 0.7,
      maxTokens: 4096,
    }
  },
  
  gateway: {
    poDevelopment Configuration

**For**: Development and testing with Azure OpenAI using GPT-3.5-turbo (faster, cheaper)

```json5
{
  agents: {
    defaults: {
      model: "azure/gpt-3.5-turbo",  // Faster and more cost-effective
      temperature: 0.7,
      maxTokens: 2048,  // Smaller responses for faster iterations
    }
  },
  
  gateway: {
    port: 18789,
    verbose: true,
  },
  
  channels: {
    teams: {
      enabled: false,  // Can enable later
    }
  },
  
  tools: {
    browser: {
      enabled: true,
      headless: true,
    },
    bash: {
      enabled: true,
    },
    files: {
      enabled: true,
    },
  }
}
```

**Setup**:
1. Set Azure credentials in environment
2. Use config above
3. Run: `openclaw gateway --port 18789`6,
    }
  },
  
  gateway: {
    port: 18789,
    veTeams Integration Configuration

**For**: Microsoft Teams integration with GPT-3.5-turbo (cost-effective)

```json5
{
  agents: {
    defaults: {
      // More cost-effective model
      model: "azure/gpt-3.5-turbo",
      temperature: 0.5,
      maxTokens: 2048,
    }
  },
  
  gateway: {
    port: 18789,
    verbose: true,
    logging: {
      level: "info",
      file: "~/.openclaw/logs/gateway.log",
    }
  },
  
  channels: {
    teams: {
      enabled: true,
      botId: "$TEAMS_BOT_ID",
      botPassword: "$TEAMS_BOT_PASSWORD",
    }
  },
  
  tools: {
    browser: {
      enabled: true,
    },
    bash: {
      enabled: false,  // Less secure over network
    },
    files: {
      enabled: true,
    },
  },
  
  security: {
    sandbox: {
      mode: "none",
    }
  },
}
```azure/gpt-4",
      temperature: 0.7,
      maxTokens: 8192,
    },
    
    list: [
      {
        name: "main",
        description: "Main assistant",
        model: "azure/gpt-4",
        temperature: 0.7,
        instructions: "You are the main assistant",
      },
      {
        name: "coder",
        description: "Code specialist",
        model: "azure/gpt-4",
        temperature: 0.3,  // More deterministic
        instructions: "You are a code review expert",
        tools: ["read", "write", "bash"],
      },
      {
        name: "researcher",
        description: "Research specialist",
        model: "azure/gpt-3.5-turbo",  // Faster for research
        instructions: "You are a research expert",
        tools: ["browser", "read", "write"],
      }
    ]
  },
  
  gateway: {
    port: 18789,
    verbose: true,
  },
  
  // Route channels to agents
  routing: {
    teams
      // Channel-specific routing
      channels: {
        "code-help": "coder",
        "research": "researcher",
      }
    }
  }
}
```

**Usage**:
```bash
openclaw agent --agent coder --message "Review this code"
openclaw agent --agent researcher --message "Find info about quantum computing"
```

---

## 6. Enterprise Configuration

**For**: Production with security, monitoring, and governance

```json5
{governance, and Teams integration
  agents: {
    defaults: {
      model: "azure/gpt-4",
      temperature: 0.5,
      maxTokens: 4096,
      
      contextLimits: {
        systemPromptMaxChars: 50000,
        toolResultMaxChars: 5000,  // More restrictive
        postCompactionMaxChars: 100000,
      },
      
      // Thinking mode for complex reasoning
      thinkingDefault: "high",
    }
  },
  
  gateway: {
    port: 18789,
    host: "0.0.0.0",  // Allow remote connections
    
    logging: {
      level: "debug",
      format: "json",
      file: "/var/log/openclaw/gateway.log",
    },
    
    sessions: {
      maxConcurrent: 100,
      idleTimeoutMinutes: 30,
      persistSessions: true,
    },
  },
  
  channels: {
    discord: {
      enabled: true,
      token: "$DISCORD_TOKEN",
    teams: {
      enabled: true,
      botId: "$TEAMS_BOT_ID",
      botPassword: "$TEAMS_BOT_PASSWORD"
  security: {
    sandbox: {
      mode: "docker",  // Strict sandbox
      enabled: true,
      
      allowedTools: [
        "bash",
        "read",
        "write",
        "edit",
      ],
      
      blockedTools: [
        "system",
        "admin",
        "credentials",
      ],
    },
    
    rateLimit: {
      enabled: true,
      requestsPerMinute: 30,  // More restrictive
      burst: 5,
    },
    
    audit: {
      enabled: true,
      logPath: "/var/log/openclaw/audit.log",
    },
  },
  
  storage: {
    type: "s3",
    bucket: "openclaw-data",
    region: "us-east-1",
    encryption: "enabled",
  },
  
  costs: {
    dailyLimit: 100.0,  // Higher limit
    monthlyLimit: 2000.0,
    alertThreshold: 0.8,
  },
}
```

---

## Environment Variable Reference

Common environment variables:

```bash
# OpenAI
OPENAI_API_KEY=sk-proj-...

# Anthropic
ANAzure OpenAI
AZURE_OPENAI_API_KEY=your-key-here
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com/
AZURE_OPENAI_DEPLOYMENT=gpt-4

# Microsoft Teams
TEAMS_BOT_ID=your-bot-id
TEAMS_BOT_PASSWORD=your-bot-password

---

## Switching Configurations

To use different configs:

```bash
# Copy an example config
cp examples/full-featured.json ~/.openclaw/openclaw.json

# Or set via environment
export OPENCLAW_CONFIG=/path/to/custom-config.json

# Then start
openclaw gateway --port 18789
```

---

## Validating Configuration

```bash
# Validate config syntax
openclaw config validate

# Test connection to LLM
openclaw config test-llm

# Check all systems
openclaw doctor
```

---

## Next Steps

1. Choose a configuration that matches your needs
2. Copy to `~/.openclaw/openclaw.json`
3. Update API keys and tokens
4. Validate with `openclaw doctor`
5. Start the gateway: `openclaw gateway --port 18789`

