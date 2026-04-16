# Scenario 03 — Cost Optimization: VM Right-Sizing

> **Duration:** 10 minutes | **Skill:** `vm-right-sizing` | **Impact:** Very high — cost savings resonate with everyone

---

## Goal

Show the agent analyzing real VM utilization data and recommending a smaller, cheaper SKU — with calculated savings. This is the **business value** scenario: the agent literally pays for itself by finding waste.

**Why this works:** Every organization has oversized VMs. Showing the agent find one with actual numbers and estimated savings makes the ROI conversation trivial. This is the demo that gets budget approval.

---

## Setup (do this 1–2 hours before the demo)

### Step 1: Deploy an oversized VM

The VM must be running for at least 30–60 minutes before the demo so Azure Monitor has enough metric data points.

```bash
# Create resource group (skip if it already exists from Scenario 01)
az group create --name rg-sre-demo-eastus2 --location eastus2

# Deploy a deliberately oversized VM — D4s_v5 = 4 vCPUs, 16 GB RAM
az vm create \
    --resource-group rg-sre-demo-eastus2 \
    --name vm-oversized \
    --image Ubuntu2404 \
    --size Standard_D4s_v5 \
    --admin-username azureuser \
    --generate-ssh-keys \
    --public-ip-address ""
```

### Step 2 (optional): Add a light workload for realism

An idle VM is a fine demo, but a light workload makes it more realistic:

```bash
az vm run-command invoke \
    --resource-group rg-sre-demo-eastus2 \
    --name vm-oversized \
    --command-id RunShellScript \
    --scripts "apt-get update -qq && apt-get install -y -qq nginx > /dev/null 2>&1 && systemctl start nginx && echo 'nginx running'"
```

This gives the VM a tiny workload (~1–3% CPU) — a 4-vCPU machine running nginx is the classic "oversized for its workload" pattern.

### Step 3: Verify Azure Monitor has data

```bash
# Linux (GNU date)
az monitor metrics list \
    --resource $(az vm show --resource-group rg-sre-demo-eastus2 --name vm-oversized --query id -o tsv) \
    --metric "Percentage CPU" \
    --aggregation Average \
    --interval PT5M \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --query "value[0].timeseries[0].data[-5:].{time:timeStamp, avg:average}" \
    -o table
```

> **macOS / BSD alternative** (replace the two `date` lines; `-v -1H` = subtract 1 hour):
> ```bash
> # --start-time $(date -u -v -1H +%Y-%m-%dT%H:%M:%SZ)
> # --end-time   $(date -u +%Y-%m-%dT%H:%M:%SZ)
> ```

You should see CPU averages well below 10%. If you see no data, wait longer.

> **PowerShell alternative** (Windows):
> ```powershell
> $start = (Get-Date).AddHours(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
> $end = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
> az monitor metrics list --resource $(az vm show --resource-group rg-sre-demo-eastus2 --name vm-oversized --query id -o tsv) --metric "Percentage CPU" --aggregation Average --interval PT5M --start-time $start --end-time $end -o table
> ```

---

## The Demo

### What to say to the customer

> *"Now let me show you the business value side. Every organization has VMs that are bigger than they need to be — you deployed a D4 for a workload that only needs a D2. Let's see if the agent can find savings."*

### Prompt to paste

```
Can you check if VM vm-oversized in rg-sre-demo-eastus2 is right-sized for its workload?
```

### What the agent does (narrate this)

| Step | What the agent does | What to tell the customer |
|------|---------------------|---------------------------|
| 1 | `az vm show` — gets current SKU (Standard_D4s_v5: 4 vCPUs, 16 GB) | *"It starts by understanding what we're working with — 4 vCPUs, 16 GB of RAM."* |
| 2 | `az vm list-sizes` — looks up SKU capabilities | *"It checks the SKU specs so it knows the baseline."* |
| 3 | `az monitor metrics list` — pulls 7-day CPU utilization | *"Now it's pulling a week of CPU data — average, max, P95. This is what matters for right-sizing."* |
| 4 | `az vm run-command invoke` — checks memory usage inside the VM | *"It's also checking memory utilization from inside the VM."* |
| 5 | Analyzes: avg CPU ~3%, max CPU ~15%, memory usage ~8% | *"Look at these numbers — 3% average CPU, 8% memory usage on a 4-vCPU machine. This VM is massively over-provisioned."* |
| 6 | Recommends downsize: D4s_v5 → D2s_v5 (or B2s) | *"The recommendation: drop from D4 to D2 — same family, half the cost. Still has plenty of headroom."* |
| 7 | Produces report with cost estimate and migration steps | *"And here's the full report — current vs. recommended, estimated monthly savings, and exact resize commands."* |

### Expected output (example)

