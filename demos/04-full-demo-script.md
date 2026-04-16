# Scenario 04 — Complete Demo Flow (30 minutes)

> **Duration:** 30 minutes | **All scenarios combined** | **Audience:** Technical decision-makers, IT leadership, or dedicated demo session

---

## Overview

This is the full orchestrated demo that weaves Scenarios 01–03 into a coherent narrative. It tells a story:

1. **"The agent can diagnose real problems"** → Scenario 01 (High CPU)
2. **"You control the quality and governance"** → Scenario 02 (Hooks)
3. **"It finds money savings"** → Scenario 03 (Right-Sizing)
4. **Q&A and discussion** → Wrap-up

---

## Pre-demo setup checklist

Complete everything from the [main README prerequisites](README.md#prerequisites), then verify:

- [ ] Agent is **Running** at [sre.azure.com](https://sre.azure.com)
- [ ] Skills loaded: `high-cpu-vm-troubleshooting`, `vm-right-sizing`
- [ ] Hooks loaded but **disabled**: `enforce-structured-response`, `require-evidence-in-diagnostics`, `audit-all-tool-usage`
- [ ] `vmlinux01` (Standard_D2s_v5) running in `rg-sre-demo-eastus2`
- [ ] `vm-oversized` (Standard_D4s_v5) running in `rg-sre-demo-eastus2` — deployed 1+ hours ago
- [ ] Browser tabs open: SRE Agent chat, Azure Portal (VM metrics for vmlinux01)
- [ ] Stress-ng command ready to copy-paste

---

## Minute-by-minute script

### 0:00–2:00 — Opening (2 min)

**Set the context.** Don't jump into the demo — frame the problem first.

> *"I want to show you something we're working with in Azure — an AI-powered operations agent that can diagnose, triage, and help remediate infrastructure issues. It's called Azure SRE Agent."*
>
> *"The best way to explain it is to show you. I've got a couple of VMs running in Azure, and I'm going to walk you through three scenarios that cover the core value:*
> 1. *How the agent handles a real operational issue autonomously*
> 2. *How you maintain governance and quality control*
> 3. *How it finds cost savings"*
>
> *"Let's start with the scenario every ops team knows: it's 3 AM, a CPU alert fires, and someone has to figure out what's going on."*

**While you're talking:** Trigger the stress-ng command so the CPU spike is building.

```bash
az vm run-command invoke \
    --resource-group rg-sre-demo-eastus2 \
    --name vmlinux01 \
    --command-id RunShellScript \
    --scripts "apt-get update -qq && apt-get install -y -qq stress-ng > /dev/null 2>&1 && nohup stress-ng --cpu 0 --timeout 300s > /dev/null 2>&1 &"
```

---

### 2:00–8:00 — Scenario 01: The Wow Moment (6 min)

> *"I've got a Linux VM with high CPU. Let me just ask the agent to investigate."*

**Paste the prompt:**

```
My VM vmlinux01 in resource group rg-sre-demo-eastus2 seems to have high CPU. Can you investigate?
```

**While the agent works** (30–60 seconds), narrate:

> *"Watch what it does — it's identifying the VM, checking the OS type, pulling Azure Monitor metrics, and now it's running commands inside the VM to find the top processes. This is the full investigation an on-call engineer would do, happening autonomously."*

**When the report appears:**

> *"There it is — root cause, evidence with actual numbers, recommended actions. stress-ng is consuming all four CPU cores at 98%. The agent traced it end-to-end."*

**Transition:**

> *"Now, you might be thinking: 'that's a good answer, but how do I make sure every answer is this structured? What if a different agent or a different shift gets a vague response?' That brings us to governance."*

---

### 8:00–18:00 — Scenario 02: Enterprise Guardrails (10 min)

#### Part A: Structured responses (5 min)

> *"Let me show you hooks — governance guardrails that enforce standards. I'm going to enable a hook that requires every diagnostic response to include Root Cause, Evidence, and Recommended Actions."*

**In the portal:** Enable `enforce-structured-response` hook.

> *"The hook is now live. It intercepts the agent's response and checks whether it meets the format standard. If not, it sends the agent back to revise."*

**Paste the prompt:**

```
Investigate high CPU on vmlinux01 in rg-sre-demo-eastus2. Provide a full diagnostic report.
```

**When the structured report appears:**

> *"Notice the format — Root Cause, Evidence with numbers, Recommended Actions with specific commands. The hook enforced this. The agent cannot return a response that doesn't meet the standard."*

#### Part B: Evidence requirements (3 min)

> *"Let me add another layer — a hook that rejects vague language."*

**In the portal:** Enable `require-evidence-in-diagnostics` hook.

> *"This hook requires at least two concrete, quantified observations in every diagnostic response. 'CPU is high' gets rejected. 'CPU is at 98%' passes."*

**Paste the prompt:**

```
Check the health of vmlinux01 in rg-sre-demo-eastus2. What's the current state?
```

> *"The agent was forced to provide actual numbers — CPU percentage, memory usage, process counts. No vague descriptions allowed."*

#### Part C: Audit trail (2 min)

> *"Last one — compliance teams always ask 'what did the agent do?' This hook logs every tool call."*

**In the portal:** Enable `audit-all-tool-usage` hook.

> *"Every Azure CLI command the agent ran is now logged with agent name, turn number, tool, and success status. This is your audit trail for compliance."*

**Transition:**

> *"So we've seen the agent diagnose a real problem, and we've seen how you enforce quality and governance. But what about business value? Let me show you the cost optimization scenario."*

**In the portal:** Disable all three hooks (so they don't slow down Scenario 03).

---

### 18:00–26:00 — Scenario 03: Cost Optimization (8 min)

> *"Every organization has oversized VMs. I've got a D4s_v5 — that's 4 vCPUs, 16 GB of RAM — running basically nothing. Let's see what the agent finds."*

**Paste the prompt:**

```
Can you check if VM vm-oversized in rg-sre-demo-eastus2 is right-sized for its workload?
```

**While the agent works:**

> *"It's pulling 7 days of metric data — CPU averages, peaks, P95. Then it checks memory utilization inside the VM. This is a thorough analysis, not just a spot check."*

**When the report appears:**

> *"The verdict: average CPU 3%, memory usage 8%. The recommendation is to downsize from D4 to D2 — same family, half the cost. That's about $70/month savings on this one VM."*

**Land the business message:**

> *"Now multiply that across your fleet. If you have 100 VMs and 30% are oversized, you're looking at thousands per month in savings. The agent analyzes each one, gives you the data, and tells you exactly how to resize. It pays for itself."*

---

### 26:00–30:00 — Wrap-up and Q&A (4 min)

**Summarize:**

> *"Let me recap what we saw:*
> 1. *The agent diagnosed a real CPU issue end-to-end — from Azure metrics to in-guest process identification — in under a minute.*
> 2. *Governance hooks enforced output quality, evidence requirements, and audit trails — automatically, with no exceptions.*
> 3. *The agent found cost savings by analyzing real utilization data and recommending right-sized SKUs.*
>
> *"All of this is running on Azure, integrated with your existing monitoring and RBAC. The skills and hooks are customizable — you encode your team's procedures and standards."*

**Open for questions.** See the Q&A section below.

---

## Q&A — Common customer questions and answers

### General

| Question | Answer |
|----------|--------|
| *"Is this GA?"* | *"Azure SRE Agent is currently in preview. Check [sre.azure.com](https://sre.azure.com) for the latest availability and SKU information."* |
| *"What does it cost?"* | *"Pricing details are on the product page. The right-sizing scenario shows it can quickly offset its own cost through savings."* |
| *"Where does it run?"* | *"The agent runs as a managed Azure service. It uses your Azure RBAC permissions to access resources — it never has more access than you give it."* |

### Technical

| Question | Answer |
|----------|--------|
| *"Can it connect to on-prem?"* | *"The agent works with Azure resources via Azure CLI and Azure APIs. For hybrid scenarios, it can interact with Arc-enabled servers."* |
| *"What if it makes a mistake?"* | *"Great question — that's why hooks exist. You can restrict the agent to read-only mode, block specific commands, or require human approval for write operations. The agent also has built-in safety classifications for all actions."* |
| *"Can I integrate it with ServiceNow/PagerDuty?"* | *"The agent can be triggered from Azure Monitor alerts, and its reports can be forwarded to any incident management system. Connector integrations are on the roadmap."* |
| *"How does it compare to Copilot for Azure?"* | *"Copilot for Azure is a general-purpose assistant across all Azure services. SRE Agent is purpose-built for operations — it runs skills autonomously, has hooks for governance, and can execute multi-step investigations without human prompting at each step."* |

### Security and compliance

| Question | Answer |
|----------|--------|
| *"Who can access the agent?"* | *"RBAC controls who can interact with the agent, and the agent itself uses a managed identity with scoped permissions. You control what subscriptions and resource groups it can access."* |
| *"Is there an audit log?"* | *"Yes — the audit hook we showed logs every tool call. Additionally, Azure Activity Log captures the agent's Azure operations just like any other service principal."* |
| *"Can it access secrets or key vaults?"* | *"Only if you explicitly grant it access via RBAC. By default, the agent has no access to Key Vault or secrets."* |
| *"What data does the agent see?"* | *"The agent sees Azure resource metadata and metrics — the same data available through Azure CLI and Azure Monitor. It doesn't access application data, databases, or storage contents unless you grant specific permissions."* |

### Enterprise adoption

| Question | Answer |
|----------|--------|
| *"How do we get started?"* | *"Start with one agent, one skill, one team. The high-cpu-troubleshooting skill is a great first deployment. Prove value on a real problem, then expand."* |
| *"How do we write skills for our environment?"* | *"Skills are Markdown files — structured prompts with specific CLI commands and decision logic. We have a full guide and 10 example skills. You can also use GitHub Copilot to help write them."* |
| *"Can we have different agents for different teams?"* | *"Yes — you can deploy multiple agents with different permissions, skills, and hooks. A production ops agent might be read-only with strict hooks, while a dev/test agent has more freedom."* |

---

## Post-demo cleanup

```bash
# Kill stress-ng if still running
az vm run-command invoke \
    --resource-group rg-sre-demo-eastus2 \
    --name vmlinux01 \
    --command-id RunShellScript \
    --scripts "killall stress-ng 2>/dev/null; echo done"

# Delete all demo resources
az group delete --name rg-sre-demo-eastus2 --yes --no-wait

# Disable hooks in the portal
# Builder → Hooks → toggle off all three hooks
```

---

## Appendix: Quick reference

### VMs used in this demo

| VM name | SKU | Purpose | Scenario |
|---------|-----|---------|----------|
| `vmlinux01` | Standard_D2s_v5 | High CPU diagnosis target | 01, 02 |
| `vm-oversized` | Standard_D4s_v5 | Right-sizing analysis target | 03 |

### Skills used

| Skill | Scenario | Tools required |
|-------|----------|---------------|
| `high-cpu-vm-troubleshooting` | 01, 02 | `RunAzCliReadCommands`, `RunAzCliWriteCommands` |
| `vm-right-sizing` | 03 | `RunAzCliReadCommands`, `RunAzCliWriteCommands` |

### Hooks used

| Hook | Scenario | Event | Type |
|------|----------|-------|------|
| `enforce-structured-response` | 02A | Stop | Prompt |
| `require-evidence-in-diagnostics` | 02B | Stop | Prompt |
| `audit-all-tool-usage` | 02C | PostToolUse | Command |
