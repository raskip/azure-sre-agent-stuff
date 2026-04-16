# Why and When to Use Hooks

Azure SRE Agent has built-in safety features. It classifies every action as safe, cautious, or destructive. It requires confirmation for destructive actions in Review mode. It uses judgment about what's appropriate based on its knowledge of Azure best practices. So if the agent already has safety built in, **why add hooks?**

This guide explains the benefits of hooks, when to create them, and when the agent's built-in safety is enough.

---

## What the agent does without hooks

Before diving into hooks, it helps to understand what the agent already provides:

| Capability | What it means |
|------------|---------------|
| **Action classification** | Every action is classified as safe, cautious, or destructive |
| **Review mode** | Destructive actions require operator confirmation before executing |
| **Reasoning loop** | Agent reasons about safety as part of its investigation |
| **Run modes** | Autonomous or Review — controls what the agent can do without approval |
| **Built-in judgment** | Agent uses its knowledge of Azure best practices to avoid harmful actions |

For routine operations and well-understood scenarios, this is often enough.

**So why hooks?**

---

## Why use hooks

Hooks add a layer that the agent's built-in safety can't provide: **deterministic, organization-specific governance that runs automatically, every time, without relying on the agent's judgment.**

The [official docs](https://sre.azure.com/docs/capabilities/agent-hooks) describe hooks as custom checkpoints that intercept and control agent behavior at key execution points. Here are the specific benefits:

### 1. Deterministic policy enforcement

Unlike the agent's judgment (which is probabilistic), hooks enforce rules with certainty. A command hook that blocks `rm -rf` will ALWAYS block it — no reasoning, no exceptions, no edge cases where the agent decides it's okay.

**Why this matters:** In production, "the agent usually avoids this" isn't good enough. You need "this is always blocked." Hooks provide that guarantee.

> **Example from this repo:** The [`block-dangerous-commands`](../hooks/examples/block-dangerous-commands.yaml) hook uses regex to block `rm -rf`, `sudo`, `chmod 777`, `DROP TABLE`, and other destructive patterns. It doesn't matter how good the agent's reason is — the hook blocks it.

### 2. Quality gates

The agent produces good responses, but "good" varies. Hooks define a minimum quality bar that every response must clear:

- Must include a Summary section
- Must cite actual evidence (concrete numbers, not "CPU is high")
- Must follow a structured format (Root Cause, Evidence, Recommended Actions)

Without hooks, quality depends on the skill prompt and the agent's interpretation. With hooks, quality is enforced automatically.

> **Example from this repo:** The [`require-evidence-in-diagnostics`](../hooks/examples/require-evidence-in-diagnostics.yaml) hook rejects any diagnostic response that doesn't include at least two concrete, quantified observations. "CPU at 94%" passes. "CPU usage is high" gets rejected.

### 3. Audit and compliance

For regulated environments, you need a verifiable record of what the agent did. The agent doesn't automatically log every tool call in a way that's visible to operators. Hooks can.

**Why this matters:** SOC 2, ISO 27001, and similar frameworks require demonstrable control over automated actions. Hooks create the paper trail.

> **Example from this repo:** The [`audit-all-tool-usage`](../hooks/examples/audit-all-tool-usage.yaml) hook logs every tool invocation — agent name, turn number, tool name, success/failure — directly into the conversation as an audit trail.

### 4. Operational guardrails

Sometimes you need hard limits on what the agent can do, beyond what run modes provide:

- Read-only mode that blocks ALL write operations (not just destructive ones)
- VM deletion prevention in shared environments
- Allowlist-only remediation (only pre-approved commands)

Run modes give you two presets (Autonomous, Review). Hooks give you fine-grained control tailored to your exact requirements.

> **Example from this repo:** The [`restrict-to-readonly`](../hooks/examples/restrict-to-readonly.yaml) hook blocks any tool call that modifies infrastructure. The [`allowlist-remediation`](../hooks/examples/allowlist-remediation.yaml) hook takes the most secure approach: only explicitly approved commands are permitted.

### 5. Organizational standards

Your team has specific requirements for how the agent communicates:

- Every response must end with a Summary section
- Diagnostic reports must follow a specific format
- Recommendations must be actionable (specific commands, not generic advice)

Hooks enforce these standards automatically, even when the skill prompt doesn't require them. This is especially valuable when multiple skills are in use — the hook applies to all of them.

> **Example from this repo:** The [`enforce-structured-response`](../hooks/examples/enforce-structured-response.yaml) hook requires every diagnostic response to include Root Cause, Evidence, and Recommended Actions sections — with specific, actionable content in each.

### 6. Layered governance (defense in depth)

The real power of hooks is combining them. A single hook is useful; multiple hooks create comprehensive governance:

| Layer | Hook type | What it does |
|-------|-----------|-------------|
| **Safety** | PostToolUse (command) | Block dangerous commands before they cause damage |
| **Quality** | Stop (prompt) | Reject incomplete or evidence-free responses |
| **Audit** | PostToolUse (command) | Log every tool call for compliance |
| **Scope** | PostToolUse (command) | Restrict to read-only or allowlist-only operations |

These layers complement each other. A safety hook prevents damage. A quality hook ensures thoroughness. An audit hook creates the paper trail. None of them depend on the agent's judgment — they run deterministically, every time.

---

## When to create a hook

Create a hook when:

| Signal | Example |
|--------|---------|
| **You need deterministic enforcement** | "This pattern must ALWAYS be blocked, no exceptions" |
| **Compliance requires audit trails** | "We need a log of every tool call for SOC 2" |
| **Quality must be guaranteed** | "Every diagnostic report must cite evidence" |
| **You need scope limits** | "The agent should only read, never modify, in this environment" |
| **Safety is non-negotiable** | "VM deletion must be impossible, regardless of context" |
| **Output format is mandatory** | "All responses must include Root Cause, Evidence, and Recommendations" |
| **You want defense in depth** | "Even if the skill doesn't enforce safety, the hook does" |

### The hook maturity path

You don't have to deploy every hook type at once. A natural progression:

1. **Start with audit** — Add an audit hook to see what the agent does. No blocking, just visibility.
2. **Add quality gates** — Once you see response patterns, add Stop hooks to enforce minimum quality.
3. **Add safety blocks** — Block the specific dangerous patterns you've identified.
4. **Layer them** — Combine audit + quality + safety + scope hooks for comprehensive governance.
5. **Tune activation** — Move debugging hooks to On Demand, keep safety hooks as Always.

This mirrors the approach for skills: observe what the agent does, then encode what you've learned as governance rules.

---

## When built-in safety is enough

Hooks are not always needed. The agent's built-in safety is sufficient when:

| Scenario | Why hooks don't help |
|----------|-----------------------|
| **Exploratory debugging** | You want the agent to try things — rigid rules would slow it down |
| **Non-critical environments** | Dev/test environments where the blast radius is small |
| **Novel investigations** | You don't yet know what patterns to enforce |
| **Simple queries** | "What's the status of VM-01?" doesn't need governance |
| **Well-scoped run modes** | Review mode already requires confirmation for destructive actions |

**The key distinction:** Built-in safety provides judgment-based protection. Hooks provide rule-based enforcement. Most production environments benefit from both.

---

## Hooks vs. skills vs. run modes

These three mechanisms serve different purposes and work together:

| | Skills | Hooks | Run modes |
|---|--------|-------|-----------|
| **Controls** | What the agent investigates and how | What quality/safety standards must be met | What actions the agent can take without approval |
| **When it runs** | When a user question matches the skill's domain | Automatically at Stop or PostToolUse events | Always active based on configuration |
| **Output** | Structured diagnostic reports | Allow/block decisions with feedback | Autonomous or Review behavior |
| **Deterministic?** | No — agent interprets the skill prompt | Command hooks: yes. Prompt hooks: mostly. | Yes — mode is fixed |
| **Customizable?** | Per-skill prompts and tools | Per-hook scripts, prompts, and matchers | Two preset modes |

**How they work together:**

- **Skills** define the investigation procedure ("check these metrics in this order")
- **Hooks** enforce governance ("every response must cite evidence; never delete VMs")
- **Run modes** control autonomy ("require confirmation for destructive actions")

A skill tells the agent _what to do_. A hook ensures the agent _does it well and safely_. A run mode controls _how much freedom_ the agent has.

---

## Summary

| | Without hooks | With hooks |
|---|---|---|
| **Policy enforcement** | Agent's judgment (probabilistic) | Deterministic rules (always enforced) |
| **Quality** | Depends on skill prompt and agent interpretation | Minimum quality bar enforced automatically |
| **Audit trail** | No structured logging of tool usage | Every tool call logged with context |
| **Scope limits** | Run modes control destructive actions | Fine-grained control (read-only, allowlist, specific tool blocking) |
| **Organizational standards** | Best-effort compliance | Guaranteed format and content requirements |
| **Safety** | Built-in action classification | Additional rule-based layer (defense in depth) |

The agent's built-in safety is genuine and effective. Hooks don't replace it — they **complement** it with deterministic, organization-specific governance. Think of hooks as the difference between "the agent uses good judgment" and "the agent uses good judgment AND these rules are enforced every time."

---

## References

| Resource | Link |
|----------|------|
| Agent Hooks (official) | [sre.azure.com/docs/capabilities/agent-hooks](https://sre.azure.com/docs/capabilities/agent-hooks) |
| Agent Hooks — Microsoft Learn | [learn.microsoft.com/azure/sre-agent/agent-hooks](https://learn.microsoft.com/azure/sre-agent/agent-hooks) |
| Tutorial: Configure hooks via API | [sre.azure.com/docs/tutorials/agent-config/agent-hooks](https://sre.azure.com/docs/tutorials/agent-config/agent-hooks) |
| Tutorial: Create hooks in the portal | [sre.azure.com/docs/tutorials/agent-config/create-manage-hooks-ui](https://sre.azure.com/docs/tutorials/agent-config/create-manage-hooks-ui) |
| Blog: Production-Grade Governance | [techcommunity.microsoft.com/...agent-hooks-production-grade-governance...](https://techcommunity.microsoft.com/blog/appsonazureblog/agent-hooks-production-grade-governance-for-azure-sre-agent/4500292) |
| Run Modes (official) | [sre.azure.com/docs/concepts/run-modes](https://sre.azure.com/docs/concepts/run-modes) |
| Skills Documentation (official) | [sre.azure.com/docs/concepts/skills](https://sre.azure.com/docs/concepts/skills) |
| Hooks Guide (this repo) | [hooks/README.md](../hooks/README.md) |
| Why and When to Use Skills (this repo) | [why-and-when-to-use-skills.md](why-and-when-to-use-skills.md) |
| Creating Skills and Hooks with Copilot (this repo) | [creating-skills-and-hooks-with-copilot.md](creating-skills-and-hooks-with-copilot.md) |
