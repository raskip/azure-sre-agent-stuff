# Service Crash Loop Detection — Testing Guide

## What this skill does
Investigates services that keep crashing and restarting on Azure VMs. Reads systemd journal (Linux) or Windows Event Log, identifies crash patterns, exit codes, and correlates with resource pressure. Supports Linux and Windows.

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
- The service-crash-loop-detection skill added to your Azure SRE Agent

## Deploy a test VM

```bash
az group create --name rg-sre-demo-<region> --location <region> --subscription <your-subscription-id>

az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-crash \
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

Connect via Bastion and create a crashing service:

```bash
# Create the crashing application script
sudo tee /opt/crashy-app.sh << 'SCRIPT'
#!/bin/bash
echo "Starting crashy-app at $(date)"
sleep 5
echo "FATAL: Segmentation fault (simulated)" >&2
exit 139
SCRIPT
sudo chmod +x /opt/crashy-app.sh

# Create the systemd service unit
sudo tee /etc/systemd/system/crashy-app.service << 'UNIT'
[Unit]
Description=Crashy Demo Application
After=network.target

[Service]
Type=simple
ExecStart=/opt/crashy-app.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

# Enable and start the crashing service
sudo systemctl daemon-reload
sudo systemctl enable --now crashy-app.service
```

Wait **30+ seconds** for several crash cycles to accumulate in the journal. Verify with:
```bash
journalctl -u crashy-app --no-pager -n 20
```

## Try the skill

### Prompt:
> "The `crashy-app` service on `vm-sre-demo-crash` in `rg-sre-demo-<region>` keeps restarting. Can you figure out what's wrong?"

### Expected agent behavior:
1. Checks `systemctl status crashy-app` via run-command
2. Reads `journalctl -u crashy-app --no-pager -n 100` for recent logs
3. Identifies the crash pattern: exit code 139 = segmentation fault
4. Checks for core dumps
5. Correlates with resource pressure (CPU, memory, disk)
6. Produces a report: crash timeline, error messages, exit code analysis, root cause

### What to expect:
- Service crash loops are a daily reality for VM operators
- The agent reads logs intelligently and interprets exit codes
- Exit code 139 (SIGSEGV) is a realistic and recognizable error

## Cleanup

```bash
# Remove the crashing service
az vm run-command invoke --resource-group rg-sre-demo-<region> --name vm-sre-demo-crash --command-id RunShellScript --scripts "sudo systemctl disable --now crashy-app.service; sudo rm -f /etc/systemd/system/crashy-app.service /opt/crashy-app.sh; sudo systemctl daemon-reload; echo done" --subscription <your-subscription-id>

# Delete the VM
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-crash --yes --subscription <your-subscription-id>
```
