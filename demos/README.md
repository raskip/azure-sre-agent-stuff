# Azure SRE Agent — Customer Demo Playbook

> Curated demo scenarios for showcasing Azure SRE Agent to customers. Each scenario is self-contained with setup commands, agent prompts, expected behavior, and talking points.

---

## Demo packages

Pick the package that fits your meeting slot:

| Package | Duration | Scenarios | Best for |
|---------|----------|-----------|----------|
| ⚡ **Quick Wow** | 5 min | [01 — High CPU](#01--the-wow-moment) | Executive drop-in, hallway demo, "show me one thing" |
| 🎯 **Standard** | 15 min | [01](#01--the-wow-moment) + [02](#02--enterprise-guardrails) + [03](#03--cost-optimization) | Customer workshop slot, technical decision-maker |
| 🔬 **Deep Dive** | 30 min | [Full script (04)](#04--complete-demo-flow) — all scenarios combined | Dedicated demo session, proof-of-value, architecture review |

---

## Scenarios

### 01 — The Wow Moment
**File:** [`01-quick-wow-high-cpu.md`](01-quick-wow-high-cpu.md)
**Duration:** 5 minutes
**Goal:** Show the agent diagnosing a real CPU problem autonomously — from alert to root cause to recommendation.
**Skill:** `high-cpu-vm-troubleshooting`

### 02 — Enterprise Guardrails
**File:** [`02-governance-hooks.md`](02-governance-hooks.md)
**Duration:** 10 minutes
**Goal:** Demonstrate hooks enforcing structured output, evidence requirements, and audit trails.
**Hooks:** `enforce-structured-response`, `require-evidence-in-diagnostics`, `audit-all-tool-usage`

### 03 — Cost Optimization
**File:** [`03-business-value-right-sizing.md`](03-business-value-right-sizing.md)
**Duration:** 10 minutes
**Goal:** Show the agent finding cost savings by analyzing VM utilization and recommending right-sizing.
**Skill:** `vm-right-sizing`

### 04 — Complete Demo Flow
**File:** [`04-full-demo-script.md`](04-full-demo-script.md)
**Duration:** 30 minutes
**Goal:** All three scenarios woven together with narrative, transitions, and Q&A guidance.

---

## Prerequisites

Complete these **before** the customer meeting. Budget 30–45 minutes for first-time setup.

### 1. SRE Agent deployed and running

You need an Azure SRE Agent in **Running** state. Deploy using the Bicep templates in [`infra/`](../infra/):

```bash
# Deploy the agent
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

Verify at [sre.azure.com](https://sre.azure.com) → your agent shows status **Running**.

### 2. Skills loaded

Load these skills in the portal (**Builder** → **Create** → **Skill**):

| Skill | File to paste | Required tools |
|-------|--------------|----------------|
| `high-cpu-vm-troubleshooting` | [`skills/vm/high-cpu-vm-troubleshooting/SKILL.md`](../skills/vm/high-cpu-vm-troubleshooting/SKILL.md) | `RunAzCliReadCommands`, `RunAzCliWriteCommands` |
| `vm-right-sizing` | [`skills/vm/vm-right-sizing/SKILL.md`](../skills/vm/vm-right-sizing/SKILL.md) | `RunAzCliReadCommands`, `RunAzCliWriteCommands` |

### 3. Hooks loaded (for Scenario 02)

Load these hooks in the portal (**Builder** → **Hooks** → **Create hook**):

| Hook | File | Event type |
|------|------|------------|
| `enforce-structured-response` | [`hooks/examples/enforce-structured-response.yaml`](../hooks/examples/enforce-structured-response.yaml) | Stop / Prompt |
| `require-evidence-in-diagnostics` | [`hooks/examples/require-evidence-in-diagnostics.yaml`](../hooks/examples/require-evidence-in-diagnostics.yaml) | Stop / Prompt |
| `audit-all-tool-usage` | [`hooks/examples/audit-all-tool-usage.yaml`](../hooks/examples/audit-all-tool-usage.yaml) | PostToolUse / Command |

> **Tip:** Load hooks as **disabled** initially. The demo script tells you when to toggle each one on — that's part of the show.

### 4. Demo VMs deployed

Deploy the VMs at least **1–2 hours before** the demo so Azure Monitor has metric data:

```bash
# Create demo resource group
az group create --name rg-sre-demo-eastus2 --location eastus2

# VM for Scenario 01 — High CPU demo (Standard_D2s_v5)
az vm create \
    --resource-group rg-sre-demo-eastus2 \
    --name vmlinux01 \
    --image Ubuntu2404 \
    --size Standard_D2s_v5 \
    --admin-username azureuser \
    --generate-ssh-keys \
    --public-ip-address ""

# VM for Scenario 03 — Right-sizing demo (deliberately oversized D4s_v5)
az vm create \
    --resource-group rg-sre-demo-eastus2 \
    --name vm-oversized \
    --image Ubuntu2404 \
    --size Standard_D4s_v5 \
    --admin-username azureuser \
    --generate-ssh-keys \
    --public-ip-address ""
```

### 5. Pre-flight checklist (day of demo)

- [ ] Agent is **Running** at [sre.azure.com](https://sre.azure.com)
- [ ] Both skills show up under your agent's skill list
- [ ] Hooks are loaded but **disabled** (you'll enable during demo)
- [ ] `vmlinux01` and `vm-oversized` are running in `rg-sre-demo-eastus2`
- [ ] Azure Monitor has metric data (VMs have been running 1+ hours)
- [ ] Browser tabs pre-opened: SRE Agent portal, Azure Portal (VM metrics blade)
- [ ] Stress-ng ready to trigger (see Scenario 01 for the command)

---

## Post-demo cleanup

```bash
# Delete all demo VMs and resources
az group delete --name rg-sre-demo-eastus2 --yes --no-wait

# Optionally disable hooks so they don't affect other work
# (do this in the portal: Builder → Hooks → toggle off)
```

---

## Tips for a great demo

1. **Open the Azure Portal metrics blade side-by-side** — customers love seeing the CPU spike in the portal while the agent investigates. It builds trust.
2. **Let the agent work** — don't narrate over every step. The agent's autonomous reasoning is the demo. Let it run for 10–15 seconds, then point out what it's doing.
3. **Have a backup prompt** — if the agent doesn't activate the skill, try: *"Use the high-cpu-vm-troubleshooting skill to investigate vmlinux01 in rg-sre-demo-eastus2"*
4. **Know your audience** — for executives, emphasize cost savings (Scenario 03) and governance (Scenario 02). For engineers, go deep on the diagnostic flow (Scenario 01).
5. **Trigger stress-ng 2–3 minutes before you demo Scenario 01** — this gives Azure Monitor time to register the spike.
