# High Memory / OOM Troubleshooting — Testing Guide

## What this skill does
Diagnoses memory pressure, swap exhaustion, and OOM killer events on Azure VMs. Finds the memory-hogging process, OOM kill timeline, and recommends actions. Supports Linux and Windows.

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
- The high-memory-oom-troubleshooting skill added to your Azure SRE Agent

## Deploy a test VM

```bash
az group create --name rg-sre-demo-<region> --location <region> --subscription <your-subscription-id>

# Use D2s_v5 (8 GB RAM) — small enough to pressure easily
az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-memory \
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

Install stress-ng:
```bash
sudo apt-get update && sudo apt-get install -y stress-ng
```

### Scenario A: Memory pressure (safe, no OOM kill)
```bash
stress-ng --vm 2 --vm-bytes 80% --timeout 300s
```

### Scenario B: Trigger OOM kills (more dramatic for testing)
```bash
stress-ng --vm 4 --vm-bytes 95% --timeout 120s
```
This will likely trigger the Linux OOM killer, which will kill one or more stress-ng workers. Check with `dmesg | grep -i oom`.

> **Tip:** Scenario B is more impressive for testing because the agent finds actual OOM kill events in `dmesg`.

## Try the skill

### Prompt:
> "My VM `vm-sre-demo-memory` in `rg-sre-demo-<region>` is running out of memory. Processes are getting killed. Can you investigate?"

### Expected agent behavior:
1. Checks Azure Monitor memory metrics (if Azure Monitor Agent is installed) or uses `az vm run-command invoke` to run `free -h`
2. Runs `ps aux --sort=-%mem | head -20` to find memory-hogging processes
3. Checks `dmesg | grep -i oom` for OOM kill events
4. Checks swap usage and configuration
5. Produces a report: top memory consumers, OOM timeline, swap status, recommendations (restart process, add swap, scale up VM)

### What to expect:
- OOM kills are a very common and painful real-world scenario
- The agent correlates kernel-level OOM events with the guilty process
- Recommendations include both short-term (restart) and long-term (resize VM) actions

## Cleanup

```bash
# stress-ng stops automatically, or:
az vm run-command invoke --resource-group rg-sre-demo-<region> --name vm-sre-demo-memory --command-id RunShellScript --scripts "killall stress-ng 2>/dev/null; echo done" --subscription <your-subscription-id>

# Delete the VM
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-memory --yes --subscription <your-subscription-id>
```
