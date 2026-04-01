---
name: vm-extension-failure-remediation
description: >
  Remediation procedure for failed Azure VM extensions.
  Use when a VM extension has failed provisioning, is stuck in a transitioning state,
  Custom Script Extension returns an error, Azure Monitor Agent is not reporting,
  or an extension provisioning timeout occurs.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

> ⚠️ **Example skill** — designed as a starting point. Test and customize for your environment.

## When to use this skill

Use this skill when:
- A VM extension has failed provisioning or shows a failed status
- Custom Script Extension returns an error or non-zero exit code
- Azure Monitor Agent is installed but not reporting data
- An extension provisioning operation has timed out
- An extension is stuck in a "transitioning" state

## Overview

This skill guides you through a structured remediation:
1. List all extensions and their provisioning status
2. Get detailed error information for the failed extension
3. Check extension logs inside the VM (Linux or Windows)
4. Verify VM agent health
5. Apply common remediation patterns
6. Produce a structured report

## Step 1: List all extensions and their status

Get an overview of every extension installed on the VM and its current state:

```
az vm extension list --resource-group {rg} --vm-name {vm-name} --query "[].{name:name, publisher:publisher, type:typePropertiesType, version:typeHandlerVersion, status:provisioningState}" -o table
```

Look for any extension where `status` is not `Succeeded`.

## Step 2: Get detailed status for the failed extension

Once you identify the failing extension, get its full error details:

```
az vm get-instance-view --resource-group {rg} --name {vm-name} --query "instanceView.extensions[?name=='{extension-name}'].{name:name, status:statuses[0].displayStatus, code:statuses[0].code, message:statuses[0].message, substatuses:substatuses}" -o json
```

The `message` field usually contains the actual error output. The `code` field indicates the failure category.

## Step 3: Check extension logs inside the VM

> **Important:** `az vm run-command invoke` is a **write operation** and requires the `RunAzCliWriteCommands` tool, not `RunAzCliReadCommands`.

### Linux VMs

**List recent extension log files:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "ls -lt /var/log/azure/ && echo '---' && find /var/log/azure -name '*.log' -mtime -1 -exec tail -50 {} + 2>/dev/null"
```

**For Custom Script Extension specifically:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "cat /var/lib/waagent/custom-script/download/0/stderr && cat /var/lib/waagent/custom-script/download/0/stdout"
```

**Check waagent log for extension-related errors:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "tail -100 /var/log/waagent.log | grep -i 'error\|fail\|extension'"
```

### Windows VMs

**Check extension plugin logs:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-ChildItem 'C:\WindowsAzure\Logs\Plugins' -Recurse -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { Write-Output \"--- $($_.FullName) ---\"; Get-Content $_.FullName -Tail 30 }"
```

**Check Windows Azure Guest Agent log:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Content 'C:\WindowsAzure\Logs\WaAppAgent.log' -Tail 50"
```

## Step 4: Check VM agent health

Before attempting any remediation, confirm the VM agent is healthy. An unhealthy agent will prevent extension operations from succeeding:

```
az vm get-instance-view --resource-group {rg} --name {vm-name} --query "instanceView.vmAgent" -o json
```

Look for:
- `vmAgentVersion` — ensure the agent is not severely outdated
- `statuses[0].displayStatus` — should be "Ready"
- If the agent is not ready, extension operations will fail regardless of other fixes

## Step 5: Common remediation patterns

> ⚠️ **Get operator confirmation before removing or reinstalling extensions.** Removing an extension may lose its configuration permanently.

### Remove failed extension

```
az vm extension delete --resource-group {rg} --vm-name {vm-name} --name {extension-name}
```

### Reinstall extension (example for Custom Script Extension)

```
az vm extension set --resource-group {rg} --vm-name {vm-name} --name CustomScript --publisher Microsoft.Azure.Extensions --version 2.1 --settings '{...}'
```

Replace `'{...}'` with the original settings JSON for the extension.

### Force update sequence number to retry

This forces the platform to re-execute the extension without removing it:

```
az vm extension set --resource-group {rg} --vm-name {vm-name} --name {extension-name} --force-update
```

## Common failure patterns

| Pattern | Typical Cause | Remediation |
|---|---|---|
| **Timeout** (extension exceeds max execution time) | Script runs too long, downloads stall, or external dependency is unreachable | Optimize the script, check network connectivity, increase timeout if supported |
| **Dependency missing** (e.g., package not found, module not installed) | Script assumes a tool/package is present that isn't on the base image | Install prerequisites before the main script, or use a custom image |
| **Permission denied** (exit code 126/127, access denied errors) | Script not executable, or runs as a user without required privileges | Check file permissions, ensure script has execute bit, verify RBAC roles |
| **Script error** (non-zero exit code from Custom Script Extension) | Bug in the script itself — syntax error, bad variable reference, missing file | Review stdout/stderr from Step 3, fix the script, and re-run |
| **Agent unhealthy** (VM agent not ready or not responding) | Agent crashed, VM is resource-starved, or agent was manually stopped | Restart the VM agent service, or restart the VM if the agent is unrecoverable |

## Step 6: Produce structured report

After gathering evidence and applying remediation, produce a report in this format:

```
## VM Extension Failure Remediation Report

**VM**: {vm-name}
**Resource Group**: {rg}
**OS**: {Linux/Windows}
**VM Size**: {size}
**Investigation Time**: {timestamp}

### Failed Extension
- **Name**: {extension-name}
- **Publisher**: {publisher}
- **Type**: {type}
- **Version**: {version}
- **Provisioning State**: {state}
- **Error Code**: {code}
- **Error Message**: {message}

### Root Cause
{Description of why the extension failed}

### Evidence
- VM agent status: {Ready/Not Ready}
- Extension error output: {summary of stderr or error message}
- {Additional findings from log inspection}

### Remediation Applied
{One of the following, with details:}
- **Force update** — re-executed extension via --force-update
- **Remove and reinstall** — removed failed extension and reinstalled with corrected settings
- **Script fix** — corrected the underlying script error and re-ran
- **Agent recovery** — restarted VM agent / restarted VM to recover agent health
- **No action taken** — awaiting operator confirmation

### Next Steps
{Specific actions the operator should take}
```

## Important notes

- **Always check VM agent health first** — if the agent is not healthy, no extension operation will succeed. Fix the agent before attempting extension remediation.
- **Some extensions conflict with each other** — for example, multiple monitoring extensions or overlapping security extensions can interfere. Check for conflicting extensions in the list from Step 1.
- **Removing an extension may lose its configuration** — always document the extension's current settings (publisher, version, settings, protected settings) before deleting. Protected settings cannot be retrieved after deletion.
- **Run Command has a timeout of ~90 seconds** — if a log file is very large, the tail commands above are designed to return only recent entries to stay within this limit.
- **Run Command executes as root/SYSTEM** — treat this as a diagnostic operation and avoid making system changes unless explicitly part of the remediation.
