# Phase 1 Troubleshooting Guide

Common issues and solutions for Phase 1 setup.

---

## Installation Issues

### Issue: npm command not found

**Symptom**: 
```
-bash: npm: command not found
```

**Solution**:
1. Install Node.js from https://nodejs.org/ (v22 or v24)
2. Verify installation:
   ```bash
   node --version
   npm --version
   ```
3. If still not found, add to PATH:
   ```bash
   export PATH="/usr/local/bin:$PATH"
   ```

---

### Issue: openclaw command not found after global install

**Symptom**:
```
-bash: openclaw: command not found
```

**Solution**:
1. Find npm's global path:
   ```bash
   npm config get prefix
   # Usually: /usr/local or ~/.nvm/versions/node/vXX
   ```

2. Add to PATH (~/.bashrc or ~/.zshrc):
   ```bash
   export PATH="$(npm config get prefix)/bin:$PATH"
   source ~/.bashrc  # or ~/.zshrc
   ```

3. Try again:
   ```bash
   openclaw --version
   ```

---

### Issue: Permission denied when installing globally

**Symptom**:
```
npm ERR! Error: EACCES: permission denied
```

**Solution A** (Recommended): Use Node Version Manager

```bash
# Install nvm (macOS/Linux)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Install Node.js
nvm install 24
nvm use 24

# Now npm install works without sudo
npm install -g openclaw@latest
```

**Solution B**: Use pnpm instead

```bash
npm install -g pnpm
pnpm install -g openclaw@latest
```

---

## Configuration Issues

### Issue: API key not found / "Invalid API key"

**Symptom**:
```
Error: OPENAI_API_KEY not found
```

**Solution**:
1. Verify key is set:
   ```bash
   echo $OPENAI_API_KEY
   # If empty, API key is not set
   ```

2. Set the key:
   ```bash
   export OPENAI_API_KEY="sk-proj-xxxxx"
   ```

3. Make permanent (~/.bashrc or ~/.zshrc):
   ```bash
   echo 'export OPENAI_API_KEY="sk-proj-xxxxx"' >> ~/.bashrc
   source ~/.bashrc
   ```

4. Verify:
   ```bash
   echo $OPENAI_API_KEY
   # Should show your key (or part of it)
   ```

5. Test:
   ```bash
   openclaw agent --message "Hello"
   ```

---

### Issue: "Configuration file not found"

**Symptom**:
```
Error: Cannot find ~/.openclaw/openclaw.json
```

**Solution**:
1. Run setup:
   ```bash
   openclaw setup
   ```

2. Or create manually:
   ```bash
   mkdir -p ~/.openclaw/workspace
   touch ~/.openclaw/openclaw.json
   ```

3. Add minimal config:
   ```json5
   {
     agents: {
       defaults: {
         model: "openai/gpt-4o",
         temperature: 0.7,
       }
     }
   }
   ```

---

### Issue: "Model not found" or "Invalid model"

**Symptom**:
```
Error: Model 'openai/gpt4' not found
```

**Solution**:
1. Check model name format:
   ```
   ✓ openai/gpt-4o        (correct)
   ✗ openai/gpt-4         (might be deprecated)
   ✗ openai/gpt4          (wrong - missing dash)
   ✗ gpt-4                (wrong - missing provider)
   ```

2. List available models:
   ```bash
   openclaw models list
   ```

3. Use correct format:
   ```bash
   # For OpenAI
   model: "openai/gpt-4o"
   
   # For Anthropic
   model: "anthropic/claude-3-5-sonnet-20241022"
   ```

---

## Gateway Issues

### Issue: Port already in use

**Symptom**:
```
Error: Address already in use :::18789
```

**Solution**:
1. Use different port:
   ```bash
   openclaw gateway --port 18790 --verbose
   ```

2. Or kill process using port:
   ```bash
   # Find process
   lsof -i :18789
   
   # Kill it
   kill -9 <PID>
   ```

3. Or check what's using the port:
   ```bash
   netstat -tulpn | grep 18789
   ```

---

