# LLM Provider Configuration

This guide covers configuring OpenClaw with different LLM providers.

---

## Provider Comparison

| Provider | Best For | Cost | Setup Complexity |
|----------|----------|------|-----------------|
| **Azure OpenAI** | Enterprise / compliance | Pay-per-use | Medium |
| **OpenAI** | Quick start | Pay-per-use | Easy |
| **Anthropic** | Claude models (recommended for Phase 2) | Pay-per-use | Easy |
| **Ollama** | Local / free / private | Free | Medium |
| **OpenRouter** | Multiple models via one key | Pay-per-use | Easy |

---

## Azure OpenAI (Recommended)

Best for enterprise deployments with compliance requirements.

### 1. Get Credentials

1. Go to [Azure Portal](https://portal.azure.com)
2. Create or open your **Azure OpenAI** resource
3. Navigate to **Keys and Endpoint** in the left sidebar
4. Copy **Key 1** and **Endpoint**
5. Go to **Model deployments** and note your deployment name

### 2. Set Environment Variables

```bash
export AZURE_OPENAI_API_KEY="your-key-here"
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="gpt-4"  # Your deployment name

# Make permanent
echo 'export AZURE_OPENAI_API_KEY="your-key-here"' >> ~/.bashrc
echo 'export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"' >> ~/.bashrc
source ~/.bashrc
```

### 3. Configure openclaw.json

```json5
{
  agents: {
    defaults: {
      model: "azure/gpt-4",
      temperature: 0.7,
      maxTokens: 8192,
      costLimit: 50.0
    }
  },
  modelFailover: ["azure/gpt-4", "azure/gpt-3.5-turbo"]
}
```

### Available Models

- `azure/gpt-4` — Primary recommendation
- `azure/gpt-4-turbo` — Speed/quality balance
- `azure/gpt-4o` — Latest GPT-4 Omni
- `azure/gpt-3.5-turbo` — Cost-effective alternative

---

## OpenAI

Simplest setup for getting started quickly.

### 1. Get API Key

1. Go to [platform.openai.com](https://platform.openai.com)
2. Click your profile → **API keys**
3. Click **Create new secret key**
4. Copy and save securely

### 2. Set Environment Variables

```bash
export OPENAI_API_KEY="sk-proj-xxxxx"

# Make permanent
echo 'export OPENAI_API_KEY="sk-proj-xxxxx"' >> ~/.bashrc
source ~/.bashrc
```

### 3. Configure openclaw.json

```json5
{
  agents: {
    defaults: {
      model: "openai/gpt-4o",
      temperature: 0.7,
      maxTokens: 4096,
    }
  }
}
```

### Available Models

- `openai/gpt-4o` — Latest and most capable
- `openai/gpt-4-turbo` — Fast and smart
- `openai/gpt-3.5-turbo` — Budget option

---

## Anthropic (Claude) — Recommended for Phase 2

Claude models are the recommended choice for Phase 2 since openclaw-a365 defaults to Claude.

### 1. Get API Key

1. Go to [console.anthropic.com](https://console.anthropic.com)
2. Navigate to **API Keys**
3. Create a new key
4. Copy and save securely

### 2. Set Environment Variables

```bash
export ANTHROPIC_API_KEY="sk-ant-xxxxx"

# Make permanent
echo 'export ANTHROPIC_API_KEY="sk-ant-xxxxx"' >> ~/.bashrc
source ~/.bashrc
```

### 3. Configure openclaw.json

```json5
{
  agents: {
    defaults: {
      model: "anthropic/claude-sonnet-4-6",
      temperature: 0.7,
      maxTokens: 4096,
    }
  }
}
```

### Available Models

- `anthropic/claude-opus-4-7` — Most capable
- `anthropic/claude-sonnet-4-6` — Recommended (balance of speed/quality)
- `anthropic/claude-haiku-4-5-20251001` — Fast and cheap

---

## Ollama (Local / Free)

Run AI models entirely on your own hardware — no API costs, no data leaves your machine.

### 1. Install Ollama

```bash
# macOS
brew install ollama

# Linux
curl -fsSL https://ollama.ai/install.sh | sh

# Start the server
ollama serve
```

### 2. Pull a Model

```bash
# Recommended for local use
ollama pull llama3
ollama pull mistral

# Verify
ollama list
```

### 3. Configure openclaw.json

```json5
{
  agents: {
    defaults: {
      model: "ollama/llama3",
      temperature: 0.7,
    }
  }
}
```

> **Note**: Local models are slower and less capable than cloud models but are completely free and private.

---

## Model Failover Configuration

Configure fallback models for resilience:

```json5
{
  agents: {
    defaults: {
      model: "azure/gpt-4",           // Primary model
    }
  },
  modelFailover: [
    "openai/gpt-4o",                  // First fallback
    "anthropic/claude-sonnet-4-6",    // Second fallback
    "ollama/llama3",                  // Last resort (local)
  ]
}
```

---

## Cost Management

Set budget limits to prevent unexpected charges:

```json5
{
  agents: {
    defaults: {
      costLimit: 10.0,          // Per-session limit ($)
    }
  },
  costs: {
    dailyLimit: 10.0,           // Daily limit ($)
    monthlyLimit: 200.0,        // Monthly limit ($)
  }
}
```

---

## Testing Your Configuration

```bash
# Basic test
openclaw agent --message "Hello! Who are you?"

# Test tool usage
openclaw agent --message "What files are in my home directory?"

# Check which model is being used
openclaw agent --message "What model are you running on?"
```

---

## Troubleshooting

### "Invalid API key"
- Verify the key is set: `echo $OPENAI_API_KEY`
- Check for extra spaces or newlines in the key
- Ensure the key hasn't been revoked

### "Model not found"
- Check the model name format includes the provider prefix: `openai/gpt-4o`
- Run `openclaw models list` to see available models

### "Rate limit exceeded"
- Switch to a model with higher rate limits
- Add `requestDelay: 1000` to config (1 second between requests)
- Upgrade your API plan tier

### Azure-specific: "Resource not found"
- Verify the endpoint URL format: `https://your-resource.openai.azure.com/`
- Ensure the deployment name matches exactly what's in Azure Portal
- Check that the deployment is in "Succeeded" state in Azure