```
## VM Right-Sizing Report

**VM**: vm-oversized
**Resource Group**: rg-sre-demo-eastus2
**OS**: Linux (Ubuntu 24.04)
**Location**: eastus2
**Analysis Period**: Last 7 days

### Current Configuration
- **Current SKU**: Standard_D4s_v5 (4 vCPUs, 16 GB RAM)
- **Data Disks**: 0

### Utilization Summary
| Metric       | Average | Max   | P95   |
|-------------|---------|-------|-------|
| CPU (%)      | 2.8     | 14.3  | 8.1   |
| Memory (%)   | 7.5     | 12.0  | —     |

### Recommendation
- **Recommended SKU**: Standard_D2s_v5 (2 vCPUs, 8 GB RAM)
- **Justification**: CPU averages 2.8% with a P95 of 8.1%. Memory usage
  is 7.5%. The workload fits comfortably in a D2s_v5 with significant headroom.
- **Estimated Monthly Savings**: ~$70/month (~50% reduction)

### Migration Steps
1. Schedule a maintenance window (resize requires brief downtime)
2. `az vm deallocate --resource-group rg-sre-demo-eastus2 --name vm-oversized`
3. `az vm resize --resource-group rg-sre-demo-eastus2 --name vm-oversized --size Standard_D2s_v5`
4. `az vm start --resource-group rg-sre-demo-eastus2 --name vm-oversized`
5. Monitor for 24–48 hours after resize
```

---

## Talking points

| Point | What to say |
|-------|-------------|
| **ROI** | *"This pays for itself. Every VM the agent analyzes either saves money or confirms it's right-sized. Multiply that across hundreds of VMs."* |
| **Data-driven** | *"Notice it didn't guess — it pulled 7 days of metric data, calculated averages and P95, and made a recommendation based on actual utilization."* |
| **Safe** | *"The agent recommends but doesn't act. It gives you the resize commands and says 'schedule a maintenance window.' The human decides."* |
| **Scalable** | *"You can run this across your entire fleet. Ask the agent to analyze every VM in a resource group, or integrate with Azure Advisor for automated recommendations."* |
| **Beyond VMs** | *"This same pattern works for any right-sizing: AKS node pools, App Service plans, database tiers. Encode the analysis logic in a skill."* |

---

## The money slide

If the customer asks about cost impact, here's a quick reference for common D-series downsizing (East US 2, Linux, pay-as-you-go):

| Current SKU | Recommended | Monthly savings (approx.) |
|-------------|-------------|---------------------------|
| D4s_v5 → D2s_v5 | 4 vCPU → 2 vCPU | ~$70/month |
| D8s_v5 → D4s_v5 | 8 vCPU → 4 vCPU | ~$140/month |
| D16s_v5 → D8s_v5 | 16 vCPU → 8 vCPU | ~$280/month |

> *"Now multiply that by the number of VMs in your environment. We've seen customers save 20–40% on compute costs just by right-sizing."*

---

## Common customer questions

| Question | Answer |
|----------|--------|
| *"What about auto-scaling workloads?"* | *"The agent looks at actual utilization patterns. If your workload auto-scales, the P95 will reflect peak demand. The recommendation accounts for burst."* |
| *"What if memory data isn't available?"* | *"Memory metrics require Azure Monitor Agent. If AMA isn't installed, the agent falls back to a point-in-time snapshot via run-command. It notes this limitation in the report."* |
| *"Can it resize automatically?"* | *"Yes, if you give it a remediation skill and write permissions. But we recommend keeping right-sizing advisory-only — the human schedules the maintenance window."* |
| *"How does this compare to Azure Advisor?"* | *"Azure Advisor gives you a list. The agent gives you the full analysis — why it's recommending the change, the data behind it, and the exact commands to execute. Plus it can analyze VMs that Advisor doesn't flag."* |

---

## If something goes wrong

| Problem | Fix |
|---------|-----|
| Agent says "insufficient data" | The VM hasn't been running long enough. You need at least 30 min of metrics, ideally 1–2 hours. |
| CPU shows higher than expected | Another process is running. Check with: `az vm run-command invoke --resource-group rg-sre-demo-eastus2 --name vm-oversized --command-id RunShellScript --scripts "ps aux --sort=-%cpu \| head -10"` |
| Agent doesn't use the skill | Try: *"Use the vm-right-sizing skill to analyze vm-oversized in rg-sre-demo-eastus2"* |

---

## Cleanup

```bash
# Delete the oversized VM
az vm delete --resource-group rg-sre-demo-eastus2 --name vm-oversized --yes --no-wait

# Or delete the entire demo resource group (removes all demo VMs)
az group delete --name rg-sre-demo-eastus2 --yes --no-wait
```
