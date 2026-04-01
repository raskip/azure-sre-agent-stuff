# Disk Expansion — Testing Guide

## What this skill does

Expands OS and data disks on Azure VMs when space is running low. Takes a snapshot for safety, resizes the disk, and expands the filesystem. Supports Linux and Windows.

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
- The disk-expansion skill added to your Azure SRE Agent (see [main README](../../README.md))

## Deploy a test VM

```bash
# Create resource group (if not already created)
az group create \
  --name rg-sre-demo-<region> \
  --location <region> \
  --subscription <your-subscription-id>

# Create a Linux VM with a small OS disk (default 30GB)
az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-disk \
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

### Scenario A: OS disk full

Connect to the VM via Bastion and fill the OS disk:

```bash
sudo fallocate -l 24G /tmp/fill-disk.img
```

Verify: `df -h /` should show >90% used.

### Scenario B: Data disk full

First attach a small data disk:

```bash
az vm disk attach \
  --resource-group rg-sre-demo-<region> \
  --vm-name vm-sre-demo-disk \
  --name disk-sre-demo-data \
  --size-gb 32 \
  --sku StandardSSD_LRS \
  --new \
  --subscription <your-subscription-id>
```

Then on the VM:

```bash
sudo mkfs.ext4 /dev/sdc
sudo mkdir /mnt/data && sudo mount /dev/sdc /mnt/data
sudo fallocate -l 28G /mnt/data/fill-disk.img
```

## Try the skill

### Prompt for Scenario A:

> "The OS disk on `vm-sre-demo-disk` in `rg-sre-demo-<region>` is almost full. Can you expand it?"

### Prompt for Scenario B:

> "The data disk mounted at `/mnt/data` on `vm-sre-demo-disk` in `rg-sre-demo-<region>` is running out of space. Can you expand it?"

### Expected agent behavior:

1. Checks disk usage via `az vm run-command invoke` (running `df -h`)
2. Identifies the full disk and its current size
3. Asks the operator for the new size (e.g., 64 GB)
4. Takes a snapshot of the disk for safety
5. For OS disk: stop-deallocates the VM, expands disk, starts VM
6. For data disk: expands online (if supported by tier)
7. Expands the partition and filesystem inside the VM
8. Verifies the new size

## Cleanup

```bash
# Remove fill files (if VM still exists)
az vm run-command invoke \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-disk \
  --command-id RunShellScript \
  --scripts "sudo rm -f /tmp/fill-disk.img /mnt/data/fill-disk.img" \
  --subscription <your-subscription-id>

# Detach and delete data disk (Scenario B)
az vm disk detach \
  --resource-group rg-sre-demo-<region> \
  --vm-name vm-sre-demo-disk \
  --name disk-sre-demo-data \
  --subscription <your-subscription-id>

az disk delete \
  --name disk-sre-demo-data \
  --resource-group rg-sre-demo-<region> \
  --yes \
  --subscription <your-subscription-id>

# Delete any snapshots the agent created
az snapshot list \
  --resource-group rg-sre-demo-<region> \
  --query "[].name" -o tsv \
  --subscription <your-subscription-id>

# Delete the VM
az vm delete \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-disk \
  --yes \
  --subscription <your-subscription-id>

# Or delete the entire resource group to clean up everything
az group delete \
  --name rg-sre-demo-<region> \
  --yes --no-wait \
  --subscription <your-subscription-id>
```
