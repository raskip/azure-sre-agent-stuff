# Azure SRE Agent — Skills, Hooks & Deployment Guide

> Last verified against Azure SRE Agent documentation: May 2026

> A community starter kit for [Azure SRE Agent](https://sre.azure.com): **10 VM troubleshooting skills**, **18 governance hooks**, Bicep deployment templates, marketplace install metadata, and step-by-step guides to get started quickly.
>
> ⚠️ **Example content** — all skills and hooks in this repo were created with [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli) as starting points. Test and customize for your environment before production use. **Use at your own risk.**

[Azure SRE Agent](https://sre.azure.com) is an AI-powered operations assistant that diagnoses, triages, and remediates Azure infrastructure issues. It's genuinely powerful on its own — it can [reason through problems](https://sre.azure.com/docs/concepts/agent-reasoning) iteratively, [learn from past incidents](https://sre.azure.com/docs/concepts/memory), run tools in parallel, and adapt its investigation depth to the complexity of the issue.

**So why this repo?** Because the agent's built-in intelligence works best when combined with **your team's specific knowledge**. Skills encode your proven troubleshooting procedures, safety requirements, and organizational standards. Hooks enforce governance guardrails. Together, they turn a capable general-purpose agent into a team member who knows how _you_ operate. See [Why and When to Use Skills](docs/why-and-when-to-use-skills.md) and [Why and When to Use Hooks](docs/why-and-when-to-use-hooks.md) for the full picture.

This repo gives you **example skills and hooks** you can use as starting points — test, customize, and extend them for your environment. The new [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json) manifest (mirrored at [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json)) makes the repo installable in one click from the Azure SRE Agent portal.

Looking for more plugins? Microsoft maintains an official set at [Azure/sre-agent-plugins](https://github.com/Azure/sre-agent-plugins) (Datadog, Dynatrace, PagerDuty, Elasticsearch, AWS, Azure Managed Grafana, Atlassian Rovo) — installable the same way through the SRE Agent portal's plugin marketplace.

> **Scope:** This repo focuses on **skills and hooks** — it's not a comprehensive Azure SRE Agent guide. For full documentation on agent setup, connectors, memory, run modes, and more, see the [official docs](https://sre.azure.com/docs). The repo may expand to cover additional topics over time.

![Agent Canvas showing skills and custom agents](docs/images/portal-agent-canvas.png)

> 💡 **Tip:** This entire repo — every skill, hook, Bicep template, and doc — was built with [GitHub Copilot](https://github.com/features/copilot). I strongly recommend using it to create your own skills and hooks, customize deployments, and work with the Azure SRE Agent in general. It makes the process dramatically faster. See our guide: **[Creating Skills with Copilot →](docs/creating-skills-and-hooks-with-copilot.md)**

---

## Why skills?

The agent can reason through problems without any skills. But skills add critical value for production operations:

| Benefit | What it means |
|---------|---------------|
| **Consistency** | Same diagnostic procedure every time — not variable reasoning across engineers or shifts |
| **Your knowledge encoded** | Your thresholds, escalation paths, naming conventions, and architecture details — baked in |
| **Execution + safety** | Skills attach tools that actually run commands, with prescribed safety checks before any changes |
| **Structured output** | Standardized reports with evidence, severity, and recommendations — ready for handoff or audit |

**When to create a skill:** You have a proven procedure that recurs, involves safety-critical steps, or needs consistent output. **When to skip:** The problem is novel, one-off, or simple enough for the agent to handle ad-hoc.

📖 **[Full guide: Why and When to Use Skills →](docs/why-and-when-to-use-skills.md)**

---

## Quick start

Get your first skill running in 5 steps. This uses [`high-cpu-vm-troubleshooting`](plugins/vm-sre-skills/skills/high-cpu-vm-troubleshooting/) as an example — swap in any skill from the [skills table](#skills) below.

### 1. Clone the repo

```bash
git clone https://github.com/raskip/azure-sre-agent-stuff.git
cd azure-sre-agent-stuff

# Or pull latest if you already have it
git pull origin main
```

### 2. Deploy the agent

```bash
az deployment sub create \
    --subscription "<your-subscription-id>" \
    --location "eastus2" \
    --template-file infra/minimal-sre-agent.bicep \
    --parameters \
        agentName="sre-agent-001-eastus2" \
        subscriptionId="<your-subscription-id>" \
        deploymentResourceGroupName="rg-sre-agent-001-eastus2" \
        location="eastus2" \
        accessLevel="High" \
        'targetResourceGroups=["rg-sre-demo-eastus2"]' \
        'targetSubscriptions=["<your-subscription-id>"]'
```

> See [`infra/README.md`](infra/README.md) for the PowerShell deploy script, naming conventions, and access level options.

### 3. Add your first skill

This step is done in the portal — there's no CLI for skill management yet.

1. Open [sre.azure.com](https://sre.azure.com) → select your agent
2. Go to **Builder** → **Create** → **Skill**
3. Name it `high-cpu-vm-troubleshooting`
4. Paste the contents of [`plugins/vm-sre-skills/skills/high-cpu-vm-troubleshooting/SKILL.md`](plugins/vm-sre-skills/skills/high-cpu-vm-troubleshooting/SKILL.md) into the skill editor
5. Click **Choose tools** → select `RunAzCliReadCommands` and `RunAzCliWriteCommands`
6. Click **Create**

<details>
<summary>📸 What this looks like in the portal</summary>

**Skill creation dialog:**

![Skill creation dialog with SKILL.md editor](docs/images/portal-create-skill.png)

**Tool picker:**

![Choose tools panel](docs/images/portal-choose-tools.png)

</details>

> See [`skills/README.md`](skills/README.md) for tool requirements and tips on adding skills.

### 4. Deploy a test VM

```bash
# Create resource group (if not created by the Bicep deployment)
az group create \
    --name rg-sre-demo-eastus2 \
    --location eastus2

# Deploy a test VM
az vm create \
    --resource-group rg-sre-demo-eastus2 \
    --name vm-sre-demo-cpu \
    --image Ubuntu2404 \
    --size Standard_D2s_v5 \
    --admin-username azureuser \
    --generate-ssh-keys

# Simulate high CPU (runs stress-ng for 5 minutes)
az vm run-command invoke \
    --resource-group rg-sre-demo-eastus2 \
    --name vm-sre-demo-cpu \
    --command-id RunShellScript \
    --scripts "apt-get update -qq && apt-get install -y -qq stress-ng && nohup stress-ng --cpu 0 --timeout 300s &"
```

### 5. Ask the agent

Open your agent at [sre.azure.com](https://sre.azure.com) and try:

> *"Investigate high CPU on vm-sre-demo-cpu in resource group rg-sre-demo-eastus2"*

The agent will activate the skill, run diagnostics via Azure CLI, and produce a structured report with findings and recommendations.

**Cleanup when done:**

```bash
az group delete --name rg-sre-demo-eastus2 --yes --no-wait
```

---

## Skills

The marketplace-ready VM skill plugin lives in [`plugins/vm-sre-skills/`](plugins/vm-sre-skills/), with the actual skill files under [`plugins/vm-sre-skills/skills/`](plugins/vm-sre-skills/skills/). General skill authoring guidance remains in [`skills/README.md`](skills/README.md).

| Skill | Type | Description |
|-------|------|-------------|
| [`disk-expansion`](plugins/vm-sre-skills/skills/disk-expansion/) | Remediation | Expand VM disks when space is low |
| [`high-cpu-vm-troubleshooting`](plugins/vm-sre-skills/skills/high-cpu-vm-troubleshooting/) | Diagnostic | Diagnose high CPU — top processes, per-core breakdown |
| [`high-memory-oom-troubleshooting`](plugins/vm-sre-skills/skills/high-memory-oom-troubleshooting/) | Diagnostic | Diagnose memory pressure, swap, OOM kills |
| [`vm-connectivity-troubleshooting`](plugins/vm-sre-skills/skills/vm-connectivity-troubleshooting/) | Diagnostic | Diagnose SSH/RDP failures — NSGs, routes, OS firewall |
| [`service-crash-loop-detection`](plugins/vm-sre-skills/skills/service-crash-loop-detection/) | Diagnostic | Investigate services that keep crashing |
| [`security-incident-triage`](plugins/vm-sre-skills/skills/security-incident-triage/) | Diagnostic | Triage brute-force attempts, rogue processes, open ports |
| [`vm-right-sizing`](plugins/vm-sre-skills/skills/vm-right-sizing/) | Advisory | Analyze utilization and recommend optimal VM SKU |
| [`backup-health-verification`](plugins/vm-sre-skills/skills/backup-health-verification/) | Diagnostic | Verify Azure Backup config, recovery points, failed jobs |
| [`vm-extension-failure-remediation`](plugins/vm-sre-skills/skills/vm-extension-failure-remediation/) | Remediation | Diagnose and fix failed VM extensions |
| [`disk-iops-throttling`](plugins/vm-sre-skills/skills/disk-iops-throttling/) | Diagnostic | Investigate disk IOPS/throughput throttling |

---

## Why hooks?

The agent has built-in safety — action classification, review mode, and judgment-based protection. But hooks add what built-in safety can't: **deterministic, organization-specific governance that runs automatically, every time.**

| Benefit | What it means |
|---------|---------------|
| **Deterministic detection** | A rule that flags `rm -rf` will always flag it — no reasoning, no exceptions |
| **Quality gates** | Every response must cite evidence, include a summary, follow your format |
| **Audit & compliance** | Log every tool call with context — agent name, turn, tool, success/failure |
| **Operational guardrails** | Read-only enforcement via Review mode + RBAC; detect VM deletions; log remediations |

**When to create a hook:** You need a rule enforced every time, an audit trail, or a minimum quality bar. **When to skip:** The environment is non-critical, you're exploring, or run modes already provide enough control.

📖 **[Full guide: Why and When to Use Hooks →](docs/why-and-when-to-use-hooks.md)**

---

## Hooks

Hooks are governance guardrails that intercept agent behavior at key execution points. All hooks live in [`hooks/`](hooks/).

| Hook | Type | Description |
|------|------|-------------|
| [`require-summary-section`](hooks/examples/require-summary-section.yaml) | Stop · prompt | Reject responses that lack a Summary section |
| [`enforce-structured-response`](hooks/examples/enforce-structured-response.yaml) | Stop · command | Require a specific output format (severity, findings, actions) |
| [`require-evidence-in-diagnostics`](hooks/examples/require-evidence-in-diagnostics.yaml) | Stop · command | Ensure the agent cites actual command output as evidence |
| [`restrict-to-readonly`](hooks/examples/restrict-to-readonly.yaml) | PostToolUse · command | Detect write operations after they run — pair with Review mode or RBAC for true prevention |
| [`block-dangerous-commands`](hooks/examples/block-dangerous-commands.yaml) | PostToolUse · command | Detect `rm -rf`, `format`, `Stop-Computer`, and other destructive commands in output |
| [`block-vm-deletion`](hooks/examples/block-vm-deletion.yaml) | PostToolUse · command | Detect VM deletion attempts and flag them in the audit trail |
| [`audit-all-tool-usage`](hooks/examples/audit-all-tool-usage.yaml) | PostToolUse · command | Log every tool invocation for diagnostic/demo auditing |
| [`allowlist-remediation`](hooks/examples/allowlist-remediation.yaml) | PostToolUse · command | Flag any remediation command not on the pre-approved allowlist |
| [`prompt-completeness-check`](hooks/examples/prompt-completeness-check.yaml) | Stop · prompt | Grade whether the response covers root cause, remediation, and verification |
| [`prompt-evidence-quality`](hooks/examples/prompt-evidence-quality.yaml) | Stop · prompt | Check that cited evidence is concrete instead of vague |
| [`prompt-blameless-language`](hooks/examples/prompt-blameless-language.yaml) | Stop · prompt | Enforce blameless phrasing for post-mortems and customer-facing summaries |
| [`kusto-only-audit`](hooks/examples/kusto-only-audit.yaml) | PostToolUse · command | Audit every `ExecuteKustoQuery` invocation separately from shell activity |
| [`python-output-truncate`](hooks/examples/python-output-truncate.yaml) | PostToolUse · command | Truncate long Python output to keep the transcript focused |
| [`mcp-tool-budget`](hooks/examples/mcp-tool-budget.yaml) | PostToolUse · command | Track MCP tool usage and flag budget overruns per thread |
| [`stack-audit-plus-policy`](hooks/examples/stack-audit-plus-policy.yaml) | PostToolUse · command | Demonstrate stacked hooks: one for audit, one for policy enforcement |
| [`stop-strict-no-rejection-limit`](hooks/examples/stop-strict-no-rejection-limit.yaml) | Stop · command | Show a stricter Stop hook with no practical rejection limit for format training |
| [`exit-code-only-marker`](hooks/examples/exit-code-only-marker.yaml) | Stop · command | Minimal exit-code-based guard for deterministic completion markers |
| [`skill-aware-evidence`](hooks/examples/skill-aware-evidence.yaml) | Stop · prompt | Apply different evidence expectations depending on which skill was active |

See the [Hooks Guide](hooks/README.md) for concepts, configuration reference, hook stacking guidance, and best practices.

---

## Example Scenarios

The example walkthroughs surface the marketplace, knowledge-grounding, subagent, and memory stories that pair with this repo's skills and hooks:

- [`docs/walkthrough-05-marketplace-onboarding.md`](docs/walkthrough-05-marketplace-onboarding.md) — 5-minute walkthrough showing how [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json) makes the repo installable in one click from the Azure SRE Agent portal.
- [`docs/walkthrough-06-knowledge-grounded-answers.md`](docs/walkthrough-06-knowledge-grounded-answers.md) — 3-minute walkthrough for uploading a runbook or architecture doc and demonstrating citation-backed answers.
- [`scripts/upload-knowledge.sh`](scripts/upload-knowledge.sh) — companion script that probes the v2 knowledge upload API first and falls back to documented portal steps.

| Length | Demo | What it shows |
| --- | --- | --- |
| 5 min | [Subagent VM Expert](docs/walkthrough-07-subagent-vm-expert.md) | Install a custom agent via REST API + walk through /agent handoff + hook stacking |
| 3 min | [Memory & Learning](docs/walkthrough-08-memory-and-learning.md) | Prove the agent remembers — two-day arc |
| 5–7 min | [Disk IOPS Throttling](docs/walkthrough-09-disk-iops-throttling.md) | Correlate Azure Monitor disk metrics with in-guest `iostat` to identify an IOPS bottleneck |
| 7–10 min | [Disk Expansion](docs/walkthrough-10-disk-expansion.md) | Perform an end-to-end disk resize remediation across Azure, kernel, and filesystem layers |
| 5 min | [Memory Pressure & OOM](docs/walkthrough-11-high-memory-oom.md) | Investigate swap thrash and OOM kills to separate restart decisions from real leak fixes |
| 6–7 min | [Security Incident Triage](docs/walkthrough-12-security-incident-triage.md) | Triage suspicious logins, rogue processes, open ports, and integrity drift from one prompt |
| 5 min | [VM Extension Failure](docs/walkthrough-13-vm-extension-failure.md) | Diagnose failed VM extensions and remediate broken provisioning states |
| 5 min | [Backup Health Verification](docs/walkthrough-14-backup-health-verification.md) | Audit backup jobs, restore points, and policy coverage with an operator-ready report |
| 5 min | [Service Crash-Loop Detection](docs/walkthrough-15-service-crash-loop.md) | Trace a flapping systemd service to the actual crash cause instead of repeating restarts |
| 5 min | [VM Connectivity Troubleshooting](docs/walkthrough-16-vm-connectivity-troubleshooting.md) | Walk NSG, route, boot, and OS firewall layers to pinpoint SSH or RDP failures |

Looking for reusable scheduler prompts? [`docs/scheduled-tasks/`](docs/scheduled-tasks/) contains natural-language task templates ready to paste into the Azure SRE Agent portal's Scheduled Tasks form.

---

## Repo structure

```
azure-sre-agent-stuff/
├── README.md
├── CONTRIBUTING.md
├── SECURITY.md
├── DEMO-RUNBOOK.md                      ← Sample knowledge doc for citation/upload demos
├── LICENSE                              ← MIT
├── .gitignore
├── .github/
│   ├── copilot-instructions.md          ← Conventions for AI agents working in this repo
│   ├── plugin/
│   │   └── marketplace.json
│   └── workflows/
│       └── lint.yml                     ← CI: runs the repo structure validator on push/PR
├── .claude-plugin/
│   └── marketplace.json
├── skills/
│   └── README.md                        ← Skills authoring guide (domains, tools, how-to)
├── plugins/
│   └── vm-sre-skills/
│       ├── plugin.json
│       ├── README.md
│       └── skills/
│           ├── backup-health-verification/
│           ├── disk-expansion/
│           ├── disk-iops-throttling/
│           ├── high-cpu-vm-troubleshooting/
│           ├── high-memory-oom-troubleshooting/
│           ├── security-incident-triage/
│           ├── service-crash-loop-detection/
│           ├── vm-connectivity-troubleshooting/
│           ├── vm-extension-failure-remediation/
│           └── vm-right-sizing/
├── hooks/
│   ├── README.md
│   └── examples/                        ← 18 hook YAML examples (reference only, not in marketplace)
├── infra/                               ← Bicep templates + deploy script
├── docs/                                ← Guides + walkthrough scenarios
│   ├── creating-skills-and-hooks-with-copilot.md
│   ├── why-and-when-to-use-skills.md
│   ├── why-and-when-to-use-hooks.md
│   ├── scheduled-tasks/
│   └── walkthrough-05-... → walkthrough-16-...
├── examples/                            ← 4 quick-start example scenarios (01–04)
└── scripts/                             ← Helper scripts
    ├── upload-knowledge.sh
    └── validate_repo.py                 ← Repo structure validator (skills, hooks, marketplace)
```

### Validating the repo

A lightweight quality gate keeps skills, hooks, and `marketplace.json` consistent.
It checks skill frontmatter (`name`/`description`/`tools`, name matches directory),
hook YAML structure, that both `marketplace.json` copies agree, flags README
skill/hook count drift, and verifies that relative markdown links resolve to real
files. Run it locally:

```bash
pip install pyyaml
python3 scripts/validate_repo.py
```

It also runs automatically on every push and pull request via
[`.github/workflows/lint.yml`](.github/workflows/lint.yml).

---

## How to add skills to your agent

1. Open [sre.azure.com](https://sre.azure.com) and select your agent.
2. Go to **Agent Canvas** → **Custom agents** → **Create** → **Skill**.
3. Give the skill a name (e.g., `high-cpu-vm-troubleshooting`).
4. Paste the contents of the skill's `SKILL.md` file into the prompt field.
5. Attach the required tools (typically `RunAzCliReadCommands` + `RunAzCliWriteCommands`).
6. Click **Save**.

The agent will automatically invoke the skill when a user's question matches its domain.

See [`skills/README.md`](skills/README.md) for detailed instructions and tool requirements.

---

## How to add hooks

1. Open [sre.azure.com](https://sre.azure.com) and select your agent.
2. Go to **Builder** → **Hooks** tab → **Create hook**.
3. Choose the event type (**Stop** or **PostToolUse**) and execution type (**Prompt** or **Code**).
4. Paste the hook content from the corresponding YAML file in [`hooks/examples/`](hooks/examples/).
5. Click **Save**.

See [`hooks/README.md`](hooks/README.md) for the full configuration reference and best practices.

---

## Creating new skills and hooks

Want to build your own? See the guide: **[Creating Skills and Hooks](docs/creating-skills-and-hooks-with-copilot.md)**.

Key principles for writing good skills:
- Be specific — include exact CLI commands and expected output formats
- Cover both Linux and Windows where applicable
- Include safety checks before any remediation steps
- Specify the output format you expect from the agent

---

## Resources

| Resource | Link |
|----------|------|
| Azure SRE Agent portal | [sre.azure.com](https://sre.azure.com) |
| Official documentation | [Azure SRE Agent docs](https://learn.microsoft.com/azure/sre-agent/) |
| GitHub repo (Microsoft) | [microsoft/sre-agent](https://github.com/microsoft/sre-agent) |
| SRE Agent concepts | [Skills](https://sre.azure.com/docs/concepts/skills) · [Hooks](https://sre.azure.com/docs/capabilities/agent-hooks) · [Run modes](https://learn.microsoft.com/azure/sre-agent/run-modes) |

---

## License

This project is licensed under the [MIT License](LICENSE).



