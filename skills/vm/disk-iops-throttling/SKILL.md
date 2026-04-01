---
name: disk-iops-throttling
description: >
  Investigation procedure for disk IOPS and throughput throttling on Azure Virtual Machines.
  Covers both Linux and Windows VMs, Premium SSD, Standard SSD, and Ultra Disk configurations.
  Use when a VM shows slow disk performance, high IO wait, disk latency spikes, IOPS or
  throughput throttling, or when an application is slow but CPU and memory appear normal.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

> ⚠️ **Example skill** — designed as a starting point. Test and customize for your environment.

## When to use this skill

Use this skill when:
- A VM or application is experiencing slow disk performance
- High IO wait is observed on the VM
- Disk latency spikes are reported
- Azure Monitor shows IOPS or throughput consumed percentages near 100%
- An application is slow but CPU and memory utilization appear normal
- A user reports slow file operations, database performance degradation, or long boot times
- Disk throttling alerts fire in Azure Monitor

## Overview

This skill guides you through a structured investigation:
1. Identify the VM and its disk configuration
2. Get disk SKU and tier details for each attached disk
3. Determine VM-level IOPS and throughput limits
4. Check Azure Monitor disk metrics for throttling evidence
5. Run OS-level disk performance diagnostics
6. Determine the throttling source and produce a recommendation

## Step 1: Identify VM and disk configuration

Get the VM's size, OS type, and all attached disks:

```
az vm show --resource-group {rg} --name {vm-name} --query "{size:hardwareProfile.vmSize, os:storageProfile.osDisk.osType, osDisk:{name:storageProfile.osDisk.name, caching:storageProfile.osDisk.caching}, dataDisks:storageProfile.dataDisks[].{name:name, lun:lun, sizeGB:diskSizeGb, caching:caching}}" -o json
```

Note the VM size (needed for Step 3), OS type (determines commands in Step 5), and caching settings for each disk.

## Step 2: Get disk SKU and tier details

For each disk identified in Step 1, retrieve its performance limits:

```
az disk show --resource-group {rg} --name {disk-name} --query "{name:name, sizeGB:diskSizeGb, sku:sku.name, tier:tier, iops:diskIOPSReadWrite, throughputMBps:diskMBpsReadWrite, burstingEnabled:burstingEnabled}" -o json
```

Run this for the OS disk and every data disk. Record the `iops` and `throughputMBps` values — these are the per-disk limits you will compare against actual usage in Step 4.

## Step 3: Get VM size IOPS and throughput limits

Query the VM size capabilities for the VM's location:

```
az vm list-sizes --location {location} --query "[?name=='{vm-size}']" -o json
```

