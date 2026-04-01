# Creating Skills and Hooks

There are two ways to create skills and hooks for Azure SRE Agent:

1. **Ask Azure SRE Agent directly** — Chat with your agent and ask it to draft a skill or hook. The agent understands its own skill format and can generate content for you. However, it **cannot save skills or hooks** — you'll need to copy the output and paste it into the portal manually.

2. **Use GitHub Copilot** — We created all 10 skills and 8 hooks in this repo using [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli). You can do the same in your IDE, the CLI, or on GitHub.com.

Both approaches produce skill/hook content that you then add to your agent via the portal. The sections below cover both methods.

---

## Option 1: Ask SRE Agent to draft a skill or hook

The agent already knows its own skill format, available tools, and how hooks work — so you can skip the context-setting step that Copilot needs.

### Creating a skill via chat

Open a chat with your agent at [sre.azure.com](https://sre.azure.com) and try prompts like:

```
Create a skill that diagnoses high network latency between Azure VMs. 
It should check NSG rules, effective routes, proximity placement groups, 
and run traceroute via az vm run-command invoke. Include both Linux and 
Windows commands. Output a structured report with severity, findings, 
and recommendations.
```

The agent will generate a complete skill prompt. Copy it and:

1. Go to **Builder** → **Subagent builder** → **Create** → **Skill**
2. Paste the content into the prompt field
3. Attach the required tools (`RunAzCliReadCommands`, `RunAzCliWriteCommands`)
4. **Save**

### Creating a hook via chat

```
Create a PostToolUse hook that blocks any command that modifies NSG rules. 
It should allow reading NSGs but block az network nsg rule create/update/delete. 
Use a Python command hook with failMode: block.
```

Copy the output and add it via **Builder** → **Hooks** → **Create hook**.

### Limitations

- The agent **cannot save** the skill or hook for you — you always need to copy and paste into the portal
- The agent may not follow the exact same SKILL.md format as the examples in this repo — review and adjust as needed
- For hooks, verify the JSON response format matches what the system expects (`{"ok": true/false}` for prompt hooks, `{"decision": "allow/block"}` for command hooks)

---

## Option 2: Use GitHub Copilot

We created all 10 skills and 8 hooks in this repo using [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli). Here's how you can do the same — whether you're using Copilot in your IDE, the CLI, or on GitHub.com.

## Before You Start

Before asking Copilot to generate a skill or hook, make sure you (and Copilot) have the right context:

1. **Understand what Azure SRE Agent is.** Read the official docs at [sre.azure.com/docs](https://sre.azure.com/docs/) — especially the pages on [Skills](https://sre.azure.com/docs/concepts/skills) and [Hooks](https://sre.azure.com/docs/capabilities/agent-hooks). You need to understand how the agent executes skills and what tools are available.

2. **Know the available tools.** Azure SRE Agent skills can use these tools:
   - `RunAzCliReadCommands` — runs read-only `az` commands (e.g., `az vm show`, `az monitor metrics list`)
   - `RunAzCliWriteCommands` — runs `az` commands that modify resources (e.g., `az vm run-command invoke`, `az disk update`)
   - **Important:** `az vm run-command invoke` requires `RunAzCliWriteCommands` even when the command inside is read-only (e.g., running `top` on a VM)

3. **Clone this repo.** The existing skills are the best reference for format and structure. Copilot produces dramatically better results when it has examples to follow.

## Creating a New Skill

📖 See [Why and When to Use Skills](why-and-when-to-use-skills.md) for the full picture on when skills add value beyond the agent's built-in capabilities.

### Step 1: Give Copilot Context About Azure SRE Agent

This is the most important step. If you just say "I need a skill for X", Copilot won't know it's for Azure SRE Agent or what format to use. Start every session by giving Copilot the full context:

```
Read the Azure SRE Agent documentation at https://sre.azure.com/docs/ to understand 
how skills work — what tools are available (RunAzCliReadCommands, RunAzCliWriteCommands), 
how the agent executes skills, and what placeholders like {rg} and {vm-name} mean.

Then read the existing SKILL.md files in skills/vm/ in this repo to understand the 
format: YAML frontmatter (name, description, tools), numbered diagnostic steps with 
specific az CLI commands, and a structured report template at the end.
```

### Step 2: Describe What You Need

Now describe the specific skill. Be explicit about the Azure domain, the problem it solves, and what CLI commands are involved:

```
I need to create a new skill for Azure SRE Agent called "network-latency-diagnostics" 
that diagnoses high network latency between Azure VMs. 

It should:
- Check NSG rules and effective routes using az network commands
- Check proximity placement groups and availability zone placement
- Run traceroute/mtr on the VM via az vm run-command invoke
- Support both Linux and Windows VMs
- Follow the exact same SKILL.md format as the existing skills in this repo
- Include a structured report template with severity, findings, and recommendations
- List the required tools in the YAML frontmatter (needs both RunAzCliReadCommands 
  and RunAzCliWriteCommands since it uses az vm run-command)
```

### Step 3: Review and Iterate

Copilot will generate the SKILL.md with:
- YAML frontmatter (`name`, `description`, `tools`)
- A "When to use this skill" section
- Step-by-step investigation flow with specific `az` CLI commands
- Placeholders (`{rg}`, `{vm-name}`) instead of hardcoded values
- A structured report template

Review it carefully:
- Are the `az` commands correct and do they exist?
- Does the investigation flow make logical sense?
- Are edge cases handled (e.g., Linux vs. Windows VMs)?
- Are the right tools listed in the frontmatter?
- Is the report template clear and actionable?

Ask Copilot to refine anything that needs adjustment. The first draft is rarely perfect — iterate until the skill reads like the existing ones in this repo.

### Step 4: Create the Testing README

Ask Copilot to generate a README for testing the skill:

```
Create a README.md for the network-latency-diagnostics skill for Azure SRE Agent. 
Follow the same format as the other README.md files in skills/vm/. Include:
- A "What this skill does" summary
- A "Before you start" section with a placeholder table
- A Bicep template or az CLI commands to deploy test VMs in different availability zones
- A script to simulate high network latency (e.g., using tc/netem on Linux)
- Example prompts to give to the SRE Agent (e.g., "Investigate network latency on VM {vm-name} in resource group {rg}")
- Expected agent behavior and sample output
- Cleanup commands to tear down test resources
```

### Step 5: Add to Your Agent

Once the skill is ready:
1. Open [sre.azure.com](https://sre.azure.com) and select your agent
2. Go to **Builder** → **Subagent builder** → **Create** → **Skill**
3. Paste the contents of your SKILL.md into the prompt field
4. Attach the tools listed in the YAML frontmatter (`RunAzCliReadCommands`, `RunAzCliWriteCommands`)
5. Test with the example prompts from your README

## Creating a New Hook

Hooks enforce governance guardrails — they intercept agent behavior before or after tool execution.

📖 See [Why and When to Use Hooks](why-and-when-to-use-hooks.md) for the full picture on when hooks add value beyond the agent's built-in safety.

### Step 1: Give Copilot Context

Same principle as skills — start by giving Copilot the context it needs:

```
Read the Azure SRE Agent hooks documentation at https://sre.azure.com/docs/capabilities/agent-hooks 
to understand how hooks work — event types (PostToolUse, Stop), execution types 
(command, prompt), matchers, timeouts, and failMode.

Then read the hook YAML files in hooks/examples/ in this repo to understand the format.
```

### Step 2: Describe the Governance Requirement

```
I need to create a new PostToolUse hook for Azure SRE Agent that blocks any command 
that modifies NSG rules. The hook should:
- Trigger on Bash/ExecuteShellCommand/ExecutePythonCode tool calls
- Allow reading NSGs (az network nsg show, az network nsg rule list)
- Block any az network nsg rule create/update/delete
- Return a clear JSON message explaining why the action was blocked
- Use failMode: block (safety-critical)
- Follow the same YAML format as the existing hooks in this repo
```

### Step 3: Review and Iterate

Copilot will generate a hook YAML with:
- The appropriate event type (`PostToolUse` or `Stop`)
- A script or prompt that evaluates the hook context
- Matcher patterns for targeting specific tools
- Timeout and failMode settings

Review it carefully:
- Does the matcher target the right tools? (Use specific patterns like `Bash|ExecuteShellCommand` instead of `*` where possible)
- For command hooks: does the Python/bash script correctly parse the JSON context from stdin?
- For prompt hooks: is the evaluation criteria specific enough? Vague prompts lead to inconsistent results.
- Is `failMode` set correctly? Use `block` for safety-critical hooks, `allow` for advisory ones.
- Does the hook return the correct JSON format? (`{"decision": "allow/block"}` for command hooks, `{"ok": true/false}` for prompt hooks)

Ask Copilot to refine anything that doesn't look right. Test edge cases — what happens with unexpected input?

### Step 4: Test the Hook

Before deploying to your agent:

1. **Test command hooks locally** — pipe sample JSON context through the script:
   ```bash
   echo '{"tool_name": "Bash", "tool_input": {"command": "rm -rf /"}, "tool_succeeded": true}' | python3 your-hook-script.py
   ```

2. **Test in the portal playground** — Go to **Subagent builder → Test playground** to test subagent-level hooks, or use **Chat** to test agent-level hooks.

3. **Start with `failMode: allow`** — During testing, set `failMode: allow` so a buggy hook doesn't block all agent operations. Switch to `failMode: block` once validated.

### Step 5: Add to Your Agent

1. Open [sre.azure.com](https://sre.azure.com) and select your agent
2. Go to **Builder** → **Hooks** → **Create hook**
3. Set the **Event type** (`PostToolUse` or `Stop`) and **Hook type** (`Command` or `Prompt`)
4. If it's a PostToolUse hook, set the **Matcher** pattern (regex for tool names)
5. Paste your hook script or prompt
6. Set **Timeout**, **Fail mode**, and **Activation** (Always or On Demand)
7. Click **Save**

For subagent-level hooks, go to **Subagent builder → Manage Hooks** instead.

### Hook Types

| Type | When It Runs | Use Case |
|------|-------------|----------|
| **PostToolUse** | After a tool executes | Block dangerous commands, audit tool usage, enforce naming conventions |
| **Stop** | Before the agent returns a response | Require summary sections, enforce output format, ensure evidence is cited |

### Extending Hooks to Other Governance Patterns

The same hook patterns work for many governance scenarios. Here are some ideas:

| Pattern | Event type | Execution type | What it does |
|---------|-----------|----------------|-------------|
| **Tag enforcement** | PostToolUse | Command | Block resource creation that doesn't include required tags |
| **Region restriction** | PostToolUse | Command | Only allow operations in approved Azure regions |
| **Naming convention** | PostToolUse | Command | Reject resources that don't follow your naming standards |
| **Cost guardrails** | PostToolUse | Command | Block VM SKUs above a certain size without approval |
| **Sensitivity classification** | Stop | Prompt | Ensure responses don't include PII or internal resource names |
| **Runbook compliance** | Stop | Prompt | Verify the agent followed your team's runbook steps |

In every case, the approach is the same: give Copilot context about Azure SRE Agent hooks, point at existing hooks in this repo for format, describe the governance requirement, and iterate.

## Tips for Better Results

- **Always give Copilot context first.** Point it at the SRE Agent docs and existing examples before describing what you need. Without this context, Copilot doesn't know it's generating for Azure SRE Agent.
- **Be specific about Azure CLI commands.** Instead of "check the VM," say "use `az vm show`, `az vm get-instance-view`, and `az monitor metrics list`."
- **Specify both Linux and Windows if applicable.** Many VM skills need different commands for each OS (e.g., `az vm run-command invoke` with different scripts).
- **Always specify the tools in frontmatter.** Tell Copilot which tools the skill needs (`RunAzCliReadCommands`, `RunAzCliWriteCommands`) and explain that `az vm run-command invoke` requires write permissions.
- **Ask for the report template explicitly.** Say "include a markdown report template with severity, findings, and recommendations."
- **Iterate: first draft → test → refine.** Test the skill with your agent, see where it falls short, and ask Copilot to fix the gaps.

## Extending to Other Domains

The same SKILL.md format works for any Azure domain. Here are some areas to explore:

### AKS Skills
- Cluster health checks via `kubectl` commands (executed through `RunAzCliWriteCommands`)
- Node pool scaling recommendations
- Pod crash loop diagnosis

### App Service Skills
- App Service plan utilization analysis
- Deployment slot swap validation
- SSL certificate expiration checks

### Database Skills
- Azure SQL DTU/vCore utilization analysis
- Cosmos DB partition hot-spot detection
- PostgreSQL connection pool exhaustion diagnosis

### Networking Skills
- Application Gateway backend health
- VPN Gateway tunnel status
- DNS resolution troubleshooting

In every case, the approach is the same: give Copilot context about Azure SRE Agent, point at existing skills for format, describe the scenario, and iterate until the skill works well with your agent.
