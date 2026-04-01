# High CPU VM Troubleshooting — Testing Guide

## What this skill does
Diagnoses high CPU usage on Azure VMs — identifies top processes, per-core breakdown, and correlates with Azure Monitor metrics. Supports Linux and Windows.

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
- The high-cpu-vm-troubleshooting skill added to your Azure SRE Agent

## Deploy a test VM

```bash
az group create --name rg-sre-demo-<region> --location <region> --subscription <your-subscription-id>

az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-cpu \
  --image Ubuntu2404 \
  --size Standard_D2s_v5 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-address "" \
  --vnet-name <your-vnet-name> \
  --subnet <your-subnet-name> \
  --nsg "" \
  --subscription <your-subscription-id>
```

> **Note:** If your VM has no public IP, use Azure Bastion or another private connectivity method to connect.

## Simulate the issue

Connect to the VM via Bastion and install stress-ng:
```bash
sudo apt-get update && sudo apt-get install -y stress-ng
```

Run CPU stress:
```bash
# Pin all CPUs at 100% for 5 minutes
stress-ng --cpu 0 --timeout 300s
```

For a more realistic scenario (gradual ramp):
```bash
# Start with 1 CPU worker, ramps up pressure
stress-ng --cpu 1 --cpu-load 90 --timeout 300s
```

## Try the skill

### Prompt:
> "My VM `vm-sre-demo-cpu` in resource group `rg-sre-demo-<region>` has high CPU usage. Can you investigate?"

### Expected agent behavior:
1. Checks Azure Monitor CPU percentage metrics via `az monitor metrics list`
2. Runs `top` or `ps aux --sort=-%cpu` via `az vm run-command invoke` to find the process
3. Identifies `stress-ng` as the CPU-hogging process
4. Checks per-CPU core breakdown
5. Correlates with recent Azure activity (deployments, extensions)
6. Produces a diagnostic report: top processes, timeline, CPU pattern, recommendations

### What to expect:
- The agent traces the exact process causing the issue
- Shows correlation between Azure-level metrics and OS-level diagnostics
- Recommendations are actionable (kill process, scale up, investigate root cause)

## Cleanup

```bash
# stress-ng stops automatically after 300s, or kill it manually:
az vm run-command invoke --resource-group rg-sre-demo-<region> --name vm-sre-demo-cpu --command-id RunShellScript --scripts "killall stress-ng 2>/dev/null; echo done" --subscription <your-subscription-id>

# Delete the VM
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-cpu --yes --subscription <your-subscription-id>

# Or delete entire resource group
az group delete --name rg-sre-demo-<region> --yes --no-wait --subscription <your-subscription-id>
```
