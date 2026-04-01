# Disk IOPS Throttling — Testing Guide

## What this skill does
Investigates slow disk performance caused by IOPS or throughput throttling. Checks both **disk-level** limits (the disk SKU cap) and **VM-level** limits (the VM SKU's cached/uncached IOPS cap). Uses Azure Monitor metrics and OS-level IO stats. Supports Linux and Windows.

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
- The disk-iops-throttling skill added to your Azure SRE Agent

## Deploy a test VM

```bash
az group create --name rg-sre-demo-<region> --location <region> --subscription <your-subscription-id>

az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-iops \
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

### Attach a low-IOPS disk (Standard HDD = 500 IOPS — easy to saturate)

```bash
az vm disk attach \
  --resource-group rg-sre-demo-<region> \
  --vm-name vm-sre-demo-iops \
  --name disk-sre-demo-iops \
  --size-gb 32 \
  --sku Standard_LRS \
  --new \
  --subscription <your-subscription-id>
```

### Prepare the disk on the VM

Connect via Bastion:
```bash
sudo mkfs.ext4 /dev/sdc
sudo mkdir -p /mnt/iops-test && sudo mount /dev/sdc /mnt/iops-test
sudo apt-get update && sudo apt-get install -y fio sysstat
```

## Simulate the issue

```bash
# Generate high random IOPS to saturate the Standard HDD limit (500 IOPS)
sudo fio --name=iops-test \
  --directory=/mnt/iops-test \
  --rw=randwrite \
  --bs=4k \
  --direct=1 \
  --numjobs=4 \
  --iodepth=32 \
  --runtime=300 \
  --time_based \
  --size=1G
```

This generates thousands of IOPS against a disk that only supports 500 — throttling will be severe and visible in Azure Monitor within a few minutes.

## Try the skill

### Prompt:
> "The disk performance on `vm-sre-demo-iops` in `rg-sre-demo-<region>` is very slow. Writes to `/mnt/iops-test` are taking forever. Can you investigate?"

### Expected agent behavior:
1. Checks VM and disk configuration (size, SKU, IOPS limits)
2. Identifies the Standard_LRS disk with its 500 IOPS limit
3. Queries Azure Monitor disk metrics (Data Disk IOPS Consumed %, Throttled %)
4. Checks VM-level cached/uncached IOPS consumed percentages
5. Correlates VM-level limits (D2s_v5: 3,750 uncached IOPS) with disk-level limits
6. Runs `iostat` via run-command to see OS-level IO wait and queue depth
7. Identifies the bottleneck: Standard_LRS disk at 500 IOPS, being asked for much more
8. Produces a report: current IOPS limits, observed throttling, recommended disk SKU upgrade (e.g., Premium SSD P10 = 500 base + burst to 3,500)

### What to expect:
- Disk throttling is "invisible" — CPU and memory look fine, but the VM is slow
- The agent checks BOTH disk-level and VM-level limits (two different throttle points)
- Technical audiences love the depth of this analysis
- The recommendation is clear: upgrade disk SKU or enable bursting

## Cleanup

```bash
# Stop fio (if still running)
az vm run-command invoke --resource-group rg-sre-demo-<region> --name vm-sre-demo-iops --command-id RunShellScript --scripts "killall fio 2>/dev/null; sudo umount /mnt/iops-test 2>/dev/null; echo done" --subscription <your-subscription-id>

# Detach and delete the data disk
az vm disk detach --resource-group rg-sre-demo-<region> --vm-name vm-sre-demo-iops --name disk-sre-demo-iops --subscription <your-subscription-id>
az disk delete --name disk-sre-demo-iops --resource-group rg-sre-demo-<region> --yes --subscription <your-subscription-id>

# Delete the VM
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-iops --yes --subscription <your-subscription-id>
```