### Issue: Gateway won't start / "failed to start gateway"

**Symptom**:
```
Error: Failed to start gateway
```

**Solution**:
1. Check configuration:
   ```bash
   openclaw config validate
   ```

2. Run diagnostic:
   ```bash
   openclaw doctor
   ```

3. Check logs:
   ```bash
   openclaw logs tail
   ```

4. Try verbose mode:
   ```bash
   openclaw gateway --port 18789 --verbose
   ```

5. Ensure API key is set:
   ```bash
   echo $OPENAI_API_KEY
   ```

---

### Issue: Gateway is running but agent doesn't respond

**Symptom**: Gateway starts but `openclaw agent --message "Hi"` times out

**Solution**:
1. Verify gateway is listening:
   ```bash
   curl http://localhost:18789/health
   # Should return: {"status":"ok"}
   ```

2. Check if API is working:
   ```bash
   curl -X POST http://localhost:18789/agent \
     -H "Content-Type: application/json" \
     -d '{"message": "Hello"}'
   ```

3. Check logs for errors:
   ```bash
   openclaw logs tail -f
   ```

4. Verify LLM connection:
   ```bash
   openclaw config test-llm
   ```

---

## Agent & Tool Issues

### Issue: Agent responses are generic / doesn't seem to use AGENTS.md

**Symptom**: Agent doesn't behave like you defined

**Solution**:
1. Verify AGENTS.md exists:
   ```bash
   cat ~/.openclaw/workspace/AGENTS.md
   ```

2. Restart gateway to reload:
   ```bash
   openclaw gateway restart
   ```

3. Check for syntax errors:
   ```bash
   # AGENTS.md should follow Markdown format
   # Should start with: # agent:main
   # Should have proper sections
   ```

4. Test directly:
   ```bash
   openclaw agent --message "Describe yourself"
   ```

---

### Issue: Agent can't read/write files

**Symptom**: Agent says "I cannot access files" or files don't get created

**Solution**:
1. Check file tools are enabled in openclaw.json:
   ```json5
   tools: {
     files: {
       enabled: true,
     },
     write: {
       enabled: true,
     }
   }
   ```

2. Verify permissions:
   ```bash
   ls -la ~/.openclaw/workspace/
   # Should be readable and writable
   chmod 755 ~/.openclaw/workspace
   ```

3. Test file tool:
   ```bash
   openclaw agent --message "Create a test file called test.txt"
   
   # Check if created
   ls -la ~/.openclaw/workspace/test.txt
   ```

---

### Issue: Agent won't run bash commands

**Symptom**: Agent says "I cannot run bash" or command doesn't execute

**Solution**:
1. Enable bash in config:
   ```json5
   tools: {
     bash: {
       enabled: true,
       timeout: 60000,
     }
   }
   ```

2. Restart gateway:
   ```bash
   openclaw gateway restart
   ```

3. Check for blocked commands:
   ```json5
   tools: {
     bash: {
       blocked: [
         "rm -rf /",
         "sudo rm",
       ]
     }
   }
   ```

4. Test bash:
   ```bash
   openclaw agent --message "What is the current date?"
   ```

---

### Issue: Agent returns "Tool not available"

**Symptom**:
```
I cannot use that tool - it's not available in my configuration
```

**Solution**:
1. Check config for tool:
   ```bash
   grep -A5 "browser:" ~/.openclaw/openclaw.json
   ```

2. Enable tool:
   ```json5
   tools: {
     browser: {
       enabled: true,
     }
   }
   ```

3. Restart gateway
4. Test: `openclaw agent --message "Search for Python"`

---

## Microsoft Teams Integration Issues

### Issue: Bot doesn't respond in Teams

**Symptom**: Message bot in Teams or channel, no response

**Solution 1**: Check gateway is running
```bash
curl http://localhost:18789/health
```

**Solution 2**: Check bot credentials
```bash
grep -A 2 "teams:" ~/.openclaw/openclaw.json
# Should contain botId and botPassword
```

