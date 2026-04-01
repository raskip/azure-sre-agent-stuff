---
name: backup-health-verification
description: >
  Verification procedure for Azure VM backup health and compliance.
  Use when checking if VMs are properly backed up, verifying recovery points,
  auditing backup compliance, investigating failed backup alerts, or assessing
  backup coverage across a resource group or subscription.
tools:
  - RunAzCliReadCommands
---

> ⚠️ **Example skill** — designed as a starting point. Test and customize for your environment.

## When to use this skill

Use this skill when:
- You need to verify that a VM's backups are healthy and current
- A failed backup alert fires and you need to investigate
- Auditing backup compliance across a resource group or subscription
- Checking whether recovery points meet the organization's RPO requirements
- Identifying VMs that are not protected by any backup policy

## Overview

This skill guides you through a structured verification:
1. Find Recovery Services vaults in scope
2. Check if the target VM is protected
3. Inspect the latest recovery points
4. Review recent backup job history
5. Examine the backup policy configuration
6. Identify any unprotected VMs
7. Produce a structured report

## Step 1: Find Recovery Services vaults

Locate the vaults in the resource group or subscription that may be protecting VMs.

**Vaults in a specific resource group:**
```
az backup vault list --resource-group {rg} --query "[].{name:name, location:location, resourceGroup:resourceGroup}" -o table
```

**All vaults in the subscription:**
```
az backup vault list --query "[].{name:name, location:location, resourceGroup:resourceGroup}" -o table
```

## Step 2: Check if the VM is protected

Determine whether the target VM is associated with a backup policy.

**Quick check by VM resource ID:**
```
az backup protection check-vm --vm-id {vm-resource-id}
```

**List all protected items in a vault:**
```
az backup item list --resource-group {vault-rg} --vault-name {vault-name} --backup-management-type AzureIaasVM --query "[].{name:properties.friendlyName, status:properties.protectionStatus, state:properties.protectionState, lastBackup:properties.lastBackupTime, policyId:properties.policyId}" -o table
```

If the VM does not appear in any vault's protected items, it is unprotected.

## Step 3: Check latest recovery points

Inspect the most recent recovery points for the protected VM to verify backup recency.

```
az backup recoverypoint list --resource-group {vault-rg} --vault-name {vault-name} --container-name {container-name} --item-name {item-name} --backup-management-type AzureIaasVM --query "[0:5].{name:name, time:properties.recoveryPointTime, type:properties.recoveryPointType, tier:properties.recoveryPointTierDetails[0].type}" -o table
```

Compare the most recent recovery point time against the current time to calculate the recovery point age. This age should be compared against the organization's RPO target.

## Step 4: Check recent backup jobs

Review the last backup jobs for the VM to identify failures or warnings.

```
az backup job list --resource-group {vault-rg} --vault-name {vault-name} --query "[?properties.entityFriendlyName=='{vm-name}'] | [0:10].{operation:properties.operation, status:properties.status, startTime:properties.startTime, endTime:properties.endTime, duration:properties.duration}" -o table
```

Look for:
- Consecutive failed jobs — indicates a persistent issue
- Jobs stuck in "InProgress" state for abnormally long durations
- Warning statuses that may indicate partial backups

## Step 5: Check backup policy

Review the backup policy to understand the schedule and retention configuration.

```
az backup policy list --resource-group {vault-rg} --vault-name {vault-name} --backup-management-type AzureIaasVM --query "[].{name:name, scheduleFrequency:properties.schedulePolicy.scheduleFrequencyInMins, retentionDays:properties.retentionPolicy.dailySchedule.retentionDuration.count}" -o table
```

Verify that the schedule frequency and retention duration align with the organization's backup requirements.

## Step 6: Check for VMs without backup

Identify VMs in the resource group that are not protected by any backup policy.

**List all VMs in the resource group:**
```
az vm list --resource-group {rg} --query "[].{name:name, id:id}" -o json
```

Cross-reference this list with the protected items from Step 2. Any VM that appears in the VM list but not in the protected items list is unprotected and may represent a compliance gap.

## Step 7: Produce structured report

After gathering evidence, produce a report in this format:

```
## Backup Health Verification Report

**Scope**: {resource-group or subscription}
**Vault**: {vault-name}
**Investigation Time**: {timestamp}

### VM Backup Status

| VM Name | Status | Vault | Policy | Last Backup | Backup Age |
|---------|--------|-------|--------|-------------|------------|
| {vm}    | Protected / Unprotected | {vault} | {policy} | {time} | {age} |

### Recent Job History (Last 5 Jobs)

| Operation | Status | Start Time | End Time | Duration |
|-----------|--------|------------|----------|----------|
| {op}      | {status} | {start}  | {end}    | {dur}    |

### Recovery Points

- **Total recovery points**: {count}
- **Latest recovery point**: {time} ({age} ago)
- **Recovery point types**: {Snapshot / Vault-Standard / etc.}

### Compliance Assessment

- **RPO target**: {organization's RPO, e.g., 24 hours}
- **Current recovery point age**: {age}
- **Meets RPO**: {Yes / No}
- **Backup gaps detected**: {Yes — describe / No}
- **Consecutive failures**: {count, if any}

### Unprotected VMs

| VM Name | Resource ID |
|---------|-------------|
| {vm}    | {id}        |

(If none: "All VMs in scope are protected.")

### Recommendations
{One or more of the following, with justification:}
- **No action needed** — all backups are healthy and within RPO
- **Investigate failures** — {count} consecutive backup failures for {vm-name}, check VM agent health and disk snapshots
- **Enable backup** — {vm-name} is unprotected, configure a backup policy
- **Review policy** — current schedule ({frequency}) may not meet RPO requirements
- **Check vault access** — some operations may require data-plane access to the vault

### Next Steps
{Specific actions the operator should take}
```

## Important notes

- **This skill is read-only** — it does not configure backup policies, enable protection, or trigger backup jobs. All commands use `RunAzCliReadCommands` only.
- **Recovery point age vs. RPO** — always compare the latest recovery point age against the organization's defined Recovery Point Objective. A recovery point older than the RPO indicates a compliance gap.
- **Data-plane access** — some backup operations (such as listing recovery points in certain configurations) may require data-plane access to the Recovery Services vault, which is separate from ARM-level permissions.
- **Container name format** — the `--container-name` parameter typically follows the format `iaasvmcontainer;iaasvmcontainerv2;{resource-group};{vm-name}` and the `--item-name` follows `vm;iaasvmcontainerv2;{resource-group};{vm-name}`. Use the output from Step 2 to get the exact values.
