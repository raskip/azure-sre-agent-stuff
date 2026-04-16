# Azure SRE Agent — Hooks Guide

> Last verified against Azure SRE Agent documentation: April 2026

> ⚠️ **Example hooks**— the hooks in this repo are designed as a starting point. Test and customize for your environment before production use.

> ⚠️ **Important: PostToolUse hooks detect, they don't prevent.** PostToolUse hooks run **after** a tool has already executed successfully. They can flag violations, inject audit context, and block the *result* from being used further — but the underlying command has already run. To truly **prevent** actions, use [Review mode](https://sre.azure.com/docs/concepts/run-modes), [low-access RBAC deployments](#achieving-true-prevention), or Azure RBAC custom roles. PostToolUse hooks complement these as a detection and audit layer. See [Achieving True Prevention](#achieving-true-prevention) below.

> **Audience:** Azure SRE Agent users who want to add governance, quality gates, and safety controls to their agents.
>
> **Prerequisites:** An Azure SRE Agent in **Running** state and **Contributor** role or higher on the agent resource.
>
> **Official docs:** [Agent Hooks — sre.azure.com](https://sre.azure.com/docs/capabilities/agent-hooks)

📖 **[Why and When to Use Hooks →](../docs/why-and-when-to-use-hooks.md)** — understand the benefits of hooks and when to create them vs. relying on the agent's built-in safety.

---

## Table of contents

1. [What are hooks?](#what-are-hooks)
2. [Quick start — your first hook in 2 minutes](#quick-start--your-first-hook-in-2-minutes)
3. [Concepts](#concepts)
4. [Configuration reference](#configuration-reference)
5. [Practical examples](#practical-examples)
6. [Achieving true prevention](#achieving-true-prevention)
7. [How to configure hooks](#how-to-configure-hooks)
8. [Best practices](#best-practices)
9. [Further reading](#further-reading)

---

## What are hooks?

Hooks are **custom checkpoints** that evaluate agent behavior at key execution points. Think of them as governance guardrails: they let you enforce quality standards, detect dangerous operations, and maintain audit trails — without building custom middleware.

```
Agent about to stop  → Stop hook evaluates response   → Allow or reject
Agent used a tool    → PostToolUse hook checks result  → Detect, audit, inject context, or suppress result
```

### Why hooks matter

| Without hooks | With hooks |
|---------------|------------|
| Agent decides when it's "done" | **You** define what "done" means |
| Tool usage is invisible | Every tool call can be audited |
| Dangerous commands go unnoticed | PostToolUse hooks detect and flag them after execution |
| Quality depends on prompting alone | Automated quality gates catch gaps |

Hooks complement [run modes](https://sre.azure.com/docs/concepts/run-modes) — run modes control **what** the agent can do; hooks control **how well** it does it and **what happens** with the results.

---

## Quick start — your first hook in 2 minutes

1. Open [sre.azure.com](https://sre.azure.com) → select your agent.
2. Go to **Builder** → **Hooks** → **Create hook**.
3. Set **Event type** to **Stop**, **Hook type** to **Prompt**.
4. Paste this prompt:

   ```text
   Check the agent response below.

   $ARGUMENTS

   Does the response include a clear Summary section at the end?
   If yes: {"ok": true}
   If no: {"ok": false, "reason": "Add a Summary section at the end of your response."}
   ```

5. Click **Save**.
6. Go to **Chat** and ask a question — the agent will now always include a summary.

That's it. You just created a quality gate that every agent response must pass through.

---

## Concepts

### Two hook events

| Event | Triggers when | What you can do |
|-------|---------------|-----------------|
| **Stop** | Agent is about to return a final response | Validate completeness, enforce formatting, reject and force the agent to continue |
| **PostToolUse** | A tool finishes executing successfully (runs **after** execution) | Audit usage, detect dangerous operations, inject extra context, suppress results |

### Two execution types

| Type | How it works | Best for |
|------|-------------|----------|
| **Prompt** | An LLM evaluates your criteria and returns allow/block | Nuanced, subjective validation ("Is this investigation thorough enough?") |
| **Command** | A bash or Python script runs in a sandboxed environment | Deterministic checks, policy enforcement, audit logging |

**Prompt hooks** use the `$ARGUMENTS` placeholder to receive the hook context (agent response, tool output, etc.). If `$ARGUMENTS` isn't in the prompt, context is appended automatically. When a conversation transcript is available, prompt hooks also get `ReadFile` and `GrepSearch` tools to reason about the full conversation history.

**Command hooks** receive context as JSON on `stdin` and output a JSON decision on `stdout`. They run in a sandboxed code interpreter with `#!/bin/bash` or `#!/usr/bin/env python3`.

### Two levels of hooks

| Level | Where to configure | Scope | Use when |
|-------|-------------------|-------|----------|
| **Agent level** | **Builder → Hooks** in the portal | Applies to the entire agent, all threads, all subagents | Organization-wide policies (audit all tools, block dangerous commands everywhere) |
| **Custom agent level** | **Agent Canvas → Custom agents → Manage Hooks**, or REST API v2 | Applies only when that specific custom agent runs | Custom agent-specific controls (validate this agent's output format) |

Both levels can coexist. If an agent-level hook and a subagent-level hook both match the same event, **both run**. Agent-level hooks fire first.

### Activation modes

| Mode | Behavior |
|------|----------|
| **Always** | Active in every conversation by default |
| **On Demand** | Must be manually toggled on per thread (via **Chat → + → Manage Hooks**) |

Use **On Demand** for debugging/audit hooks that you don't want running in every conversation.

### Hook context schema

Hooks receive structured JSON context about the current event.

**Common fields** (all hooks):

```json
{
  "hook_event_name": "Stop",
  "agent_name": "my_agent",
  "current_turn": 5,
  "max_turns": 50,
  "execution_summary": "/path/to/transcript.txt"
}
```

**Stop hook** additional fields:

```json
{
  "final_output": "Here is my response...",
  "stop_hook_active": false,
  "stop_rejection_count": 0
}
```

**PostToolUse hook** additional fields:

```json
{
  "tool_name": "ExecutePythonCode",
  "tool_input": { "code": "print(2+2)" },
  "tool_result": "4",
  "tool_succeeded": true
}
```

> **Note:** The `execution_summary` field contains a **file path** to the conversation transcript (not inline content). For prompt hooks, the LLM can use `ReadFile`/`GrepSearch` to access it. For command hooks, the file is at the specified path in the sandbox.

### Hook response formats

**Prompt hooks** — simple format:

```json
{"ok": true}
{"ok": false, "reason": "Please include more details."}
```

**Command hooks** — expanded format:

```json
{"decision": "allow"}
{"decision": "block", "reason": "Dangerous command detected."}
{"decision": "allow", "hookSpecificOutput": {"additionalContext": "Audit note."}}
```

The `additionalContext` field is injected as a user message into the conversation, giving the agent visibility into what the hook decided.

**Command hooks** can also use exit codes:

| Exit code | Behavior |
|-----------|----------|
| `0` with no output | Allow (no objection) |
| `0` with JSON | Parse JSON for decision |
| `2` | Always block — stderr becomes the reason |
| Other | Uses `failMode` setting (allow or block) |

> ⚠️ **Important:** For Stop hooks, a rejection **without a reason** is treated as approval and the agent stops. Always include a `reason` when rejecting.

---

## Configuration reference

Full YAML schema for hook configuration:

```yaml
hooks:
  Stop:
    - type: prompt          # "prompt" or "command"
      prompt: |             # LLM prompt (required for prompt hooks)
        Your evaluation prompt here.
        $ARGUMENTS
      model: ReasoningFast  # Model for prompt hooks (default: ReasoningFast)
      timeout: 30           # Execution timeout in seconds (1–300)
      failMode: allow       # "allow" or "block" on errors
      maxRejections: 3      # Max rejections before forcing stop (1–25, prompt Stop hooks only)

  PostToolUse:
    - type: command         # "prompt" or "command"
      matcher: "*"          # Regex for tool names (* = all tools)
      timeout: 30
      failMode: allow
      script: |             # Multi-line script (mutually exclusive with 'command')
        #!/usr/bin/env python3
        import sys, json
        # ... your logic here
      # command: "echo ok"  # Inline command (mutually exclusive with 'script')
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `type` | string | `prompt` | `prompt` or `command` |
| `prompt` | string | — | LLM prompt text (required for prompt hooks). Use `$ARGUMENTS` for context injection |
| `command` | string | — | Inline shell command (for command hooks, mutually exclusive with `script`) |
| `script` | string | — | Multi-line script (for command hooks, mutually exclusive with `command`) |
| `matcher` | string | — | Regex for tool names (**required** for PostToolUse). `*` matches all. Patterns are anchored as `^(pattern)$` and matched case-sensitively |
| `timeout` | int | `30` | Execution timeout in seconds (1–300) |
| `failMode` | string | `allow` | How to handle hook errors: `allow` or `block` |
| `model` | string | `ReasoningFast` | Model for prompt hooks |
| `maxRejections` | int | `3` | Max rejections before forcing stop (1–25). Applies to **prompt-type Stop hooks only**. Command-type Stop hooks have no implicit limit |

### Limits

| Limit | Value |
|-------|-------|
| Script size | 64 KB maximum |
| Timeout | 1–300 seconds |
| Max rejections (prompt Stop hooks) | 1–25 (default: 3) |
| Supported script shebangs | `#!/bin/bash`, `#!/usr/bin/env python3` |
| Script execution environment | Sandboxed code interpreter |

---

## Practical examples

All examples below are in YAML format and can be configured either through the **portal UI** or the **REST API v2**. Standalone YAML files are in the [`examples/`](examples/) directory.

---

### Example 1: Detect dangerous shell commands

**Event:** PostToolUse · **Type:** Command · **File:** [`examples/block-dangerous-commands.yaml`](examples/block-dangerous-commands.yaml)

Detect destructive operations like `rm -rf`, `sudo`, `chmod 777`, and SQL `DROP TABLE` after execution. The hook flags the violation and suppresses the result, but note the command has already run. For true prevention, combine with [Review mode or RBAC controls](#achieving-true-prevention).

```yaml
hooks:
  PostToolUse:
    - type: command
      matcher: "Bash|ExecuteShellCommand"
      timeout: 30
      failMode: block
      script: |
        #!/usr/bin/env python3
        import sys, json, re

        context = json.load(sys.stdin)
        command = context.get('tool_input', {}).get('command', '')

        dangerous = [
            (r'\brm\s+-rf\b', 'rm -rf (recursive force delete)'),
            (r'\bsudo\b', 'sudo (privilege escalation)'),
            (r'\bchmod\s+777\b', 'chmod 777 (world-writable permissions)'),
            (r'\bdrop\s+(table|database)\b', 'DROP TABLE/DATABASE (irreversible)'),
            (r'\btruncate\s+table\b', 'TRUNCATE TABLE (data wipe)'),
            (r'\bdelete\s+from\b(?!.*\bwhere\b)', 'DELETE FROM without WHERE (full table wipe)'),
            (r'\bmkfs\b', 'mkfs (format filesystem)'),
        ]

        for pattern, label in dangerous:
            if re.search(pattern, command, re.IGNORECASE):
                print(json.dumps({
                    "decision": "block",
                    "reason": f"🛑 Blocked: {label}. Use safe, non-destructive alternatives."
                }))
                sys.exit(0)

        print(json.dumps({"decision": "allow"}))
```

**When to use:** Always-on agent-level hook for any environment where the agent has shell access. Provides detection and audit trail.

**How to test:** Ask the agent to "run `rm -rf /tmp/test`" — the hook should detect and flag it with a clear reason.

---

### Example 2: Audit all tool usage

**Event:** PostToolUse · **Type:** Command · **File:** [`examples/audit-all-tool-usage.yaml`](examples/audit-all-tool-usage.yaml)

Log every tool call with the agent name, turn number, tool name, and success status. The audit message is injected into the conversation so the agent can see its own audit trail.

```yaml
hooks:
  PostToolUse:
    - type: command
      matcher: "*"
      timeout: 30
      failMode: allow
      script: |
        #!/usr/bin/env python3
        import sys, json

        context = json.load(sys.stdin)
        tool_name = context.get('tool_name', 'unknown')
        agent_name = context.get('agent_name', 'unknown')
        succeeded = context.get('tool_succeeded', False)
        turn = context.get('current_turn', '?')

        audit = f"[AUDIT] Turn {turn} | Agent: {agent_name} | Tool: {tool_name} | Success: {succeeded}"
        print(audit, file=sys.stderr)

        print(json.dumps({
            "decision": "allow",
            "hookSpecificOutput": {
                "additionalContext": audit
            }
        }))
```

**When to use:** Set to **On Demand** activation — toggle on during incident investigations or diagnostic/demo sessions.

> ⚠️ **Not compliance-grade audit.** This hook writes to stderr and injects context into the conversation — useful for diagnostics and demos. For production compliance auditing (SOC 2, ISO 27001), send audit events to Azure Monitor Log Analytics or Event Hub.

**How to test:** Enable the hook in a thread (**Chat → + → Manage Hooks**), then ask a question that uses tools. You'll see `[AUDIT]` messages in the conversation.

---

### Example 3: Enforce structured SRE response

**Event:** Stop · **Type:** Prompt · **File:** [`examples/enforce-structured-response.yaml`](examples/enforce-structured-response.yaml)

Force every diagnostic response to include **Root Cause**, **Evidence**, and **Recommended Actions** sections — the standard SRE incident report format.

```yaml
hooks:
  Stop:
    - type: prompt
      timeout: 30
      failMode: allow
      maxRejections: 3
      prompt: |
        You are a quality gate for an SRE agent that investigates infrastructure issues.
        Review the agent's response below:

        $ARGUMENTS

        Evaluate whether the response meets ALL of the following criteria:
        1. Has a "## Root Cause" section with a specific, clear explanation
           (not vague — must name the exact failure mechanism)
        2. Has a "## Evidence" section with at least one concrete metric or data point
           with an actual number (e.g., "CPU at 98%", "disk at 95% capacity")
        3. Has a "## Recommended Actions" section with numbered, specific steps
           (must include actual resource names or commands, not just "restart the service")

        If ALL three criteria are met: {"ok": true}
        If ANY criterion is missing or vague:
        {"ok": false, "reason": "Your response needs more depth. Specifically: Root Cause must name the exact failure mechanism, Evidence must include real metric values with numbers, Recommended Actions must reference actual resource names and specific commands. Go back and verify your findings."}
```

**When to use:** Subagent-level hook on your SRE diagnostic subagents to guarantee structured, evidence-based responses.

**How to test:** Ask "Investigate the VM `test-vm-01` for performance issues" — the agent should respond with clearly labeled sections containing real metrics.

---

### Example 4: Require evidence in diagnostics

**Event:** Stop · **Type:** Prompt · **File:** [`examples/require-evidence-in-diagnostics.yaml`](examples/require-evidence-in-diagnostics.yaml)

A lighter alternative to Example 3 — simply requires that diagnostic responses contain **concrete numbers** (percentages, counts, latency values) rather than vague descriptions.

```yaml
hooks:
  Stop:
    - type: prompt
      timeout: 30
      failMode: allow
      maxRejections: 3
      prompt: |
        Review the agent's response below:

        $ARGUMENTS

        Does the response contain at least TWO concrete, quantified observations?
        Examples of concrete observations:
        - "CPU utilization is 94%"
        - "Disk /dev/sda1 is at 97% capacity (47.5 GB / 49 GB)"
        - "3,847 failed SSH login attempts in the last 24 hours"
        - "P95 latency is 847ms"

        Examples of vague observations that do NOT count:
        - "CPU usage is high"
        - "The disk is almost full"
        - "There are many failed login attempts"

        If the response includes at least two concrete, quantified observations: {"ok": true}
        If not: {"ok": false, "reason": "Please provide concrete numbers in your observations. Use actual metric values (percentages, counts, latency in ms, disk sizes in GB) rather than qualitative descriptions."}
```

**When to use:** Agent-level hook when you want all agent responses to be data-driven. Good default for VM troubleshooting scenarios.

**How to test:** Ask "Check CPU usage on test-vm-01" — the agent should respond with actual numbers, not "CPU is high."

---

### Example 5: Detect VM and resource deletion

**Event:** PostToolUse · **Type:** Command · **File:** [`examples/block-vm-deletion.yaml`](examples/block-vm-deletion.yaml)

Detect and alert on Azure VM, resource group, or other critical resource deletion attempts. The hook runs after the command has executed, so it serves as an audit trail and flags violations — but does not prevent the deletion itself. For true prevention, combine with [RBAC controls or Review mode](#achieving-true-prevention).

```yaml
hooks:
  PostToolUse:
    - type: command
      matcher: "Bash|ExecuteShellCommand|ExecutePythonCode"
      timeout: 30
      failMode: block
      script: |
        #!/usr/bin/env python3
        import sys, json, re

        context = json.load(sys.stdin)
        tool_input = context.get('tool_input', {})

        # Get command from shell tools or code from Python tools
        command = ''
        if isinstance(tool_input, dict):
            command = tool_input.get('command', '') or tool_input.get('code', '')

        # Azure CLI delete operations to block
        blocked_patterns = [
            (r'az\s+vm\s+delete', 'az vm delete (VM deletion)'),
            (r'az\s+vm\s+deallocate', 'az vm deallocate (VM deallocation)'),
            (r'az\s+group\s+delete', 'az group delete (resource group deletion)'),
            (r'az\s+resource\s+delete', 'az resource delete (resource deletion)'),
            (r'az\s+disk\s+delete', 'az disk delete (disk deletion)'),
            (r'az\s+network\s+nsg\s+delete', 'az network nsg delete (NSG deletion)'),
            (r'az\s+network\s+vnet\s+delete', 'az network vnet delete (VNet deletion)'),
        ]

        for pattern, label in blocked_patterns:
            if re.search(pattern, command, re.IGNORECASE):
                print(json.dumps({
                    "decision": "block",
                    "reason": f"🛑 Blocked: {label} is not permitted. This is a safety control to prevent accidental resource deletion."
                }))
                sys.exit(0)

        print(json.dumps({"decision": "allow"}))
```

**When to use:** Always-on agent-level hook for testing and shared environments. Provides an audit trail for deletion attempts. Combine with RBAC controls for true prevention.

**How to test:** Ask "Delete the VM test-vm-01 to clean up" — the hook should detect and flag the delete command after execution.

---

### Example 6: Detect write operations

**Event:** PostToolUse · **Type:** Command · **File:** [`examples/restrict-to-readonly.yaml`](examples/restrict-to-readonly.yaml)

Detect write/modification operations after execution and flag them. Allows read/diagnostic operations to pass through. Note: since PostToolUse runs after the tool executes, the write operation will have already completed. For true read-only enforcement, use a [Reader-only RBAC deployment](#achieving-true-prevention).

```yaml
hooks:
  PostToolUse:
    - type: command
      matcher: "Bash|ExecuteShellCommand|ExecutePythonCode"
      timeout: 30
      failMode: block
      script: |
        #!/usr/bin/env python3
        import sys, json, re

        context = json.load(sys.stdin)
        tool_input = context.get('tool_input', {})
        command = ''
        if isinstance(tool_input, dict):
            command = tool_input.get('command', '') or tool_input.get('code', '')

        # Allowed read-only patterns (Azure CLI)
        readonly_patterns = [
            r'az\s+\S+\s+(show|list|get)',
            r'az\s+monitor\s+metrics\s+list',
            r'az\s+vm\s+run-command\s+invoke',   # run-command needed for diagnostics
            r'az\s+vm\s+get-instance-view',
            r'az\s+network\s+(nsg|nic|vnet)\s+(show|list)',
            r'az\s+resource\s+(show|list)',
            r'az\s+backup\s+.*\s+(show|list)',
        ]

        # Diagnostic shell commands (always safe)
        safe_commands = [
            r'^(cat|head|tail|less|grep|awk|sed|wc|sort|uniq|find|ls|df|du|free|top|ps|uptime|vmstat|iostat|netstat|ss|ip|dig|nslookup|curl|wget|journalctl|systemctl\s+status|dmesg|lsblk|mount|fdisk\s+-l)\b',
        ]

        # Check if this is a known safe pattern
        for pattern in readonly_patterns + safe_commands:
            if re.search(pattern, command, re.IGNORECASE):
                print(json.dumps({"decision": "allow"}))
                sys.exit(0)

        # Block modification commands
        modify_patterns = [
            r'az\s+\S+\s+(create|update|delete|start|stop|restart|resize|set)',
            r'\b(rm|mv|cp|chmod|chown|mkdir|touch|tee|sed\s+-i|dd)\b',
            r'\b(systemctl\s+(start|stop|restart|enable|disable))\b',
            r'\b(apt|yum|dnf|pip)\s+install\b',
        ]

        for pattern in modify_patterns:
            if re.search(pattern, command, re.IGNORECASE):
                print(json.dumps({
                    "decision": "block",
                    "reason": "🔒 Read-only mode: This operation would modify the system. Only diagnostic (read) operations are allowed in this mode."
                }))
                sys.exit(0)

        # Default: allow unknown commands (safe default for diagnostics)
        print(json.dumps({"decision": "allow"}))
```

**When to use:** Toggle on when you want to detect write operations. Great as an **On Demand** hook — enable it for auditing during investigations. For true read-only enforcement, use a Reader RBAC role on the managed identity.

**How to test:** Enable the hook, then ask "Restart the service nginx" or "Resize the VM" — the hook should detect and flag them. Ask "Check disk usage" — should pass through.

---

### Example 7: Require summary section

**Event:** Stop · **Type:** Prompt · **File:** [`examples/require-summary-section.yaml`](examples/require-summary-section.yaml)

Ensure every response ends with a clear summary section. Simple but effective for ensuring consistent output format.

```yaml
hooks:
  Stop:
    - type: prompt
      timeout: 30
      failMode: allow
      maxRejections: 3
      prompt: |
        Check the agent response below.

        $ARGUMENTS

        Does the response include a clear "## Summary" or "## Conclusion" section
        near the end that concisely summarizes the key findings and next steps?

        If yes: {"ok": true}
        If no: {"ok": false, "reason": "Add a ## Summary section at the end of your response that concisely lists your key findings and recommended next steps."}
```

**When to use:** Good default agent-level hook. Ensures every response is easy to skim and act on.

**How to test:** Ask any diagnostic question — the agent should include a summary section at the end of its response.

---

### Example 8: Detect unapproved remediation commands

**Event:** PostToolUse · **Type:** Command · **File:** [`examples/allowlist-remediation.yaml`](examples/allowlist-remediation.yaml)

Instead of blocklisting dangerous commands, this hook takes the **allowlist** approach: it detects any command not on the approved list after execution. Approved commands pass through; unapproved ones are flagged. Since PostToolUse runs after execution, combine with [Review mode or RBAC controls](#achieving-true-prevention) for true prevention in production.

```yaml
hooks:
  PostToolUse:
    - type: command
      matcher: "Bash|ExecuteShellCommand|ExecutePythonCode"
      timeout: 30
      failMode: block
      script: |
        #!/usr/bin/env python3
        import sys, json, re

        context = json.load(sys.stdin)
        tool_input = context.get('tool_input', {})
        command = ''
        if isinstance(tool_input, dict):
            command = tool_input.get('command', '') or tool_input.get('code', '')

        # ---- APPROVED REMEDIATION COMMANDS ----
        # Add patterns here as you approve new remediation actions
        approved = [
            # VM restart
            (r'az\s+vm\s+restart\b', 'VM restart'),
            # VM resize
            (r'az\s+vm\s+resize\b', 'VM resize'),
            # Disk expand
            (r'az\s+disk\s+update\s+.*--size-gb\b', 'Disk expansion'),
            # Service restart (systemd)
            (r'systemctl\s+restart\s+\S+', 'Service restart'),
            # Extension reinstall
            (r'az\s+vm\s+extension\s+(set|delete)\b', 'VM extension management'),
            # PostgreSQL restart
            (r'az\s+postgres\s+flexible-server\s+restart\b', 'PostgreSQL restart'),
        ]

        # ---- ALWAYS-SAFE OPERATIONS (read-only) ----
        safe = [
            r'^az\s+\S+\s+(show|list|get)\b',
            r'^az\s+monitor\s+',
            r'^az\s+vm\s+run-command\s+invoke\b',
            r'^(cat|grep|head|tail|df|du|free|ps|top|journalctl|systemctl\s+status|dmesg|lsblk|uptime|vmstat|iostat|ss|netstat|ip\s+(a|r|link)|dig|nslookup|curl\s+-[sISo])\b',
        ]

        # Check approved remediation first
        for pattern, label in approved:
            if re.search(pattern, command, re.IGNORECASE):
                print(json.dumps({
                    "decision": "allow",
                    "hookSpecificOutput": {
                        "additionalContext": f"[SAFETY] ✅ Approved remediation: {label}"
                    }
                }))
                sys.exit(0)

        # Check always-safe operations
        for pattern in safe:
            if re.search(pattern, command, re.IGNORECASE):
                print(json.dumps({"decision": "allow"}))
                sys.exit(0)

        # Block everything else
        print(json.dumps({
            "decision": "block",
            "reason": "🛑 This command is not in the approved remediation list. Only pre-approved operations are allowed. Contact your platform team to add new approved commands."
        }))
```

**When to use:** Production environments where you want strict control over what the agent can change. Combine with [Review mode or RBAC controls](#achieving-true-prevention) for true enforcement — this hook provides the detection and audit layer.

**How to test:**
- ✅ "Restart the VM" → Allowed (matches `az vm restart`)
- ✅ "Check disk usage" → Allowed (matches safe `df` command)
- 🛑 "Change NSG rules" → Detected and flagged (not on the allowlist)

---

## Achieving true prevention

PostToolUse hooks are valuable for **detection, audit trails, and context injection** — but they run after a tool has already executed. If you need to truly **prevent** the agent from performing certain actions, use these complementary controls:

### Review mode (agent asks before executing)

Put the agent in **Review mode** so it asks for human approval before executing any tool. This is the most direct way to prevent unwanted actions.

- Configure via **Builder → Run Mode → Review**
- The agent will pause and present its planned action for approval
- You can approve, reject, or modify before execution happens
- See [Run Modes documentation](https://sre.azure.com/docs/concepts/run-modes) for details

### Low-access deployment (Reader-only RBAC)

Assign the agent's managed identity a **Reader** role (or no write permissions). Even if the agent tries to run a destructive command, Azure will deny it at the API level.

- Assign `Reader` role on the target subscription/resource group
- The agent can still investigate and diagnose, but cannot modify resources
- This is the strongest prevention — the platform enforces it, not the agent

### Azure RBAC custom roles

Create a **custom RBAC role** that allows only specific actions. This gives fine-grained control over what the agent's managed identity can do.

- Example: Allow `Microsoft.Compute/virtualMachines/read` and `Microsoft.Compute/virtualMachines/restart/action`, but deny `Microsoft.Compute/virtualMachines/delete`
- Use `az role definition create` to define custom roles
- Assign the custom role to the agent's managed identity

### Recommended layered approach

For production environments, combine all three:

| Layer | Control | Purpose |
|-------|---------|---------|
| **1. RBAC** | Reader role or custom role on the managed identity | True prevention — Azure denies unauthorized API calls |
| **2. Review mode** | Agent asks for approval before tool execution | Human-in-the-loop for approved actions |
| **3. PostToolUse hooks** | Detection, audit trail, context injection | Visibility, compliance logging, guardrail feedback to the agent |

This defense-in-depth approach ensures that even if one layer is misconfigured, the others provide protection.

---

## How to configure hooks

### Method 1: Portal UI (easiest)

**Agent-level hooks** (apply to all threads and subagents):

1. Go to [sre.azure.com](https://sre.azure.com) → select your agent.
2. Expand **Builder** → select **Hooks**.
3. Click **Create hook**.
4. Fill in the form: name, event type, activation mode, hook type, prompt/script.
5. Click **Save**.

**Subagent-level hooks** (apply to one specific subagent):

1. Go to **Agent Canvas** → **Custom agents**.
2. Select an existing subagent (or create a new one).
3. Scroll to the **Hooks** section → click **Manage Hooks**.
4. Click **Add hook** → fill in the form → **Save**.
5. **Save** the subagent to persist the hook.

### Method 2: REST API v2 (for CI/CD)

Get your agent's API URL and an access token:

```bash
# Find API URL: sre.azure.com → Agent Canvas → Developer Tools (F12) → Network tab → look for *.azuresre.ai
AGENT_URL="https://your-agent--xxxxxxxx.yyyyyyyy.region.azuresre.ai"

# Get access token
TOKEN=$(az account get-access-token \
  --resource <RESOURCE_ID> \
  --query accessToken -o tsv)
```

Create a subagent with hooks:

```bash
curl -X PUT "${AGENT_URL}/api/v2/extendedAgent/agents/my_hooked_agent" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my_hooked_agent",
    "properties": {
      "instructions": "You are a helpful SRE assistant.",
      "handoffDescription": "",
      "handoffs": [],
      "enableVanillaMode": true,
      "hooks": {
        "Stop": [{
          "type": "prompt",
          "prompt": "Check the response below.\n$ARGUMENTS\nDoes it end with === RESPONSE COMPLETE ===?\nIf yes: {\"ok\": true}\nIf no: {\"ok\": false, \"reason\": \"Add === RESPONSE COMPLETE === at the end.\"}",
          "timeout": 30
        }],
        "PostToolUse": [{
          "type": "command",
          "matcher": "*",
          "timeout": 30,
          "failMode": "allow",
          "script": "#!/usr/bin/env python3\nimport sys, json\nctx = json.load(sys.stdin)\nprint(json.dumps({\"decision\": \"allow\", \"hookSpecificOutput\": {\"additionalContext\": f\"[AUDIT] {ctx.get(\"tool_name\", \"unknown\")} executed.\"}}))"
        }]
      }
    }
  }'
```

### Method 3: Toggle per thread

For hooks with **On Demand** activation:

1. Open a **Chat** thread.
2. Click the **+** button in the chat footer.
3. Select **Manage Hooks**.
4. Toggle individual hooks on/off for the current thread.

You can also temporarily deactivate **Always** hooks in a specific thread.

---

## Best practices

1. **Always provide a reason when rejecting.** A rejection without a `reason` is treated as approval — the agent will stop.

2. **Use `failMode: allow` during development**, `failMode: block` in production. During development, you don't want a buggy script to block all agent operations.

3. **Be specific with matchers.** Use `Bash|ExecuteShellCommand` instead of `*` for shell-specific policies. Overly broad matchers slow down the agent.

4. **Prefer allowlists over blocklists.** Example 8 (allowlist) is fundamentally more reliable than Example 1 (blocklist) as a detection layer — you can't forget to detect something if only approved commands pass through.

5. **Combine hooks for layered governance.** Use a Stop hook for quality + a PostToolUse hook for safety + an audit hook for visibility. They complement each other.

6. **Use On Demand for debugging hooks.** Audit-all-tools hooks are invaluable during incidents but noisy in routine operations. Set them to On Demand and toggle as needed.

7. **Test hooks in the playground first.** Use **Agent Canvas → Custom agents → Test playground** to test custom agent hooks, or **Chat** with a specific prompt to test agent-level hooks.

8. **Log to stderr for debugging.** Command hooks should use `print(..., file=sys.stderr)` for debug output. The system parses `stdout` as the hook result.

9. **Handle the maxRejections limit.** Prompt Stop hooks default to 3 rejections before forcing stop. Don't set it too high — you'll waste agent turns. Don't set it too low — the agent may not have enough attempts to fix its response.

10. **Multiple hooks can coexist.** You can have multiple PostToolUse hooks with different matchers. For Stop, multiple hooks all evaluate the same response. If any one rejects, the agent continues.

---

## Further reading

| Resource | Description |
|----------|-------------|
| [Agent Hooks — sre.azure.com](https://sre.azure.com/docs/capabilities/agent-hooks) | Product documentation with concepts, configuration reference, and examples |
| [Agent Hooks — Microsoft Learn](https://learn.microsoft.com/azure/sre-agent/agent-hooks) | Full reference documentation with context schema, response format, and limits |
| [Tutorial: Configure hooks via API](https://sre.azure.com/docs/tutorials/agent-config/agent-hooks) | Step-by-step REST API v2 tutorial with curl commands |
| [Tutorial: Create hooks in the portal](https://sre.azure.com/docs/tutorials/agent-config/create-manage-hooks-ui) | Visual portal walkthrough with screenshots |
| [Blog: Production-Grade Governance](https://techcommunity.microsoft.com/blog/appsonazureblog/agent-hooks-production-grade-governance-for-azure-sre-agent/4500292) | Real-world PostgreSQL incident scenario with layered hooks |
| [Run Modes](https://sre.azure.com/docs/concepts/run-modes) | Complements hooks — controls what the agent can do |
| [Skills Documentation](https://sre.azure.com/docs/concepts/skills) | How to create custom skills for SRE Agent |
| [Why and When to Use Hooks (this repo)](../docs/why-and-when-to-use-hooks.md) | Benefits of hooks, when to create them, hooks vs. skills vs. run modes |
