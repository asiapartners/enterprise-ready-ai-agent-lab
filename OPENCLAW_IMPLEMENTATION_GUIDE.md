# OpenClaw Implementation Guide - Code Patterns & Examples

## Table of Contents

1. [Agent Tool Development](#agent-tool-development)
2. [Multi-Agent Orchestration Patterns](#multi-agent-orchestration-patterns)
3. [Skill Creation](#skill-creation)
4. [Plugin Development](#plugin-development)
5. [Custom Tool Implementation](#custom-tool-implementation)
6. [Advanced Patterns](#advanced-patterns)

---

## Agent Tool Development

### 1. Using Built-in Tools

#### Memory Tools

```typescript
// In agent TOOLS.md or agent prompt
// The agent can use these tools:

// 1. Search memory
{
  "name": "memory_search",
  "input": {
    "query": "project requirements",
    "limit": 5
  }
  // Returns: Top 5 matching passages from MEMORY.md and memory/*.md
}

// 2. Get specific memory file
{
  "name": "memory_get",
  "input": {
    "path": "memory/2024-01-15.md"
  }
  // Returns: Full file contents
}

// 3. Update memory
{
  "name": "memory_update",
  "input": {
    "path": "memory/2024-01-15.md",
    "content": "## New Entry\nAdded information about project decisions"
  }
  // Returns: Success/failure + audit trail
}
```

#### Message Tools

```typescript
// Send message to current channel
{
  "name": "message",
  "input": {
    "text": "Here's the analysis you requested",
    "mentions": ["@user1", "@user2"]  // Optional
  }
}

// React with emoji
{
  "name": "reactions",
  "input": {
    "emoji": "👍",
    "action": "add"  // or "remove"
  }
}

// Delete previous message
{
  "name": "reactions",
  "input": {
    "messageId": "msg_123",
    "action": "delete"
  }
}
```

#### Session Tools

```typescript
// Spawn sub-agent for delegation
{
  "name": "sessions_spawn",
  "input": {
    "agentId": "developer",
    "prompt": "Please review this TypeScript code and suggest improvements",
    "sandbox": "inherit",  // or "require"
    "runTimeoutSeconds": 300
  }
  // Returns: sessionKey + result from sub-agent
}

// List current sessions
{
  "name": "sessions_list",
  "input": {
    "scope": "tree"  // "tree", "agent", "all"
  }
  // Returns: Array of session info
}

// Send cross-session message
{
  "name": "sessions_send",
  "input": {
    "sessionKey": "agent:discord:peer_123",
    "message": "Update from main agent"
  }
}
```

### 2. Custom Tool Definition

Create a tool in your agent's `workspace/TOOLS.md`:

```markdown
# Custom Tools

## git_commit
Commit changes to git repository

**Usage**:
```
{
  "name": "git_commit",
  "input": {
    "message": "Add new feature",
    "files": ["src/feature.ts"]
  }
}
```

**Behavior**:
- Stages specified files
- Creates commit with message
- Returns commit hash

**Constraints**:
- Requires git to be installed
- Limited to workspace directory
- Tool policy: `alsoAllow: ["git_commit"]`

## web_search
Search the web using configured search engine

**Usage**:
```
{
  "name": "web_search",
  "input": {
    "query": "latest AI breakthroughs",
    "limit": 5
  }
}
```

**Returns**:
- URL
- Title
- Description/snippet
- Relevance score
```

### 3. Tool Policy Profiles

Define reusable tool policies:

```yaml
toolPolicies:
  profiles:
    # Read-only profile
    - id: "viewer"
      description: "Can read but not modify"
      allow:
        - "memory_search"
        - "memory_get"
        - "browser"
        - "web_search"
      deny:
        - "memory_update"
        - "exec"
        - "git_commit"
    
    # Developer profile
    - id: "developer"
      description: "Full development access"
      allow: "*"  # Allow all tools
      deny:
        - "browser:unsafe_domains"  # Except unsafe domains
    
    # Admin profile
    - id: "admin"
      description: "Complete access"
      allow: "*"
    
    # Messaging profile
    - id: "messaging"
      description: "Message-only bot"
      allow:
        - "message"
        - "reactions"
        - "memory_search"
      deny: "*"  # Deny everything else

# Assign profiles to agents
agents:
  list:
    - id: "analyst"
      toolPolicies:
        profile: "viewer"
    
    - id: "developer"
      toolPolicies:
        profile: "developer"
        alsoAllow: ["web_search"]  # Add extra tools
    
    - id: "bot"
      toolPolicies:
        profile: "messaging"
```

---

## Multi-Agent Orchestration Patterns

### Pattern 1: Delegation Pyramid

```markdown
# AGENTS.md

## Orchestrator
- Purpose: Routes requests to appropriate specialist
- Model: GPT-4 (expensive, but coordinates well)
- Accessible to: Discord, Telegram

When to delegate:
- **Code questions** → developer agent
- **Data analysis** → analyst agent
- **Content creation** → writer agent
```

**System Prompt Guidance**:
```
When you receive a request:
1. Classify the request type:
   - Technical/coding → delegate to "developer"
   - Data/analysis → delegate to "analyst"
   - Writing/content → delegate to "writer"
   - Other → handle directly

2. Call sessions_spawn with appropriate agent

3. Wait for result

4. Summarize and send to user
```

### Pattern 2: Parallel Processing

```typescript
// Agent spawns multiple sub-agents in parallel

// In TOOLS.md, document the pattern:
```markdown
## parallel_analysis

The agent uses `sessions_spawn` multiple times without waiting:

1. Spawn analyst: "Analyze sales trends"
2. Spawn developer: "Check code quality"
3. Spawn writer: "Draft report"
4. Use sessions_list to check completion
5. Combine results

This runs all analyses in parallel, combining results at the end.
```

### Pattern 3: Hierarchical Teams

```yaml
agents:
  list:
    - id: "cto"
      name: "CTO Agent"
      description: "Technical leadership"
      model: "openai/gpt-4"
    
    - id: "engineering_lead"
      name: "Engineering Lead"
      description: "Manages development team"
      model: "openai/gpt-4"
    
    - id: "developer_1"
      name: "Developer 1"
      model: "openai/gpt-3.5-turbo"
    
    - id: "developer_2"
      name: "Developer 2"
      model: "openai/gpt-3.5-turbo"
    
    - id: "qa_lead"
      name: "QA Lead"
      model: "openai/gpt-4"

# Hierarchy
# CTO -> Engineering Lead -> [Developer 1, Developer 2, QA Lead]

agents:
  defaults:
    subagents:
      allowAgents:  # CTO can spawn anyone
        - "engineering_lead"
        - "developer_1"
        - "developer_2"
        - "qa_lead"

# In AGENTS.md:
```markdown
# Organizational Hierarchy

## CTO (Chief Technology Officer)
- Receives high-level technical requests
- Delegates to Engineering Lead or specific teams
- Makes architectural decisions

## Engineering Lead
- Receives project tasks
- Coordinates developers
- Reports to CTO

## Developer 1, Developer 2
- Receive coding tasks
- Report to Engineering Lead

## QA Lead
- Receives test requirements
- Reports to Engineering Lead
```
```

### Pattern 4: Collaborative Multi-Agent

```markdown
# AGENTS.md - Collaborative Pattern

## Scenario: Code Review Process

1. **Requester** (any agent) sends code to review
2. **Code Reviewer** analyzes structure and patterns
3. **Security Specialist** checks for vulnerabilities
4. **Performance Analyst** reviews efficiency
5. All compile findings into single response

## Using sessions_send for coordination

Coordinator spawns:
- reviewer: "Review code structure"
- security: "Check security issues"
- performance: "Analyze performance"

Then uses sessions_send to update shared context as each completes.
```

---

## Skill Creation

### Skill Project Structure

```
my-skill/
├── commands/
│   └── data-analysis/
│       ├── README.md
│       └── index.md
├── skills/
│   └── tools/
│       └── data-tools.yaml
├── manifest.json
└── package.json
```

### 1. Create Markdown-based Skill

**commands/data-analysis/index.md**:
```markdown
# Data Analysis Skill

## `/analyze_csv`

Analyze CSV files with statistical summaries.

### Usage

```
/analyze_csv /path/to/file.csv
```

### Parameters
- `file_path` - Path to CSV file
- `analysis_type` - "summary" | "detailed" (default: summary)

### Example

User asks: "Analyze our Q4 sales data"
Bot uses: `file_path: "~/data/q4_sales.csv"`

Bot responds with:
- Row count
- Column statistics
- Correlations
- Trends

### Implementation

This uses Python pandas under the hood:
```python
import pandas as pd
df = pd.read_csv(file_path)
summary = df.describe()
```
```

**commands/data-analysis/README.md**:
```markdown
# Data Analysis Skill

Quick statistical analysis of CSV files.

## Features
- Summary statistics
- Correlation analysis
- Data visualization

## Installation

```bash
openclaw skills install data-analysis
```

## Configuration

```yaml
skills:
  allowlist:
    - "data-analysis"
```

## Support

Issues: https://github.com/myname/my-skill/issues
```

### 2. Create YAML Tool Definition

**skills/tools/data-tools.yaml**:
```yaml
tools:
  - id: "analyze_csv"
    name: "Analyze CSV"
    description: "Statistical analysis of CSV files"
    
    parameters:
      file_path:
        type: "string"
        description: "Path to CSV file"
        required: true
      
      analysis_type:
        type: "string"
        enum: ["summary", "detailed"]
        description: "Type of analysis"
        default: "summary"
    
    permissions:
      - "filesystem:read"
      - "python:execute"
    
    timeout_seconds: 30
    
    examples:
      - input:
          file_path: "data.csv"
        output: "Summary statistics with 5 columns..."
```

### 3. Create Manifest

**manifest.json**:
```json
{
  "id": "data-analysis-skill",
  "name": "Data Analysis",
  "version": "1.0.0",
  "author": "Your Name",
  "description": "CSV analysis and statistical tools",
  "keywords": ["data", "analysis", "csv", "statistics"],
  
  "commands": [
    {
      "id": "data-analysis",
      "path": "commands/data-analysis"
    }
  ],
  
  "tools": [
    {
      "id": "data-tools",
      "path": "skills/tools/data-tools.yaml"
    }
  ],
  
  "requirements": {
    "python": "3.8+",
    "packages": ["pandas", "numpy"]
  },
  
  "permissions": [
    "filesystem:read",
    "python:execute"
  ]
}
```

### 4. Publish to ClawHub

```bash
# Install ClawHub CLI
npm install -g @clawhub/cli

# Package skill
clawhub package create

# Publish
clawhub package publish --name "data-analysis-skill" \
  --description "CSV analysis tool" \
  --path ./

# Users can then install:
# openclaw skills install data-analysis-skill
```

---

## Plugin Development

### Plugin Project Structure

```
my-plugin/
├── src/
│   ├── index.ts          # Main entry point
│   ├── channels/
│   │   └── custom-chat.ts
│   ├── tools/
│   │   └── custom-tool.ts
│   └── hooks/
│       └── lifecycle.ts
├── manifest.json         # Plugin manifest
├── package.json
└── tsconfig.json
```

### 1. Minimal Plugin Template

**src/index.ts**:
```typescript
import { OpenClawPlugin, api } from "openclaw/plugin-sdk";

export default {
  id: "my-plugin",
  name: "My Plugin",
  version: "1.0.0",
  
  // Optional: Register tools
  registerTools: async (api) => {
    api.registerTool({
      id: "my-tool",
      name: "My Custom Tool",
      description: "Does something useful",
      
      parameters: {
        input: {
          type: "string",
          description: "Input text"
        }
      },
      
      handler: async (params) => {
        return {
          result: `Processed: ${params.input}`
        };
      }
    });
  },
  
  // Optional: Register channel adapter
  registerChannels: async (api) => {
    api.registerChannel({
      id: "custom-chat",
      name: "Custom Chat Platform",
      
      connect: async (config) => {
        // Connect to custom platform
      },
      
      send: async (message) => {
        // Send message to platform
      },
      
      // Additional methods...
    });
  },
  
  // Optional: Lifecycle hooks
  hooks: {
    gateway_start: async (api) => {
      console.log("Plugin started");
    },
    
    gateway_stop: async (api) => {
      console.log("Plugin stopped");
    },
    
    config_changed: async (api, config) => {
      console.log("Config updated");
    }
  }
} as OpenClawPlugin;
```

### 2. Plugin Manifest

**manifest.json**:
```json
{
  "id": "my-plugin",
  "name": "My Custom Plugin",
  "version": "1.0.0",
  "author": "Your Name",
  "description": "Custom channel and tools",
  
  "channels": ["custom-chat"],
  "tools": ["my-tool"],
  
  "setup": {
    "channels": [
      {
        "id": "custom-chat",
        "requiresConfig": true,
        "configSchema": {
          "type": "object",
          "properties": {
            "apiKey": {
              "type": "string",
              "description": "API Key"
            }
          },
          "required": ["apiKey"]
        }
      }
    ],
    "requiresRuntime": true
  },
  
  "permissions": [
    "network:outbound",
    "config:read"
  ]
}
```

### 3. Build and Package

```bash
# Build TypeScript
pnpm build

# Test locally
OPENCLAW_DEV_PLUGIN_PATH=./dist pnpm gateway:watch

# Package for distribution
npm pack

# Install as npm package
npm install /path/to/my-plugin-1.0.0.tgz

# Or publish to npm
npm publish
```

---

## Custom Tool Implementation

### Built-in Tool: Execution

```typescript
// Create executable tool in your agent config

// In ~/.openclaw/agents/default/workspace/TOOLS.md:

## python_exec
Execute Python code

**Usage**:
```
{
  "name": "python_exec",
  "input": {
    "code": "import pandas as pd\ndf = pd.read_csv('data.csv')\nprint(df.head())"
  }
}
```

**Constraints**:
- Sandbox mode: restricted imports
- Timeout: 30 seconds
- Max output: 10KB
- Allowed packages: pandas, numpy, matplotlib

## bash_exec
Execute bash commands

**Usage**:
```
{
  "name": "bash_exec",
  "input": {
    "command": "git log --oneline -5"
  }
}
```

**Constraints**:
- Only in workspace directory
- Limited commands (no rm, sudo, etc.)
- Timeout: 10 seconds
```

### Web Scraping Tool

```typescript
// In TOOLS.md

## web_scrape
Extract content from web pages

**Usage**:
```
{
  "name": "web_scrape",
  "input": {
    "url": "https://example.com",
    "selector": ".content",
    "includeText": true,
    "includeLinks": true
  }
}
```

**Returns**:
- Extracted HTML/text
- Links with href/text
- Metadata (title, description)

**Constraints**:
- Allowed domains: github.com, docs.*, api.*
- Timeout: 10 seconds
- Max size: 1MB
```

### GitHub Integration Tool

```typescript
// Create GitHub skill

// skills/github-tools.yaml
tools:
  - id: "github_search"
    name: "Search GitHub"
    description: "Search repositories or issues"
    
    parameters:
      query:
        type: "string"
        description: "Search query"
      type:
        type: "string"
        enum: ["repositories", "issues", "pulls"]
        default: "repositories"
      language:
        type: "string"
        description: "Programming language filter"
    
    handler:
      type: "http"
      method: "GET"
      url: "https://api.github.com/search/{{type}}"
      params:
        q: "{{query}} language:{{language}}"
      auth: "github"
      timeout: 10
    
    examples:
      - input:
          query: "javascript framework"
          type: "repositories"
        output: "Returns top 30 JavaScript frameworks..."
```

---

## Advanced Patterns

### Pattern: Autonomous Daily Digest

```yaml
# Schedule daily digest generation

automation:
  cron:
    tasks:
      - id: "daily-digest"
        schedule: "0 9 * * *"  # 9 AM daily
        agentId: "analyst"
        prompt: |
          Generate daily digest from:
          1. Memory entries from today (memory/{{date}}.md)
          2. Session logs from today
          3. Key metrics/trends
          
          Format as:
          ## Daily Digest - {{date}}
          ### Highlights
          - Top 3 important items
          ### Metrics
          - KPIs
          ### Tomorrow
          - Action items

# Agent uses memory tools to gather context and update MEMORY.md with summary
```

### Pattern: Approval Workflow

```yaml
approvals:
  enabled: true
  
  # Require approval for specific tools/actions
  requireFor:
    - exec                      # Code execution
    - file_write               # File modifications
    - git_push                 # Git operations
    - delete_data              # Destructive actions
  
  # Tool-specific approval rules
  tools:
    exec:
      mode: "each_call"        # Approve each execution
      
      # Auto-approve safe commands
      autoApprovePatterns:
        - "python -c print"
        - "npm test"
      
      # Require approval for dangerous commands
      requireApprovalPatterns:
        - "rm -rf"
        - "sudo"
        - "chmod"
    
    file_write:
      mode: "each_call"
      
      # Require approval for sensitive files
      requireApprovalPaths:
        - "/etc"
        - "~/.ssh"
        - "/root"
```

### Pattern: Context Caching for Performance

```typescript
// In agent configuration

agents:
  defaults:
    # Prompt caching settings
    promptCache:
      enabled: true
      retention: "long"  # Keep cache for 24h
      strategy: "prefix"  # Cache prefix of conversation
    
    # Reuse context across turns
    contextReuse:
      enabled: true
      memorizeFiles: [
        "README.md",
        "docs/API.md"
      ]
```

### Pattern: Multi-Model Fallback

```yaml
agents:
  defaults:
    model: "openai/gpt-4"
    
    # Fallback chain
    modelFailover:
      chains:
        - models:
            - "openai/gpt-4"
            - "openai/gpt-4-turbo"
            - "openai/gpt-3.5-turbo"
          conditions:
            - "rate_limit"
            - "timeout"
          maxRetries: 3
        
        - models:
            - "anthropic/claude-opus"
            - "anthropic/claude-sonnet"
          conditions:
            - "service_unavailable"
          maxRetries: 2
        
        - models:
            - "google/gemini-2-flash"
          conditions:
            - "all_providers_failed"
          maxRetries: 1
```

### Pattern: Long-Running Task Tracking

```typescript
// Use cron jobs for long tasks

automation:
  cron:
    tasks:
      - id: "weekly-analysis"
        schedule: "0 2 * * 0"  # Sunday 2 AM
        agentId: "analyst"
        prompt: "Run comprehensive weekly analysis"
        
        # Track execution
        hooks:
          on_start: "Log task started"
          on_complete: "Update MEMORY.md with results"
          on_failure: "Send alert to admin"
        
        # Long timeout for complex analysis
        timeoutSeconds: 3600  # 1 hour

# In AGENTS.md, document the async pattern:
```markdown
## Long-Running Tasks

When handling time-consuming requests:
1. Acknowledge receipt immediately
2. Suggest scheduling as cron job
3. Provide estimated completion time
4. Update memory when done
5. Notify via message tool
```
```

---

## Testing & Validation

### Test Tool Execution

```bash
# Test specific tool
openclaw tools test my-tool --input '{"key": "value"}'

# Test agent turn
openclaw agents test default --prompt "Hello, world"

# Test with specific model
openclaw agents test default --model "openai/gpt-3.5-turbo" \
  --prompt "Quick test"
```

### Validate Configuration

```bash
# Validate config schema
openclaw config validate

# Show config schema
openclaw config schema show

# Check specific field
openclaw config schema lookup agents.defaults.model
```

### Monitor Performance

```bash
# Session metrics
openclaw sessions metrics

# Tool usage statistics
openclaw tools stats

# Memory usage
openclaw memory stats
```

---

## Performance Optimization

### Reduce Context Window

```yaml
agents:
  defaults:
    # Smaller context = faster, cheaper responses
    bootstrapTotalMaxChars: 30000  # Default: 60000
    
    # Disable features not needed
    memorySearch: false              # If not using memory
    thinking: "off"                  # If not needed
    
    # Use faster model
    model: "openai/gpt-3.5-turbo"   # vs gpt-4
```

### Cache Frequently Used Data

```markdown
# In MEMORY.md - Cache static data

## Common Queries (Updated weekly)

### FAQ Answers
- Q1: ...
- Q2: ...

### API Endpoints
- Endpoint 1: ...
- Endpoint 2: ...

### Frequently Needed Context
- Company policies
- Team structure
- Current projects
```

### Batch Processing

```typescript
// In AGENTS.md

## Batch Processing Pattern

When handling multiple requests:
1. Collect in queue (up to 10 items)
2. Wait for quiet period (5 minutes no new requests)
3. Process batch as single agent turn
4. Return results together

Reduces model calls and context switching overhead.
```

---

## Production Readiness Checklist

- [ ] All tools have permission constraints
- [ ] Memory growth monitored (MEMORY.md size)
- [ ] Sub-agent timeout limits set
- [ ] Approval workflows for sensitive operations
- [ ] Sandbox constraints enabled
- [ ] Audit logging enabled
- [ ] Error handling for all tool calls
- [ ] Fallback models configured
- [ ] Rate limiting configured
- [ ] Session cleanup policies set
- [ ] Backup strategy for session history
- [ ] Monitoring alerts configured

