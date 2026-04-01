# VM Right-Sizing — Testing Guide

## What this skill does
Analyzes CPU, memory, disk, and network utilization over time to recommend the optimal VM SKU. Produces a right-sizing report with current vs. recommended size and estimated cost savings. This is an advisory (read-only) skill.

## Before you start

Replace the placeholder values in the commands below with your own environment details:

| Placeholder | Your value |
|-------------|-----------|
| `<your-subscription-id>` | Your Azure subscription ID |
| `<region>` | Your Azure region (e.g., `eastus2`, `swedencentral`) |
| `rg-sre-demo-<region>` | Your demo resource group name |
| `<your-vnet-name>` | Your VNet name (or omit `--vnet-name` and `--subnet` to use the default VNet) |
| `<your-subnet-name>` | Your subnet name |

## Prerequisites
- Azure CLI installed and logged in
- Access to subscription `<your-subscription-name>` (<your-subscription-id>)
- The vm-right-sizing skill added to your Azure SRE Agent

## Deploy a test VM

Deploy an **intentionally oversized** VM with a light workload:

```bash
az group create --name rg-sre-demo-<region> --location <region> --subscription <your-subscription-id>

# D4s_v5 = 4 vCPUs, 16 GB RAM — oversized for a light workload
az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-oversized \
  --image Ubuntu2404 \
  --size Standard_D4s_v5 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-address "" \
  --vnet-name <your-vnet-name> \
  --subnet <your-subnet-name> \
  --nsg "" \
  --subscription <your-subscription-id>
```

## Simulate the issue

This skill doesn't need a failure simulation — it analyzes utilization data. The "issue" is that the VM is **oversized** for its workload.

**Option A: Just let it idle** — a D4s_v5 doing nothing is already the perfect test case.

**Option B: Run a light workload** — more realistic:
```bash
# Install and run a simple nginx server (uses minimal resources)
sudo apt-get update && sudo apt-get install -y nginx
sudo systemctl start nginx
```

> **Important:** Let the VM run for at least **30 minutes** (preferably 1-2 hours) before running the demo so that Azure Monitor has enough metric data points to analyze.

## Try the skill

### Prompt:
> "Can you analyze the sizing of `vm-sre-demo-oversized` in `rg-sre-demo-<region>`? I want to know if it's the right size for its workload."

### Expected agent behavior:
1. Gets current VM size and SKU details (D4s_v5: 4 vCPUs, 16 GB)
2. Queries Azure Monitor for CPU, memory, disk IOPS, and network metrics over 24-72 hours
3. Analyzes utilization patterns (peak, average, P95)
4. Compares against smaller VM sizes
5. Produces a right-sizing report: current vs. recommended SKU, estimated monthly savings, migration steps

### What to expect:
- Cost optimization resonates with every customer, especially management
- Shows the agent analyzing real metrics, not just guessing
- The recommendation to downsize from D4s_v5 to D2s_v5 (or B2s for idle workloads) is clear and actionable
- Estimated cost savings make the value immediately tangible

## Cleanup

```bash
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-oversized --yes --subscription <your-subscription-id>
```
