# Azure SRE Agent — Skills Guide

> Last verified against Azure SRE Agent documentation: April 2026

> ⚠️ **Example skills**— the skills in this repo are designed as a starting point. Test and customize for your environment before production use.

> **Audience:** Azure SRE Agent users who want to add domain-specific troubleshooting procedures to their agents.
>
> **Prerequisites:** An Azure SRE Agent in **Running** state with skills loaded via the portal ([sre.azure.com](https://sre.azure.com)).
>
> **Official docs:** [SRE Agent Skills — sre.azure.com](https://sre.azure.com/docs/concepts/skills)

📖 **[Why and When to Use Skills →](../docs/why-and-when-to-use-skills.md)** — understand the benefits of skills and when to create them vs. letting the agent reason on its own.

---

## Table of contents

1. [What are skills?](#what-are-skills)
2. [Available domains](#available-domains)
3. [How to add a skill to your agent](#how-to-add-a-skill-to-your-agent)
4. [Optional: Assign skills to a custom agent](#optional-assign-skills-to-a-custom-agent)
5. [How to write new skills](#how-to-write-new-skills)
6. [Per-domain READMEs](#per-domain-readmes)
7. [Further reading](#further-reading)

---

## What are skills?

A skill is a structured prompt (Markdown file) that gives the agent domain expertise for a specific scenario — for example, "diagnose high CPU on a VM" or "expand a disk that's running out of space." When a user asks a question, the agent automatically selects the most relevant skill and follows its instructions.

Each skill typically includes:
- **What to investigate** — the diagnostic steps, CLI commands, and checks to run
- **How to interpret results** — thresholds, known patterns, and edge cases
- **What to report** — the output format, severity classification, and recommended actions
- **Safety guardrails** — what the agent should and shouldn't do

---

## Available domains

| Domain | Skills | Status | Path |
|--------|--------|--------|------|
| **VM** | 10 skills — diagnostics, remediation, advisory | ✅ Available | [`vm/`](vm/) |
| **AKS** | Kubernetes troubleshooting | 🔜 Planned | — |
| **Networking** | NSG, Load Balancer, DNS diagnostics | 🔜 Planned | — |
| **Storage** | Blob, disk, file share issues | 🔜 Planned | — |

See [`vm/README.md`](vm/README.md) for the full list of VM skills, testing guide, and deployment instructions.

---

## How to add a skill to your agent

### Step-by-step

1. **Open the portal** — Go to [sre.azure.com](https://sre.azure.com) and select your agent.
2. **Navigate to Builder** — Click **Builder** in the left nav.
3. **Open Custom agents** — Click **Agent Canvas** → **Custom agents** → **Create** → **Skill**.
4. **Name the skill** — Use a descriptive name that matches the folder name (e.g., `high-cpu-vm-troubleshooting`).
5. **Paste the prompt** — Open the skill's `SKILL.md` file and paste its full contents into the prompt field.
6. **Attach tools** — Add the tools the skill needs (see [Tool requirements](#tool-requirements) below).
7. **Save** — Click **Save**. The skill is now active.

### Tool requirements

Most VM skills require two tools:

| Tool | Why |
|------|-----|
| **`RunAzCliReadCommands`** | Run read-only Azure CLI commands (`az vm show`, `az monitor metrics list`, etc.) |
| **`RunAzCliWriteCommands`** | Run commands that modify state — **including `az vm run-command invoke`** |

> ⚠️ **Why is `RunAzCliWriteCommands` needed for diagnostics?**
>
> Even purely diagnostic skills often need `RunAzCliWriteCommands` because `az vm run-command invoke` is classified as a write operation by Azure (it executes a script inside the VM). Without it, the agent can't run in-guest commands like `top`, `df -h`, or `Get-Process` — which are essential for most diagnostic scenarios.
>
> If you want to restrict what the agent can actually do inside the VM, use [hooks](../hooks/) to enforce an allowlist of approved commands.

Some skills may also use:
- **`RunKQLQuery`** — For querying Azure Monitor Logs / Log Analytics
- **`GetAzureMonitorMetrics`** — For pulling VM metric data

Check each skill's `README.md` for its specific tool requirements.

> 💡 **MCP tools:** Azure SRE Agent skills now support attaching [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) tools alongside built-in tools like `RunAzCliReadCommands`. If your organization exposes internal APIs or tooling via MCP servers, you can attach them to skills for richer diagnostics and remediation workflows.

---

## Optional: Assign skills to a custom agent

By default, skills are available to the root agent. For more control, you can group related skills under a **custom agent** (subagent) with its own identity and permissions.

Example — a VM expert agent that handles all VM-related skills:

```yaml
name: vm_expert
description: >
  Specialist agent for Azure VM troubleshooting.
  Handles CPU, memory, disk, connectivity, security,
  and extension issues for both Linux and Windows VMs.
skills:
  - high-cpu-vm-troubleshooting
  - high-memory-oom-troubleshooting
  - disk-expansion
  - disk-iops-throttling
  - vm-connectivity-troubleshooting
  - service-crash-loop-detection
  - security-incident-triage
  - vm-right-sizing
  - backup-health-verification
  - vm-extension-failure-remediation
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
```

Custom agents are configured in the portal under **Agent Canvas** → **Custom agents** → **Create** → **Agent** (with `allowed_skills`).

---

## How to write new skills

### Key principles

1. **Be specific** — Include exact CLI commands the agent should run, not vague instructions like "check the disk." Specify command flags, output fields to examine, and what to look for.

2. **Include diagnostic steps** — Structure the skill as a sequence: gather info → analyze → classify → report. The agent works best when it has a clear workflow.

3. **Specify output format** — Tell the agent exactly what its response should look like (e.g., "Include a Severity field, a Findings section, and a Recommended Actions list").

4. **Cover both OS types** — If the skill applies to both Linux and Windows, include commands for both and tell the agent how to detect the OS first.

5. **Safety first** — For remediation skills, always include pre-flight checks, require confirmation semantics, and specify rollback steps. Never assume the agent should proceed without validating the current state.

6. **Include thresholds and context** — Don't just say "check CPU." Say "if CPU > 90% sustained for 5+ minutes, classify as Critical." The agent needs decision criteria.

7. **Test with edge cases** — Consider what happens when a VM is stopped/deallocated, when an extension is in a transitioning state, or when the user provides incomplete information.

### Skill file structure

Each skill lives in its own folder:

```
skills/<domain>/<skill-name>/
├── SKILL.md       ← The prompt the agent uses (paste this into the portal)
└── README.md      ← Human-facing docs: what it does, how to test, setup instructions
```

### Getting started

See **[Creating Skills and Hooks](../docs/creating-skills-and-hooks-with-copilot.md)** for a walkthrough of building new skills and hooks — either by asking SRE Agent directly or using GitHub Copilot.

---

## Per-domain READMEs

- **[VM Skills](vm/README.md)** — All 10 VM troubleshooting skills with testing guide and deployment instructions

---

## Further reading

| Resource | Description |
|----------|-------------|
| [SRE Agent Skills — sre.azure.com](https://sre.azure.com/docs/concepts/skills) | Product documentation with concepts and configuration |
| [SRE Agent Skills — Microsoft Learn](https://learn.microsoft.com/azure/sre-agent/skills) | Full reference documentation |
| [Tutorial: Create a skill](https://sre.azure.com/docs/tutorials/automation/create-skill) | Step-by-step tutorial for creating your first skill |
| [Why and When to Use Skills (this repo)](../docs/why-and-when-to-use-skills.md) | Benefits of skills, when to create them, skills vs. agents vs. knowledge files |
| [Creating Skills and Hooks (this repo)](../docs/creating-skills-and-hooks-with-copilot.md) | How to create skills and hooks — via SRE Agent chat or GitHub Copilot |
| [Hooks Guide (this repo)](../hooks/README.md) | Governance guardrails that complement skills |
