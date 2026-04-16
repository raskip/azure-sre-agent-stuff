# Scenario 02 — Enterprise Guardrails: Governance Hooks

> **Duration:** 10 minutes | **Hooks:** `enforce-structured-response`, `require-evidence-in-diagnostics`, `audit-all-tool-usage` | **Impact:** High for enterprise/regulated customers

---

## Goal

Show that the agent isn't just smart — it's **governed**. Hooks enforce output quality, require evidence, and create audit trails. This is the "enterprise-ready" message: *your team's standards are enforced automatically, every time, with no exceptions.*

**Why this works:** Enterprise customers always ask "how do I control it?" and "how do I audit it?" This scenario answers both questions with a live demo.

---

## Setup

### Prerequisites

- SRE Agent running with `high-cpu-vm-troubleshooting` skill loaded (from Scenario 01)
- `vmlinux01` running in `rg-sre-demo-eastus2` (from Scenario 01)
- Three hooks loaded in the portal but **initially disabled**:

| Hook | File | Event | Type |
|------|------|-------|------|
| `enforce-structured-response` | [`hooks/examples/enforce-structured-response.yaml`](../hooks/examples/enforce-structured-response.yaml) | Stop | Prompt |
| `require-evidence-in-diagnostics` | [`hooks/examples/require-evidence-in-diagnostics.yaml`](../hooks/examples/require-evidence-in-diagnostics.yaml) | Stop | Prompt |
| `audit-all-tool-usage` | [`hooks/examples/audit-all-tool-usage.yaml`](../hooks/examples/audit-all-tool-usage.yaml) | PostToolUse | Command |

### How to load hooks in the portal

