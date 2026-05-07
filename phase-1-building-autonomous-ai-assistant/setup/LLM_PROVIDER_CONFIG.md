# LLM Provider Configuration Guide

## Overview

Your agent needs an LLM (Large Language Model) to think and make decisions. This guide covers configuring Azure OpenAI, Microsoft's enterprise-grade platform for AI models.

---

## Azure OpenAI Overview

| Feature | Details |
|---------|----------|
| **Provider** | Microsoft Azure | 
| **Models** | GPT-4, GPT-3.5-turbo, and more |
| **Best For** | Enterprise deployments, security, compliance |
| **Pricing** | Usage-based, custom enterprise pricing |
| **Support** | Microsoft Enterprise Support |

---

## Setup Azure OpenAI

#### Get Azure OpenAI Credentials

1. Go to [Azure Portal](https://portal.azure.com)
2. Create an Azure OpenAI resource
3. Deploy a model (GPT-4, GPT-3.5-turbo, etc.)
4. Get endpoint and keys from the Keys section
5. **Keep credentials secure!** Treat like passwords

#### Configuration

**Option A: Environment Variables**

```bash
export AZURE_OPENAI_API_KEY="your-key-here"
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="gpt-4"  # Your deployment name

# Permanent (add to ~/.bashrc or ~/.zshrc)
echo 'export AZURE_OPENAI_API_KEY="your-key-here"' >> ~/.bashrc
echo 'export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"' >> ~/.bashrc
echo 'export AZURE_OPENAI_DEPLOYMENT="gpt-4"' >> ~/.bashrc
source ~/.bashrc
```

**Option B: In `openclaw.json`**

```json5
{
  agents: {
    defaults: {
      // Using Azure OpenAI
      model: "azure/gpt-4",
      
      // Alternative: GPT-3.5-turbo (faster, cheaper)
      // model: "azure/gpt-3.5-turbo",
      
      temperature: 0.7,
      maxTokens: 8192,
    }
  }
}
```

#### Supported Models

- `gpt-4` - Most capable (recommended for enterprise)
- `gpt-4-turbo` - Good balance of speed/quality
- `gpt-3.5-turbo` - Fast and cost-effective

#### Test

```bash
export AZURE_OPENAI_API_KEY="your_key"
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="gpt-4"
openclaw agent --message "What's your name?"
```


---

## Model Failover (Reliability)

Configure multiple Azure OpenAI deployments for automatic failover:

```json5
{
  agents: {
    defaults: {
      model: "azure/gpt-4",  // Primary
      temperature: 0.7,
      maxTokens: 8192,
    }
  },
  
  // Azure deployments to try if primary fails
  modelFailover: [
    "azure/gpt-4",
    "azure/gpt-3.5-turbo",
  ]
}
```

When the primary deployment fails (rate limit, outage, etc.), OpenClaw automatically tries the fallback deployment.

---

## Cost Management

### Azure OpenAI Pricing (Estimated)

| Model | Cost per 1M input tokens |
|-------|---------------------------|
| GPT-4 | ~$15.00 |
| GPT-3.5-turbo | ~$1.50 |

### Strategies to Reduce Costs

1. **Use GPT-3.5-turbo**: Significantly cheaper than GPT-4
2. **Prompt Caching**: OpenClaw supports prompt caching to reduce token usage
3. **Monitor Usage**:
   ```bash
   openclaw usage full
   ```
4. **Request Custom Pricing**: Contact Microsoft for enterprise licensing

### Set Budget Limits

```json5
{
  agents: {
    defaults: {
      model: "azure/gpt-4",
      // Stop generating if costs exceed $50/day
      costLimit: 50.0,  // USD per day
    }
  }
}
```

---

## Testing Your Configuration

### Test 1: Basic Response

```bash
openclaw agent --message "Hello! Who are you?"
```

**Expected**: Agent introduces itself

### Test 2: Tool Usage

```bash
openclaw agent --message "Create a file called 'test.txt' with 'Hello World'"
```

**Expected**: File created, agent confirms

### Test 3: Check Token Usage

```bash
openclaw agent --message "What is AI?" --usage full
```

**Expected**: Shows tokens used and estimated Azure cost

---

## Troubleshooting

### Issue: "Invalid API key"

```bash
# Verify keys are set
echo $AZURE_OPENAI_API_KEY
echo $AZURE_OPENAI_ENDPOINT
echo $AZURE_OPENAI_DEPLOYMENT

# Re-set if needed
export AZURE_OPENAI_API_KEY="your-key-here"
export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="gpt-4"
```

### Issue: "Rate limit exceeded"

The API is throttling requests. Solutions:

1. **Wait a bit**: Rate limits reset quickly (usually per minute)
2. **Use cheaper model**: Switch to Haiku or DeepSeek
3. **Add failover**: Configure model failover above
4. **Local model**: Switch to Ollama

### Issue: "Model not found"

```bash
# Ensure model name is correct
# Common mistake: typos or deployment name mismatch

# Correct format:
azure/gpt-4            # Correct
azure/gpt-3.5-turbo    # Correct

# Verify deployment exists in Azure:
# Azure Portal → OpenAI resource → Deployments
```

### Issue: High costs

```bash
# Check what you're being charged
openclaw usage full

# Switch to cheaper model
# Edit openclaw.json and change to:
# - claudeHaiku
# - deepseek/deepseek-chat
# - ollama/llama2 (local, free)
```

---

## Production Considerations

### Security

- **Never commit API keys** to git
- **Use environment variables** for production
- **Rotate keys** regularly
- **Monitor usage** for unusual activity

### Performance

- **Use model failover** for reliability
- **Enable prompt caching** for repeated prompts
- **Consider local models** (Ollama) for sensitive data
- **Monitor response times**

### Cost

- **Set budget limits** to prevent runaway costs
- **Use cheaper models** for development
- **Monitor daily usage** with `openclaw usage`
- **Consider reserved capacity** for high-volume use

---

## Next Steps

1. **Create Azure OpenAI resource** in Azure portal
2. **Get API key and endpoint** from the resource
3. **Deploy a model** (GPT-4 recommended)
4. **Set environment variables** or update `openclaw.json`
5. **Test with** `openclaw agent --message "Test"`
6. **Proceed to** [AGENT_PERSONALITY.md](./AGENT_PERSONALITY.md)

---

## Resource Links

- [Azure OpenAI Service](https://azure.microsoft.com/en-us/products/cognitive-services/openai-service/)
- [Azure OpenAI Pricing](https://azure.microsoft.com/en-us/pricing/details/cognitive-services/openai-service/)
- [Azure Portal](https://portal.azure.com)
- [OpenClaw Documentation](https://docs.openclaw.ai)

