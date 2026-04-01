---
name: high-cpu-vm-troubleshooting
description: >
  Troubleshooting procedure for high CPU usage on Azure Virtual Machines.
  Covers both Linux and Windows VMs. Use when a VM shows sustained high CPU,
  a CPU alert fires, or a user reports slow VM performance related to CPU.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

## When to use this skill

Use this skill when:
- A high CPU alert fires on an Azure VM
- A user reports a VM is slow and CPU is suspected
- Azure Monitor shows sustained CPU above 85% for more than 5 minutes

## Overview

This skill guides you through a structured investigation:
1. Identify the VM and determine its OS (Linux or Windows)
2. Check Azure-level metrics for context
3. Run OS-level diagnostics via `az vm run-command`
4. Correlate findings with recent changes
5. Produce a structured report

## Step 1: Identify the VM and its OS

Before running any commands, determine the target VM's details:

```
az vm show --resource-group {rg} --name {vm-name} --query "{os:storageProfile.osDisk.osType, size:hardwareProfile.vmSize, location:location}" -o json
```

This tells you whether to use Linux or Windows commands in the following steps.

## Step 2: Check Azure-level CPU metrics

Query Azure Monitor for the VM's CPU trend over the last hour. Use your built-in Kusto/metrics capabilities to check:
- `Percentage CPU` metric — is it sustained or spiky?
- When did the spike start?
- Does it correlate with any known deployment or scaling event?

This gives you a timeline before looking inside the VM.

## Step 3: OS-level diagnostics via Run Command

> **Important:** `az vm run-command invoke` is a **write operation** and requires the `RunAzCliWriteCommands` tool, not `RunAzCliReadCommands`.

### Pre-check: Verify VM Agent health

Before running any commands, confirm the VM agent is healthy. If the agent is unhealthy, Run Command will fail.

```
az vm get-instance-view --resource-group {rg} --name {vm-name} --query "instanceView.vmAgent.statuses[0]" -o json
```

If the agent status is not "Ready", do not proceed with Run Command. Instead, check VM boot diagnostics or serial console.

### Linux VMs

Based on the OS type from Step 1, run the appropriate commands.

**Top CPU-consuming processes:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "ps aux --sort=-%cpu | head -20"
```

**CPU breakdown per core:**

> **Note:** `mpstat` requires the `sysstat` package, which is not installed by default on many Linux distributions. The command below attempts `mpstat` first and falls back to parsing `/proc/stat` if unavailable.

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "mpstat -P ALL 1 3 2>/dev/null || cat /proc/stat | head -10"
```

**System load and memory pressure (which can cause CPU wait):**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "uptime && echo '---' && free -m && echo '---' && vmstat 1 3"
```

**Recent OOM killer activity or kernel issues:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "dmesg -T --level=err,warn | tail -30"
```

**Check for runaway cron jobs or recently started services:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "systemctl list-units --state=running --type=service --no-pager && echo '---' && ls -lt /var/log/cron* 2>/dev/null | head -5"
```

### Windows VMs

Run these commands to identify what is consuming CPU:

**Top CPU-consuming processes:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Process | Sort-Object CPU -Descending | Select-Object -First 20 Name, Id, CPU, WorkingSet64 | Format-Table -AutoSize"
```

**CPU usage per core:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Counter '\\Processor(*)\\% Processor Time' | Select-Object -ExpandProperty CounterSamples | Sort-Object CookedValue -Descending | Format-Table InstanceName, CookedValue -AutoSize"
```

**System uptime and recent reboots:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime; Get-EventLog -LogName System -EntryType Information -Source 'EventLog' -Newest 5 | Format-Table TimeGenerated, Message -AutoSize"
```

**Check for high-CPU services and scheduled tasks:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Service | Where-Object {$_.Status -eq 'Running'} | Select-Object Name, DisplayName | Format-Table -AutoSize; Get-ScheduledTask | Where-Object {$_.State -eq 'Running'} | Select-Object TaskName, TaskPath | Format-Table -AutoSize"
```

**Recent application errors in Event Log:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-EventLog -LogName Application -EntryType Error -Newest 10 | Format-Table TimeGenerated, Source, Message -Wrap"
```

## Step 4: Correlate with recent changes

Check the Azure Activity Log for recent operations on the VM or its resource group:

```
az monitor activity-log list --resource-group {rg} --offset 24h --query "[?contains(to_lower(resourceId), to_lower('{vm-name}'))].{time:eventTimestamp, op:operationName.localizedValue, status:status.localizedValue, caller:caller}" -o table
```

Look for:
- Recent deployments or extensions installed
- VM resizing events
- Disk or network changes
- Any failed operations

## Step 5: Produce structured report

After gathering evidence, produce a report in this format:

```
## High CPU Investigation Report

**VM**: {vm-name}
**Resource Group**: {rg}
**OS**: {Linux/Windows}
**VM Size**: {size}
**Investigation Time**: {timestamp}

### Timeline
- CPU spike started: {time}
- Current CPU: {percentage}%
- Duration: {duration}

### Root Cause
{Description of what is consuming CPU and why}

### Evidence
- Top process: {process-name} (PID {pid}) using {cpu}% CPU
- {Additional findings from commands above}

### Recommendation
{One of the following, with justification:}
- **No action needed** — transient spike, already resolving
- **Restart process** — {process} is runaway, safe to restart
- **Scale up VM** — workload legitimately needs more CPU ({current-size} → {recommended-size})
- **Investigate application** — {process} is misbehaving, needs application-level debugging
- **Rollback recent change** — CPU spike correlates with {change} at {time}

### Next Steps
{Specific actions the operator should take}
```

## Important notes

- **Run Command has a timeout of ~90 seconds** — if a command hangs, it will fail. The commands above are designed to complete quickly.
- **Run Command executes as root/SYSTEM** — the commands have full access but treat this as read-only investigation.
- **Do NOT restart services or kill processes** unless the operator explicitly asks. This skill is diagnostic only.
