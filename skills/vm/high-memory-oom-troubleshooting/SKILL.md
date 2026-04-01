---
name: high-memory-oom-troubleshooting
description: >
  Troubleshooting procedure for high memory usage and OOM (Out of Memory) conditions
  on Azure Virtual Machines. Covers both Linux and Windows VMs. Use when a VM shows
  high memory utilization, OOM kills occur, swap pressure is elevated, or a user
  reports slow VM performance related to memory exhaustion.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

> ⚠️ **Example skill** — designed as a starting point. Test and customize for your environment.

## When to use this skill

Use this skill when:
- A high memory alert fires on an Azure VM
- OOM killer is terminating processes on a Linux VM
- A user reports a VM is slow and memory exhaustion is suspected
- Azure Monitor shows Available Memory Bytes dropping near zero
- Swap usage is abnormally high or swap pressure is reported
- Applications are crashing unexpectedly due to memory allocation failures

## Overview

This skill guides you through a structured investigation:
1. Identify the VM and determine its OS (Linux or Windows)
2. Check Azure-level memory metrics for context
3. Run OS-level diagnostics via `az vm run-command`
4. Correlate findings with recent changes
5. Produce a structured report

## Step 1: Identify the VM and its OS

Before running any commands, determine the target VM's details:

```
az vm show --resource-group {rg} --name {vm-name} --query "{os:storageProfile.osDisk.osType, size:hardwareProfile.vmSize, location:location}" -o json
```

This tells you whether to use Linux or Windows commands in the following steps.

## Step 2: Check Azure-level memory metrics

Query Azure Monitor for the VM's memory trend over the last hour. Use your built-in Kusto/metrics capabilities to check:
- `Available Memory Bytes` metric — is it steadily declining or did it drop suddenly?
- When did available memory start decreasing?
- Does the pattern correlate with any known deployment, scaling event, or workload change?

```
az monitor metrics list --resource-group {rg} --resource {vm-name} --resource-type Microsoft.Compute/virtualMachines --metric "Available Memory Bytes" --interval PT1M --start-time {start-time} --end-time {end-time} -o json
```

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

**Check memory usage overview:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "free -m && echo '---' && cat /proc/meminfo | head -20"
```

**Top memory-consuming processes:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "ps aux --sort=-%mem | head -20"
```

**Check swap usage:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "swapon --show && echo '---' && vmstat 1 3"
```

**Check OOM killer activity:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "dmesg -T | grep -i 'oom\|out of memory\|killed process' | tail -30"
```

**Check memory pressure over time:**

> **Note:** `sar` requires the `sysstat` package, which is not installed by default on many Linux distributions. The command below attempts `sar` first and falls back to `/proc/meminfo` if unavailable.

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "sar -r 1 5 2>/dev/null || cat /proc/meminfo"
```

**Check for memory leaks (growing RSS):**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "ps -eo pid,ppid,rss,vsz,comm --sort=-rss | head -20"
```

**Check cgroup memory limits:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null && echo '---' && cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || echo 'cgroup v1 memory controller not available'"
```

### Windows VMs

Run these commands to identify what is consuming memory:

**Top memory-consuming processes:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 Name, Id, @{N='MemMB';E={[math]::Round($_.WorkingSet64/1MB,1)}}, @{N='VMMB';E={[math]::Round($_.VirtualMemorySize64/1MB,1)}} | Format-Table -AutoSize"
```

**System memory overview:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-CimInstance Win32_OperatingSystem | Select-Object @{N='TotalGB';E={[math]::Round($_.TotalVisibleMemorySize/1MB,2)}}, @{N='FreeGB';E={[math]::Round($_.FreePhysicalMemory/1MB,2)}}, @{N='UsedPct';E={[math]::Round(($_.TotalVisibleMemorySize - $_.FreePhysicalMemory)/$_.TotalVisibleMemorySize * 100,1)}}"
```

**Page file usage:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-CimInstance Win32_PageFileUsage | Select-Object Name, @{N='AllocatedMB';E={$_.AllocatedBaseSize}}, @{N='UsedMB';E={$_.CurrentUsage}}"
```

**Recent memory-related events:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-EventLog -LogName System -EntryType Error,Warning -Newest 20 | Where-Object {$_.Message -match 'memory|resource exhaustion|pool'}"
```

## Step 4: Correlate with recent changes

Check the Azure Activity Log for recent operations on the VM or its resource group:

```
az monitor activity-log list --resource-group {rg} --offset 24h --query "[?contains(to_lower(resourceId), to_lower('{vm-name}'))].{time:eventTimestamp, op:operationName.localizedValue, status:status.localizedValue, caller:caller}" -o table
```

Look for:
- Recent deployments or extensions installed
- VM resizing events (especially downsizing which reduces available memory)
- Application updates that may have changed memory consumption patterns
- Any failed operations

## Step 5: Produce structured report

After gathering evidence, produce a report in this format:

```
## High Memory / OOM Investigation Report

**VM**: {vm-name}
**Resource Group**: {rg}
**OS**: {Linux/Windows}
**VM Size**: {size}
**Investigation Time**: {timestamp}

### Timeline
- Memory pressure started: {time}
- Current available memory: {available} MB / {total} MB ({used-pct}% used)
- Swap usage: {swap-used} MB / {swap-total} MB
- OOM kills detected: {yes/no, count if applicable}
- Duration: {duration}

### Root Cause
{Description of what is consuming memory and why}

### Evidence
- Top process: {process-name} (PID {pid}) using {mem} MB RSS
- OOM killer log: {relevant dmesg excerpt or "no OOM events found"}
- {Additional findings from commands above}

### Recommendation
{One of the following, with justification:}
- **No action needed** — transient spike, already resolving
- **Restart process** — {process} has a memory leak, safe to restart
- **Scale up VM** — workload legitimately needs more memory ({current-size} → {recommended-size})
- **Investigate application** — {process} is leaking memory, needs application-level profiling
- **Add or increase swap** — workload has occasional spikes that swap can absorb
- **Adjust cgroup/container limits** — memory limits are too restrictive for the workload
- **Rollback recent change** — memory spike correlates with {change} at {time}

### Next Steps
{Specific actions the operator should take}
```

## Important notes

- **Run Command has a timeout of ~90 seconds** — if a command hangs, it will fail. The commands above are designed to complete quickly.
- **Run Command executes as root/SYSTEM** — the commands have full access but treat this as read-only investigation.
- **Do NOT restart services or kill processes** unless the operator explicitly asks. This skill is diagnostic only.
- **OOM killer logs may be rotated** — if `dmesg` shows no OOM events but the issue is suspected, check `/var/log/syslog` or `/var/log/messages` for older entries.
- **Available Memory Bytes in Azure Monitor includes buffers/cache** — a low value here is more meaningful than what `free` shows under "used", since Linux aggressively uses free memory for caching.
