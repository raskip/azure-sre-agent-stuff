# Scenario 01 — The Wow Moment: High CPU Diagnosis

> **Duration:** 5 minutes | **Skill:** `high-cpu-vm-troubleshooting` | **Impact:** High — this is your opener

---

## Goal

Show the agent diagnosing a **real infrastructure problem** autonomously — it identifies the VM, checks Azure metrics, SSHes into the OS, finds the offending process, and produces a structured incident report. All from a single natural-language prompt.

**Why this works:** Every ops team has been woken up at 3 AM by a CPU alert. Seeing the agent handle the entire triage in seconds — from metric check to process identification — is an immediate "I want that" moment.

---

## Setup (do this 5–10 minutes before the demo)

### Step 1: Ensure the demo VM is running

```bash
# Check if vmlinux01 exists and is running
az vm show --resource-group rg-sre-demo-eastus2 --name vmlinux01 --query "{name:name, state:instanceView.statuses[1].displayStatus}" -o table

# If it doesn't exist, create it:
az vm create \
    --resource-group rg-sre-demo-eastus2 \
    --name vmlinux01 \
    --image Ubuntu2404 \
    --size Standard_D2s_v5 \
    --admin-username azureuser \
    --generate-ssh-keys \
    --public-ip-address ""
```

### Step 2: Trigger CPU stress (2–3 minutes before demo)

```bash
az vm run-command invoke \
    --resource-group rg-sre-demo-eastus2 \
    --name vmlinux01 \
    --command-id RunShellScript \
    --scripts "apt-get update -qq && apt-get install -y -qq stress-ng > /dev/null 2>&1 && nohup stress-ng --cpu 0 --timeout 300s > /dev/null 2>&1 &"
```

This pins all CPU cores at 100% for 5 minutes. The `nohup` ensures it keeps running after the run-command returns.

> **Timing tip:** Run this 2–3 minutes before you switch to the SRE Agent tab. This gives Azure Monitor time to register the spike so the agent sees elevated metrics.

### Step 3: Open these browser tabs

1. **SRE Agent portal** — [sre.azure.com](https://sre.azure.com) → your agent → chat
2. **Azure Portal** — VM `vmlinux01` → Monitoring → Metrics → "Percentage CPU" chart (set to last 30 min)

---

## The Demo

### What to say to the customer

> *"Let me show you what happens when a VM has high CPU. I've got a Linux VM running in Azure — let's say we got an alert. Watch what the agent does with just a simple question."*

### Prompt to paste

```
My VM vmlinux01 in resource group rg-sre-demo-eastus2 seems to have high CPU. Can you investigate?
```

### What the agent does (narrate this)

The agent will work through these steps autonomously. Let it run — point out each step as it happens:

| Step | What the agent does | What to tell the customer |
|------|---------------------|---------------------------|
| 1 | `az vm show` — identifies the VM, OS type (Linux), and SKU | *"It first identifies the VM and checks what OS it's running — it needs to know whether to use Linux or Windows commands."* |
| 2 | `az monitor metrics list` — checks Azure-level CPU percentage | *"Now it's pulling the Azure Monitor metrics to understand the CPU trend — when it started, how severe it is."* |
| 3 | `az vm run-command invoke` — runs `ps aux --sort=-%cpu` inside the VM | *"This is the key part — it's actually running commands inside the VM to find the top CPU-consuming processes."* |
| 4 | Identifies `stress-ng` as the culprit | *"It found it — stress-ng is consuming all the CPU. In a real scenario, this would be your runaway process, a crypto miner, or a misconfigured service."* |
| 5 | Checks Activity Log for recent changes | *"It also checks for recent deployments or changes that might correlate with the spike."* |
| 6 | Produces a structured report with severity, evidence, and recommendations | *"And here's the report — root cause, evidence with actual numbers, and specific next steps. This is what your on-call engineer gets at 3 AM instead of having to figure it out themselves."* |

### Expected output (example)

The agent should produce something like:

```
## High CPU Investigation Report

**VM**: vmlinux01
**Resource Group**: rg-sre-demo-eastus2
**OS**: Linux (Ubuntu 24.04)
**VM Size**: Standard_D2s_v5

### Root Cause
The process `stress-ng` (multiple worker processes) is consuming 100% of all
available CPU cores. This is a synthetic load generator, not a production workload.

### Evidence
- CPU utilization: 98-100% sustained over the last 3 minutes
- Top process: stress-ng (PID 1234) — 4 worker threads, each at ~100% CPU
- No recent deployments or changes in Activity Log

### Recommended Actions
1. Kill the stress-ng process: `kill -9 <PID>` or `killall stress-ng`
2. Investigate who/what started stress-ng — check cron jobs and recent SSH sessions
3. If this is expected (load testing), no action needed — it will self-terminate
```

---

## Talking points

Use these when the customer reacts:

| Customer says | Your response |
|---------------|---------------|
| *"How did it know to run those commands?"* | *"The agent has a skill loaded — a structured troubleshooting procedure that encodes your team's best practices. It follows your playbook, not a generic one."* |
| *"Could it actually fix the issue?"* | *"Yes — if you give it write permissions and a remediation skill, it can restart services, scale VMs, or execute any approved action. Hooks control what it's allowed to do."* |
| *"What if the VM agent is down?"* | *"The skill checks VM agent health first. If run-command won't work, it falls back to Azure Monitor metrics and boot diagnostics."* |
| *"Does it work on Windows?"* | *"Same skill handles both — it detects the OS first, then uses PowerShell or bash commands accordingly."* |

---

## If something goes wrong

| Problem | Fix |
|---------|-----|
| Agent doesn't activate the skill | Try: *"Use the high-cpu-vm-troubleshooting skill to investigate vmlinux01 in rg-sre-demo-eastus2"* |
| CPU isn't showing as high in metrics | Wait 2–3 more minutes — Azure Monitor needs time to ingest. Or re-run the stress command. |
| Run-command times out | The VM agent might be overloaded. Say: *"Even the agent times out sometimes — just like a human operator would. It retries or falls back to metrics-only analysis."* |
| stress-ng already finished | Re-trigger it: run the stress command from Step 2 again. |

---

## Cleanup

```bash
# Stop stress-ng (it auto-stops after 5 min, but just in case)
az vm run-command invoke \
    --resource-group rg-sre-demo-eastus2 \
    --name vmlinux01 \
    --command-id RunShellScript \
    --scripts "killall stress-ng 2>/dev/null; echo 'stress-ng stopped'"

# If you're done with all demos, delete the VM:
az vm delete --resource-group rg-sre-demo-eastus2 --name vmlinux01 --yes --no-wait

# Or delete the entire demo resource group:
az group delete --name rg-sre-demo-eastus2 --yes --no-wait
```
