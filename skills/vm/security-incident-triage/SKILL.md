---
name: security-incident-triage
description: >
  Triage procedure for security incidents on Azure Virtual Machines.
  Covers both Linux and Windows VMs. Use when suspicious activity is reported,
  brute force attempts are detected, unauthorized access is suspected,
  unexpected processes are found, or a security alert fires.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

> ⚠️ **Example skill** — designed as a starting point. Test and customize for your environment.

## When to use this skill

Use this skill when:
- Suspicious activity is reported on an Azure VM
- Brute force login attempts are detected or suspected
- Unauthorized access to a VM is suspected
- Unexpected or unknown processes are observed running on a VM
- A security alert fires from Microsoft Defender for Cloud or Azure Monitor

## Overview

This skill guides you through a structured security triage:
1. Identify the VM and determine its OS (Linux or Windows)
2. Run OS-level security checks via `az vm run-command`
3. Perform Azure-level security checks (NSGs, Activity Log, public exposure)
4. Correlate findings and identify indicators of compromise (IOCs)
5. Produce a structured security triage report

## Step 1: Identify the VM and its OS

Before running any commands, determine the target VM's details:

```
az vm show --resource-group {rg} --name {vm-name} --query "{os:storageProfile.osDisk.osType, size:hardwareProfile.vmSize, location:location}" -o json
```

This tells you whether to use Linux or Windows commands in the following steps.

## Step 2: OS-level security checks via Run Command

> **Important:** `az vm run-command invoke` is a **write operation** and requires the `RunAzCliWriteCommands` tool, not `RunAzCliReadCommands`.

### Pre-check: Verify VM Agent health

Before running any commands, confirm the VM agent is healthy. If the agent is unhealthy, Run Command will fail.

```
az vm get-instance-view --resource-group {rg} --name {vm-name} --query "instanceView.vmAgent.statuses[0]" -o json
```

If the agent status is not "Ready", do not proceed with Run Command. Instead, check VM boot diagnostics or serial console.

### Linux VMs

Based on the OS type from Step 1, run the appropriate commands.

**Check failed login attempts:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "grep 'Failed password\|authentication failure' /var/log/auth.log 2>/dev/null | tail -30 || journalctl -u sshd --since '24 hours ago' --no-pager | grep -i 'failed\|invalid' | tail -30"
```

**Check successful logins:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "last -20 && echo '---WTMP---' && lastb 2>/dev/null | tail -20"
```

**Check currently logged in users:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "who && echo '---' && w"
```

**List unexpected listening ports:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "ss -tlnp"
```

**Check for suspicious processes:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "ps auxf | head -50"
```

**Check cron jobs (all users):**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "for user in \$(cut -f1 -d: /etc/passwd); do crontab -l -u \$user 2>/dev/null && echo \"---\$user---\"; done && cat /etc/crontab && ls -la /etc/cron.d/"
```

**Check recently modified system files:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "find /etc /usr/bin /usr/sbin -mtime -7 -type f 2>/dev/null | head -30"
```

**Check for unauthorized SSH keys:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "find /home -name authorized_keys -exec echo '--- {} ---' \; -exec cat {} \; 2>/dev/null && cat /root/.ssh/authorized_keys 2>/dev/null"
```

**Check sudo log:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "grep 'sudo' /var/log/auth.log 2>/dev/null | tail -20"
```

### Windows VMs

Run these commands to investigate security events:

**Check failed logon events:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625} -MaxEvents 30 | Format-Table TimeCreated, @{N='Account';E={$_.Properties[5].Value}}, @{N='Source';E={$_.Properties[19].Value}} -AutoSize"
```

**Check successful logons:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624} -MaxEvents 20 | Format-Table TimeCreated, @{N='Account';E={$_.Properties[5].Value}}, @{N='LogonType';E={$_.Properties[8].Value}} -AutoSize"
```

**Check listening ports:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-NetTCPConnection -State Listen | Select-Object LocalPort, OwningProcess, @{N='Process';E={(Get-Process -Id $_.OwningProcess).Name}} | Sort-Object LocalPort | Format-Table -AutoSize"
```

