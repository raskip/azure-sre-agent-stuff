# VM Extension Failure Remediation — Testing Guide

## What this skill does
Diagnoses and fixes failed VM extensions (Custom Script Extension, Azure Monitor Agent, Dependency Agent, etc.). Reads extension status, checks logs inside the VM, removes failed extensions, and optionally reinstalls. Supports Linux and Windows.

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
- The vm-extension-failure-remediation skill added to your Azure SRE Agent

## Deploy a test VM

```bash
az group create --name rg-sre-demo-<region> --location <region> --subscription <your-subscription-id>

az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-ext \
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

## Simulate the issue

Install a Custom Script Extension with a script that intentionally fails:

```bash
az vm extension set \
  --resource-group rg-sre-demo-<region> \
  --vm-name vm-sre-demo-ext \
  --name CustomScript \
  --publisher Microsoft.Azure.Extensions \
  --version 2.1 \
  --settings '{"commandToExecute": "exit 1"}' \
  --subscription <your-subscription-id>
```

This creates an extension in a **failed** provisioning state. Verify:
```bash
az vm extension list --resource-group rg-sre-demo-<region> --vm-name vm-sre-demo-ext --query "[].{name:name, status:provisioningState}" -o table --subscription <your-subscription-id>
```

## Try the skill

### Prompt:
> "The VM extension on `vm-sre-demo-ext` in `rg-sre-demo-<region>` has failed. Can you investigate and fix it?"

### Expected agent behavior:
1. Lists all extensions on the VM via `az vm extension list`
2. Identifies the CustomScript extension in failed state
3. Gets detailed extension status with error message
4. Checks extension logs inside the VM (`/var/log/azure/custom-script/handler.log`)
5. Identifies the root cause: script exited with code 1
6. Offers to remove the failed extension
7. Asks operator if they want to reinstall with a corrected configuration
8. Produces a report with failure cause and remediation steps

### What to expect:
- Extension failures are a common operational headache during deployments
- The agent reads both Azure-level status AND OS-level extension logs
- Shows remediation capability (remove and reinstall)

## Cleanup

```bash
# Remove the failed extension
az vm extension delete \
  --resource-group rg-sre-demo-<region> \
  --vm-name vm-sre-demo-ext \
  --name CustomScript \
  --subscription <your-subscription-id>

# Delete the VM
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-ext --yes --subscription <your-subscription-id>
```
