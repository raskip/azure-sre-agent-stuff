---
name: disk-expansion
description: >
  Expand VM disks (OS or data) when disk space is running low. Covers both Linux
  and Windows VMs. Use when a disk space alert fires, a user reports a full disk,
  or monitoring shows disk usage above 90%. Handles Azure managed disk resize,
  partition expansion, and filesystem growth. Always snapshots before changes.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

## When to use this skill

Use this skill when:
- A disk space alert fires on an Azure VM (OS or data disk)
- A user reports a VM disk is full or nearly full
- Monitoring shows disk usage above 90%
- A disk needs to be proactively expanded before it fills up

## Overview

This skill guides you through a structured disk expansion:
1. Diagnose which disk is full and map it to an Azure managed disk
2. Determine current size, SKU, and OS type
3. Take a safety snapshot
4. Resize the Azure managed disk
5. Expand the partition and filesystem at the OS level
6. Verify the expansion succeeded

> **CRITICAL**: Always get operator confirmation before proceeding with steps that cause downtime (VM deallocation). Data disk expansion can often be done online; OS disk expansion usually requires deallocation.

## Step 1: Diagnose — identify which disk is full

First, determine the VM's OS type:

```
az vm show --resource-group {rg} --name {vm-name} --query "{os:storageProfile.osDisk.osType, size:hardwareProfile.vmSize, location:location}" -o json
```

Then check disk usage inside the VM.

### Linux

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "df -Th | grep -v tmpfs && echo '---INODES---' && df -i | grep -v tmpfs"
```

This shows filesystem type (ext4, xfs, etc.), size, used, available, and mount points. Also check inode usage — a disk can appear to have space but be out of inodes.

### Windows

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Volume | Where-Object {$_.DriveLetter} | Select-Object DriveLetter, FileSystemLabel, FileSystem, @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}}, @{N='UsedPct';E={[math]::Round(($_.Size - $_.SizeRemaining)/$_.Size * 100,1)}} | Format-Table -AutoSize"
```

## Step 2: Map the disk to an Azure managed disk

### Identify all disks attached to the VM

```
az vm show --resource-group {rg} --name {vm-name} --query "{osDisk:{name:storageProfile.osDisk.name, diskSizeGB:storageProfile.osDisk.diskSizeGb, caching:storageProfile.osDisk.caching}, dataDisks:storageProfile.dataDisks[].{name:name, lun:lun, diskSizeGB:diskSizeGb, caching:caching}}" -o json
```

### For Linux data disks — map LUN to device

If the full disk is a data disk, find which Azure LUN it maps to:

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "ls -la /dev/disk/azure/scsi1/ 2>/dev/null && echo '---LSBLK---' && lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,TYPE"
```

The LUN number from `/dev/disk/azure/scsi1/lun{N}` corresponds to the LUN in the Azure disk list.

### Get the managed disk details

Once you know the disk name:

```
az disk show --resource-group {rg} --name {disk-name} --query "{name:name, sizeGB:diskSizeGb, sku:sku.name, tier:sku.tier, state:diskState, maxShares:maxShares, encryption:encryption.type}" -o json
```

## Step 3: Safety — snapshot the disk before resizing

> **ALWAYS take a snapshot before expanding a disk. This is non-negotiable.**

```
az snapshot create --resource-group {rg} --name {disk-name}-snap-$(date +%Y%m%d%H%M) --source {disk-name} --query "{name:name, provisioningState:provisioningState, diskSizeGB:diskSizeGb}" -o json
```

Wait for the snapshot to complete before proceeding.

## Step 4: Resize the Azure managed disk

### Determine if online resize is possible

Online resize (no downtime) is supported when **ALL** of these are true:
- The disk is a **data disk** (not the OS disk)
- The disk is **not a shared disk**
- The target size is **≤ 4 TiB**, OR the disk is already > 4 TiB
- The disk is **not** an Ultra Disk or Premium SSD v2 with an active background copy

**If the disk is the OS disk**, the VM almost always needs to be deallocated first.

### Option A: Online resize (data disks, no downtime)

```
az disk update --resource-group {rg} --name {disk-name} --size-gb {new-size-gb}
```

### Option B: Resize with VM deallocation (OS disk, or when online isn't supported)

> **⚠️ WARN THE OPERATOR**: This will cause VM downtime. Get explicit confirmation before proceeding.

```
az vm deallocate --resource-group {rg} --name {vm-name}
```

Wait for deallocation to complete, then resize:

```
az disk update --resource-group {rg} --name {disk-name} --size-gb {new-size-gb}
```

Then start the VM:

```
az vm start --resource-group {rg} --name {vm-name}
```

### Determining the new size

Calculate the new size to ensure **at least 20% free space** after expansion:

```
Required total = Current used space / 0.80
New disk size  = Round up to nearest sensible increment (e.g. 64, 128, 256, 512, 1024 GB)
```

**Examples:**
| Current Size | Used | Used % | Calculated Minimum | Suggested New Size |
|-------------|------|--------|--------------------|--------------------|
| 30 GB       | 28 GB| 93%    | 35 GB              | 64 GB              |
| 128 GB      | 120 GB| 94%   | 150 GB             | 256 GB             |
| 512 GB      | 490 GB| 96%   | 613 GB             | 1024 GB            |

**Rules:**
- Target: **≤80% used** after expansion (i.e. at least 20% free)
- **Premium SSD v2 / Ultra Disk**: Set the exact GiB you need — these SKUs support any size (no tier rounding). Use the calculated minimum directly (e.g. 150 GB, not 256 GB).
- **All other SKUs** (Standard HDD, Standard SSD, Premium SSD v1): Round up to a managed disk tier size — pricing is tiered (32, 64, 128, 256, 512, 1024, 2048, 4096 GiB)
- Confirm the suggested new size with the operator before proceeding
- New size must be **greater than** current size (shrinking is not supported)
- OS disk maximum: **4,095 GiB**
- MBR partitioned disks: usable limit is **2 TiB** — warn if expanding beyond this

## Step 5: Expand partition and filesystem at the OS level

After the Azure managed disk is resized, the OS needs to recognize and use the new space.

### Linux

#### 5a. Rescan the disk (required for online expansion)

If the VM was NOT rebooted (online data disk expansion), the OS needs to rescan:

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "echo 1 | tee /sys/class/block/{device}/device/rescan && sleep 2 && lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT"
```