**Check scheduled tasks:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-ScheduledTask | Where-Object {$_.State -ne 'Disabled'} | Select-Object TaskName, TaskPath, State, @{N='Action';E={$_.Actions.Execute}} | Format-Table -AutoSize"
```

**Check for new local admins:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-LocalGroupMember -Group 'Administrators' | Format-Table Name, ObjectClass, PrincipalSource -AutoSize"
```

## Step 3: Azure-level security checks

These checks use `RunAzCliReadCommands` to inspect the Azure control plane for signs of compromise or misconfiguration.

**Review NSG flow logs for the VM's network interface:**
```
az network nsg list --resource-group {rg} --query "[].{name:name, rules:securityRules[?direction=='Inbound' && access=='Allow'].{port:destinationPortRange, source:sourceAddressPrefix, priority:priority}}" -o json
```

**Check Activity Log for suspicious operations (last 24 hours):**
```
az monitor activity-log list --resource-group {rg} --offset 24h --query "[].{time:eventTimestamp, op:operationName.localizedValue, status:status.localizedValue, caller:caller}" -o table
```

Look for:
- Unusual callers or service principals
- Role assignment changes (`Microsoft.Authorization/roleAssignments/write`)
- NSG rule modifications
- VM extension installations
- Password or key resets

**Check if the VM has a public IP exposed:**
```
az vm list-ip-addresses --resource-group {rg} --name {vm-name} -o json
```

If a public IP is present, verify that NSG rules are not overly permissive (e.g., allowing SSH/RDP from `*` or `0.0.0.0/0`).

## Step 4: Produce structured security triage report

After gathering evidence, produce a report in this format:

```
## Security Triage Report

**VM**: {vm-name}
**Resource Group**: {rg}
**OS**: {Linux/Windows}
**VM Size**: {size}
**Investigation Time**: {timestamp}

### Findings

| # | Finding | Severity | Evidence |
|---|---------|----------|----------|
| 1 | {description} | {Critical/High/Medium/Low} | {command output or log excerpt} |
| 2 | {description} | {Critical/High/Medium/Low} | {command output or log excerpt} |

### Indicators of Compromise (IOCs)
- **Suspicious IPs**: {list of source IPs from failed logins or connections}
- **Suspicious accounts**: {unauthorized or unknown user accounts}
- **Suspicious processes**: {unknown processes, crypto miners, reverse shells}
- **Suspicious files**: {recently modified system binaries, unauthorized SSH keys}
- **Suspicious scheduled tasks/cron**: {persistence mechanisms}

### Timeline
- First suspicious activity: {time}
- Most recent suspicious activity: {time}
- Investigation window: {duration}

### Recommendations
{One or more of the following, with justification:}
- **Isolate VM immediately** — active compromise confirmed, restrict NSG to block all inbound
- **Rotate credentials** — compromised accounts detected, reset passwords and SSH keys
- **Remove unauthorized access** — revoke unauthorized SSH keys, local admin accounts, or role assignments
- **Restrict NSG rules** — overly permissive rules exposing SSH/RDP to the internet
- **Enable MFA/JIT access** — VM is publicly accessible without just-in-time access controls
- **Capture forensic snapshot** — take OS disk snapshot before remediation for forensic analysis
- **No action needed** — alert is a false positive, activity is expected

### Next Steps
{Specific actions the operator should take, in priority order}
```

## Important notes

- **This skill is for investigation only.** Do NOT take remediation actions (kill processes, modify firewall rules, disable accounts, delete files) without explicit operator approval.
- **Preserve evidence.** Do not restart the VM, clear logs, or modify files during triage. If a disk snapshot is needed for forensics, recommend it before any changes.
- **Run Command has a timeout of ~90 seconds** — if a command hangs, it will fail. The commands above are designed to complete quickly.
- **Run Command executes as root/SYSTEM** — the commands have full access but treat this as read-only investigation.
- **Severity classification guide:**
  - **Critical**: Active compromise confirmed (unauthorized users logged in, malware running, data exfiltration in progress)
  - **High**: Strong indicators of compromise (brute force success, unauthorized SSH keys, unknown admin accounts)
  - **Medium**: Suspicious activity requiring further investigation (unusual login patterns, unexpected open ports)
  - **Low**: Minor configuration issues (overly permissive NSG rules with no evidence of exploitation)
