# Why and When to Use Skills

Azure SRE Agent is a powerful AI operations assistant. It can reason through problems, learn from past incidents, run tools in parallel, and adapt its investigation depth to the complexity of the issue. So if the agent is already this capable, **why write skills at all?**

This guide explains the benefits of skills, when to create them, and when to let the agent reason on its own.

---

## What the agent can do without skills

Before diving into skills, it helps to understand what the agent already brings to the table:

| Capability | What it means |
|------------|---------------|
| **Reasoning loop** | The agent gathers evidence, reasons over it, and acts — iterating up to 10 times per turn ([Agent Reasoning](https://sre.azure.com/docs/concepts/agent-reasoning)) |
| **Automatic memory** | After every conversation, the agent extracts learnings — symptoms, resolution steps, root causes, and pitfalls — and indexes them for future use ([Memory](https://sre.azure.com/docs/concepts/memory)) |
| **Deep context** | The agent reads your repositories, remembers past investigations, and runs background analysis to continuously deepen its understanding ([Deep Context](https://sre.azure.com/docs/concepts/workspace-tools)) |
| **Parallel execution** | Independent tool calls (log queries, resource checks, deployment history) run simultaneously, not sequentially |
| **Adaptive thinking** | A status check gets a quick response; a multi-service outage gets multi-step reasoning with evidence correlation |
| **Action classification** | Every action is classified as safe, cautious, or destructive — with destructive actions requiring confirmation in Review mode |

For general Azure operations, ad-hoc debugging, and novel problems, this is often enough. The agent can figure things out.

**So why skills?**

---

## Why use skills

The [official docs](https://sre.azure.com/docs/concepts/skills) put it simply:

> *"Without skills, your agent relies on its built-in knowledge. This works for general Azure operations, but lacks your team's specific procedures."*
>
> *"Skills turn your agent from a general assistant into a team member who knows how **you** operate."*

Here are the specific benefits:

### 1. Consistency and repeatability

Without a skill, the agent reasons about how to approach a problem each time. It might check different metrics, run different commands, or investigate in a different order. The result may be correct, but the path varies.

With a skill, the agent follows the same diagnostic procedure every time. Every high-CPU investigation checks the same metrics, runs the same `ps aux --sort=-%cpu` command, looks at the same activity log window, and produces the same report format.

**Why this matters:** In operations, consistency isn't optional. When three different engineers investigate the same class of problem and get three different report formats, it's hard to compare, audit, or hand off.

> **Example from this repo:** The [`high-cpu-vm-troubleshooting`](../skills/vm/high-cpu-vm-troubleshooting/) skill defines a fixed sequence: check Azure Monitor metrics → verify VM agent health → run OS-level diagnostics (both Linux and Windows) → correlate with Activity Log → produce structured report. Every investigation follows this path.

### 2. Encoding organizational knowledge

The agent knows Azure. It doesn't know _your_ Azure. Skills encode the things that are specific to your team:

- **Thresholds** — "CPU above 85% for 5+ minutes" instead of "high CPU"
- **Naming conventions** — Your resource group patterns, VM naming schemes
- **Escalation paths** — Who to notify, which Teams channel, what severity
- **Architecture details** — Which services depend on what, known single points of failure
- **Compliance requirements** — What must be documented, what approvals are needed

Without skills, the agent makes reasonable guesses about these things. With skills, it knows.

> **Example from this repo:** The [`disk-expansion`](../skills/vm/disk-expansion/) skill knows that your team requires a minimum of 20% free space after expansion, that Premium SSD v2 has different resizing rules than tier-based disks, and that MBR partitions can't exceed 2 TiB.

### 3. Execution capability

Skills aren't just instructions — they come with tools attached. A skill with `RunAzCliReadCommands` and `RunAzCliWriteCommands` can actually run the diagnostic commands it describes, not just tell you what to run.

This is the difference between:
- **"You should run `az vm run-command invoke` to check CPU usage"** (advice)
- **Actually running the command, parsing the output, and incorporating results into the investigation** (execution)

> **Example from this repo:** Every diagnostic skill in this repo attaches `RunAzCliReadCommands` and `RunAzCliWriteCommands`. The agent runs `az vm run-command invoke` to execute `top`, `df -Th`, `systemctl list-units --failed`, and other OS-level commands directly on the VM — then reasons about the output.

### 4. Safety guardrails

For remediation skills — anything that changes infrastructure — skills provide prescribed safety steps that the agent follows every time:

- **Pre-flight checks** before any destructive operation
- **Snapshots** before disk modifications (the disk-expansion skill makes this non-negotiable)
- **Confirmation gates** before operations that cause downtime (VM deallocation)
- **Scope limits** — "diagnostic only, no restarts" vs. "can remediate with approval"
- **Rollback procedures** if something goes wrong

Without a skill, the agent uses its judgment about safety. With a skill, your team's safety requirements are baked in.

> **Example from this repo:** The [`disk-expansion`](../skills/vm/disk-expansion/) skill mandates: (1) always snapshot before changes, (2) get operator confirmation before deallocation, (3) never shrink a disk, (4) verify new size in both Azure and OS after expansion. These aren't suggestions — they're steps the agent must follow.

### 5. Structured, auditable output

Skills define exactly what the agent's output should look like. Every skill in this repo ends with a report template specifying the format:

```
## Report Template
- **VM:** {vm-name} in {rg}
- **Severity:** Critical / Warning / Info
- **Findings:** What was discovered
- **Evidence:** Actual command output
- **Root cause:** Why it happened
- **Recommendation:** What to do next
```

This gives you:
- **Consistent reports** that teammates can read without context
- **Audit trails** with cited command output as evidence
- **Comparable investigations** across different incidents
- **Compliance documentation** for regulated environments

### 6. Efficiency

A skill with focused instructions gets to the answer faster. Without a skill, the agent's reasoning loop might explore several approaches, run extra queries, or gather information it doesn't need. With a skill, the agent knows exactly what to check and in what order.

This translates to:
- **Fewer reasoning iterations** — direct path vs. exploration
- **Less token usage** — shorter conversations, lower cost
- **Faster time to resolution** — especially important during incidents

### 7. Knowledge preservation

When your best SRE writes a skill, their troubleshooting methodology is captured for the whole team. Skills are institutional knowledge that:

- **Doesn't leave when people do** — the skill stays even if the author changes teams
- **Onboards new engineers** — a new team member gets expert-level investigation from day one
- **Maintains consistency during on-call** — 2 AM investigations follow the same quality bar as 2 PM ones
- **Improves over time** — skills are version-controlled, reviewed, and refined

This is especially powerful combined with the agent's [automatic memory](https://sre.azure.com/docs/concepts/memory). The agent learns from every investigation and applies those learnings to future conversations — but skills provide the baseline quality floor.

---

## When to create a skill

Create a skill when:

| Signal | Example |
|--------|---------|
| **You have a proven procedure** | "Every time disk space alerts fire, we check these 5 things in this order" |
| **Consistency matters** | Multiple engineers should investigate the same way |
| **Safety is critical** | The procedure involves write operations, restarts, or resource changes |
| **You need structured output** | Compliance requires a specific report format with evidence |
| **The problem recurs** | You've seen this class of issue 3+ times |
| **Domain expertise is required** | The procedure requires specific thresholds, known-good values, or environment-specific knowledge |
| **On-call quality varies** | Senior engineers handle it well; juniors struggle |

### The skill maturity path

You don't have to write skills from scratch. A natural progression:

1. **Start with the agent** — Let it reason through the problem. Watch what it does.
2. **Notice patterns** — After handling the same type of issue several times, you'll see which steps always matter and which are dead ends.
3. **Encode as a skill** — Write a SKILL.md capturing the proven diagnostic path.
4. **Test and iterate** — Run the skill against real scenarios. Refine where it falls short.
5. **Add governance** — Pair with [hooks](../hooks/) to enforce safety and compliance.

This is the approach the official docs recommend:

> *"Test the skill with your agent, see where it falls short, and ask Copilot to fix the gaps."*

---

## When to let the agent reason

Skills are not always the answer. Let the agent use its built-in reasoning when:

| Scenario | Why skills don't help |
|----------|-----------------------|
| **Novel or unknown problems** | You can't write a procedure for something you've never seen |
| **Simple, one-off queries** | "What's the status of VM-01?" doesn't need a skill |
| **Exploratory debugging** | You're still figuring out what's wrong — the agent's adaptive reasoning is ideal for open-ended investigation |
| **Rapidly changing environments** | If procedures change faster than you can update skills, rigid steps may be counterproductive |
| **General Azure operations** | The agent already knows Azure well — listing resources, checking configurations, querying logs |

**The key distinction:** Skills encode _known procedures_. Agent reasoning handles _unknown situations_. Most teams need both.

---

## Skills vs. custom agents vs. knowledge files

The Azure SRE Agent has three extensibility mechanisms. They serve different purposes:

| Feature | Skills | Custom agents | Knowledge files |
|---------|--------|---------------|-----------------|
| **How it's accessed** | Automatic — agent loads when relevant | Explicit — invoke with `/agent` command | Automatic — agent searches when relevant |
| **Can execute tools?** | ✅ Yes | ✅ Yes | ❌ No |
| **Purpose** | Reusable procedures + execution | Scoped domain specialists | Reference content |
| **Best for** | Team-wide troubleshooting guides | Database experts, security auditors | Runbooks, architecture docs |

**When to use what:**

- **Skill** — You have a team-wide procedure with optional execution. Example: an AKS troubleshooting guide with Azure CLI commands attached.
- **Custom agent** — You need a scoped specialist invoked on demand. Example: a PostgreSQL expert with database-specific tools and knowledge.
- **Knowledge file** — You have reference content the agent should search. Example: architecture docs, naming conventions, team procedures.

These work together. A custom agent can use skills. Both the main agent and custom agents search knowledge files. The right architecture often uses all three.

For more details, see the official docs:
- [Skills](https://sre.azure.com/docs/concepts/skills)
- [Custom agents](https://sre.azure.com/docs/concepts/subagents)
- [Memory and knowledge](https://sre.azure.com/docs/concepts/memory)

---

## Summary

| | Without skills | With skills |
|---|---|---|
| **Investigation approach** | Agent reasons each time — may vary | Same procedure every time |
| **Organizational context** | Agent's general Azure knowledge | Your thresholds, conventions, escalation paths |
| **Execution** | Agent has tools but decides what to run | Skill prescribes exactly what to run |
| **Safety** | Agent's built-in judgment | Your team's mandatory safety steps |
| **Output** | Varies by conversation | Standardized report format |
| **Speed** | May explore before converging | Direct path to answer |
| **Knowledge retention** | Depends on who's available | Encoded and version-controlled |

The agent is genuinely powerful on its own. Skills don't replace its reasoning — they **focus** it. Think of skills as the difference between "figure it out" and "follow our playbook."

---

## References

| Resource | Link |
|----------|------|
| Skills concept (official) | [sre.azure.com/docs/concepts/skills](https://sre.azure.com/docs/concepts/skills) |
| Agent reasoning (official) | [sre.azure.com/docs/concepts/agent-reasoning](https://sre.azure.com/docs/concepts/agent-reasoning) |
| Custom agents (official) | [sre.azure.com/docs/concepts/subagents](https://sre.azure.com/docs/concepts/subagents) |
| Memory and knowledge (official) | [sre.azure.com/docs/concepts/memory](https://sre.azure.com/docs/concepts/memory) |
| Skills on Microsoft Learn | [learn.microsoft.com/azure/sre-agent/skills](https://learn.microsoft.com/en-us/azure/sre-agent/skills) |
| Create a skill tutorial | [sre.azure.com/docs/tutorials/automation/create-skill](https://sre.azure.com/docs/tutorials/automation/create-skill) |
| Creating skills and hooks with Copilot (this repo) | [creating-skills-and-hooks-with-copilot.md](creating-skills-and-hooks-with-copilot.md) |
