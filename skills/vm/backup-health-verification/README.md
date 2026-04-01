# Backup Health Verification — Testing Guide

## What this skill does
Verifies Azure Backup configuration across VMs — checks if backup is configured, validates recovery point freshness, identifies failed backup jobs. This is a read-only diagnostic skill that only needs RunAzCliReadCommands.

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
- The backup-health-verification skill added to your Azure SRE Agent

## Deploy a test VM

```bash
az group create --name rg-sre-demo-<region> --location <region> --subscription <your-subscription-id>

# Create a VM WITHOUT backup configured — this is the demo scenario
az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-nobackup \
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

### Optional: Create a second VM WITH backup (for contrast)

```bash
# Create another VM
az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-backed-up \
  --image Ubuntu2404 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-address "" \
  --vnet-name <your-vnet-name> \
  --subnet <your-subnet-name> \
  --nsg "" \
  --subscription <your-subscription-id>

# Create a Recovery Services Vault and enable backup
az backup vault create \
  --resource-group rg-sre-demo-<region> \
  --name rsv-sre-demo \
  --location <region> \
  --subscription <your-subscription-id>

az backup protection enable-for-vm \
  --resource-group rg-sre-demo-<region> \
  --vault-name rsv-sre-demo \
  --vm vm-sre-demo-backed-up \
  --policy-name DefaultPolicy \
  --subscription <your-subscription-id>
```

> Wait for the initial backup to complete (or fail), which gives the agent more to report on.

## Try the skill

### Prompt:
> "Can you check the backup health of VMs in `rg-sre-demo-<region>`? I want to make sure everything is properly backed up."

### Expected agent behavior:
1. Lists all VMs in the resource group
2. Lists Recovery Services Vaults in the subscription
3. For each VM, checks if Azure Backup is configured
4. For backed-up VMs: checks latest recovery point age and backup job status
5. Flags `vm-sre-demo-nobackup` as having NO backup configured
6. Produces a backup health report with recommendations

### What to expect:
- "Are my VMs backed up?" is a question every ops team dreads
- Finding a VM with NO backup is a very clear and impactful finding
- Having one backed-up and one not shows the contrast
- The agent checks real Azure Backup data, not just guessing

## Cleanup

```bash
# Disable backup protection (deletes backup data)
az backup protection disable \
  --resource-group rg-sre-demo-<region> \
  --vault-name rsv-sre-demo \
  --container-name "IaasVMContainer;iaasvmcontainerv2;rg-sre-demo-<region>;vm-sre-demo-backed-up" \
  --item-name "VM;iaasvmcontainerv2;rg-sre-demo-<region>;vm-sre-demo-backed-up" \
  --delete-backup-data true --yes \
  --subscription <your-subscription-id>

# Delete vault
az backup vault delete \
  --resource-group rg-sre-demo-<region> \
  --name rsv-sre-demo --yes \
  --subscription <your-subscription-id>

# Delete VMs
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-nobackup --yes --subscription <your-subscription-id>
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-backed-up --yes --subscription <your-subscription-id>
```