1. Go to [sre.azure.com](https://sre.azure.com) → select your agent
2. **Builder** → **Hooks** tab → **Create hook**
3. Choose the event type (Stop or PostToolUse) and execution type (Prompt or Code)
4. Paste the hook content from the YAML file
5. **Save** — but leave the hook **disabled** for now

> **Important:** Load all three hooks before the demo starts. You'll toggle them on during the demo — that's the dramatic reveal.

---

## The Demo

This scenario has three parts. Each builds on the previous one.

---

### Part A: Enforce Structured Responses (5 min)

**What to say:**

> *"Now let me show you the enterprise side. The agent gives good answers — but how do you enforce that every answer follows your incident report format? That every on-call engineer gets the same structured output?"*

#### Step 1: Show the "before" (no hook)

Make sure the `enforce-structured-response` hook is **disabled**. Trigger a simple investigation:

```
What's happening with vmlinux01 in rg-sre-demo-eastus2? Quick check.
```

The agent will respond — likely with useful information, but in a **free-form format**. It may or may not include structured sections.

> *"The agent's answer is helpful, but notice the format — it's conversational. In an enterprise, you need every diagnostic report to follow the same structure: Root Cause, Evidence, Recommended Actions. Let me turn on a hook."*

#### Step 2: Enable the hook

In the portal: **Builder** → **Hooks** → find `enforce-structured-response` → **toggle it on**.

> *"I just enabled a Stop hook. This intercepts the agent's response before it reaches the user, and checks whether it meets our format requirements."*

#### Step 3: Show the "after" (hook active)

Trigger the same investigation again:

```
Investigate high CPU on vmlinux01 in rg-sre-demo-eastus2. Provide a full diagnostic report.
```

Now the agent's response **must** include:
- `## Root Cause` — with a specific explanation (not vague)
- `## Evidence` — with at least one concrete metric (actual numbers)
- `## Recommended Actions` — with numbered, specific steps (resource names, commands)

If the agent's initial response doesn't meet these criteria, the hook rejects it and the agent revises automatically. The customer may see the agent "thinking longer" — that's the hook working.

> *"See the difference? The hook forced the agent to include Root Cause, Evidence, and Recommended Actions with real numbers and specific commands. This isn't optional — the agent literally cannot return a response that doesn't meet the standard."*

#### What the hook checks

| Criterion | Requirement | Example that passes | Example that fails |
|-----------|-------------|--------------------|--------------------|
| Root Cause | Specific failure mechanism | *"stress-ng process spawned 4 CPU-bound workers"* | *"CPU is high"* |
| Evidence | Concrete metric with a number | *"CPU at 98% for 3 minutes"* | *"CPU usage is elevated"* |
| Recommended Actions | Specific commands or resource names | *"Run `killall stress-ng` on vmlinux01"* | *"Restart the service"* |

---

### Part B: Require Evidence in Diagnostics (3 min)

**What to say:**

> *"Let's take it further. What if you want to ensure the agent never gives you vague answers like 'CPU is high'? You can enforce that every observation includes actual numbers."*

#### Step 1: Enable the hook

In the portal: **Builder** → **Hooks** → find `require-evidence-in-diagnostics` → **toggle it on**.

> *"This is a lighter hook — it doesn't enforce a full report format, just requires that every diagnostic observation includes concrete, quantified data."*

#### Step 2: Ask a diagnostic question

```
Check the health of vmlinux01 in rg-sre-demo-eastus2. What's the current state?
```

The agent's response must now contain **at least two concrete, quantified observations** — for example:
- ✅ *"CPU utilization is 94%"*
- ✅ *"Disk /dev/sda1 is at 47.5 GB / 49 GB (97% capacity)"*
- ❌ *"CPU usage is high"* (rejected — no number)
- ❌ *"The disk is almost full"* (rejected — no number)

> *"The hook rejected vague language and forced the agent to go back and get actual numbers. This is how you enforce evidence-based operations across your team."*

#### Talking point

> *"Think about this: every diagnostic report from every engineer, every shift, always includes real data. No more 'it looked slow.' The agent cites evidence or it doesn't get to finish."*

---

### Part C: Audit Trail (2 min, optional)

**What to say:**

> *"One more — compliance teams always ask 'what did the agent actually do?' Let me show you the audit hook."*

#### Step 1: Enable the hook

In the portal: **Builder** → **Hooks** → find `audit-all-tool-usage` → **toggle it on**.

> *"This hook fires after every tool call. It logs the agent name, turn number, tool name, and whether the call succeeded."*

#### Step 2: Trigger any investigation

```
Check vmlinux01 status in rg-sre-demo-eastus2.
```

As the agent runs, each tool call produces an audit entry like:

```
[AUDIT] Turn 1 | Agent: sre-agent-001 | Tool: RunAzCliReadCommands | Success: True
[AUDIT] Turn 2 | Agent: sre-agent-001 | Tool: RunAzCliWriteCommands | Success: True
```

> *"Every tool call is logged — what ran, when, and whether it succeeded. This is your compliance audit trail. You can pipe this to your SIEM, your incident management system, or a Log Analytics workspace."*

---

## Key talking points

Use these to land the governance message:

| Point | What to say |
|-------|-------------|
| **Standards enforcement** | *"This is how you enforce standards across your SRE team — not with documentation that nobody reads, but with guardrails that run automatically."* |
| **No exceptions** | *"The hook is deterministic. Unlike asking a human to follow a checklist, the hook always runs. There's no 'I forgot to add the evidence section.'"* |
| **Customizable** | *"These are example hooks — you write your own. If your standard requires a severity rating, a customer impact assessment, or a specific JSON schema, you encode that in a hook."* |
| **Layered** | *"You can stack hooks. One enforces format, another requires evidence, a third audits every action. They compose."* |
| **Code or prompt** | *"Hooks can be AI-powered prompts (like the format check) or deterministic code (like the audit log). Use the right tool for the job."* |

---

## Common customer questions

| Question | Answer |
|----------|--------|
| *"Can the agent bypass the hook?"* | *"No. Stop hooks intercept the response before it reaches the user. The agent cannot skip them. If the hook rejects the response, the agent must revise."* |
| *"What if the hook is too strict?"* | *"Hooks have `maxRejections` (default 3). After 3 failed attempts, `failMode: allow` lets the response through anyway. You can set `failMode: block` for critical hooks."* |
| *"Can I scope hooks to specific agents?"* | *"Yes — you can assign hooks at the agent level or subagent level. A production agent might have strict hooks while a sandbox agent has none."* |
| *"What about latency?"* | *"Prompt hooks add a few seconds (the LLM evaluates the response). Code hooks (like audit) run in milliseconds. The timeout setting controls the maximum wait."* |

---

## Cleanup

After the demo, disable the hooks so they don't affect your other work:

1. Go to **Builder** → **Hooks**
2. Toggle **off**: `enforce-structured-response`, `require-evidence-in-diagnostics`, `audit-all-tool-usage`

No VMs to clean up for this scenario — it reuses Scenario 01's VM.