Replace `{device}` with the block device name (e.g., `sdc`, `sda`). If the VM was deallocated and restarted, this step is not needed.

#### 5b. Determine the partition and filesystem setup

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,TYPE && echo '---PVDISPLAY---' && pvdisplay 2>/dev/null | head -20 && echo '---LVDISPLAY---' && lvdisplay 2>/dev/null | head -30"
```

This tells you:
- Which partition to grow (e.g., `/dev/sda1`, `/dev/sdc1`)
- Filesystem type (ext4, xfs)
- Whether LVM is in use

#### 5c. Expand the partition

**Standard partition (no LVM):**

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "growpart /dev/{device} {partition-number} && echo 'Partition expanded successfully'"
```

Example: `growpart /dev/sda 1` expands partition 1 on `/dev/sda`.

> **Note:** `growpart` may need to be installed: `apt-get install -y cloud-guest-utils` (Debian/Ubuntu) or `yum install -y cloud-utils-growpart` (RHEL/CentOS).

**LVM — expand physical volume, logical volume, then filesystem:**

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "growpart /dev/{device} {partition-number} && pvresize /dev/{partition} && lvextend -l +100%FREE /dev/{vg-name}/{lv-name} && echo 'LVM expanded successfully'"
```

#### 5d. Expand the filesystem

After the partition (or logical volume) is expanded, grow the filesystem.

**ext4:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "resize2fs /dev/{partition-or-lv} && echo 'ext4 filesystem expanded' && df -Th {mount-point}"
```

**xfs:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "xfs_growfs {mount-point} && echo 'xfs filesystem expanded' && df -Th {mount-point}"
```

> **Note:** `xfs_growfs` takes the mount point, not the device. XFS cannot be shrunk.

### Windows

#### 5a. Rescan disks

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Update-Disk -Number {disk-number}; Get-Partition -DiskNumber {disk-number} | Select-Object PartitionNumber, DriveLetter, @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}} | Format-Table -AutoSize"
```

#### 5b. Get maximum supported partition size

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "$partition = Get-Partition -DriveLetter {drive-letter}; $maxSize = (Get-PartitionSupportedSize -DriveLetter {drive-letter}).SizeMax; Write-Output \"Current: $([math]::Round($partition.Size/1GB,2)) GB\"; Write-Output \"Maximum: $([math]::Round($maxSize/1GB,2)) GB\""
```

#### 5c. Expand the partition

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "$maxSize = (Get-PartitionSupportedSize -DriveLetter {drive-letter}).SizeMax; Resize-Partition -DriveLetter {drive-letter} -Size $maxSize; Get-Volume -DriveLetter {drive-letter} | Select-Object DriveLetter, @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}} | Format-Table -AutoSize"
```

## Step 6: Verify the expansion

### Linux

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "df -Th | grep -v tmpfs && echo '---' && lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT"
```

### Windows

```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Volume | Where-Object {$_.DriveLetter} | Select-Object DriveLetter, FileSystemLabel, @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}}, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}} | Format-Table -AutoSize"
```

Confirm that:
- The Azure managed disk shows the new size
- The OS partition has been expanded
- The filesystem reflects the new available space
- The mount point is still correct and the disk is healthy

## Step 7: Produce structured report

```
## Disk Expansion Report

**VM**: {vm-name}
**Resource Group**: {rg}
**OS**: {Linux/Windows}

### Disk Expanded
- **Azure Disk Name**: {disk-name}
- **Disk Type**: {OS disk / Data disk (LUN {n})}
- **Previous Size**: {old-size} GB
- **New Size**: {new-size} GB
- **SKU**: {Standard_LRS / Premium_LRS / etc.}

### Safety
- **Snapshot**: {snapshot-name} created at {timestamp}
- **Method**: {Online resize / Deallocated VM}

### OS-Level Changes
- **Partition**: {device/partition} expanded via {growpart / Resize-Partition}
- **Filesystem**: {ext4/xfs/NTFS} expanded via {resize2fs / xfs_growfs / Resize-Partition}

### Verification
- Disk usage before: {old-usage}%
- Disk usage after: {new-usage}%

### Notes
{Any warnings, issues encountered, or follow-up recommendations}
```

## Important notes

- **NEVER shrink a disk** — Azure does not support it and it causes data loss.
- **Always snapshot first** — this is mandatory, not optional.
- **OS disk expansion requires downtime** in most cases (VM deallocation).
- **MBR limit**: If the disk uses MBR partitioning, it cannot use more than 2 TiB. Warn the operator if they're expanding near this limit.
- **Run Command timeout**: ~90 seconds. All commands above are designed to complete within this window. `growpart` and filesystem expansion on very large disks may take longer — warn if the disk is very large.
- **Ubuntu with cloud-init**: On Ubuntu 16.04+, the root partition may auto-expand on reboot after Azure disk resize. Verify before manually expanding.
- **Do NOT proceed without operator confirmation** when the operation requires VM deallocation.