> **Note:** The `az vm list-sizes` output includes `maxDataDiskCount` and resource limits, but does **not** include the VM-level cached/uncached IOPS and throughput caps. These limits are critical for diagnosing VM-level throttling. Refer to the following common limits or consult the [Azure VM sizes documentation](https://learn.microsoft.com/azure/virtual-machines/sizes):
>
> | VM Size | Uncached IOPS | Uncached Throughput (MBps) | Cached IOPS | Cached Throughput (MBps) |
> |---------|--------------|---------------------------|-------------|--------------------------|
> | Standard_D2s_v3 | 3,200 | 48 | 4,000 | 100 |
> | Standard_D4s_v3 | 6,400 | 96 | 8,000 | 200 |
> | Standard_D8s_v3 | 12,800 | 192 | 16,000 | 400 |
> | Standard_D16s_v3 | 25,600 | 384 | 32,000 | 800 |
> | Standard_E4s_v3 | 6,400 | 96 | 8,000 | 200 |
> | Standard_E8s_v3 | 12,800 | 192 | 16,000 | 400 |
> | Standard_L8s_v2 | 6,400 | 160 | 8,000 | 200 |

## Step 4: Check Azure Monitor disk metrics

### Per-disk IOPS

```
az monitor metrics list --resource {disk-resource-id} --metric "Composite Disk Read Operations/sec" "Composite Disk Write Operations/sec" --aggregation Average Maximum --interval PT5M --start-time {1-hour-ago}
```

### Per-disk throughput

```
az monitor metrics list --resource {disk-resource-id} --metric "Composite Disk Read Bytes/sec" "Composite Disk Write Bytes/sec" --aggregation Average Maximum --interval PT5M --start-time {1-hour-ago}
```

### VM-level consumed IOPS percentage

```
az monitor metrics list --resource {vm-resource-id} --metric "VM Cached IOPS Consumed Percentage" "VM Uncached IOPS Consumed Percentage" --aggregation Average Maximum --interval PT5M --start-time {1-hour-ago}
```

### VM-level consumed bandwidth percentage

```
az monitor metrics list --resource {vm-resource-id} --metric "VM Cached Bandwidth Consumed Percentage" "VM Uncached Bandwidth Consumed Percentage" --aggregation Average Maximum --interval PT5M --start-time {1-hour-ago}
```

If consumed percentage metrics are consistently above 90%, throttling is occurring at that level.

## Step 5: Check OS-level disk performance

> **Important:** `az vm run-command invoke` is a **write operation** and requires the `RunAzCliWriteCommands` tool, not `RunAzCliReadCommands`.

### Linux VMs

**IO statistics and IO wait:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "iostat -xdm 1 3 2>/dev/null || cat /proc/diskstats && echo '---IOWAIT---' && vmstat 1 3"
```

Key indicators:
- **`%iowait`** in vmstat: High values (>20%) indicate processes are blocked waiting for disk IO
- **`await`** in iostat: Average time (ms) for IO requests to complete — values >20ms on SSD indicate throttling
- **`avgqu-sz`** in iostat: Average queue depth — high values mean requests are queuing behind throttle
- **`%util`** in iostat: Values near 100% indicate the disk is saturated

### Windows VMs

**Disk performance counters:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Counter '\PhysicalDisk(*)\Avg. Disk Queue Length', '\PhysicalDisk(*)\Disk Reads/sec', '\PhysicalDisk(*)\Disk Writes/sec', '\PhysicalDisk(*)\Avg. Disk sec/Read', '\PhysicalDisk(*)\Avg. Disk sec/Write' -SampleInterval 1 -MaxSamples 3 | Select-Object -ExpandProperty CounterSamples | Format-Table InstanceName, Path, CookedValue -AutoSize"
```

Key indicators:
- **Avg. Disk Queue Length** > 2 per spindle: IO is queuing
- **Avg. Disk sec/Read** or **Avg. Disk sec/Write** > 20ms on SSD: latency is elevated, likely throttled
- **Disk Reads/sec + Disk Writes/sec**: Compare total against the disk and VM IOPS limits from Steps 2–3

## Step 6: Determine throttling source

Use this decision tree to identify where throttling is occurring:

```
Is disk-level IOPS near disk tier limit?
├── YES → Disk-level IOPS throttling
│         → Upgrade disk SKU (e.g., P20 → P30) or enable on-demand bursting
│
Is disk-level throughput near disk tier limit?
├── YES → Disk-level throughput throttling
│         → Upgrade disk SKU or switch to Premium SSD v2 / Ultra Disk
│
Is VM Cached IOPS Consumed % > 90%?
├── YES → VM-level cached IOPS throttling
│         → Resize VM to a larger SKU with higher cached IOPS limits
│
Is VM Uncached IOPS Consumed % > 90%?
├── YES → VM-level uncached IOPS throttling
│         → Resize VM or move workloads to cached disks (ReadOnly caching)
│
Is VM Cached/Uncached Bandwidth Consumed % > 90%?
├── YES → VM-level throughput throttling
│         → Resize VM to a larger SKU with higher throughput limits
│
None of the above near limits?
└── Issue is not IOPS/throughput throttling
    → Investigate network, application-level locks, or other bottlenecks
```

### Additional recommendations

- **Caching**: Enable `ReadOnly` caching on data disks with read-heavy workloads. This uses the VM's local SSD as a read cache and can dramatically reduce throttling on the managed disk.
- **Premium SSD v2**: Supports independently configurable IOPS and throughput without changing disk size. Ideal when you need more IOPS without paying for larger capacity.
- **Ultra Disk**: Supports sub-millisecond latency and up to 160,000 IOPS per disk. Best for IO-intensive workloads (databases, transaction logs).
- **Disk striping**: If a single disk cannot meet requirements, stripe multiple disks using LVM (Linux) or Storage Spaces (Windows) to aggregate IOPS and throughput.

## Reference: Common Premium SSD IOPS and throughput limits

| Disk SKU | Size (GiB) | Provisioned IOPS | Provisioned Throughput (MBps) | Burst IOPS | Burst Throughput (MBps) |
|----------|-----------|------------------|-------------------------------|------------|-------------------------|
| P10      | 128       | 500              | 100                           | 3,500      | 170                     |
| P15      | 256       | 1,100            | 125                           | 3,500      | 170                     |
| P20      | 512       | 2,300            | 150                           | 3,500      | 170                     |
| P30      | 1,024     | 5,000            | 200                           | 30,000     | 1,000                   |
| P40      | 2,048     | 7,500            | 250                           | 30,000     | 1,000                   |
| P50      | 4,096     | 7,500            | 250                           | 30,000     | 1,000                   |
| P60      | 8,192     | 16,000           | 500                           | 30,000     | 1,000                   |
| P70      | 16,384    | 18,000           | 750                           | 30,000     | 1,000                   |
| P80      | 32,767    | 20,000           | 900                           | 30,000     | 1,000                   |

> **Note:** Burst values apply to disks ≤512 GiB with credit-based bursting (default) or to any size with on-demand bursting enabled. For P30 and above, burst values apply only with on-demand bursting enabled.

## Step 7: Produce structured report

After gathering evidence, produce a report in this format:

```
## Disk IOPS / Throughput Throttling Investigation Report

**VM**: {vm-name}
**Resource Group**: {rg}
**OS**: {Linux/Windows}
**VM Size**: {size}
**Location**: {location}
**Investigation Time**: {timestamp}

### Disk Inventory

| Disk Name | Type | SKU | Size (GiB) | Max IOPS | Max Throughput (MBps) | Caching | Bursting |
|-----------|------|-----|-----------|----------|----------------------|---------|----------|
| {disk}    | OS   | {sku} | {size}  | {iops}   | {throughput}         | {cache} | {yes/no} |
| {disk}    | Data | {sku} | {size}  | {iops}   | {throughput}         | {cache} | {yes/no} |

### VM-Level Limits

| Metric | Limit | Current (Avg) | Current (Max) | Status |
|--------|-------|---------------|---------------|--------|
| Cached IOPS | {limit} | {avg}% | {max}% | {OK/THROTTLED} |
| Uncached IOPS | {limit} | {avg}% | {max}% | {OK/THROTTLED} |
| Cached Bandwidth | {limit} | {avg}% | {max}% | {OK/THROTTLED} |
| Uncached Bandwidth | {limit} | {avg}% | {max}% | {OK/THROTTLED} |

### Per-Disk Analysis

| Disk Name | Metric | Current (Avg) | Current (Max) | Disk Limit | % Used | Status |
|-----------|--------|---------------|---------------|------------|--------|--------|
| {disk}    | IOPS   | {avg}         | {max}         | {limit}    | {pct}% | {OK/THROTTLED} |
| {disk}    | Throughput | {avg} MBps | {max} MBps   | {limit}    | {pct}% | {OK/THROTTLED} |

### Throttling Source
{disk-level / VM-level / both / none detected}

### Root Cause
{Description of what is causing the throttling and which workload is driving IO}

### Recommendation
{One or more of the following, with justification:}
- **No action needed** — IO is within limits, investigate elsewhere
- **Upgrade disk SKU** — {disk-name} is hitting {current-sku} limits → upgrade to {recommended-sku}
- **Enable bursting** — enable on-demand bursting on {disk-name} for intermittent spikes
- **Resize VM** — VM-level throttling at {percentage}% → resize from {current-size} to {recommended-size}
- **Enable caching** — add ReadOnly caching on {disk-name} for read-heavy workload
- **Switch to Premium SSD v2 / Ultra Disk** — workload needs dynamically adjustable IOPS/throughput
- **Stripe disks** — aggregate IOPS across multiple disks using LVM or Storage Spaces

### Next Steps
{Specific actions the operator should take}
```

## Important notes

- **Run Command has a timeout of ~90 seconds** — if a command hangs, it will fail. The commands above are designed to complete quickly.
- **Run Command executes as root/SYSTEM** — the commands have full access but treat this as read-only investigation.
- **Disk SKU changes**: Upgrading from one Premium SSD size to another (e.g., P20 → P30) can be done online without deallocation. However, changing disk type (e.g., Standard SSD → Premium SSD) may require deallocation on some VM series.
- **Premium SSD v2 and Ultra Disk** support dynamic IOPS and throughput adjustment without VM deallocation. You can scale performance independently of disk size using `az disk update`.
- **Changing disk caching** settings (e.g., None → ReadOnly) requires a brief IO pause on the disk. Plan for a short disruption during the change.
- **Do NOT resize VMs or change disk SKUs** unless the operator explicitly asks. This skill is diagnostic only.