**Solution 3**: Verify Teams bot permissions
1. Go to Azure Portal → Bot Services
2. Select your bot resource
3. Channels → Teams → Configure
4. Verify messaging is enabled

**Solution 4**: Check Teams app installed correctly
```bash
# In Teams, verify the app is listed in "Apps"
# You may need to sideload or install from org app store
```

---

### Issue: Bot credentials are invalid

**Symptom**:
```
Error: Invalid bot ID or password
```

**Solution**:
1. Go to Azure Portal → Bot Services → Your Bot
2. Settings → Configuration
3. Copy fresh credentials (Microsoft App ID and Client secret)
4. Update config:
   ```bash
   nano ~/.openclaw/openclaw.json
   # Update botId and botPassword fields
   ```
5. Restart gateway:
   ```bash
   openclaw gateway restart
   ```

---

### Issue: Can't find bot in Teams

**Symptom**: Bot app not visible in Teams after installation

**Solution**:
1. Verify app is installed:
   - Teams → Apps → Manage your apps
   - Search for your app name
   
2. For sideloading:
   - Upload manifest.json via App Studio
   - Or use Azure Portal to get installation link

3. Install via direct link:
   ```
   https://teams.microsoft.com/l/app/{appId}
   ```
   (Get appId from Azure Bot Service)

---

## Memory & Context Issues

### Issue: Agent forgets previous conversations

**Symptom**: Agent doesn't remember what you told it in previous sessions

**Solution**:
1. Check memory is enabled:
   ```json5
   agents: {
     defaults: {
       memoryEnabled: true,
     }
   }
   ```

2. Create MEMORY.md file:
   ```bash
   nano ~/.openclaw/workspace/MEMORY.md
   ```

3. Add facts:
   ```markdown
   # User Preferences
   - Prefers detailed explanations
   - Works with Python and JavaScript
   - Timezone: US Eastern
   
   # Previous Learnings
   - User's project structure: ...
   - Important tools used: ...
   ```

4. Test:
   ```bash
   openclaw agent --message "What do you know about me?"
   ```

---

## Performance Issues

### Issue: Agent responses are slow

**Symptom**: `openclaw agent` command takes 10+ seconds

**Solution**:
1. Use faster model:
   ```json5
   model: "anthropic/claude-3-5-haiku-20241022"  // Faster, cheaper
   ```

2. Reduce token limits:
   ```json5
   maxTokens: 2048  // Smaller responses
   contextLimits: {
     toolResultMaxChars: 5000,
   }
   ```

3. Check network:
   ```bash
   # Test API connectivity
   curl https://api.openai.com/v1/models \
     -H "Authorization: Bearer $OPENAI_API_KEY"
   ```

---

### Issue: High API costs

**Symptom**: Spending more than expected

**Solution**:
1. Track usage:
   ```bash
   openclaw usage full
   ```

2. Use cheaper model:
   ```json5
   model: "anthropic/claude-3-5-haiku-20241022"  // ~90% cheaper than GPT-4
   ```

3. Use local model:
   ```bash
   # Install Ollama
   brew install ollama
   ollama pull llama2
   ollama serve
   
   # Configure:
   model: "ollama/llama2"  // Free!
   ```

4. Set budget limit:
   ```json5
   costs: {
     dailyLimit: 5.0,  // Stop at $5/day
   }
   ```

---

## Getting More Help

If you're stuck:

1. **Run diagnostic**: `openclaw doctor`
2. **Check logs**: `openclaw logs tail -f`
3. **Microsoft Teams Bot Docs**: https://learn.microsoft.com/en-us/azure/bot-service/bot-service-overview
4. **GitHub Issues**: https://github.com/openclaw/openclaw/issues
5. **Docs**: https://docs.openclaw.ai

---

## Success Checklist

✅ `openclaw --version` shows a version
✅ `openclaw doctor` shows all checks passing
✅ `openclaw agent --message "Hi"` returns a response
✅ Your agent responds with your defined personality
✅ Agent can read and write files
✅ Gateway starts without errors
✅ (Optional) Teams bot responds to messages

When all checked, you're ready for Module 3!

