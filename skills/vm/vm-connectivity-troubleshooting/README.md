# VM Connectivity Troubleshooting — Testing Guide

## What this skill does
Diagnoses SSH/RDP connectivity failures on Azure VMs. Systematically checks VM power state, NSG rules, effective routes, boot diagnostics, OS firewall, and service status. Supports Linux and Windows.

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
- The vm-connectivity-troubleshooting skill added to your Azure SRE Agent

## Deploy a test VM

```bash
az group create --name rg-sre-demo-<region> --location <region> --subscription <your-subscription-id>

az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-conn \
  --image Ubuntu2404 \
  --size Standard_D2s_v5 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-address "" \
  --vnet-name <your-vnet-name> \
  --subnet <your-subnet-name> \
  --nsg-rule SSH \
  --subscription <your-subscription-id>
```

> **Note:** This time we include `--nsg-rule SSH` so an NSG is created that we can manipulate. Connect via Bastion.

## Simulate the issue

### Scenario A: NSG blocking inbound traffic (Azure-level)
```bash
# Get the NSG name (created with the VM)
az network nsg list --resource-group rg-sre-demo-<region> --query "[].name" -o tsv --subscription <your-subscription-id>

# Add a deny-all inbound rule with highest priority
az network nsg rule create \
  --resource-group rg-sre-demo-<region> \
  --nsg-name vm-sre-demo-connNSG \
  --name DenyAllInbound \
  --priority 100 \
  --access Deny \
  --direction Inbound \
  --protocol "*" \
  --source-address-prefix "*" \
  --destination-port-range "*" \
  --subscription <your-subscription-id>
```

### Scenario B: SSH service stopped (OS-level)
Connect via Bastion first, then:
```bash
sudo systemctl stop sshd
```
> **Important:** Do this BEFORE testing. Bastion uses a different channel than SSH, so you can still connect via Bastion to set this up.

## Try the skill

### Prompt:
> "I can't connect to `vm-sre-demo-conn` in `rg-sre-demo-<region>`. SSH connections time out. Can you help?"

### Expected agent behavior:
1. Checks VM power state (should be running)
2. Checks VM agent health
3. Checks NIC configuration and IP addresses
4. Checks effective NSG rules — **Scenario A: finds the DenyAllInbound rule**
5. Checks effective routes
6. Checks boot diagnostics
7. If Scenario B: uses `az vm run-command invoke` to check sshd status — finds it stopped
8. Produces a connectivity diagnostic report with root cause and fix recommendation

### What to expect:
- "I can't connect to my VM" is the #1 support request
- Watching the agent systematically eliminate causes is very satisfying
- Two different scenarios show breadth (Azure-level vs OS-level)

## Cleanup

### Scenario A:
```bash
az network nsg rule delete --resource-group rg-sre-demo-<region> --nsg-name vm-sre-demo-connNSG --name DenyAllInbound --subscription <your-subscription-id>
```

### Scenario B:
```bash
az vm run-command invoke --resource-group rg-sre-demo-<region> --name vm-sre-demo-conn --command-id RunShellScript --scripts "sudo systemctl start sshd" --subscription <your-subscription-id>
```

### Full cleanup:
```bash
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-conn --yes --subscription <your-subscription-id>
```
