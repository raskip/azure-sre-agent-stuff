---
name: service-crash-loop-detection
description: >
  Detection and diagnosis procedure for services stuck in crash or restart loops
  on Azure Virtual Machines. Covers both Linux (systemd) and Windows VMs. Use when
  a service keeps crashing, is stuck in a systemd restart loop, an application won't
  stay up, or repeated restart events appear in the Event Log.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

> ⚠️ **Example skill** — designed as a starting point. Test and customize for your environment.

## When to use this skill

Use this skill when:
- A service keeps crashing and restarting on an Azure VM
- A systemd unit is stuck in a restart loop (active → failed → activating)
- An application process won't stay up and is being restarted by the init system
- The Windows Event Log shows repeated Service Control Manager errors for a service
- An alert fires indicating a service is flapping or unavailable

## Overview

This skill guides you through a structured investigation:
1. Identify the VM and determine its OS (Linux or Windows)
2. Discover which services are failing or restart-looping
3. Collect crash logs and error details for the affected service
4. Check resource pressure (disk, memory) that could cause crashes
5. Correlate with recent Azure-level changes
6. Produce a structured report

## Step 1: Identify the VM and its OS

Before running any commands, determine the target VM's details:

```
az vm show --resource-group {rg} --name {vm-name} --query "{os:storageProfile.osDisk.osType, size:hardwareProfile.vmSize, location:location}" -o json
```

This tells you whether to use Linux or Windows commands in the following steps.

## Step 2: Pre-check — Verify VM Agent health

Before running any commands, confirm the VM agent is healthy. If the agent is unhealthy, Run Command will fail.

```
az vm get-instance-view --resource-group {rg} --name {vm-name} --query "instanceView.vmAgent.statuses[0]" -o json
```

If the agent status is not "Ready", do not proceed with Run Command. Instead, check VM boot diagnostics or serial console.

## Step 3: OS-level diagnostics via Run Command

> **Important:** `az vm run-command invoke` is a **write operation** and requires the `RunAzCliWriteCommands` tool, not `RunAzCliReadCommands`.

### Linux VMs

Based on the OS type from Step 1, run the appropriate commands.

**List failed and restarting services:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "systemctl --failed && systemctl list-units --state=activating --no-pager"
```

**Check specific service status:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "systemctl status {service-name} --no-pager -l"
```

**Get recent journal logs for the service:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "journalctl -u {service-name} --since '1 hour ago' --no-pager | tail -100"
```

**Check restart count and timing:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "systemctl show {service-name} --property=NRestarts,ActiveEnterTimestamp,ActiveExitTimestamp,Result"
```

**Check for core dumps:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "coredumpctl list 2>/dev/null | tail -10"
```

**Check resource pressure (disk, memory) that could cause crashes:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "df -h && free -m && dmesg -T --level=err,warn | tail -20"
```

**Check for dependency services:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "systemctl list-dependencies {service-name} --no-pager"
```

### Windows VMs

Run these commands to identify crash-looping services:

**List recently stopped/failed services from Event Log:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-EventLog -LogName System -EntryType Error,Warning -Source 'Service Control Manager' -Newest 20 | Format-Table TimeGenerated, Message -Wrap"
```

**Check specific service status and process details:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Service {service-name} | Select-Object Name, Status, StartType; Get-CimInstance Win32_Service | Where-Object {$_.Name -eq '{service-name}'} | Select-Object ProcessId, ExitCode, StartMode"
```

**Application event log errors:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-EventLog -LogName Application -EntryType Error -Newest 20 | Format-Table TimeGenerated, Source, Message -Wrap"
```

**Check if process is crashing repeatedly (Windows Error Reporting events):**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1001,1002} -MaxEvents 20 | Format-Table TimeCreated, Message -Wrap"
```

**Check resource state (memory and disk):**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-CimInstance Win32_OperatingSystem | Select-Object FreePhysicalMemory, TotalVisibleMemorySize; Get-Volume | Where-Object {$_.DriveLetter} | Select-Object DriveLetter, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}}"
```

## Step 4: Correlate with recent changes

Check the Azure Activity Log for recent operations on the VM or its resource group:

```
az monitor activity-log list --resource-group {rg} --offset 24h --query "[?contains(to_lower(resourceId), to_lower('{vm-name}'))].{time:eventTimestamp, op:operationName.localizedValue, status:status.localizedValue, caller:caller}" -o table
```

Look for:
- Recent deployments or extensions installed
- Configuration changes to the VM or its dependencies
- VM resizing events that may have triggered a reboot
- Disk or network changes that could break service dependencies
- Any failed operations

## Step 5: Produce structured report

After gathering evidence, produce a report in this format:

```
## Service Crash Loop Investigation Report

**VM**: {vm-name}
**Resource Group**: {rg}
**OS**: {Linux/Windows}
**VM Size**: {size}
**Affected Service**: {service-name}
**Investigation Time**: {timestamp}

### Crash Timeline
- First crash observed: {time}
- Number of restarts: {count}
- Last restart attempt: {time}
- Current service status: {status}

### Log Excerpts
{Key error messages from journal/event log, trimmed to the relevant lines}

### Root Cause
{Description of why the service is crashing — e.g., missing dependency, out of memory,
configuration error, disk full, permission denied, segfault in application code}

### Evidence
- Service exit code: {exit-code}
- {Key log lines or error messages}
- {Resource state: disk usage, memory availability}
- {Correlation with recent changes if any}

### Recommendation
{One of the following, with justification:}
- **Fix configuration** — {service} is failing due to {config issue}, correct {file/setting}
- **Free disk space** — disk is {usage}% full, service cannot write to {path}
- **Increase memory** — service is being OOM-killed, consider scaling up from {current-size}
- **Restart dependency** — {dependency-service} is down, causing {service} to fail
- **Rollback recent change** — crash correlates with {change} at {time}
- **Investigate application** — crash is in application code, needs developer attention

### Next Steps
{Specific actions the operator should take}
```

## Important notes

- **Run Command has a timeout of ~90 seconds** — if a command hangs, it will fail. The commands above are designed to complete quickly.
- **Run Command executes as root/SYSTEM** — the commands have full access but treat this as read-only investigation.
- **Do NOT restart services or kill processes** unless the operator explicitly asks. This skill is diagnostic only.
- **Replace `{service-name}` with the actual service** — if the affected service is not known, start with the "list failed services" command to discover it.
