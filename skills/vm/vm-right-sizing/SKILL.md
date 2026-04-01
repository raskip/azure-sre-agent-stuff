---
name: vm-right-sizing
description: >
  Procedure for generating VM right-sizing recommendations on Azure Virtual Machines.
  Analyzes CPU, memory, disk, and network utilization to identify over-provisioned or
  under-provisioned VMs. Use when performing a cost optimization review, VM performance
  assessment, or when a user requests right-sizing guidance.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

> ⚠️ **Example skill** — designed as a starting point. Test and customize for your environment.

## When to use this skill

Use this skill when:
- A cost optimization review identifies potentially over-provisioned VMs
- A VM performance assessment is requested
- A user reports a VM may be over-provisioned or under-provisioned
- Azure Advisor flags a right-sizing recommendation
- A user requests a right-sizing analysis for one or more VMs

## Overview

This skill guides you through a structured right-sizing analysis:
1. Identify the VM and its current SKU
2. Retrieve current SKU capabilities
3. Collect CPU, memory, disk, and network utilization metrics
4. Analyze utilization against thresholds
5. Recommend a target SKU with justification
6. Produce a structured report with migration steps

## Step 1: Identify VM details

Retrieve the VM's current size, OS, location, and attached disks:

```
az vm show --resource-group {rg} --name {vm-name} --query "{size:hardwareProfile.vmSize, os:storageProfile.osDisk.osType, location:location, disks:storageProfile.dataDisks[].{name:name,sizeGB:diskSizeGb}}" -o json
```

Record the `size`, `os`, `location`, and number of data disks — these constrain which target SKUs are valid.

## Step 2: Get current VM SKU capabilities

Look up the current SKU's vCPU count, memory, and max data disk count:

```
az vm list-sizes --location {location} --query "[?name=='{current-size}'].{name:name, vCPUs:numberOfCores, memoryGB:memoryInMb, maxDataDisks:maxDataDiskCount}" -o table
```

Note: `memoryInMb` is in megabytes. Divide by 1024 for GB.

## Step 3: Check Azure Monitor CPU metrics (last 7 days)

Query the VM's CPU utilization over the past 7 days to understand average, maximum, and P95 usage:

```
az monitor metrics list --resource {vm-resource-id} --metric "Percentage CPU" --aggregation Average Maximum --interval PT1H --start-time {7-days-ago} --end-time {now}
```

From the returned time series:
- Calculate the **average** across all hourly data points
- Identify the **maximum** value (peak)
- Calculate the **P95** by sorting values and taking the 95th percentile

This is the most important signal for right-sizing decisions.

## Step 4: Check memory utilization (requires Azure Monitor Agent)

Memory metrics are not available by default — they require the Azure Monitor Agent (AMA) and VM Insights.

**If AMA / VM Insights is enabled**, query Log Analytics:

```
az monitor log-analytics query --workspace {workspace-id} --analytics-query "InsightsMetrics | where Name == 'AvailableMB' | where _ResourceId contains '{vm-name}' | where TimeGenerated > ago(7d) | summarize AvgAvailableMB=avg(Val), MinAvailableMB=min(Val) by bin(TimeGenerated, 1h) | order by TimeGenerated desc" --timespan P7D
```

Compare `AvailableMB` against total memory to derive utilization percentage.

**If AMA is not installed**, use Run Command to check current memory:

> **Important:** `az vm run-command invoke` is a **write operation** and requires the `RunAzCliWriteCommands` tool.

For **Linux** VMs:
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "free -m"
```

For **Windows** VMs:
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize, FreePhysicalMemory | Format-Table -AutoSize"
```

Note: Run Command gives a point-in-time snapshot only. Prefer AMA data for trend analysis.

## Step 5: Check disk IOPS and throughput

Query disk performance metrics to ensure the target SKU supports the workload's I/O requirements:

```
az monitor metrics list --resource {disk-resource-id} --metric "Composite Disk Read Operations/sec" "Composite Disk Write Operations/sec" --aggregation Average Maximum --interval PT1H --start-time {7-days-ago} --end-time {now}
```

Also check throughput if available:

```
az monitor metrics list --resource {disk-resource-id} --metric "Composite Disk Read Bytes/sec" "Composite Disk Write Bytes/sec" --aggregation Average Maximum --interval PT1H --start-time {7-days-ago} --end-time {now}
```

Compare peak IOPS and throughput against the target SKU's limits.

## Step 6: Check network utilization

Query network traffic to ensure the target SKU supports the workload's bandwidth requirements:

```
az monitor metrics list --resource {vm-resource-id} --metric "Network In Total" "Network Out Total" --aggregation Total --interval PT1H --start-time {7-days-ago} --end-time {now}
```

High network throughput may require SKUs that support accelerated networking or higher bandwidth tiers.

## Step 7: Analyze and recommend

Apply the following decision matrix to the collected metrics:

| Condition | Interpretation | Action |
|---|---|---|
| Avg CPU < 20% AND Max CPU < 50% | Over-provisioned | Recommend smaller SKU |
| Avg CPU 20–80% AND P95 CPU < 90% | Appropriately sized | No change needed |
| Avg CPU > 80% OR P95 CPU > 90% | Under-provisioned | Recommend larger SKU |
| Memory usage consistently > 85% | Memory-constrained | Recommend memory-optimized family (e.g., E-series) |
| Memory usage consistently < 30% | Memory over-provisioned | Recommend general-purpose or compute-optimized family |
| Disk IOPS near SKU limits | I/O-constrained | Recommend storage-optimized family or Premium SSD |
| Network throughput near SKU limits | Network-constrained | Recommend higher-bandwidth SKU with accelerated networking |

When multiple signals conflict (e.g., CPU is low but memory is high), prioritize the bottleneck resource and recommend a family that addresses it.

## Step 8: Find recommended SKUs

Search for candidate SKUs in the same region that meet the workload's requirements:

```
az vm list-sizes --location {location} --query "[?numberOfCores >= {min-vcpus} && numberOfCores <= {max-vcpus} && memoryInMb >= {min-mem}] | sort_by(@, &memoryInMb)" -o table
```

Ensure the candidate SKU:
- Has enough `maxDataDiskCount` for attached disks
- Supports accelerated networking if currently enabled
- Is available in the VM's region
- Belongs to an appropriate family (D-series for general purpose, E-series for memory-optimized, F-series for compute-optimized)

## Step 9: Get pricing comparison

Direct pricing comparison via the Azure CLI is limited. For cost estimates:
- Check **Azure Advisor** for right-sizing recommendations with estimated savings
- Use the **Azure Pricing Calculator** (https://azure.microsoft.com/pricing/calculator/) for side-by-side SKU comparison
- Query Azure Retail Prices API if programmatic pricing is needed

```
az advisor recommendation list --query "[?category=='Cost' && contains(impactedField, 'Microsoft.Compute/virtualMachines')]" -o table
```

## Step 10: Produce structured report

After completing the analysis, produce a report in this format:

```
## VM Right-Sizing Report

**VM**: {vm-name}
**Resource Group**: {rg}
**OS**: {Linux/Windows}
**Location**: {location}
**Analysis Period**: Last 7 days
**Report Time**: {timestamp}

### Current Configuration
- **Current SKU**: {current-size}
- **vCPUs**: {vcpus}
- **Memory**: {memory-gb} GB
- **Data Disks**: {disk-count}

### Utilization Summary
| Metric | Average | Max | P95 |
|---|---|---|---|
| CPU (%) | {avg-cpu} | {max-cpu} | {p95-cpu} |
| Memory (%) | {avg-mem} | {max-mem} | — |
| Disk IOPS | {avg-iops} | {max-iops} | — |
| Network (MB/hr) | {avg-net} | {max-net} | — |

### Recommendation
- **Recommended SKU**: {recommended-size}
- **Justification**: {reason — e.g., "CPU avg 12%, max 38% over 7 days indicates significant over-provisioning. Memory usage avg 45% supports downsizing."}
- **Family Change**: {e.g., "D4s_v5 → D2s_v5 (same family, fewer vCPUs)" or "D4s_v5 → E4s_v5 (memory-optimized)"}

### Estimated Impact
- **Cost Change**: {estimated monthly savings or increase}
- **Performance Impact**: {e.g., "CPU headroom reduced from 88% to 60% avg — still adequate for observed workload"}

### Migration Steps
1. **Schedule a maintenance window** — VM resize requires deallocation (brief downtime)
2. Deallocate the VM:
   `az vm deallocate --resource-group {rg} --name {vm-name}`
3. Resize the VM:
   `az vm resize --resource-group {rg} --name {vm-name} --size {recommended-size}`
4. Start the VM:
   `az vm start --resource-group {rg} --name {vm-name}`
5. Verify the VM is running and application is healthy
6. Monitor metrics for 24–48 hours after resize to confirm stability

### Risks and Considerations
- VM resize requires deallocation — plan for {estimated-downtime} of downtime
- Verify the target SKU supports all attached disk types and counts
- Verify accelerated networking support on the target SKU if currently enabled
- If the VM is in an availability set, the target size must be available in the hardware cluster
- For VMs in a VMSS, use a rolling update policy instead of manual resize
- Temporary disk size may change between SKUs — do not store persistent data on temp disks
- Review application licenses that may be tied to vCPU count

### Next Steps
{Specific follow-up actions — e.g., "Monitor for 1 week after resize", "Repeat analysis for other VMs in the resource group"}
```

## Important notes

- **This skill is advisory only** — it produces recommendations but does not automatically resize VMs. Always get operator approval before making changes.
- **VM resize requires deallocation** — this means brief downtime. Always coordinate with the application owner and schedule a maintenance window.
- **Check disk compatibility** — some SKUs do not support Premium SSD or Ultra Disk. Verify before resizing.
- **Check accelerated networking support** — not all SKUs support accelerated networking. If the VM currently uses it, the target SKU must also support it.
- **Memory metrics require Azure Monitor Agent** — if AMA is not installed, memory analysis will be limited to a point-in-time snapshot via Run Command.
- **Run Command has a timeout of ~90 seconds** — the memory check commands above are designed to complete quickly.
- **Run Command executes as root/SYSTEM** — treat this as read-only investigation. Do not modify the VM via Run Command in this skill.
